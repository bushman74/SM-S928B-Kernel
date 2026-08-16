# Plan

Phases are sequential. Each has an **exit gate** that requires a real flash on real hardware.
No phase begins before the previous gate passes.

---

## Phase 0 — Discovery

**Goal:** know what we actually have, with zero assumptions. Deliverable: a filled-in `docs/FACTS.md`.

- [ ] Obtain the SM-S928B source archive; record the firmware build string
- [ ] Extract to scratch (outside the repo); map the directory layout
- [ ] Determine build system: Kleaf/Bazel vs legacy
- [ ] Identify the e3q defconfig / bazel target by name
- [ ] Record exact kernel VERSION/PATCHLEVEL/SUBLEVEL and `CONFIG_LOCALVERSION`
- [ ] Transcribe Samsung's shipped build instructions verbatim
- [ ] Identify the reference Clang version
- [ ] Confirm partition layout: is there a separate `init_boot`? Where does the ramdisk live?
- [ ] Record ramdisk compression (lz4_legacy?) and whether SEANDROIDENFORCE footer is present
- [ ] Record vbmeta / AVB situation and what the custom ROM already disables
- [ ] Pull `modules.load` + `ls /vendor/lib/modules/` from the device; build the module
      inventory table (buildable-from-source vs must-reuse-stock)
- [ ] Locate Samsung security modules; record their real `CONFIG_` symbols and paths
- [ ] Record `CONFIG_KPROBES`, `CONFIG_MODVERSIONS`, `CONFIG_CFI_CLANG`, `CONFIG_LTO_*`,
      `CONFIG_MODULE_SIG*`
- [ ] Fill in `docs/FACTS.md` completely; mark unknowns `TBD`, do not guess

**Exit gate:** owner has read `docs/FACTS.md` and confirmed it. No `TBD` in *(blocking)* fields.

---

## Phase 1 — Reproducible stock build that boots

**Goal:** compile Samsung's source and boot it with all hardware working, changing only the
minimum required to make a *self-built* kernel boot on **this** device.

> **Device reality — why the protections come off in Phase 1, not later.** We flash a **self-built
> (modified) kernel** built from pristine Samsung source, where uH/RKP/KDP/DEFEX/PROCA/FIVE are on
> by default; those protections accept only Samsung's own signed kernel and bootloop a modified one.
> So **disabling the Samsung boot-blocking protections is part of "the minimum to boot"** for us and
> lives in Phase 1. (Correction, 2026-08-17: an earlier version of this note claimed BeyondROM's
> *own* kernel runs these `=y` — the device config dump proved otherwise. BeyondROM ships them
> **off** — no `MODULE_SIG_*`, none of UH/RKP/KDP/DEFEX/PROCA/FIVE `=y` — `FACTS §0.6`, which is
> exactly why plain KSU root loads on BeyondROM's kernel without ours.)

- [x] Import the archive to `vanilla`; tag `osrc/<build-string>` (done: `osrc/S928BXXU5DZDP`)
- [x] `scripts/setup-toolchain.sh` — fetch the reference Clang + prebuilts (green in CI)
- [x] `scripts/build.sh` — the single canonical build invocation (compiles, CI run #2)
- [x] **Disable the Samsung boot-blocking protections — UH/RKP/KDP, DEFEX, PROCA, FIVE —
      one per commit**, at the defconfig level where possible (symbols/evidence: `FACTS §0.4`,
      none are force-selected). Granular commits so a bootloop can be bisected to one protection.
      *(done: PR #9, one commit per protection; CI build #3 extracts the built kernel's config
      and confirms all six are `off` — see `build.sh` verification step.)*
- [x] `scripts/package.sh` — repack to a flashable `boot.img` (+ SEANDROIDENFORCE / vbmeta
      handling as needed). Simplest first flash: our `boot.img` only, keeping stock modules.
      *(done: mkbootimg header-v4 + SEANDROIDENFORCE; sandbox-verified byte-identical to the
      stock boot.img through the footer. The CI-produced artifact from a fresh build is the
      next trigger — build #4.)*
- [x] `.github/workflows/build.yml` green (manual trigger)
- [x] Owner flashes the result *(done: Build #9 — boots, all hardware working incl. audio)*

**Exit gate:** device boots on a self-built kernel (protections off, otherwise unmodified), with
**Wi-Fi, Bluetooth, mobile data, S-Pen, camera, and fingerprint all working**. Owner confirms
each. Commit `Verified: boots+all-hw`. Do not proceed on a partial pass — "boots but no
Bluetooth" means the module pipeline is wrong and every later phase inherits the bug.

**Status: MET (Build #9).** Boots + Wi-Fi/BT/mobile-data/S-Pen/camera/fingerprint **and audio**
confirmed on hardware (`docs/FACTS.md` §0.3.2; baseline in `docs/REGRESSION.md`).

---

## Phase 2 — Reproducibility hardening

- [~] Build twice from a clean checkout; confirm identical output *(reproducibility timestamps
      pinned in the workflow; full double-build diff not yet re-run)*
- [x] ccache working in CI; build time recorded *(configured in `build.yml`)*
- [x] `docs/FLASHING.md` written, including the rollback procedure and vbmeta steps; tested
      once by deliberately flashing back to stock *(done: owner's stock A/B was exactly this)*
- [x] Capture a baseline for the regression checklist (Phase 5) before any behavioural change
      *(done: `docs/REGRESSION.md`, Build #9)*

**Exit gate:** owner can flash, break, and recover without assistance.

**Status: MET.** Owner has flashed, reverted to stock, and re-flashed unaided (the stock A/B that
tested `FLASHING.md`).

---

## Phase 3 — KernelSU Next root

**Status: root ACHIEVED (2026-08-16) — exit gate MET.** The owner reached working KernelSU-Next root
by patching `init_boot` with the KSU-Next **manager** and flashing it, running on **BeyondROM's own
kernel** — which already ships the six protections off + module loading (`FACTS §0.6`, config dump:
`KPROBES=y`, no `MODULE_SIG_*`, none of UH/RKP/KDP/DEFEX/PROCA/FIVE `=y`). So **root did not need our
custom kernel**, and the from-source KSU pipeline we had built for it (an in-tree `CONFIG_KSU=m`
`.ko` build + `scripts/patch-init-boot.sh` + a `kernelsu` workflow input) went unused and has been
removed (`DECISIONS.md` 2026-08-17).

- [x] Kprobes already enabled by Samsung (`CONFIG_KPROBES=y`, `FACTS §0.5`) — no patch needed.
- [x] `MODULE_SIG_PROTECT` off so an unsigned `kernelsu.ko` can load *(done in Phase 1: protection
      #7 — and, as it turned out, BeyondROM's kernel already has it off, which is where root loaded)*.
- [x] Root installed on-device: patch `init_boot` with the KSU-Next manager and flash it.

**Exit gate:** KSU Next manager shows the module active and grants root, **and** the full
hardware checklist from Phase 1 still passes. **→ MET 2026-08-16** (manager shows `KernelSU: 33214`,
LKM active, root granted, hardware unaffected). One minor upstream bug: the manager's in-app
*Reboot* seccomp-crashes ksud on Android 16 (`FACTS §0.6`) — use the power menu.

---

## Phase 4 — SUSFS *(paused)*

**Wound down 2026-08-17.** SUSFS's author confirmed it is **incompatible with KernelSU's LKM mode**
for now (a performance trade-off) and plans to revisit it later. Since root here runs in LKM mode,
SUSFS is dropped from scope until that changes. All SUSFS artifacts and the from-source KSU pipeline
that would have carried it have been removed (`DECISIONS.md` 2026-08-17). If SUSFS becomes
LKM-compatible, the custom kernel (Build #9 — device-verified, all hardware working) is the base it
would build on.

---

## Phase 5 — Regression checklist (set up in Phase 2, used at every gate)

Not a perf-optimization program (there is no CLO work now) — a guard against silent breakage.
At each gate the owner confirms: boots; Wi-Fi; Bluetooth; mobile data; S-Pen; camera;
fingerprint; SafetyNet/Play Integrity status unchanged or as expected; no new bootloader
warning screens; battery/thermals not obviously worse under a fixed workload.

Record results in `docs/MEASUREMENTS.md` against the commit SHA.

---

## Explicitly out of scope (for now)

- **Qualcomm CLO backporting** — dropped 2026-08-11. No CLO remotes, no cherry-picks. Reopen
  only via a new DECISIONS entry.
- **AutoFDO** — dropped. No android14-6.1 profiles upstream; self-profiling needs ARM
  ETE/TRBE trace likely fused off on retail hardware.
- **Kernel version bumps** beyond LTS SUBLEVEL — breaks stock module ABI.
