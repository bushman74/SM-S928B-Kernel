# Decisions

Append-only. Newest at the bottom. Each entry: date, decision, reasoning, and what would
change our mind. Read this before reopening a settled question.

---

## 2026-08-11 — Branch model: `vanilla` + patch series, not per-feature branches

**Decided:** `vanilla` is import-only (one commit per Samsung OSRC drop, tagged by firmware
build string). Our changes live as a rebasable patch series replayed onto it. Build variants
(toolchain, LTO mode, KernelSU on/off, later SUSFS) are GitHub Actions workflow inputs.

**Why:** Samsung ships tarballs, not git history, so "vanilla" can only be import commits.
Long-lived feature branches would each need reconciling against every firmware drop; a patch
series replays mechanically and fails loudly when it doesn't apply. Variant-as-branch
multiplies that cost by the number of variants.

**Would change our mind:** if the patch series grows past a few hundred patches and replay
stops being mechanical, a merge-based topic-branch model becomes worth the overhead.

---

## 2026-08-11 — AutoFDO: out of scope

**Decided:** not pursuing AutoFDO.

**Why:** Google publishes kernel AutoFDO profiles for `android16-6.12` and `android15-6.6`,
not `android14-6.1` (our baseline). Their optimization targets `vmlinux`, not the vendor `.ko`
modules where much of this SoC's hot code lives. Self-collecting profiles needs ARM ETE/TRBE
hardware trace via simpleperf (done on Pixel); on retail Snapdragon, CoreSight is commonly
fused off.

**Would change our mind:** `ls /sys/bus/coresight` showing usable trace hardware, plus a 6.1
profile appearing upstream.

---

## 2026-08-11 — Toolchain: reference Clang first, bumps as isolated commits

**Decided:** Phase 1 uses the exact Clang Samsung's scripts reference. Any newer toolchain is
introduced later as its own revertible commit.

**Why:** stock `.ko` we cannot rebuild must still load against our kernel. Compiler, LTO mode,
and CFI settings are ABI-relevant; bundling a toolchain change into another change makes
"modules stopped loading" impossible to attribute.

**Would change our mind:** once every module in `modules.load` is confirmed buildable from
source, the ABI constraint relaxes.

---

## 2026-08-11 — Qualcomm CLO backporting: dropped for now

**Decided:** removed from scope. No CLO remotes, no cherry-picks, no CLO-related files.

**Why:** owner chose to focus on a working rooted kernel first (vanilla → KSU Next → SUSFS).
CLO backporting is high-effort, firmware-coupling-prone, and better attempted once the base is
stable — if at all.

**Would change our mind:** a stable Phase 4 result plus a specific, measured motivation to
backport a scoped subsystem. Reopen with a new entry here first.

---

## 2026-08-11 — KernelSU Next via LKM into init_boot (not built-in)

**Decided:** integrate KernelSU Next in **LKM mode**, patched into `init_boot.img`, rather than
compiling it into the kernel.

**Why:** owner's choice; keeps root decoupled from the kernel (manager/module updatable without
a kernel rebuild) and matches KSU Next's recommended install flow. The usual "Knox blocks LKM"
objection applies to *stock* kernels — since we build the kernel, we can enable kprobes and
neutralize the protections that block module loading, which makes LKM viable.

**Consequences (must hold or LKM won't load):**
- Kernel built with `CONFIG_KPROBES=y` (+ `HAVE_KPROBES`, `KPROBE_EVENTS`). LKM hooks via kprobes.
- `kernelsu.ko` built **against our kernel** so vermagic/KMI matches; a generic prebuilt will
  likely be rejected by the Samsung KMI.
- If `CONFIG_MODULE_SIG_FORCE` is set, the `.ko` is signed with the kernel key or signing is
  disabled.
- KSU Next pinned to a specific tag (record the tag when chosen), not floating `next`.

**Would change our mind:** if the Samsung KMI makes a loadable KSU module impractical despite
neutralized protections, fall back to built-in integration (source hooks). Record the switch here.

---

## 2026-08-11 — Security neutralization in source; only SEANDROIDENFORCE + vbmeta post-build

**Supersedes an earlier draft** that had defaulted PROCA/RKP/KDP/DEFEX to post-build image
patches. That was wrong: it copied the approach of source-blind tools (Magisk, ExtremeROM)
into a project that has the full source.

**Decided:** two categories, handled at different levels.
- **Category A — security protections (PROCA, RKP/uH, KDP, DEFEX, FIVE):** neutralize in
  source. Preference order per symbol: defconfig off-switch → targeted C patch of the
  enforcement function → post-build image patch only when source has no workable off-switch.
- **Category B — SEANDROIDENFORCE footer and vbmeta/AVB:** stay as post-build steps in
  `scripts/package.sh` / `patch-init-boot.sh`. These are partition/bootloader-level, not kernel
  behaviour; no source line produces them regardless of source access. Ramdisk compression
  (lz4_legacy) is likewise a packaging concern.

**Why:** ExtremeROM's PROCA `sed` renames a symbol string and pokes kernel offset 40 because
the builder had no source to recompile. With source we disable PROCA's Kconfig or patch its
check directly — removing the mechanism instead of tricking it, visible in `git log`, and
reviewable. Only the genuinely image-level pieces belong in packaging.

**Would change our mind:** per-symbol, if §0.4 shows a specific protection is force-selected
and disabling it breaks the build *and* a clean C patch is impractical, that one protection
drops to a post-build image patch — recorded as its own note, not a blanket policy change.
