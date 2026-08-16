# SUSFS (susfs4ksu) — pinned kernel-side artifacts

Vendored, pinned copy of the **kernel-side** of [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)
for Phase 4 (SUSFS on top of a working KernelSU-Next). Vendored on purpose: susfs4ksu lives on
**GitLab**, and committing the exact files here means the build never depends on GitLab reachability
and the version can't drift under us.

## Pin

| | |
|---|---|
| Source | `https://gitlab.com/simonpunk/susfs4ksu` (GPLv3) |
| Branch | `gki-android14-6.1` (our KMI — exact match) |
| Commit | `e287d59066380bf6de4396532d4a42edf4408701` |
| Cloned | 2026-08-16 |

## Contents (kernel-side only)

| File | Role |
|---|---|
| `kernel_patches/50_add_susfs_in_gki-android14-6.1.patch` | The kernel patch — 114 hunks across 23 files (fs/, proc/, selinux/, mm/, kernel/). **Modifies** existing files; does not create the new ones. |
| `kernel_patches/fs/susfs.c` | New file → copy to `kernel_platform/common/fs/susfs.c`. |
| `kernel_patches/include/linux/susfs.h`, `susfs_def.h` | New headers → copy to `kernel_platform/common/include/linux/`. |
| `kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch` | KSU-side patch. **Targets weishu's original KernelSU, not KernelSU-Next** — kept for reference; see open questions. |

The userspace side (`ksu_module_susfs/` flashable module and the `ksu_susfs` tool) is **not** vendored
here — it is a packaging/artifact concern, pulled at packaging time like ksud/magiskboot in
`scripts/patch-init-boot.sh`.

## Status against OUR tree (dry-run, 2026-08-16)

`patch -p1 --dry-run` of `50_add_susfs_in_gki-android14-6.1.patch` against
`kernel_platform/common` (Samsung 6.1.145): **111 of 114 hunks apply** (54 with harmless
offset/fuzz). **3 hunks fail, in 2 files** — expected, because the patch is built against Google's
*generic* kernel and Samsung forks these files:

- `fs/namespace.c` hunk #1 (line 32) — **trivial**: a `#include <linux/susfs_def.h>` + extern block;
  Samsung's include list differs, so it needs repositioning.
- `fs/proc/base.c` hunk #1 (line 100) — **trivial**: same `#include` context drift.
- `fs/namespace.c` hunk #8 (line 3704) — a function-body hunk (`copy_mnt_ns` area); needs inspection,
  but localized.

**This patch is NOT yet build-integrated** — it is not applied by `scripts/build.sh`, and it will not
apply cleanly until those 3 hunks are adapted. Adapting + build-verifying them is the next step.

## Integration plan (upstream README, adapted for us)

1. Copy `fs/susfs.c` and `include/linux/*.h` into `kernel_platform/common/`.
2. Apply the (adapted) `50_…patch` into `kernel_platform/common/`.
3. Enable `CONFIG_KSU` and `CONFIG_KSU_SUSFS` (+ the `CONFIG_KSU_SUSFS_*` feature sub-options).
4. **Delete `kernel_platform/common/android/abi_gki_protected_exports_aarch64` and `…_x86_64`** —
   upstream step 11: otherwise GKI ABI protection blocks the new exports and **modules like Wi-Fi
   fail to load** (directly relevant to our Phase-1 module ABI work).
5. Build our kernel, package `boot.img` + a KSU/SUSFS `init_boot.img`, install the `ksu_module_susfs`
   module in the KSU-Next manager.

## Open questions (resolve before build-integrating)

- **KSU-Next vs weishu KSU.** SUSFS's `10_enable_susfs_for_ksu.patch` targets weishu's KernelSU.
  KernelSU-Next has its *own* SUSFS support; determine whether we enable it via KSU-Next's Kconfig
  (`CONFIG_KSU_SUSFS`) instead of this patch, and which susfs version KSU-Next v3.3.0 expects.
- **Built-in KSU vs LKM.** SUSFS ≥ v2.0.0 uses **inline hooks, not kprobes**, which points toward
  building KSU **into** the kernel (`CONFIG_KSU=y`) rather than the LKM mode currently in use for
  plain root. Confirm KSU-Next's supported combination for SUSFS.
- **Custom kernel required.** SUSFS is a kernel patch, so it needs our built-from-source kernel — it
  cannot ride on BeyondROM's prebuilt kernel (which currently carries plain KSU root). That custom
  kernel (Build #9) is already device-verified with all hardware working, **audio included**
  (`docs/FACTS.md` §0.3.2, resolved) — so it is a known-good base, not an audio blocker.
