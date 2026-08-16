# Samsung Galaxy S24 Ultra — custom GKI kernel (SM-S928B / e3q)

A from-source rebuild of Samsung's own kernel for the **Galaxy S24 Ultra (SM-S928B)**, changed
as little as possible to boot on a custom ROM. The guiding rule of the project is *conservatism*:
build Samsung's **unmodified** source, add only a small, reviewable patch series, and never claim
something works until it has been flashed and checked on the actual device. (Root and SUSFS were
later goals; see the status and roadmap below for where they landed.)

> **Status — custom kernel device-verified · KernelSU Next root working · SUSFS paused.**
> The self-built kernel (Build #9, the six Samsung protections off) **boots on hardware with all
> hardware working — Wi-Fi, Bluetooth, mobile data, S-Pen, camera, fingerprint, and audio** (see
> `docs/FACTS.md` §0.3.2). A tested flash/rollback procedure and a regression baseline are in place.
> **KernelSU Next root works on the device**, achieved by patching `init_boot` with the KSU-Next
> manager on the ROM's existing kernel — independent of this from-source build. **SUSFS is paused:**
> its author confirmed it is incompatible with KernelSU's LKM mode for now. The custom kernel stands
> as a complete, verified result; no active build task is open against it.

This repository is a work log as much as a kernel tree: every change is a small commit with its
reasoning, so a boot failure can be bisected to one decision. If you are reading it to learn how a
Samsung GKI kernel is rebuilt and rooted from scratch, the [documentation map](#where-things-are)
below is the place to start.

---

## ⚠️ Before you flash anything

This produces a **kernel that replaces part of your phone's firmware.** Treat it accordingly:

- You need an **unlocked bootloader** and you accept the risk that comes with it.
- **Compiling is not testing.** No build here is promised to boot. Each build's flashing guide
  states the expected good outcome *and* the failure signature for every step.
- **Keep a rollback ready** — at minimum your current stock `boot.img`, ideally the full stock
  `S928BXXU5DZDP` firmware — *before* you flash. The kernel-only first flash is designed so that
  rollback is a single re-flash.
- Do **not** flash the `vendor_*`/`system_dlkm*` images that appear in build logs — they are
  byproducts, not release artifacts.

**The flashing and rollback procedure is [`docs/FLASHING.md`](docs/FLASHING.md). Read it fully
before flashing.** There is no warranty; see [Disclaimer](#disclaimer).

---

## The device

| | |
|---|---|
| Model | SM-S928B (international) · codename **e3q** |
| SoC | Qualcomm SM8650 / Snapdragon 8 Gen 3 (`pineapple`) |
| Kernel | Linux **6.1.145**, GKI 2.0, KMI `android14-6.1` |
| Source base | Samsung OSRC drop `S928BXXU5DZDP` (tagged `osrc/S928BXXU5DZDP` on `vanilla`) |
| Toolchain | Clang `r487747c` (the compiler Samsung's scripts specify), `--lto=none` to match stock module ABI |

The full, cited version of these facts — build strings, partition layout, config symbols, module
inventory — lives in [`docs/FACTS.md`](docs/FACTS.md), which is the project's ground truth.

---

## What we change — and what we deliberately don't

**We change only what a self-built kernel needs to boot on this device:**

- **Disable the six Samsung boot-blocking protections** — uH/RKP/KDP, DEFEX, PROCA, FIVE — at the
  defconfig level, one protection per commit. These accept only Samsung's own signed kernel and
  bootloop a modified one; they are the minimum removal required to boot our build.

Root (KernelSU Next) is **not** a change to this source tree — it is applied on-device by patching
`init_boot` with the KSU-Next manager, and works on the ROM's existing kernel. SUSFS is paused.

**We deliberately don't touch:**

- **Firmware-coupled subsystems** — display/DPU, KGSL (GPU), camera, audio, modem/IPA,
  remoteproc. They talk to blobs in partitions we are not replacing; changing them breaks the
  device in ways that look like unrelated bugs.
- **The kernel version** beyond its LTS sublevel (it would break the stock module ABI), and
- **Qualcomm CLO backporting** — explicitly out of scope (see `docs/DECISIONS.md`).

Everything we add lives as a rebasable patch series on top of the pristine Samsung import, so it
can be replayed onto the next Samsung source drop and audited line by line.

---

## How a build happens

Builds run **only in GitHub Actions**, started **by hand** (`workflow_dispatch` on the
[Build kernel](.github/workflows/build.yml) workflow) — never automatically, to keep CI minutes
and disk deliberate. There are no prebuilt kernels checked into this repo; you produce one by
running the workflow. Toolchain fetch, compile, and packaging each self-check and fail loudly
rather than shipping a bad artifact.

A green run uploads each of these as a **separate artifact in its native extension** — no wrapping
zip (`upload-artifact@v7` with `archive: false`), so you download the file itself, ready to flash:

| File | What it is |
|---|---|
| `e3q-kernel-<date>-AK3.zip` | **The flashable kernel** — an AnyKernel3 zip for a custom recovery (primary method). |
| `boot.tar.md5` | Odin (Download-Mode) image — the no-recovery fallback. |
| `boot.img` | Raw kernel image — for the `dd`/Heimdall path. |
| `e3q-modules-<date>.zip` | The vendor modules built against this kernel (reference; not flashed for the first boot). |

The single canonical build command is [`scripts/build.sh`](scripts/build.sh); repacking is
[`scripts/package.sh`](scripts/package.sh). Never hand-run a different command — CI and local must
not diverge.

---

## Where things are

Each document owns one lane; start with the one that matches your question.

| Path | What it is | Read it when you want… |
|---|---|---|
| `README.md` (this file) | Orientation, status, safety, and the map. | …the 30-second picture. |
| [`docs/FACTS.md`](docs/FACTS.md) | Ground-truth facts about the device and source tree, each cited to the file it came from. | …an exact value (version, config symbol, partition, path). |
| [`docs/PLAN.md`](docs/PLAN.md) | The phased roadmap, each phase gated by a real on-device check. | …to know what's done and what's next. |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Dated log of settled choices and their reasoning. | …to know *why* something is the way it is before reopening it. |
| [`docs/HANDBOOK.md`](docs/HANDBOOK.md) | The deep technical reference — GKI, Samsung security stack, the build system, the module ABI. | …to actually understand the machinery. |
| [`docs/FLASHING.md`](docs/FLASHING.md) | Owner-facing flash + rollback procedure. | …to put a build on the phone (and get back). |
| [`CLAUDE.md`](CLAUDE.md) | The standing engineering rules this repo is built under. | …to contribute in the project's style. |
| `.claude/skills/e3q-kernel/` | The operational build/patch/package/flash procedure. | …the step-by-step for a specific operation. |
| `scripts/` | `setup-toolchain.sh`, `build.sh`, `package.sh` — the build pipeline. | …to see exactly how a build is produced. |
| `anykernel3/` · `anykernel/` | osm0sis's AnyKernel3 (pinned submodule, unmodified) + our small e3q config. | …to see how the flashable zip is assembled. |
| `kernel_platform/` · `vendor/` | The Samsung GKI kernel and Qualcomm driver sources (the OSRC drop). | …to read Samsung's actual code. |

---

## Branch model

```
vanilla   Import-only. One commit per Samsung OSRC drop, tagged by firmware build string
          (current: osrc/S928BXXU5DZDP). Pristine — nothing else ever lands here.
main      vanilla + our patch series. This is what CI builds.
task/*    Short-lived branches, opened as pull requests into main and merged when done.
```

Build **variants** (toolchain, LTO mode) are **workflow inputs**, not branches — a variant is a way
to build the same code, not a change to it. Every new Samsung
source drop is imported onto `vanilla`, then the patch series is replayed onto it; a patch that no
longer applies is treated as a signal to investigate, not to force.

---

## Roadmap

| Phase | Goal | State |
|---|---|---|
| **1** | Reproducible build of Samsung's source that boots with all hardware working (protections off, otherwise unmodified). | **Done — device-verified.** Build #9 boots; all hardware works, audio included (FACTS §0.3.2). |
| **2** | Reproducibility hardening; a tested flash/rollback procedure. | **Done.** `docs/FLASHING.md` written + rollback tested; regression baseline in `docs/REGRESSION.md`. |
| **3** | KernelSU Next root. | **Done — root working.** Achieved on-device by patching `init_boot` with the KSU-Next manager (on the ROM's existing kernel); not a change to this source tree. |
| **4** | ~~SUSFS~~ | **Paused.** Its author confirmed SUSFS is incompatible with KernelSU's LKM mode for now; dropped from scope until that changes (see `docs/DECISIONS.md`). |

Each phase has an **exit gate that requires a real flash on real hardware** — see
[`docs/PLAN.md`](docs/PLAN.md) for the gates and the per-phase checklist.

---

## Built on

- **Samsung Open Source Release Center** — the kernel and driver source (`S928BXXU5DZDP`).
- **[osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3)** — the flashing engine, vendored
  as a pinned submodule and used unmodified.
- **[KernelSU Next](https://github.com/KernelSU-Next/KernelSU-Next)** — root, applied on-device via
  the manager (LKM mode), independent of this kernel build.

## License

The kernel and driver sources under `kernel_platform/` and `vendor/` are Samsung's OSRC release
and are licensed **GPLv2** (the Linux kernel license); our changes to them are likewise GPLv2. The
AnyKernel3 submodule carries its own license — see `anykernel3/LICENSE`.

## Disclaimer

This is a personal, in-progress project for one specific unlocked device. Flashing a custom kernel
can leave a phone temporarily unbootable and, in the worst case, harder to recover; you do it at
your own risk and are responsible for keeping the backups described in
[`docs/FLASHING.md`](docs/FLASHING.md). **No warranty of any kind.** Nothing here is affiliated
with or endorsed by Samsung, Qualcomm, or Google.
