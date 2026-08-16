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

## Phase 3 — Samsung protection neutralization + KernelSU Next (LKM)

This is the core of the project. Order matters: the kernel must first boot modified (Phase 1
already disables the boot-blocking protections) and be able to load an out-of-tree module,
*then* the LKM goes into init_boot.

**Status: root ACHIEVED (2026-08-16) — exit gate MET, via a route we didn't originally plan.** The
owner reached working KernelSU-Next root by patching `init_boot` with the KSU-Next **manager** and
flashing it, running on **BeyondROM's own kernel** — which already ships the six protections off +
module loading (`FACTS §0.6`, config dump: `KPROBES=y`, no `MODULE_SIG_*`, no UH/RKP/KDP/DEFEX/
PROCA/FIVE). So **plain root did not need our custom kernel.** The generic `android14-6.1` module
loaded (modversions ignores the sublevel gap); `/proc/modules` shows `kernelsu … Live`, SELinux
Enforcing, no crashes (one minor bug: the manager's in-app *Reboot* seccomp-crashes ksud on
Android 16 — use the power menu). The from-source pieces below matter now only for the Phase-4
SUSFS build, where a custom kernel *is* required.

- [x] Kprobes already enabled by Samsung (`CONFIG_KPROBES=y`, `FACTS §0.5`) — no patch needed.
- [x] `MODULE_SIG_PROTECT` off so the unsigned `kernelsu.ko` can load *(done: protection #7; the
      boot-blocking protections were already neutralized in Phase 1)*
- [ ] Add KernelSU Next to the tree (pinned tag); build `kernelsu.ko` **against our kernel**
      *(deferred to Phase 4 — plain root used the manager's module on BeyondROM's kernel; this
      in-tree `CONFIG_KSU=m` build is only needed for the custom-kernel SUSFS image)*
- [x] `scripts/patch-init-boot.sh` — restore the stock ramdisk + `ksud boot-patch` the LKM into
      `init_boot.img` *(done: PR #31, validated end-to-end against the real image)*
- [~] Add `kernelsu` input to the workflow *(the input exists in `build.yml`; the `package.sh`
      wiring that calls `patch-init-boot.sh` is a Phase-4 step)*
- [x] Owner flashes a patched `init_boot.img` *(done via the KSU-Next manager on BeyondROM's kernel,
      not our `boot.img` — see Status above)*

**Exit gate:** KSU Next manager shows the module active and grants root, **and** the full
hardware checklist from Phase 1 still passes. Re-verify every item — this is where
regressions hide. **→ MET 2026-08-16** (manager shows `KernelSU: 33214`, LKM active, root granted,
hardware unaffected).

---

## Phase 4 — SUSFS

- [x] Select the susfs4ksu branch matching our KMI *(done: `gki-android14-6.1`, pinned commit
      `e287d590`, vendored in `patches/susfs/`)*
- [~] Apply the SUSFS kernel patch as one of our patches; resolve fallout in-tree *(dry-run applies
      111/114 hunks to our tree; 3 hunks in `fs/namespace.c` + `fs/proc/base.c` to adapt — not yet
      wired into `build.sh`)*
- [ ] Resolve KSU-Next's SUSFS mode (native `CONFIG_KSU_SUSFS`; built-in vs LKM), enable it, rebuild
      the custom kernel + repack `init_boot`; delete `android/abi_gki_protected_exports_*`
- [ ] Owner flashes and verifies SUSFS features via the manager / `ksu_susfs`

**Exit gate:** SUSFS active, root works, hardware checklist still passes.

**Status: groundwork done (2026-08-16).** Pinned + vendored; patch de-risked against our tree; open
questions recorded in `patches/susfs/README.md`. Needs the custom kernel (Build #9 — a known-good,
all-hardware-working base; **no** audio blocker).

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
