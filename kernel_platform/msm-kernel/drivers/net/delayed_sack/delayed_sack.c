// SPDX-License-Identifier: GPL-2.0-only
/*
 * delayed-SACK driver
 *
 * Copyright (C) 2025 Samsung Electronics Co,LTD.
 */
#include <linux/module.h>
#include <linux/workqueue.h>
#include <linux/netfilter_netdev.h>
#include <net/ip.h>
#include <net/tcp.h>

#if IS_ENABLED(CONFIG_ANDROID_VENDOR_HOOKS)
#include <trace/hooks/net.h>
#endif

#include "delayed_sack.h"

#define DEFAULT_DELAYED_SACK_TIMEOUT_NS	(2000000)	/* 2ms */
#define DELAYED_SACK_TIMEOUT_RETRY_NS	(500000)	/* 0.5ms */
#define DELAYED_SACK_MAX_TRY		1

struct delayed_sack {
	struct sk_buff_head delayed_sack_queue;
	struct hrtimer timeout_timer;
	struct sock *sk;
	int delayed_sack_count;
	spinlock_t lock;
};

/*
 * Caution! Be careful not to use duplicated numbers. Check 'struct sock'
 */
#define SK_RESERVE_FIELD		android_kabi_reserved8

/* helpers */
#define SK_DELAYED_SACK(sk)		((struct delayed_sack *)(sk->SK_RESERVE_FIELD))
#define SK_DELAYED_SACK_ASSIGN(sk, obj)	(sk->SK_RESERVE_FIELD = (u64)obj)
#define SK_DELAYED_SACK_QUEUE(sk)	((struct sk_buff_head *)&(SK_DELAYED_SACK(sk)->delayed_sack_queue))
#define SK_DELAYED_SACK_TIMER(sk)	((struct hrtimer *)&(SK_DELAYED_SACK(sk)->timeout_timer))
#define SK_DELAYED_SACK_EMPTY(sk)	(skb_queue_empty_lockless(SK_DELAYED_SACK_QUEUE(sk)))
#define SK_DELAYED_SACK_LOCK(sk)	(SK_DELAYED_SACK(sk)->lock)

static inline bool is_tcp_sack_delay_ongoing(struct sock *sk)
{
	return (SK_DELAYED_SACK(sk) && !SK_DELAYED_SACK_EMPTY(sk));
}

static inline bool tcp_sack_delay_terminated(struct sock *sk)
{
	return (SK_DELAYED_SACK(sk) && SK_DELAYED_SACK(sk)->delayed_sack_count == 0);
}

static u8 skb_is_tcp_sack(const struct sk_buff *skb)
{
	const unsigned char *ptr;
	const struct tcphdr *th = tcp_hdr(skb);
	int length = (th->doff * 4) - sizeof(struct tcphdr);

	ptr = (const unsigned char *)(th + 1);

	while (length > 0) {
		int opcode = *ptr++;
		int opsize;

		switch (opcode) {
		case TCPOPT_EOL:
			goto skb_is_not_sack;
		case TCPOPT_NOP:	/* Ref: RFC 793 section 3.1 */
			length--;
			continue;
		default:
			if (length < 2)
				goto skb_is_not_sack;
			opsize = *ptr++;
			if (opsize < 2) /* "silly options" */
				goto skb_is_not_sack;
			if (opsize > length)
				goto skb_is_not_sack;	/* don't parse partial options */
			if (opcode == TCPOPT_SACK) {
				if ((opsize >= (TCPOLEN_SACK_BASE + TCPOLEN_SACK_PERBLOCK)) &&
				   !((opsize - TCPOLEN_SACK_BASE) % TCPOLEN_SACK_PERBLOCK)) {
					return (ptr - 2) - (unsigned char *)th;
				}
			}
			ptr += opsize-2;
			length -= opsize;
		}
	}

skb_is_not_sack:
	return 0;
}

static void queued_sack_copy_to(struct sock *sk, struct sk_buff_head *local_list)
{
	unsigned long flags;

	skb_queue_head_init(local_list);

	spin_lock_irqsave(&SK_DELAYED_SACK_QUEUE(sk)->lock, flags);
	skb_queue_splice_init(SK_DELAYED_SACK_QUEUE(sk), local_list);
	spin_unlock_irqrestore(&SK_DELAYED_SACK_QUEUE(sk)->lock, flags);
}

static void consume_queued_sack(struct sk_buff_head *q)
{
	struct sk_buff *queued_skb, *tmp;

	/* consume skbs under unlocked */
	skb_queue_walk_safe(q, queued_skb, tmp) {
		__skb_unlink(queued_skb, q);
		consume_skb(queued_skb);
	}
}

static void flush_queued_sack(struct sk_buff_head *q)
{
	struct sk_buff *queued_skb, *tmp;

	/* xmit sack under unlocked */
	skb_queue_walk_safe(q, queued_skb, tmp) {
		__skb_unlink(queued_skb, q);
		nf_skip_egress(queued_skb, true);
		dev_queue_xmit(queued_skb);
	}
}

static void replace_queued_sack(struct sk_buff *skb, struct sk_buff_head *q)
{
	struct sk_buff *old;

	spin_lock_bh(&q->lock);

	old = skb_peek_tail(q);
	if (old) {
		__skb_queue_after(q, old, skb);
		__skb_unlink(old, q);
	} else {
		__skb_queue_tail(q, skb);
	}

	spin_unlock_bh(&q->lock);

	if (old)
		consume_skb(old);
}

static void cancel_delayed_sack_timer(struct sock *sk)
{
	if (hrtimer_try_to_cancel(SK_DELAYED_SACK_TIMER(sk)) == 1)
		__sock_put(sk);
}

static void free_delayed_sack(struct sock *sk)
{
	struct sk_buff_head local_list;

	if (!SK_DELAYED_SACK(sk))
		return;

	spin_lock_bh(&SK_DELAYED_SACK_LOCK(sk));

	cancel_delayed_sack_timer(sk);
	queued_sack_copy_to(sk, &local_list);

	spin_unlock_bh(&SK_DELAYED_SACK_LOCK(sk));

	consume_queued_sack(&local_list);

	kfree(SK_DELAYED_SACK(sk));
	SK_DELAYED_SACK_ASSIGN(sk, NULL);
}

static void rearm_delayed_sack_timer(struct sock *sk)
{
	struct delayed_sack *ds = SK_DELAYED_SACK(sk);

	ds->sk = sk;

	hrtimer_start(SK_DELAYED_SACK_TIMER(sk),
		      ns_to_ktime(DEFAULT_DELAYED_SACK_TIMEOUT_NS),
		      HRTIMER_MODE_REL_PINNED_SOFT);
	sock_hold(sk);
}

static enum hrtimer_restart delayed_sack_timeout(struct hrtimer *timer)
{
	struct delayed_sack *ds = container_of(timer, struct delayed_sack, timeout_timer);
	struct sock *sk = ds->sk;

	bh_lock_sock(sk);

	if (sock_flag(sk, SOCK_DEAD) || SK_DELAYED_SACK_EMPTY(sk)) {
		pr_info("delayed_sack: %s: sk=%p(%d), dead=%d, empty=%d\n",
			__func__, sk, refcount_read(&sk->sk_refcnt),
			sock_flag(sk, SOCK_DEAD), SK_DELAYED_SACK_EMPTY(sk));
		goto sack_timeout_exit;
	}

	pr_info("delayed_sack: %s: sk=%p(%d), expired, owned(%d)\n",
		__func__, sk, refcount_read(&sk->sk_refcnt),
		sock_owned_by_user(sk));

	if (!sock_owned_by_user(sk)) {
		struct sk_buff_head local_list;

		spin_lock_bh(&SK_DELAYED_SACK_LOCK(sk));

		queued_sack_copy_to(sk, &local_list);
		ds->delayed_sack_count--;

		spin_unlock_bh(&SK_DELAYED_SACK_LOCK(sk));

		flush_queued_sack(&local_list);
	} else {
		/* Try again later. */
		sock_hold(sk);
		hrtimer_start(SK_DELAYED_SACK_TIMER(sk),
			      ns_to_ktime(DELAYED_SACK_TIMEOUT_RETRY_NS),
			      HRTIMER_MODE_REL_PINNED_SOFT);
	}

sack_timeout_exit:
	bh_unlock_sock(sk);
	sock_put(sk);

	return HRTIMER_NORESTART;
}

static void init_delayed_sack_timer(struct sock *sk)
{
	hrtimer_init(SK_DELAYED_SACK_TIMER(sk), CLOCK_MONOTONIC,
		     HRTIMER_MODE_REL_PINNED_SOFT);
	SK_DELAYED_SACK_TIMER(sk)->function = delayed_sack_timeout;
}

static bool init_delayed_sack(struct sock *sk)
{
	if (SK_DELAYED_SACK(sk) == NULL) {
		struct delayed_sack *ds = kzalloc(sizeof(struct delayed_sack),
						  GFP_ATOMIC | __GFP_NOWARN);
		if (!ds) {
			pr_err("%s: failed to alloc delayed_sack(%lu)\n",
				__func__, sizeof(struct delayed_sack));
			return false;
		}

		SK_DELAYED_SACK_ASSIGN(sk, ds);

		spin_lock_init(&SK_DELAYED_SACK_LOCK(sk));
		spin_lock_bh(&SK_DELAYED_SACK_LOCK(sk));

		init_delayed_sack_timer(sk);
	} else {
		spin_lock_bh(&SK_DELAYED_SACK_LOCK(sk));

		/* try to cancel if timer still running */
		cancel_delayed_sack_timer(sk);
	}

	SK_DELAYED_SACK(sk)->sk = sk;
	SK_DELAYED_SACK(sk)->delayed_sack_count = DELAYED_SACK_MAX_TRY;

	return true;
}

static int delayed_sack_process(struct sk_buff *skb)
{
	struct sock *sk;
	struct tcp_sock *tp;
	u8 sacktag_pos;

	/* For now, we don't consider Piggy-back case. */
	if (!skb_is_tcp_pure_ack(skb))
		goto nothing_to_process;

	if (skb->sk == NULL)
		goto nothing_to_process;

	sk = skb->sk;
	tp = (struct tcp_sock *)sk;

	sock_hold(sk);

	if (tcp_sack_delay_terminated(sk))
		goto nothing_to_process_with_sock_hold;

	sacktag_pos = skb_is_tcp_sack(skb);
	if (!sacktag_pos) {
		/* Cumulative ACK coming!
		 */
		struct sk_buff_head local_list;

		if (!is_tcp_sack_delay_ongoing(sk))
			goto nothing_to_process_with_sock_hold;

		spin_lock_bh(&SK_DELAYED_SACK_LOCK(sk));

		cancel_delayed_sack_timer(sk);
		queued_sack_copy_to(sk, &local_list);

		spin_unlock_bh(&SK_DELAYED_SACK_LOCK(sk));

		/* delayed-sack was on-going.
		 * check if reorderings were resolved or not.
		 */
		if (tp->rx_opt.num_sacks != 0) {
			pr_info("delayed_sack: %s: sk=%p, ack=%u(%d) failed\n",
				__func__, sk, tp->rcv_nxt, tp->rx_opt.num_sacks);

			flush_queued_sack(&local_list);

		} else {
			/* reorderings were resolved.
			 * we don't need these queued sacks.
			 */
			consume_queued_sack(&local_list);

			pr_info("delayed_sack: %s: sk=%p, ack=%u(%d) resolved\n",
				__func__, sk, tp->rcv_nxt, tp->rx_opt.num_sacks);
		}

	} else {
		/* SACK coming!
		 */
		if (!is_tcp_sack_delay_ongoing(sk)) {
			/* The 1st time SACK.
			 */
			if (tp->rx_opt.num_sacks == 0) {
				/* it seems DSACK. ignore that. */
				pr_debug("delayed_sack: %s: Ignore DSACK\n",
					 __func__);
				goto nothing_to_process_with_sock_hold;
			}

			/* This will hold the lock */
			if (!init_delayed_sack(sk))
				goto nothing_to_process_with_sock_hold;

			skb_queue_head_init(SK_DELAYED_SACK_QUEUE(sk));
			skb_queue_tail(SK_DELAYED_SACK_QUEUE(sk), skb);

			rearm_delayed_sack_timer(sk);

			/* Must unlock here */
			spin_unlock_bh(&SK_DELAYED_SACK_LOCK(sk));

			pr_info("delayed_sack: %s: sk=%p, ack=%u(%d) new\n",
				__func__, sk, tp->rcv_nxt, tp->rx_opt.num_sacks);

			goto skip_this_skb;
		} else {
			/* trailing SACKs.
			 */
			spin_lock_bh(&SK_DELAYED_SACK_LOCK(sk));
			replace_queued_sack(skb, SK_DELAYED_SACK_QUEUE(sk));
			spin_unlock_bh(&SK_DELAYED_SACK_LOCK(sk));

			pr_debug("delayed_sack: %s: sk=%p, sack replaced\n",
				__func__, sk);
			goto skip_this_skb;
		}
	}

nothing_to_process_with_sock_hold:
	sock_put(sk);
nothing_to_process:
	return 0;

skip_this_skb:
	sock_put(sk);
	return 1;
}

static unsigned int
delayed_sack_nf_hook(void *priv, struct sk_buff *skb,
		     const struct nf_hook_state *state)
{
	if (delayed_sack_process(skb))
		return NF_STOLEN;

	return NF_ACCEPT;
}

static struct nf_hook_ops delayed_sack_nf_hook_ops = {
	.hook = delayed_sack_nf_hook,
	.pf = NFPROTO_NETDEV,
	.hooknum = NF_NETDEV_EGRESS,
	.priority = -1
};

static int delayed_sack_netdev_event(struct notifier_block *this,
				     unsigned long event, void *ptr)
{
	struct net_device *dev = netdev_notifier_info_to_dev(ptr);
	int ret;

	if (!dev)
		return NOTIFY_DONE;

	if (strncmp(dev->name, "rmnet_ipa", 9) == 0 ||
	    strncmp(dev->name, "rmnet_usb", 9) == 0 ||
	    strncmp(dev->name, "rmnet", 5) != 0)
		return NOTIFY_DONE;

	switch (event) {
	case NETDEV_REGISTER:
		delayed_sack_nf_hook_ops.dev = dev;
		ret = nf_register_net_hook(dev_net(dev), &delayed_sack_nf_hook_ops);
		if (ret) {
			pr_err("delayed_sack: failed to register nf_hook_ops for %s\n",
				dev->name);
			return NOTIFY_BAD;
		}
		pr_info("delayed_sack: registered for %s\n", dev->name);
		break;

	case NETDEV_UNREGISTER:
		delayed_sack_nf_hook_ops.dev = dev;
		nf_unregister_net_hook(dev_net(dev), &delayed_sack_nf_hook_ops);
		break;
	}

	return NOTIFY_DONE;
}

static struct notifier_block delayed_sack_netdev_notifier = {
	.notifier_call	= delayed_sack_netdev_event,
};

#if IS_ENABLED(CONFIG_ANDROID_VENDOR_HOOKS)
static void sk_alloc_cb(void *data, struct sock *sk)
{
	SK_DELAYED_SACK_ASSIGN(sk, NULL);
}

static void sk_free_cb(void *data, struct sock *sk)
{
	free_delayed_sack(sk);
}

static void register_hook_in_runtime(struct tracepoint *tp, void *ignore)
{
	if (!strcmp(tp->name, "android_vh_sk_alloc")) {
		tracepoint_probe_register(tp, sk_alloc_cb, NULL);
		pr_info("delayed_sack: android_vh_sk_alloc registered\n");
	} else if (!strcmp(tp->name, "android_rvh_sk_alloc")) {
		android_rvh_probe_register(tp, sk_alloc_cb, NULL);
		pr_info("delayed_sack: android_rvh_sk_alloc registered\n");
	} else if (!strcmp(tp->name, "android_vh_sk_free")) {
		tracepoint_probe_register(tp, sk_free_cb, NULL);
		pr_info("delayed_sack: android_vh_sk_free registered\n");
	} else if (!strcmp(tp->name, "android_rvh_sk_free")) {
		android_rvh_probe_register(tp, sk_free_cb, NULL);
		pr_info("delayed_sack: android_rvh_sk_free registered\n");
	}
}

static inline int register_hook_in_static(void)
{
#if (KERNEL_VERSION(6, 12, 0) > LINUX_VERSION_CODE && KERNEL_VERSION(6, 6, 0) <= LINUX_VERSION_CODE)
	return register_trace_android_vh_sk_alloc(sk_alloc_cb, NULL) ||
	       register_trace_android_vh_sk_free(sk_free_cb, NULL);

#elif (KERNEL_VERSION(5, 4, 0) <= LINUX_VERSION_CODE)
	return register_trace_android_rvh_sk_alloc(sk_alloc_cb, NULL) ||
	       register_trace_android_rvh_sk_free(sk_free_cb, NULL);
#endif

	return -1;
}

static void register_sk_lifecycle_tracepoint(void)
{
	if (!register_hook_in_static()) {
		pr_info("delayed_sack: registered in static\n");
	} else {
		pr_info("delayed_sack: try to register in runtime\n");

		for_each_kernel_tracepoint(register_hook_in_runtime, NULL);
	}
}

#else
#define register_sk_lifecycle_tracepoint()	do { } while (0)

#endif

static int __init delayed_sack_init(void)
{
	int ret;

	if (!IS_ENABLED(CONFIG_ANDROID_VENDOR_HOOKS)) {
		pr_info("delayed_sack: needs vendor hooks\n");
		return 0;
	}

	ret = register_netdevice_notifier(&delayed_sack_netdev_notifier);
	if (ret < 0)
		return ret;

	register_sk_lifecycle_tracepoint();

	pr_info("delayed_sack: +++\n");
	return 0;
}

static void __exit delayed_sack_exit(void)
{
	unregister_netdevice_notifier(&delayed_sack_netdev_notifier);

	pr_info("delayed_sack: ---\n");
}

module_init(delayed_sack_init);
module_exit(delayed_sack_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Samsung delayed-SACK driver");
