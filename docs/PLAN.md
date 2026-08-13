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

> **Device reality (owner-confirmed, verified against `/proc/config.gz`) — protections come in
> here, not Phase 3.** BeyondROM runs the **stock, unmodified kernel** (its live config has all
> six protections still `=y`), and boots because uH/RKP/KDP are satisfied by the unmodified
> kernel they guard — only PROCA is byte-patched, and Magisk supplies root. But *we* flash a
> **self-built (modified) kernel**, which uH/RKP/KDP detect as tampered → bootloop. So
> **disabling the Samsung boot-blocking protections is part of "the minimum to boot"** for us and
> lives in Phase 1, *before* any KernelSU/SUSFS. (Phase 3 keeps only the LKM-specific pieces.)

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
- [ ] Owner flashes the result

**Exit gate:** device boots on a self-built kernel (protections off, otherwise unmodified), with
**Wi-Fi, Bluetooth, mobile data, S-Pen, camera, and fingerprint all working**. Owner confirms
each. Commit `Verified: boots+all-hw`. Do not proceed on a partial pass — "boots but no
Bluetooth" means the module pipeline is wrong and every later phase inherits the bug.

---

## Phase 2 — Reproducibility hardening

- [ ] Build twice from a clean checkout; confirm identical (or explainably different) output
- [ ] ccache working in CI; build time recorded
- [ ] `docs/FLASHING.md` written, including the rollback procedure and vbmeta steps; tested
      once by deliberately flashing back to stock
- [ ] Capture a baseline for the regression checklist (Phase 5) before any behavioural change

**Exit gate:** owner can flash, break, and recover without assistance.

---

## Phase 3 — Samsung protection neutralization + KernelSU Next (LKM)

This is the core of the project. Order matters: the kernel must first boot modified (Phase 1
already disables the boot-blocking protections) and be able to load an out-of-tree module,
*then* the LKM goes into init_boot.

- [x] Kprobes already enabled by Samsung (`CONFIG_KPROBES=y`, `FACTS §0.5`) — no patch needed.
- [ ] The Samsung boot-blocking protections (UH/RKP/KDP, DEFEX, PROCA, FIVE) are **already
      neutralized in Phase 1** (a self-built kernel can't boot on this device otherwise). Here,
      only address anything that specifically blocks *module loading* if the LKM is rejected —
      chiefly verify `MODULE_SIG_PROTECT=y` does not reject the unsigned `kernelsu.ko`
      (`MODULE_SIG_FORCE` is not set, so it should load). If a targeted C patch is needed, one
      per commit (skill Category A: defconfig → C patch → image patch as last resort).
- [ ] Add KernelSU Next to the tree (pinned tag); build `kernelsu.ko` **against our kernel**
- [ ] `scripts/patch-init-boot.sh` — install the LKM into `init_boot.img` (unpack ramdisk,
      inject ksud + the KMI-matched `.ko`, repack with matching compression, re-apply
      SEANDROIDENFORCE)
- [ ] Add `kernelsu` input to the workflow so CI emits a patched `init_boot.img` artifact
- [ ] Owner flashes `boot.img` + patched `init_boot.img`

**Exit gate:** KSU Next manager shows the module active and grants root, **and** the full
hardware checklist from Phase 1 still passes. Re-verify every item — this is where
regressions hide.

---

## Phase 4 — SUSFS

- [ ] Select the susfs4ksu branch matching our KMI and KSU Next version
- [ ] Apply the SUSFS kernel patch as one of our patches; resolve fallout in-tree
- [ ] Rebuild kernel + KSU `.ko`; repack init_boot with the SUSFS-aware setup
- [ ] Owner flashes and verifies SUSFS features via the manager / `ksu_susfs`

**Exit gate:** SUSFS active, root works, hardware checklist still passes.

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
