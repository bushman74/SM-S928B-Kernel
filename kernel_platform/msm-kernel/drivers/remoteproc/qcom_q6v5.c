// SPDX-License-Identifier: GPL-2.0
/*
 * Qualcomm Peripheral Image Loader for Q6V5
 *
 * Copyright (C) 2016-2018 Linaro Ltd.
 * Copyright (C) 2014 Sony Mobile Communications AB
 * Copyright (c) 2012-2013, 2020-2021, The Linux Foundation. All rights reserved.
 * Copyright (c) 2023-2025 Qualcomm Innovation Center, Inc. All rights reserved.
 */
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/soc/qcom/smem.h>
#include <linux/soc/qcom/smem_state.h>
#include <linux/remoteproc.h>
#include <linux/delay.h>
#include <linux/interconnect.h>
#include "qcom_common.h"
#include "qcom_q6v5.h"
#include <trace/events/rproc_qcom.h>
#if IS_ENABLED(CONFIG_SEC_SENSORS_SSC)
#include <linux/adsp/ssc_ssr_reason.h>
#endif
#if IS_ENABLED(CONFIG_SND_SOC_SAMSUNG_AUDIO)
#include <sound/samsung/sec_audio_sysfs.h>
#include <sound/samsung/snd_debug_proc.h>
#endif

#define Q6V5_PANIC_DELAY_MS	200
#define SEC_DETAILED_CRASH_REASON

/**
 * qcom_q6v5_prepare() - reinitialize the qcom_q6v5 context before start
 * @q6v5:	reference to qcom_q6v5 context to be reinitialized
 *
 * Return: 0 on success, negative errno on failure
 */
int qcom_q6v5_prepare(struct qcom_q6v5 *q6v5)
{
	reinit_completion(&q6v5->start_done);
	reinit_completion(&q6v5->stop_done);

	q6v5->running = true;
	q6v5->handover_issued = false;

	enable_irq(q6v5->handover_irq);

	return 0;
}
EXPORT_SYMBOL_GPL(qcom_q6v5_prepare);

/**
 * qcom_q6v5_unprepare() - unprepare the qcom_q6v5 context after stop
 * @q6v5:	reference to qcom_q6v5 context to be unprepared
 *
 * Return: 0 on success, 1 if handover hasn't yet been called
 */
int qcom_q6v5_unprepare(struct qcom_q6v5 *q6v5)
{
	disable_irq(q6v5->handover_irq);

	return !q6v5->handover_issued;
}
EXPORT_SYMBOL_GPL(qcom_q6v5_unprepare);

void qcom_q6v5_register_ssr_subdev(struct qcom_q6v5 *q6v5, struct rproc_subdev *ssr_subdev)
{
	q6v5->ssr_subdev = ssr_subdev;
}
EXPORT_SYMBOL(qcom_q6v5_register_ssr_subdev);

static void qcom_q6v5_crash_handler_work(struct work_struct *work)
{
	struct qcom_q6v5 *q6v5 = container_of(work, struct qcom_q6v5, crash_handler);
	struct rproc *rproc = q6v5->rproc;
	struct rproc_subdev *subdev;
	int votes;
#ifdef SEC_DETAILED_CRASH_REASON
	char *msg;
	size_t len;
#endif

	if (atomic_read(&q6v5->ssr_in_prog) != 0) {
		dev_err(q6v5->dev, "skip crash handling\n");
		return;
	}

	mutex_lock(&rproc->lock);
	votes = atomic_read(&rproc->power);
	if (votes == 0 || q6v5->crash_seq != q6v5->seq) {
		mutex_unlock(&rproc->lock);
		return;
	}

	rproc->state = RPROC_CRASHED;
	list_for_each_entry_reverse(subdev, &rproc->subdevs, node) {
		if (subdev->stop)
			subdev->stop(subdev, true);
	}

	mutex_unlock(&rproc->lock);

	/*
	 * Temporary workaround until ramdump userspace application calls
	 * sync() and fclose() on attempting the dump.
	 */
	msleep(100);
#ifdef SEC_DETAILED_CRASH_REASON
	msg = qcom_smem_get(QCOM_SMEM_HOST_ANY, q6v5->crash_reason, &len);
	if (!IS_ERR(msg) && len > 0 && msg[0]) {
		/*
		 * From this code in BL,
		 * snprintf_rc(buf, 150, "Panic Msg : %s",  summary->apss->excp.panic_msg
		 * we can use only 150 - 12(Panic Msg : )
		 */
		char fatal_msg[150-12];
		char *lined_msg = fatal_msg;
		char *remoteproc_name;

		/* for long device name, condense rproc name */
		remoteproc_name = strstr(q6v5->rproc->name, "remoteproc-");
		if (remoteproc_name != NULL)
			remoteproc_name += 11;
		else
			remoteproc_name = (char *)q6v5->rproc->name;

		len = snprintf(fatal_msg, sizeof(fatal_msg)-1,
					"FATAL %s, %s", remoteproc_name, msg);
		len = min(len, sizeof(fatal_msg)-2);

		/* '\n' -> ' ', except the last one */
		while (len--) {
			if (*lined_msg == '\n') *lined_msg = ' ';
			lined_msg++;
		}
		*lined_msg++ = '\n';
		*lined_msg = '\0';
		panic(fatal_msg);
	} else
#endif
		panic("Panicking, remoteproc %s crashed\n", q6v5->rproc->name);
}

static irqreturn_t q6v5_wdog_interrupt(int irq, void *data)
{
	struct qcom_q6v5 *q6v5 = data;
	size_t len;
	char *msg;
#if IS_ENABLED(CONFIG_SEC_SENSORS_SSC) || IS_ENABLED(CONFIG_SND_SOC_SAMSUNG_AUDIO)
	char *chk_name = NULL;
#endif

	if (q6v5->early_boot && !completion_done(&q6v5->subsys_booted))
		complete(&q6v5->subsys_booted);

	/* Sometimes the stop triggers a watchdog rather than a stop-ack */
	if (!q6v5->running) {
		dev_info(q6v5->dev, "received wdog irq while q6 is offline\n");
		complete(&q6v5->stop_done);
		return IRQ_HANDLED;
	}

	q6v5->crash_seq = q6v5->seq;
	msg = qcom_smem_get(QCOM_SMEM_HOST_ANY, q6v5->crash_reason, &len);
	if (!IS_ERR(msg) && len > 0 && msg[0]) {
		dev_err(q6v5->dev, "watchdog received: %s\n", msg);
		trace_rproc_qcom_event(dev_name(q6v5->dev), "q6v5_wdog", msg);
#if IS_ENABLED(CONFIG_SEC_SENSORS_SSC)
		chk_name = strstr(q6v5->rproc->name, "adsp");
		if (chk_name != NULL)
			ssr_reason_call_back(msg, len);
#endif
#if IS_ENABLED(CONFIG_SND_SOC_SAMSUNG_AUDIO)
		chk_name = strstr(q6v5->rproc->name, "adsp");
		if (chk_name != NULL) {
			sdp_info_print("watchdog received: %s\n", msg);
			send_adsp_silent_reset_ev();
		}
#endif
	} else
		dev_err(q6v5->dev, "watchdog without message\n");

	q6v5->running = false;
	dev_err(q6v5->dev, "rproc recovery state: %s\n",
		q6v5->rproc->recovery_disabled ?
		"disabled and lead to device crash" :
		"enabled and kick reovery process");

	if (q6v5->ssr_subdev)
		qcom_notify_early_ssr_clients(q6v5->ssr_subdev);

	if (q6v5->rproc->recovery_disabled)
		schedule_work(&q6v5->crash_handler);
	else
		rproc_report_crash(q6v5->rproc, RPROC_WATCHDOG);

	return IRQ_HANDLED;
}

#if IS_ENABLED(CONFIG_SEC_SENSORS_SSC)
bool sensor_force_ssr(struct rproc *rproc, char *msg)
{
	if (strstr(msg, "IPLSREVOCER")
#if IS_ENABLED(CONFIG_SEC_SENSORS_RECOVERY)
		|| (strstr(msg, "qsh_process") && !rproc->fssr_ignore)
#endif
		|| strstr(msg, "PMUDRSS")
		|| strstr(msg, "SLIMBUS_PM_ERR_FATAL_V01")) {
		return true;
	}
	return false;
}
#endif

static irqreturn_t q6v5_fatal_interrupt(int irq, void *data)
{
	struct qcom_q6v5 *q6v5 = data;
	size_t len;
	char *msg;
#if IS_ENABLED(CONFIG_SEC_SENSORS_SSC) || IS_ENABLED(CONFIG_SND_SOC_SAMSUNG_AUDIO)
	char *chk_name = NULL;
#endif

	if (q6v5->early_boot && !completion_done(&q6v5->subsys_booted))
		complete(&q6v5->subsys_booted);

	if (!q6v5->running) {
		dev_info(q6v5->dev, "received fatal irq while q6 is offline\n");
		return IRQ_HANDLED;
	}

	q6v5->crash_seq = q6v5->seq;
	msg = qcom_smem_get(QCOM_SMEM_HOST_ANY, q6v5->crash_reason, &len);
	if (!IS_ERR(msg) && len > 0 && msg[0]) {
		dev_err(q6v5->dev, "fatal error received: %s\n", msg);
		trace_rproc_qcom_event(dev_name(q6v5->dev), "q6v5_fatal", msg);
#if IS_ENABLED(CONFIG_SEC_SENSORS_SSC)
		chk_name = strstr(q6v5->rproc->name, "adsp");
		if (chk_name != NULL) {
			ssr_reason_call_back(msg, len);
			if (sensor_force_ssr(q6v5->rproc, msg)) {
				q6v5->rproc->fssr = true;
				q6v5->rproc->prev_recovery_disabled =
					q6v5->rproc->recovery_disabled;
				q6v5->rproc->recovery_disabled = false;
				if (strstr(msg, "PMUDRSS"))
					q6v5->rproc->fssr_dump = true;

			} else {
				q6v5->rproc->fssr = false;
				q6v5->rproc->fssr_dump = false;
			}
			dev_info(q6v5->dev, "recovery:%d,%d\n",
				(int)q6v5->rproc->prev_recovery_disabled,
				(int)q6v5->rproc->recovery_disabled);
		}
#endif
#if IS_ENABLED(CONFIG_SND_SOC_SAMSUNG_AUDIO)
		chk_name = strstr(q6v5->rproc->name, "adsp");
		if (chk_name != NULL) {
			sdp_info_print("fatal error received: %s\n", msg);
			send_adsp_silent_reset_ev();
		}
#endif
	} else
		dev_err(q6v5->dev, "fatal error without message\n");

	q6v5->running = false;
	dev_err(q6v5->dev, "rproc recovery state: %s\n",
		q6v5->rproc->recovery_disabled ? "disabled and lead to device crash" :
		"enabled and kick reovery process");

	if (q6v5->ssr_subdev) {
		int silent_ssr_in_progress;

		spin_lock(&q6v5->silent_ssr_lock);
		silent_ssr_in_progress = atomic_read(&q6v5->ssr_in_prog);
		spin_unlock(&q6v5->silent_ssr_lock);

		if (silent_ssr_in_progress) {
			dev_err(q6v5->dev, "silent ssr is ongoing. Return\n");
			return IRQ_HANDLED;
		}
		qcom_notify_early_ssr_clients(q6v5->ssr_subdev);
	}

	if (q6v5->rproc->recovery_disabled)
		schedule_work(&q6v5->crash_handler);
	else
		rproc_report_crash(q6v5->rproc, RPROC_FATAL_ERROR);

	return IRQ_HANDLED;
}

static irqreturn_t q6v5_ready_interrupt(int irq, void *data)
{
	struct qcom_q6v5 *q6v5 = data;

	complete(&q6v5->start_done);

	if (q6v5->early_boot && !completion_done(&q6v5->subsys_booted))
		complete(&q6v5->subsys_booted);

	return IRQ_HANDLED;
}

/**
 * qcom_q6v5_wait_for_start() - wait for remote processor start signal
 * @q6v5:	reference to qcom_q6v5 context
 * @timeout:	timeout to wait for the event, in jiffies
 *
 * qcom_q6v5_unprepare() should not be called when this function fails.
 *
 * Return: 0 on success, -ETIMEDOUT on timeout
 */
int qcom_q6v5_wait_for_start(struct qcom_q6v5 *q6v5, int timeout)
{
	int ret;

	ret = wait_for_completion_timeout(&q6v5->start_done, timeout);
	if (!ret)
		disable_irq(q6v5->handover_irq);

	return !ret ? -ETIMEDOUT : 0;
}
EXPORT_SYMBOL_GPL(qcom_q6v5_wait_for_start);

static irqreturn_t q6v5_handover_interrupt(int irq, void *data)
{
	struct qcom_q6v5 *q6v5 = data;

	if (q6v5->handover)
		q6v5->handover(q6v5);

	if (q6v5->early_boot && !completion_done(&q6v5->subsys_booted))
		complete(&q6v5->subsys_booted);

	icc_set_bw(q6v5->path, 0, 0);

	q6v5->handover_issued = true;

	return IRQ_HANDLED;
}

static irqreturn_t q6v5_stop_interrupt(int irq, void *data)
{
	struct qcom_q6v5 *q6v5 = data;

	complete(&q6v5->stop_done);

	return IRQ_HANDLED;
}

/**
 * qcom_q6v5_request_stop() - request the remote processor to stop
 * @q6v5:	reference to qcom_q6v5 context
 * @sysmon:	reference to the remote's sysmon instance, or NULL
 *
 * Return: 0 on success, negative errno on failure
 */
int qcom_q6v5_request_stop(struct qcom_q6v5 *q6v5, struct qcom_sysmon *sysmon)
{
	int ret;

	q6v5->running = false;

	/* Don't perform SMP2P dance if sysmon already shut
	 * down the remote or if it isn't running
	 */
	if (q6v5->rproc->state != RPROC_RUNNING || qcom_sysmon_shutdown_acked(sysmon))
		return 0;

	qcom_smem_state_update_bits(q6v5->state,
				    BIT(q6v5->stop_bit), BIT(q6v5->stop_bit));

	ret = wait_for_completion_timeout(&q6v5->stop_done, 5 * HZ);

	qcom_smem_state_update_bits(q6v5->state, BIT(q6v5->stop_bit), 0);

	return ret == 0 ? -ETIMEDOUT : 0;
}
EXPORT_SYMBOL_GPL(qcom_q6v5_request_stop);

/**
 * qcom_q6v5_panic() - panic handler to invoke a stop on the remote
 * @q6v5:	reference to qcom_q6v5 context
 *
 * Set the stop bit and sleep in order to allow the remote processor to flush
 * its caches etc for post mortem debugging.
 *
 * Return: 200ms
 */
unsigned long qcom_q6v5_panic(struct qcom_q6v5 *q6v5)
{
	qcom_smem_state_update_bits(q6v5->state,
				    BIT(q6v5->stop_bit), BIT(q6v5->stop_bit));

	return Q6V5_PANIC_DELAY_MS;
}
EXPORT_SYMBOL_GPL(qcom_q6v5_panic);

static irqreturn_t q6v5_pong_interrupt(int irq, void *data)
{
	struct qcom_q6v5 *q6v5 = NULL;

	q6v5 = data;

	if (!q6v5) {
		pr_err("Could not get driver data\n");
		return -ENODEV;
	}

	complete(&q6v5->ping_done);

	return IRQ_HANDLED;
}

int ping_subsystem(struct qcom_q6v5 *q6v5)
{
	int ret = -ETIMEDOUT;
	int ping_failed = 0;

	reinit_completion(&q6v5->ping_done);

	/* Set master kernel Ping bit */
	ret = qcom_smem_state_update_bits(q6v5->ping_state,
			    0xffffffff,
			    BIT(q6v5->ping_bit));
	if (ret) {
		dev_err(q6v5->dev, "Failed to update ping bits\n");
		return ret;
	}

	ret = wait_for_completion_timeout(&q6v5->ping_done, msecs_to_jiffies(PING_TIMEOUT));
	if (!ret) {
		ping_failed = -ETIMEDOUT;
		dev_err(q6v5->dev, "Failed to get back pong\n");
	}


	/* Clear ping bit master kernel */
	ret = qcom_smem_state_update_bits(q6v5->ping_state,
			    BIT(q6v5->ping_bit),
			    0);
	if (ret) {
		pr_err("Failed to clear master kernel bits\n");
		return ret;
	}
	if (ping_failed)
		return ping_failed;

	return ret;

}
EXPORT_SYMBOL_GPL(ping_subsystem);

int ping_subsystem_init(struct qcom_q6v5 *q6v5, struct platform_device *pdev)
{
	int ret = -ENODEV;

	if (!q6v5) {
		pr_err("could not get q6v5 data\n");
		return -ENODEV;
	}

	q6v5->ping_state = devm_qcom_smem_state_get(&pdev->dev,
							"ping", &q6v5->ping_bit);
	if (IS_ERR(q6v5->ping_state)) {
		pr_err("failed to acquire smem state %ld\n", PTR_ERR(q6v5->ping_state));
		ret = -ENODEV;
		return ret;
	}

	q6v5->pong_irq = platform_get_irq_byname(pdev, "pong");
	if (q6v5->pong_irq < 0) {
		pr_err("failed to acquire pong irq\n");
		ret = -ENODEV;
		return ret;
	}

	ret = devm_request_threaded_irq(&pdev->dev, q6v5->pong_irq, NULL,
			q6v5_pong_interrupt, IRQF_TRIGGER_RISING | IRQF_ONESHOT,
			"q6v5 pong", q6v5);
	if (ret)
		pr_err("failed to acquire pong IRQ\n");

	init_completion(&q6v5->ping_done);
	return ret;
}
EXPORT_SYMBOL_GPL(ping_subsystem_init);

/**
 * qcom_q6v5_init() - initializer of the q6v5 common struct
 * @q6v5:	handle to be initialized
 * @pdev:	platform_device reference for acquiring resources
 * @rproc:	associated remoteproc instance
 * @crash_reason: SMEM id for crash reason string, or 0 if none
 * @handover:	function to be called when proxy resources should be released
 *
 * Return: 0 on success, negative errno on failure
 */
int qcom_q6v5_init(struct qcom_q6v5 *q6v5, struct platform_device *pdev,
		   struct rproc *rproc,  int crash_reason, bool early_boot,
		   void (*handover)(struct qcom_q6v5 *q6v5))
{
	int ret;
	struct resource *res;

	q6v5->rproc = rproc;
	q6v5->dev = &pdev->dev;
	q6v5->crash_reason = crash_reason;
	q6v5->handover = handover;
	q6v5->early_boot = early_boot;
	q6v5->ssr_subdev = NULL;

	atomic_set(&q6v5->ssr_in_prog, 0);

	init_completion(&q6v5->start_done);
	init_completion(&q6v5->stop_done);

	res = platform_get_resource(pdev, IORESOURCE_MEM, 1);
	if (res) {
		q6v5->rmb_base = devm_ioremap_resource(&pdev->dev, res);
		if (IS_ERR(q6v5->rmb_base))
			q6v5->rmb_base = NULL;
	} else
		q6v5->rmb_base = NULL;


	q6v5->wdog_irq = platform_get_irq_byname(pdev, "wdog");
	if (q6v5->wdog_irq < 0)
		return q6v5->wdog_irq;

	ret = devm_request_threaded_irq(&pdev->dev, q6v5->wdog_irq,
					NULL, q6v5_wdog_interrupt,
					IRQF_ONESHOT,
					"q6v5 wdog", q6v5);
	if (ret) {
		dev_err(&pdev->dev, "failed to acquire wdog IRQ\n");
		return ret;
	}

	q6v5->fatal_irq = platform_get_irq_byname(pdev, "fatal");
	if (q6v5->fatal_irq < 0)
		return q6v5->fatal_irq;

	ret = devm_request_threaded_irq(&pdev->dev, q6v5->fatal_irq,
					NULL, q6v5_fatal_interrupt,
					IRQF_TRIGGER_RISING | IRQF_ONESHOT,
					"q6v5 fatal", q6v5);
	if (ret) {
		dev_err(&pdev->dev, "failed to acquire fatal IRQ\n");
		return ret;
	}

	q6v5->ready_irq = platform_get_irq_byname(pdev, "ready");
	if (q6v5->ready_irq < 0)
		return q6v5->ready_irq;

	ret = devm_request_threaded_irq(&pdev->dev, q6v5->ready_irq,
					NULL, q6v5_ready_interrupt,
					IRQF_TRIGGER_RISING | IRQF_ONESHOT,
					"q6v5 ready", q6v5);
	if (ret) {
		dev_err(&pdev->dev, "failed to acquire ready IRQ\n");
		return ret;
	}

	q6v5->handover_irq = platform_get_irq_byname(pdev, "handover");
	if (q6v5->handover_irq < 0)
		return q6v5->handover_irq;

	ret = devm_request_threaded_irq(&pdev->dev, q6v5->handover_irq,
					NULL, q6v5_handover_interrupt,
					IRQF_TRIGGER_RISING | IRQF_ONESHOT,
					"q6v5 handover", q6v5);
	if (ret) {
		dev_err(&pdev->dev, "failed to acquire handover IRQ\n");
		return ret;
	}
	disable_irq(q6v5->handover_irq);

	q6v5->stop_irq = platform_get_irq_byname(pdev, "stop-ack");
	if (q6v5->stop_irq < 0)
		return q6v5->stop_irq;

	ret = devm_request_threaded_irq(&pdev->dev, q6v5->stop_irq,
					NULL, q6v5_stop_interrupt,
					IRQF_TRIGGER_RISING | IRQF_ONESHOT,
					"q6v5 stop", q6v5);
	if (ret) {
		dev_err(&pdev->dev, "failed to acquire stop-ack IRQ\n");
		return ret;
	}

	q6v5->state = qcom_smem_state_get(&pdev->dev, "stop", &q6v5->stop_bit);
	if (IS_ERR(q6v5->state)) {
		dev_err(&pdev->dev, "failed to acquire stop state\n");
		return PTR_ERR(q6v5->state);
	}

	INIT_WORK(&q6v5->crash_handler, qcom_q6v5_crash_handler_work);

	spin_lock_init(&q6v5->silent_ssr_lock);
	return 0;
}
EXPORT_SYMBOL_GPL(qcom_q6v5_init);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("Qualcomm Peripheral Image Loader for Q6V5");
