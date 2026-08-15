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

---

## 2026-08-12 — Branch model settled: pristine `vanilla` + `main` for work + task branches

**Refines the 2026-08-11 branch-model decision** (which stated "no per-feature branches"), at the
owner's explicit choice among presented options.

**Decided:**
- **`vanilla`** — import-only; pristine Samsung source drops, one per firmware, tagged
  (`osrc/S928BXXU5DZDP`). Nothing of ours ever lands here. Created 2026-08-12 as an orphan branch
  holding exactly `kernel_platform/` + `vendor/` + `build_kernel_GKI.sh` (minus the excluded GCC
  prebuilt and dangling bazel symlinks, per the no-toolchains rule).
- **`main`** — `vanilla` content + everything of ours (scaffolding, docs, scripts, CI, and the
  eventual patch series). **This is what CI builds.**
- **Task branches** — each unit of work on its own short-lived `task/<name>` branch → PR → merge
  into `main`. This supersedes "no per-feature branches"; that earlier rule was about build
  *variants* (toolchain/LTO/KernelSU/SUSFS), which remain **workflow inputs**, not branches.

**Why:** keeps "vanilla" meaning *unmodified*, so re-importing a future Samsung firmware drop is
mechanical — import onto `vanilla`, replay `main`'s series, and fail loudly if a patch no longer
applies. That re-import workflow is the core reason the project is structured this way. Per-task
branches also give the granular, independently reviewable/revertible units the "quantise commits"
rule wants.

**Note on existing history:** `main` was **not** rebased onto `vanilla` retroactively. `main`'s
current history already contains the source import interleaved with our scaffolding (a consequence
of how the repo was bootstrapped under an initial single-branch constraint), and rewriting shared,
already-merged history is not worth the risk. `vanilla` therefore stands as the pristine
reference/base for *future* re-imports rather than a literal git ancestor of today's `main`.

**Would change our mind:** if the patch series grows unwieldy (hundreds of patches), a merge-based
topic-branch model as noted in the 2026-08-11 entry.

---

## 2026-08-12 — Samsung boot-blocking protections are disabled in Phase 1, not Phase 3

**Corrects the original phase split** (which put all protection neutralization in Phase 3
alongside KernelSU), based on the owner's knowledge of their device.

**Decided:** disabling the Samsung protections that block a *self-built* kernel from booting
(UH/RKP/KDP, DEFEX, PROCA, FIVE) is part of Phase 1 — "the minimum required to boot a self-built
kernel" — and happens **before** any KernelSU Next / SUSFS work, even for a plain no-root test
build.

**Why (precise mechanism, confirmed by the device's `/proc/config.gz`):** BeyondROM runs the
**stock, unmodified kernel** — its live config shows all six protections still `=y` (kernel
6.1.145, clang r487747c, `CONFIG_LTO_NONE=y`), i.e. BeyondROM disabled *none* of them in the
kernel. It boots anyway because uH/RKP/KDP are satisfied by the *unmodified* kernel they guard;
the only Samsung block on a modified *system* (not the kernel), PROCA, is neutralized by a
post-build byte-patch (the source-blind method), and Magisk supplies root. **Our case differs:**
we flash a *self-built, modified* kernel — uH/RKP/KDP will see it as tampered and bootloop. So we
must disable uH/RKP/KDP (which BeyondROM never had to, keeping the stock kernel) as well as
DEFEX/PROCA/FIVE. Owner-confirmed a raw self-built kernel won't boot here; there is no useful
"unmodified boots" baseline, so the first flashable build already has these off.

**How:** each protection is its own commit (bisectability), at the defconfig level where
possible (`FACTS §0.4` shows none are force-selected, so defconfig off-switches suffice as the
first approach). If a bootloop remains after disabling all of them, bisect by re-enabling one at
a time.

**Consequence for Phase 3:** Phase 3 no longer re-does protection neutralization; it covers only
the KernelSU-LKM-specific pieces (kprobes are already on; verify `MODULE_SIG_PROTECT` doesn't
reject the unsigned `.ko`; inject the LKM into `init_boot`).

**Cannot be pre-verified (no device):** which exact subset is strictly necessary to boot is
unknown until flashed; we disable all six and let the first flash confirm. Standard practice for
Samsung custom kernels aligns with the owner's assessment.

**Would change our mind:** the first flash shows some protection can stay on without blocking
boot — then re-enable it (smaller blast radius is better) and record which.

---

## 2026-08-14 — Flashing format is AnyKernel3 (recovery zip); osm0sis's engine is vendored, not modified

**Decided (owner's choice):** the primary way we flash our self-built kernel is an **AnyKernel3
zip** flashed from a custom recovery (TWRP/OrangeFox). A pre-built `boot.img` and its Odin
`boot.tar.md5` wrapper remain as the no-recovery fallback (and `boot.img` is the input AnyKernel3
wraps). This matches the e3q-kernel skill's stated preferred iteration format.

**Why AnyKernel3 for the first-boot test:** on-device it unpacks the *current* `boot.img`, swaps
in only our kernel `Image`, repacks with matching compression, and re-applies `SEANDROIDENFORCE`
and the vbmeta flag by itself. So the flash changes exactly the kernel and nothing else — fewer
moving parts than shipping a hand-assembled `boot.img`, and it adapts to whatever is currently in
the boot partition.

**How it's vendored (owner constraint: do not modify his scripts):**
- `osm0sis/AnyKernel3` is added as a **git submodule** at `anykernel3/`, pinned to commit
  `e4b1bb2`. His flashing engine (`tools/`, `META-INF/.../update-binary`, `magiskboot`,
  `ak3-core.sh`) is included **verbatim** and is never edited by us. Pinning (not floating
  `master`) keeps builds reproducible and prevents an upstream change from silently altering how
  we write the boot partition.
- Our device configuration lives in a **separate file we own**, `anykernel/anykernel.sh` — a copy
  of his template changed only where the device requires: `kernel.string`; `device.name1=e3q`
  (his were Galaxy-Nexus codenames, and `do.devicecheck=1` is kept); `BLOCK=boot`;
  `IS_SLOT_DEVICE=auto` (S24 Ultra is A/B); and removal of his `init.rc`/`init.tuna.rc`/
  `fstab.tuna` demo ramdisk patches (they target files that don't exist on this phone and would
  make the flash error). The install reduces to his default `dump_boot; write_boot;`. Nothing
  else is changed.
- `scripts/package.sh` assembles the zip = his engine (from the submodule) + our `anykernel.sh` +
  our `Image`, and self-checks that the result carries our e3q config, our kernel, and his engine
  (and that no demo config leaked). CI already checks out submodules recursively, so no workflow
  change was needed to fetch it.

**Cannot be pre-verified (no device):** that the zip flashes and boots is proven only on the
device. The device-check name (`e3q`) is from the repo's ground truth; if the owner's recovery
reports a different codename the flash aborts harmlessly and we correct the one line.

**Would change our mind:** the owner has no working custom recovery → the Odin `boot.tar.md5`
fallback becomes primary, but the AnyKernel3 zip stays for when a recovery is available.

---

## 2026-08-14 — e3q is 64-bit-only: AnyKernel3 needs arm64 tools; raw-image flashing is simplest

**Trigger:** the first AnyKernel3 flash (build #6) aborted in the owner's TWRP:
`/tmp/anykernel/tools/busybox: not executable: 32-bit ELF file` → `Busybox setup failed. Aborting...`.

**Cause (not the owner's TWRP):** `osm0sis/AnyKernel3` bundles **32-bit ARM** tools (busybox,
magiskboot, magiskpolicy, httools_static — all verified 32-bit). The S24 Ultra is a **64-bit-only**
device — its recovery log shows `ro.product.cpu.abilist32=` empty — so it cannot exec 32-bit
binaries, and AK3 aborts before writing anything. (Nothing was flashed; TWRP even made a
Boot/Init_boot/Vendor_boot backup first.)

**Decided:**
1. **`scripts/package.sh` overlays arm64 tools into the AK3 zip**, taken from a pinned, checksummed
   Magisk release (**v28.1**, sha256 `8bfd3346…`; its `lib/arm64-v8a/lib{busybox,magiskboot,
   magiskpolicy}.so` are ELF 64-bit AArch64). Only the tool **binaries** are swapped — osm0sis's
   scripts stay unchanged (consistent with the 2026-08-14 AnyKernel3 vendoring decision). The AK3
   self-check now asserts the tools are 64-bit AArch64 ELF, so a 32-bit-tools zip can't ship again.
   On a Magisk fetch/verify failure the AK3 zip is skipped, not shipped broken.
2. **The documented simplest flash is TWRP → *Install Image* → raw `boot.img` → Boot partition**
   (`FLASHING.md` §3a) — it needs no on-device busybox/magiskboot at all, and our `boot.img` is
   already the finished image (kernel-only boot, so equivalent to what AK3 would repack). The
   AnyKernel3 zip (§3b, build ≥ #7) and Odin `boot.tar.md5` (§4) are alternatives.

**Consequence for Phase 3 (KernelSU LKM in init_boot):** prefer building the patched `init_boot.img`
in CI (arm64 Linux magiskboot) and flashing it raw via *Install Image*, rather than relying on
on-device tools — the same 64-bit-only constraint applies to any recovery-side repack.

**Would change our mind:** a newer upstream AnyKernel3 that ships arm64 (or dual-arch) tools would
let us drop the Magisk overlay and just bump the submodule pin.

---

## 2026-08-14 — Disable `CONFIG_MODULE_SIG_PROTECT` (protection #7): stock GKI modules need it off

**Trigger:** on the first clean boot of our protections-off kernel (Magisk modules disabled, so it
booted without the timer-triggered bootloop), Wi-Fi, Bluetooth and Hotspot were dead while
NFC/GPS/mobile-data worked. Loaded-module count was **480 vs the stock baseline's 541**; the 61
missing were exactly the GKI network-protocol modules and dependents (`cfg80211`, `mac80211`,
`qca_cld3_kiwi_v2`, `wonder`, `bluetooth`, `hci_uart`, `rfkill`, `nfc`, `can*`, `ieee802154*`,
`tipc`, `l2tp*`, `ppp*`, `usbnet…`). Userspace: `wificond: Failed to get NL80211 family info`.

**Cause (source-confirmed):** `CONFIG_MODULE_SIG_PROTECT=y` ("Android GKI module protection") adds
two `-EACCES` gates keyed on `mod->sig_ok` — a module not signed by *this kernel's* key is refused
if it exports (or, symmetrically, imports) a protected GKI KMI symbol
(`kernel/module/main.c:1298` and `:1128`; `sig_ok` set in `signing.c:96`). Our build signs modules
with its **own auto-generated key** (`CONFIG_MODULE_SIG_KEY` unset, no pinned `certs/signing_key.pem`,
no `CONFIG_SYSTEM_TRUSTED_KEY`). The owner kept the **stock, Samsung-signed** `system_dlkm`, so those
GKI modules fail `sig_ok` on our kernel and are rejected; everything depending on them cascades. The
480 vendor modules load because they export only non-protected vendor symbols. (This is the gate the
FACTS §0.3.1 module-compat analysis had missed — it reasoned only about vermagic/CRC/undefined
symbols, which were genuinely fine.)

**Decided:** neutralize it at level 1 (defconfig), consistent with the other six protections:
`# CONFIG_MODULE_SIG_PROTECT is not set` in `gki_defconfig`. With it off, the two helper predicates
become inert stubs (`kernel/module/internal.h:311-317`: protected-export → `false`,
unprotected-symbol → `true`) and `gki_module.o` is dropped (`Makefile:13`); foreign-signed stock
modules then load with a benign `TAINT_UNSIGNED_MODULE` notice. `MODULE_SIG` stays `=y`,
`MODULE_SIG_FORCE` stays off. Nothing force-selects the symbol, so the off-switch is clean.

**Why this over flashing our own modules:** flashing our *matched* `system_dlkm.img` +
`vendor_dlkm.img` (signed with our key) would also work with the protection left on, but those are
logical partitions inside `super` — far riskier to flash via TWRP on a no-PC device — and it is a
much larger change than one defconfig line. Held as the fallback if disabling ever breaks the build.

**Bonus:** the same gate would have rejected the out-of-tree `kernelsu.ko` in Phase 3 (an open
question in FACTS). Disabling it now clears that too.

**Would change our mind:** if disabling `MODULE_SIG_PROTECT` breaks the Kleaf/ABI build, drop back to
a level-2 C patch (make `gki_is_module_protected_export()` return false) or to the matched-modules
flash. Verification is still pending a real flash: re-flashed `boot.img`, `lsmod | wc -l` ≈ 541, and
Wi-Fi/BT/Hotspot toggling on.

---

## 2026-08-14 — Verify hardware health explicitly; don't infer it from "it booted" or lsmod

**Trigger:** twice now a subsystem was reported working when it was not. First the Wi-Fi/BT
breakage was found only because the owner tested the radios; then audio (playback + recording)
turned out broken even though every audio module loads and the kernel boots. The gap: "it
booted" and "the .ko is in lsmod" do not imply the hardware works — a driver can load and still
fail to bring up its device (the audio HAL aborts at mixer init with a full sound-card set
loaded). Diagnosing after the fact was also hobbled because the captures missed the state that
matters (sound card, DSP state, early dmesg).

**Decided:** build verification in three layers instead of eyeballing logs.

1. **On-device PASS/FAIL self-test — `scripts/verify-hw.sh`.** Tests the *result*, not the
   module list: every module in the device's own `modules.load` actually loaded; a real ALSA
   sound card + PCM devices exist (`/proc/asound`); every remoteproc DSP is `running`; no
   tombstone since boot; key HAL `init.svc.*` are running; a `wlan*` netdev exists; dmesg red
   flags. Prints a verdict on the phone. Would have flagged both the 61 blocked net modules
   and the dead sound card on sight.
2. **Better raw capture — `collect-logs.sh`** now grabs `/proc/asound`, remoteproc state,
   `init.svc`, filtered audio dmesg, and `/data/log/dumpstate_booting_delay.zip` (the full
   early-boot dmesg the ring buffer overwrites), so a probe/HAL failure can actually be
   root-caused next time instead of guessed.
3. **Build-time config gate — `scripts/check-defconfig-parity.sh` in CI.** Fails the build if
   `gki_defconfig` changed any symbol outside the protection allowlist (UH, RKP, KDP,
   SECURITY_DEFEX, PROCA, FIVE, MODULE_SIG_PROTECT) vs the vanilla import. This is the machine
   check for "we only compiled vanilla source with protections off."

**Honest limits (stated so they aren't mistaken for guarantees):** none of this proves the
device is perfect — only a real flash + hands-on test does. The config gate checks the source
defconfig, not the final built `.config` (Kconfig deps can ripple; that is checked on-device
against `/proc/config.gz`). verify-hw.sh checks the subsystems it knows to check; a failure it
has no probe for still needs the owner to notice. The goal is to shrink the "reported working
but wasn't" gap, not to claim it is zero.

**Would change our mind:** if a lighter check (e.g. parsing a single Samsung boot self-test)
covered the same ground, prefer it. If the final-`.config` vs `/proc/config.gz` diff can be run
in CI cheaply, promote that to the build gate too.

---

## 2026-08-14 — Prove "only protections changed" mechanically; prefer minimal/surgical neutralization

**Context:** the owner pushed back on fixing hardware subsystem-by-subsystem as failures
surface (networking, then audio). The premise of Phase 1 — compile *vanilla* Samsung source,
change only what's needed to boot — should be *enforced and verified universally*, not
eyeballed and discovered on the device.

**Decided — two-layer config parity, whole-config:**
- **Source gate** (`check-defconfig-parity.sh`, CI, before the build): the defconfig differs
  from the vanilla import only by the allowlisted protection symbols.
- **Built/running gate** (`check-config-parity.sh`, in `build.sh` on the extracted config and
  in `verify-hw.sh` on `/proc/config.gz`): the *final* config differs from the stock baseline
  (`docs/baseline/config-S928BXXU5DZDP.stock`) only by the allowlisted protection family —
  across all ~6100 symbols, so a Kconfig `select`/`depends` ripple that silently drops *any*
  driver (codec, sensor, fs, netdev) fails the build instead of surfacing as dead hardware.
  Validated against the real Build-#7 running config: exactly 47 differing symbols, all in the
  protection family, zero additions.

**Decided — neutralization principle (from the Magisk cross-check, FACTS §0.4.1):** prefer the
**minimal, most surgical** off-switch that still boots, over a blanket one. Magisk keeps µH
running and only un-enforces RKP; we currently remove `CONFIG_UH` wholesale, which is the
prime suspect for the audio (ADSP) breakage. When a protection's blanket removal breaks a
firmware-coupled subsystem, drop to a narrower level (keep the subsystem present, neuter only
the enforcement) or restore the generic capabilities it collaterally disabled (e.g. FIVE →
`CONFIG_SIGNATURE`/`INTEGRITY_*`). Do not disable *more* than the minimum, and isolate each
protection's effect rather than guessing.

**Honest limit:** parity proves we changed only the protections; it does **not** prove the
device works, because the protections we *do* disable have runtime effects (that is the audio
bug). Config parity + `verify-hw.sh` (runtime) + a real flash together are the check — none
alone is sufficient.

**Would change our mind:** if a Samsung boot self-test or a single vendor health signal
covered the runtime side as well as `verify-hw.sh`'s probes, prefer it.

---

## 2026-08-15 — Phase 3: pin KernelSU Next v3.3.0 (LKM mode), KMI android14-6.1

**Decided:** integrate **KernelSU Next `v3.3.0`** (released 2026-07-03) in **LKM mode**, built
against our own kernel. Pinned tag, not the floating `next` branch.

**Why v3.3.0:**
- It ships an **`android14-6.1_kernelsu.ko`** asset — our exact KMI (kernel 6.1.145,
  `android14-6.1`), confirming this generation is supported.
- LKM mode has been supported since v1.0.8; v3.x is the current line with a matching manager app.
- Latest stable (non-prerelease) at decision time, so the manager and the module match.

**Why LKM (not GKI-integrated KSU):** we already did the hard part in Phase 1 — a self-built,
protections-off kernel that boots and loads foreign modules. LKM keeps KSU as a `.ko` in
`init_boot`, leaving `boot.img` = pure protections-off kernel. That preserves the clean Phase-1
baseline and keeps root a separate, independently-flashable/revertible artifact.

**Prerequisites already met (no extra kernel patch needed):**
- `CONFIG_KPROBES=y` (FACTS §0.5) — LKM syscall hooks work.
- `MODULE_SIG_FORCE` not set, and `MODULE_SIG_PROTECT` now **off** (protection #7, 2026-08-14) —
  an unsigned `kernelsu.ko` built against our kernel will load. (This is the payoff of that fix:
  the same gate that rejected the stock Wi-Fi modules would have rejected `kernelsu.ko`.)

**Build sequence:**
1. Add KSU Next (pinned v3.3.0) to the tree; build `kernelsu.ko` **in the same CI job**, against
   our kernel output, so vermagic/CRC match. (No device needed — verifies the `.ko` builds.)
2. Obtain the **stock** `init_boot.img` (owner's BeyondROM firmware) as the patch base — it is
   firmware, not committed to the repo.
3. `scripts/patch-init-boot.sh`: unpack the ramdisk (detect compression — FACTS open item says
   source default `lz4`, confirm on the real image), inject `ksud` + the KMI-matched `.ko` into
   the init sequence, repack with matching compression, re-apply SEANDROIDENFORCE (+ vbmeta as
   needed).
4. Add a `kernelsu` workflow input emitting a patched `init_boot.img` artifact.
5. Owner backs up their current (Magisk) `init_boot`, flashes our `boot.img` + patched
   `init_boot.img`, verifies KSU manager shows root, then re-runs the full REGRESSION.md checklist.

**Rollback:** `init_boot` is separate from `boot`; the owner's existing Magisk `init_boot` (backed
up first) restores their current setup in one flash. `boot.img` (Build #9) is unaffected.

**Would change our mind:** if v3.3.0's `.ko` fails to load or fails the hardware checklist, drop
to the prior stable tag or investigate vermagic/kprobes before proceeding to SUSFS (Phase 4).
