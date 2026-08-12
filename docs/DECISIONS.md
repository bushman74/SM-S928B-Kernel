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

---

## 2026-08-12 — Platform is Android 16; the kernel KMI is still `android14-6.1`

**Decided:** treat `android14-6.1` as the KMI generation for every KMI-sensitive choice (SUSFS
branch = `gki-android14-6.1`, prebuilt/module matching), independent of the platform Android
version.

**Why:** the source drop `S928BXXU5DZDP` is an **Android 16 / One UI 8** firmware (archive name
`..._16_...`; `README_Platform.txt`: "Android 16.0"), but its GKI kernel is **6.1.145** with
`BRANCH=android14-6.1` (`kernel_platform/common/build.config.constants:1`). "android14-6.1" is a
GKI KMI generation string, not the platform version — GKI keeps a frozen KMI across Android
releases. The "Android 14" phrasing in `CLAUDE.md`/`PLAN.md` is imprecise but harmless; this note
exists so it isn't mistaken for a stale source drop or re-investigated.

**Would change our mind:** a future drop whose `build.config.constants` shows a different `BRANCH`.

---

## 2026-08-12 — Device baseline BeyondROM 5.0 (DZDP); rollback is the stock DZDP firmware

**Decided:** the working baseline is the owner's **BeyondROM 5.0**, firmware base **DZDP**, which
matches this source drop (`S928BXXU5DZDP`). The rollback/recovery path we rely on is the **official
stock DZDP firmware flashed via Odin**, not Magisk's restore.

**Why:**
- **ABI match.** Building from DZDP source against a device already on DZDP keeps our kernel aligned
  with the vendor modules and the rest of the ROM. (If BeyondROM is later updated — the XDA thread
  already lists a DZG1 build — we want the matching source drop before rebuilding.)
- **AVB is already handled.** The ROM ships a patched/disabled `vbmeta` (owner-confirmed), so a
  self-built `boot`/`init_boot` boots without an extra AVB step, as long as a stock `vbmeta` is never
  re-flashed over it.
- **Magisk restore is not a sufficient rollback for this project.** Root is currently Magisk Alpha
  (`e8a58776-alpha`, a closed-source fork), which the owner will remove before KernelSU Next. Magisk
  only backs up `boot`/`init_boot`. Our module pipeline also repacks `vendor_boot`/`vendor_dlkm`
  (inside `super`), which Magisk never touches — so only the stock firmware can undo a bad module
  flash.

**Consequence (blocking before the first flash, not before build work):** obtain and stash the stock
`S928BXXU5DZDP` firmware (keep `AP_*.tar.md5`) off-device. This is the guaranteed recovery.

**Would change our mind:** owner produces verified independent backups of all four partitions
(`boot`/`init_boot`/`vendor_boot`/`vendor_dlkm`) for DZDP by other means.

---

## 2026-08-12 — Root is KernelSU **Next** (LKM), following its own install flow

**Decided (reaffirming the 2026-08-11 LKM decision with the correct project):** the root solution is
**KernelSU Next** (`github.com/KernelSU-Next/KernelSU-Next`), **not** upstream KernelSU. Our kernel is
GKI 2.0 with a stable KMI, so we use KSU Next's **LKM install path** (module into `init_boot`), per
`kernelsu-next.github.io/webpage/pages/installation.html`.

**Why:** owner specified KernelSU Next explicitly. LKM mode fits a GKI kernel and keeps root
updatable without a kernel rebuild. KSU Next's non-GKI *built-in* integration guide
(`.../how-to-integrate-for-non-gki.html`) is the **fallback** already recorded on 2026-08-11 (source
hooks compiled in) — reached only if a loadable `.ko` proves impractical on the Samsung KMI despite
neutralized protections. §0.5 evidence is favourable to LKM: `KPROBES=y`, signing not forced.

**Would change our mind:** the LKM refuses to load on our built kernel (vermagic/KMI or
`MODULE_SIG_PROTECT`) → switch to KSU Next built-in integration; record it here.

---

## 2026-08-12 — Clarification: we did NOT switch compilers, and nothing became "less Samsung"

**Recorded to prevent a recurring misunderstanding, not because a choice changed.**

There is a natural assumption that "fetching clang from Google (android.googlesource.com)" means
we *swapped* Samsung's compiler for Google's, e.g. to chase performance. That is not what
happened, and it is worth stating plainly:

- **It is the same compiler Samsung uses.** Samsung's own build config names the exact toolchain:
  `CLANG_VERSION=r487747c` (`kernel_platform/common/build.config.constants:2`). Samsung does not
  ship a compiler of their own — their build downloads AOSP's clang prebuilt, the same one we
  fetch. The OSRC drop simply omits `prebuilts/` (it says so in `README_Kernel.txt`: "get the
  toolchain … decompress in `kernel_platform/prebuilts`"), so `scripts/setup-toolchain.sh` fetches
  clang `r487747c` — the version Samsung specifies — from the android14-6.1 manifest. No newer or
  different compiler is substituted.
- **No performance/battery change results from this**, because there is no compiler change. Same
  clang, same version, same flags Samsung's config sets. The build is maximally Samsung-faithful.
- **The kernel was already GKI.** Samsung's S24 kernel is GKI 2.0 (KMI `android14-6.1`) by design;
  we did not "turn it into GKI." Nothing we have done makes it less Samsung-intended — as of this
  writing we have neutralized zero Samsung protections (that is Phase 3).

**Why the reference compiler is pinned (not upgraded):** the stock `.ko` modules we do not rebuild
must keep loading against our kernel; compiler/LTO/CFI are ABI-relevant, so a *different* clang
risks breaking module loading. That is the whole point of the 2026-08-11 "reference Clang first"
decision.

**Would change our mind (path to real compiler-based optimization, if desired later):** §0.3 now
confirms **all 351 device modules build from source**, which relaxes the ABI constraint the pin
protects. So a *deliberate, isolated, revertible* experiment with a newer clang and/or LTO tuning
(thin→full) for performance/battery becomes reasonable **after** a known-good stock baseline boots
and is verified. It would be its own phase with before/after measurements, not a silent swap.
(AutoFDO, the other compiler-driven optimization, was already evaluated and dropped — see
2026-08-11.)
