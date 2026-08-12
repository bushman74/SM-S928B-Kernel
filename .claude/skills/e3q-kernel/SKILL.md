---
name: e3q-kernel
description: Build, patch, package, and flash procedure for the Samsung Galaxy S24 Ultra (SM-S928B / e3q / SM8650) 6.1 GKI kernel. Use this skill whenever the task touches compiling the kernel, choosing a toolchain or defconfig, handling vendor .ko modules, repacking boot/init_boot/vendor_boot/vendor_dlkm images, making a modified Samsung kernel bootable (SEANDROIDENFORCE, vbmeta/AVB, PROCA/RKP/KDP/DEFEX neutralization), integrating KernelSU Next in LKM mode into init_boot.img, adding SUSFS, writing or debugging the GitHub Actions build workflow, or triaging a build log or a boot failure on this device. Use it even if the request sounds like a generic "build the kernel", "add root", or "why did CI fail" — this device has non-obvious GKI 2.0, Samsung-security, and KMI constraints that generic kernel knowledge will get wrong.
---

# e3q kernel build & root procedure

Read `docs/FACTS.md` before using anything here. Any value written as `<from FACTS>` must be
looked up in the tree or on the device, never assumed.

## Constraint 1 — GKI 2.0 module set

The kernel image is only part of the picture. Most drivers ship as `.ko` in `vendor_boot` and
`vendor_dlkm`. A freshly built `boot.img` alone boots to a UI with **no Wi-Fi, Bluetooth, or
S-Pen**. Every build must produce a matched set: kernel plus modules, repacked into the right
partitions. Any module we cannot build from source is reused as a stock binary from the
device's own `vendor_dlkm`. The inventory table is `docs/FACTS.md` §0.3 — fill it before building.

## Constraint 2 — module ABI

Stock `.ko` files must still load against our kernel. Do not let these drift without cause:
kernel version string / vermagic, `CONFIG_MODVERSIONS` and symbol CRCs, CFI/LTO settings,
`CONFIG_MODULE_SIG*`. Change compiler or LTO mode only as its own isolated, revertible commit,
after a stock rebuild is confirmed booting. If modules stop loading after a toolchain change,
revert that first.

## Build

### Toolchain
Use the exact Clang Samsung's scripts reference (`docs/FACTS.md` §0.5) for the baseline. If the
archive vendors a toolchain under `kernel_platform/prebuilts/`, prefer it. AOSP prebuilts:
`https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/`.

### Invocation
The entry point depends on what shipped (`docs/FACTS.md` §0.2): Kleaf/Bazel
(`build_with_bazel.sh` / `//msm-kernel:<target>_dist`) or legacy `build_kernel.sh`.
`scripts/build.sh` is the single source of truth for the invocation — never hand-run a
different command, or CI and local will diverge.

### Local vs CI
Do not run full builds in the sandbox — insufficient disk. Builds run in GitHub Actions
(`.github/workflows/build.yml`, manual-only). Local work: edits, scripts, grep, log triage.

## Samsung bootability — required before any modified kernel will boot

Two distinct categories. Do not conflate them: one is kernel behaviour we fix in source, the
other is partition-level packaging that has no source representation at all.

### Category A — security protections: fix in SOURCE (we have it; use it)

PROCA, RKP/uH, KDP, DEFEX, FIVE block a modified kernel from booting and block the LKM from
loading. Because we compile the kernel, neutralize each **at the source**, preferring the
cleanest level that works (per §0.4 evidence, decided per symbol):

1. **Defconfig** — drop the `CONFIG_*` symbol when the subsystem can just be turned off.
2. **Targeted C patch** — when the symbol is force-selected elsewhere or disabling it fails to
   link, patch the enforcement function to be inert (e.g. make the check return success / early).
3. **Post-build image patch** — last resort only, for a protection with no workable source
   off-switch.

For PROCA specifically: source-blind tools patch the compiled image — ExtremeROM's script
overwrites the 4-byte config marker at kernel offset 40 with `ef ec ef ec` and `sed`-renames
the `proca_config` symbol string so runtime lookups miss. **Do not copy that approach by
default.** It exists only because the ROM builder had no source. With source, find PROCA's
Kconfig and its enforcement code and disable/patch it there — more correct (you remove the
mechanism instead of tricking it), readable in `git log`, and reviewable. Fall back to the
byte/offset patch only if §0.4 shows PROCA can't be cleanly disabled in source.

One protection per commit, each noting what it guarded and which level (defconfig / C patch /
image) was used and why.

### Category B — genuinely partition-level: stays in `scripts/package.sh`

These are not kernel behaviour and have no source line to change, regardless of source access:

- **SEANDROIDENFORCE.** A literal footer string the *bootloader* looks for on the assembled
  partition image; appended after repack or the image is rejected. Post-packaging by nature.
- **vbmeta / AVB.** A separate signed partition describing others. Nothing in kernel source
  touches it. A modified `boot`/`init_boot` needs verity/verification satisfied or disabled
  (patched `vbmeta`). The custom ROM may already handle this; re-flashing `init_boot` can
  re-trigger it. Confirm in `docs/FACTS.md` §0.6 and `docs/FLASHING.md`.
- **Ramdisk compression.** Samsung ramdisks are often `lz4_legacy`. Repack tooling must match
  the original or first-stage init fails. Detect, don't assume.

magiskboot in `https://github.com/topjohnwu/Magisk` is the canonical implementation of these
image/partition specifics (SEANDROIDENFORCE footer, lz4_legacy, AVB). Read it for Category B;
it is *not* a model for Category A, where we have the source it lacks.

## KernelSU Next — LKM mode into init_boot.img

We build the kernel ourselves, so LKM is viable here (the usual "Knox blocks LKM" applies to
*stock* kernels). Two things make or break it:

1. **Kernel must be built with kprobes.** LKM hooks syscalls at runtime via kprobes. Ensure
   `CONFIG_KPROBES=y` (plus `CONFIG_HAVE_KPROBES`, `CONFIG_KPROBE_EVENTS`) in our defconfig.
   If Samsung disabled them, enabling them is one of our patches.
2. **Build `kernelsu.ko` against OUR kernel.** A generic prebuilt KSU `.ko` will likely refuse
   to load on a Samsung KMI (vermagic / symbol CRC mismatch). Build the KSU Next kernel module
   out-of-tree against our freshly built kernel in the same CI job, so vermagic matches.

Procedure:
- Add KernelSU Next to the tree for the module build:
  `curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -`
  (pin a specific tag rather than floating `next` — record the tag in DECISIONS). Source:
  `https://github.com/KernelSU-Next/KernelSU-Next`, install docs:
  `https://kernelsu-next.github.io/webpage/pages/installation.html`.
- Build `kernelsu.ko` against our kernel output.
- Patch `init_boot.img`: unpack the ramdisk, install the LKM (ksud + the KMI-matched `.ko`)
  into the init sequence, repack with matching compression, re-apply Samsung bootability
  (SEANDROIDENFORCE, vbmeta as needed).
- If `CONFIG_MODULE_SIG_FORCE` is set (`docs/FACTS.md` §0.5), our `.ko` must be signed with the
  kernel's key or module signing must be disabled — otherwise the LKM won't load.

Verify: flash `boot.img` (our kernel) **and** patched `init_boot.img`; KSU Next manager app
should show the module active and grant root. Then re-run the full hardware checklist.

## SUSFS (after KSU Next works)

Source: `https://gitlab.com/simonpunk/susfs4ksu` (GPLv3). It has two parts:
- a **kernel-side patch** on a branch matching our KMI (look for `gki-android14-6.1` or the
  closest tag — confirm against our exact SUBLEVEL), applied into the tree as one of our patches;
- a **userspace/module** side that pairs with a SUSFS-aware KernelSU (KSU Next supports it).

Match the susfs4ksu branch to both the KMI and the KSU Next version; a mismatch fails to apply
or fails at runtime. Treat SUSFS as its own phase after plain KSU Next is confirmed working.

## Packaging

Preferred iteration format: **AnyKernel3 zip** flashed from a root-capable kernel flasher.
Repack checklist — each item, or the device comes up degraded:
1. `Image`/`Image.gz` replaced in `boot.img`; SEANDROIDENFORCE re-appended.
2. Source-built modules replaced in `vendor_dlkm`; stock modules copied through unchanged.
3. `modules.load` / `modules.dep` regenerated consistently.
4. `vendor_boot` first-stage modules handled separately from `vendor_dlkm`.
5. When rooting: patched `init_boot.img` produced and flagged as a separate artifact.
6. vbmeta guidance emitted alongside the artifact if verification must be disabled.

Always keep a known-good stock `boot` / `init_boot` / `vendor_boot` / `vendor_dlkm` set beside
every build so rollback is one flash away.

## Triaging a boot failure

Ask the owner, in order:
1. **Reaches boot animation?** Bootloop before → kernel panic / missing first-stage modules /
   failed AVB. After → userspace or module-load failure.
2. `dmesg` / `logcat` if it boots at all.
3. `/sys/fs/pstore/` after reboot — ramoops usually holds the previous-boot panic.
4. Missing hardware → almost always a `vendor_dlkm` module mismatch, not a kernel bug. Compare
   `lsmod` against `modules.load`.
5. Root missing but device boots → LKM didn't load. Check vermagic match, `CONFIG_KPROBES`,
   module signing, and whether a Samsung protection is still active.

Do not speculate about causes before seeing at least one of these.
