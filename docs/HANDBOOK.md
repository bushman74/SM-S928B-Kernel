# HANDBOOK — a complete, studyable reference for this repository

This document exists so that a reader — the owner, a future contributor, or a fresh Claude
session with no chat history — can understand *every* meaningful fact about this project from
one place, in a structured order, without having to reverse-engineer it or ask.

It is deliberately verbose. It explains not only *what* is true but *why*, and for a
non-programmer audience it defines the jargon as it goes. Where a claim is a fact read out of
the source or off the device, it cites the source (`file:line`) or points at `docs/FACTS.md`.
Nothing here is invented; if something is unknown it says so.

**How the docs fit together (read in this order for depth):**

| Doc | Role |
|---|---|
| `CLAUDE.md` | Standing rules that govern *how* work is done (commits, safety, style). Outranks everything. |
| `docs/PLAN.md` | The phased roadmap and the flash-gated exits between phases. |
| `docs/DECISIONS.md` | Settled choices, each with date + reasoning + what would reverse it. |
| `docs/FACTS.md` | Ground truth read out of the source tree and the device. The authority for values. |
| **`docs/HANDBOOK.md`** (this file) | The connective tissue — explains and relates all of the above into one studyable whole. |
| `.claude/skills/e3q-kernel/SKILL.md` | The operational how-to for building, patching, packaging, flashing. |

When this handbook and `docs/FACTS.md` disagree, **FACTS wins** (it is the machine-checked
ground truth); fix the handbook to match.

---

## 1. What this project is, in one paragraph

We are building a custom Android **kernel** for the Samsung Galaxy S24 Ultra (model
**SM-S928B**, codename **e3q**, SoC **Qualcomm SM8650 / Snapdragon 8 Gen 3**, Qualcomm target
name **pineapple**). The end goal, in strict priority order, is: (1) a **reproducible build of
Samsung's own source that boots with all hardware working**; then (2) **KernelSU Next** root in
"LKM" mode patched into `init_boot.img`, plus the Samsung/Knox neutralization required to boot a
self-built kernel and load the root module; then (3) **SUSFS** on top. Goal 1 gates everything —
there is no point starting 2 or 3 until 1 is boringly reliable.

The device is bootloader-unlocked, running a custom ROM (**BeyondROM 5.0**, firmware base
**DZDP**), and already rooted (with Magisk Alpha, which the owner will remove). No warranty/Knox
warnings are needed.

---

## 2. The device and firmware — the hard facts

| Fact | Value | Where it comes from |
|---|---|---|
| Marketing name | Galaxy S24 Ultra | — |
| Model | SM-S928B (international/EUR) | — |
| Codename | e3q | build target `e3q_eur_openx` |
| SoC | Qualcomm SM8650, Snapdragon 8 Gen 3 | — |
| QC platform name | `pineapple` | `README_Kernel.txt`, `build.config.msm.pineapple` |
| Kernel version | **6.1.145** | `kernel_platform/common/Makefile:2-4` |
| Kernel codename | "Curry Ramen" | `common/Makefile:6` |
| GKI generation / KMI | **GKI 2.0, `android14-6.1`** | `build.config.constants:1` (`BRANCH=android14-6.1`) |
| Platform Android version | **Android 16 / One UI 8** | `README_Platform.txt`, archive name `..._16_...` |
| Reference compiler | Clang **`r487747c`** | `build.config.constants:2` (`CLANG_VERSION=`) |
| Firmware build string | **`S928BXXU5DZDP`** | OSRC archive filename |
| Current ROM on device | BeyondROM 5.0 (base DZDP) | owner-supplied |
| Verified boot state | ROM ships **patched vbmeta** (AVB disabled) | owner-confirmed, `FACTS.md §0.6` |

**The Android-14-vs-16 subtlety (important, and a common source of confusion):** the *platform*
(the Android OS/One UI on the phone) is Android **16**. The *kernel* is 6.1 with the KMI
generation **`android14-6.1`**. "android14-6.1" is a **GKI KMI generation label**, not the
platform version — Google freezes a kernel ABI ("KMI") for a generation and carries it across
several Android releases. So an Android 16 phone legitimately runs an `android14-6.1` kernel.
This matters because tools that key off the KMI (notably **SUSFS**, whose branch is
`gki-android14-6.1`) must use the *kernel* label, not the platform version. Recorded in
`DECISIONS.md 2026-08-12`.

---

## 3. Repository anatomy — what is in this repo and why

```
/CLAUDE.md                     standing rules (loaded every session)
/.gitignore                    excludes build output, fetched toolchains, blobs
/docs/                         FACTS, PLAN, DECISIONS, HANDBOOK (this), later FLASHING/MEASUREMENTS
/.claude/skills/e3q-kernel/    the operational build/patch/package/flash skill
/.github/workflows/build.yml   the manual-only CI build
/scripts/                      setup-toolchain.sh, build.sh, package.sh
/build_kernel_GKI.sh           Samsung's own top-level build wrapper (from the OSRC drop)
/kernel_platform/              the Samsung GKI kernel source (see §4)
/vendor/qcom/opensource/       the Qualcomm out-of-tree driver sources (see §6)
```

The kernel source (`kernel_platform/`, `vendor/`, `build_kernel_GKI.sh`) is the **unmodified
Samsung Open Source Release Center (OSRC) drop**, committed verbatim as the base every later
change replays onto. Two things were deliberately *left out* of the import, per `CLAUDE.md`
("never commit toolchains" / no blobs): Samsung's `kernel_platform/gcc/` (a ~131 MB host GCC
prebuilt — unreferenced by our build) and the build machine's dangling `bazel-*` output
symlinks. Everything else is byte-for-byte Samsung. Archive SHA256:
`512c0a0b74646ddbb64ac8adea7c396c90458c2c12cf7f437e9d20282a33fa3c`.

Files intentionally **absent by design** (created in later phases, their absence is not a bug):
`docs/FLASHING.md` (Phase 2), `docs/MEASUREMENTS.md` (first checklist run),
`scripts/patch-init-boot.sh` (Phase 3, KernelSU LKM injection). The CI preflight names the
scripts it expects, so a missing one fails loudly rather than silently.

---

## 4. The Samsung source tree and the build system

### 4.1 `kernel_platform/` layout

| Subdir | What it is |
|---|---|
| `common/` | The **GKI kernel** — Google's Generic Kernel Image sources, *as modified by Samsung* (Samsung adds their security drivers here, e.g. `common/security/samsung/`, `common/drivers/uh/`, and the UH/RKP/KDP Kconfig in `common/arch/arm64/Kconfig`). This is what becomes `boot.img`'s kernel. |
| `msm-kernel/` | The Qualcomm vendor kernel tree — a full kernel tree plus QC/SoC drivers, the bazel build definitions (`BUILD.bazel`, `*.bzl`), and Samsung's per-model "lego" wiring (`lego.bzl`). |
| `build/` | The Kleaf/bazel build framework (`build/kernel/kleaf/…`), hermetic tools, image rules. |
| `external/` | Vendored bazel dependencies (skylib, stardoc, rules_pkg, …). |
| `WORKSPACE`, `build.config`, `build_with_bazel.py` | bazel entry points (symlinks into `msm-kernel/`). |
| `prebuilts/` | **Not shipped** in the OSRC drop; fetched by `scripts/setup-toolchain.sh` (see §5). |

"common vs msm-kernel" is a genuine duplication: both are complete 6.1.145 kernel trees (~1.5 GB
each). `common/` is the GKI half; `msm-kernel/` is the vendor half that drives the build and adds
Qualcomm code. This is how Samsung/Qualcomm ship GKI kernels; it is not a mistake in the import.

### 4.2 Kleaf / Bazel — how a build actually runs

The build system is **Kleaf**, Google's Bazel-based kernel build (GKI 2.0). You do not run
`make`. The canonical entry point Samsung documents (`README_Kernel.txt`) is:

```
RECOMPILE_KERNEL=1 ./kernel_platform/build/android/prepare_vendor.sh pineapple gki
```

`prepare_vendor.sh` is a wrapper that ultimately runs the real Kleaf builder:

```
build_with_bazel.py -t pineapple gki --lto=<none|thin|full> --out_dir <out>
```

which builds the bazel targets `//msm-kernel:pineapple_gki_dist` (+ `_abl_dist`, `_dtc_dist`) and
drops results in `<out>/dist/` (`Image`, the `*.ko` modules, `modules.load`, dtbs). Our
`scripts/build.sh` calls `build_with_bazel.py` **directly** (with `--skip abl`), skipping
`prepare_vendor`'s Android-tree integration steps (bootloader/ABL, devicetree overlay,
`ANDROID_PRODUCT_OUT`) that a bare CI runner does not have. See §10.

Model selection ("e3q") happens through Samsung's **lego** layer (`msm-kernel/lego.bzl`,
`lego_model = 'e3q'`), which also lists the 64 Samsung per-model modules and the `e3q_eur_openx_*`
device-tree overlays. There is no standalone `e3q_defconfig` file; the effective config is
`common/arch/arm64/configs/gki_defconfig` (where Samsung's security symbols live) plus vendor
fragments.

---

## 5. Toolchain and prebuilts — and the compiler clarification

**The single most important conceptual point for the owner:** we did **not** switch to a
different or "better" compiler. Samsung's own build config *names* the compiler —
`CLANG_VERSION=r487747c` (`build.config.constants:2`) — and Samsung does not ship a compiler of
their own; their build downloads AOSP's clang prebuilt, the exact same one. The OSRC drop just
omits `prebuilts/` and tells you to fetch it (`README_Kernel.txt`). So fetching clang `r487747c`
from `android.googlesource.com` **is using Samsung's specified compiler**, not replacing it.
There is therefore **no performance/battery change** from this, and nothing about the kernel
became "less Samsung." Full reasoning: `DECISIONS.md 2026-08-12` ("we did NOT switch compilers").

### 5.1 What `setup-toolchain.sh` fetches

The Kleaf build loads its compiler and host tools from bazel packages under `//prebuilts/…`,
which the OSRC drop does not include. The authoritative list of what to fetch, and the exact
pinned revision, is the **AOSP GKI manifest** (`kernel/manifest`, branch `common-android14-6.1`),
which pins every prebuilt at revision **`main-kernel-build-2023`**. The script fetches, into
`kernel_platform/prebuilts/`:

| Into `prebuilts/` | Source repo (on android.googlesource.com) | Notes |
|---|---|---|
| `clang/host/linux-x86` | `platform/prebuilts/clang/host/linux-x86` | **sparse** checkout of `clang-r487747c` + `kleaf/` only (full repo ≈ 40 GB) |
| `build-tools` | `platform/prebuilts/build-tools` | general host tools |
| `clang-tools` | `platform/prebuilts/clang-tools` | `bindgen` |
| `kernel-build-tools` | `kernel/prebuilts/build-tools` | `mkbootimg`, `avbtool`, `lz4`, … |
| `bazel/linux-x86_64` | `platform/prebuilts/bazel/linux-x86_64` | bazel launcher bits |
| `jdk/jdk11` | `platform/prebuilts/jdk/jdk11` | JDK for bazel |
| `ndk-r23` | `toolchain/prebuilts/ndk/r23` | referenced by `workspace.bzl` |
| `gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8` | `platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8` | **host glibc sysroot** for the hermetic tools |

The `gcc` entry is a subtle one and was the cause of CI **run #1**'s failure: nothing in any
BUILD file references `prebuilts/gcc`, but the tree reaches its `sysroot` via the symlink
`build/kernel/build-tools/sysroot -> ../../../prebuilts/gcc/.../sysroot`. Omit it and
`//build/kernel`'s `sysroot` glob is empty, so `hermetic_tools_toolchain` never registers. The
method that caught it: enumerate every in-tree symlink whose target is under `prebuilts/`. Full
detail in `docs/FACTS.md §0.5`.

The total fetch is ~6 GB; the CI workflow caches `kernel_platform/prebuilts/` so it is a one-time
cost. The fetch is gitignored — fetched, never committed.

### 5.2 LTO, CFI, module signing (the ABI-relevant knobs)

- **LTO** (Link-Time Optimization) is *not* a defconfig value here; it is a Kleaf build flag
  (`--lto=none|thin|full`, exposed as the workflow `lto` input). GKI's default is `thin`. LTO is
  a real performance/size knob but is **ABI-relevant** — mixing LTO modes between the kernel and
  the stock modules risks breakage, which is why we pin it deliberately.
- **`CONFIG_CFI_CLANG=y`** (Control-Flow Integrity) and **`CONFIG_MODVERSIONS=y`** are set; both
  are ABI-relevant. This is why any out-of-tree module (like KernelSU's `.ko`) must be built
  *against our kernel*.
- **Module signing:** `CONFIG_MODULE_SIG=y` and `MODULE_SIG_PROTECT=y`, but **`MODULE_SIG_FORCE`
  is not set** for pineapple — so unsigned modules should load (to be confirmed at LKM load time).

---

## 6. The module set — why "a boot.img alone is not enough" (answers a common question)

This is GKI 2.0. The kernel image is **only part of the picture**. Most hardware drivers ship as
**loadable kernel modules** (`.ko` files), not compiled into the kernel. On this device the
generic ramdisk lives in `init_boot`, and the vendor modules live in `vendor_boot` (first-stage)
and `vendor_dlkm` (inside the `super` partition, second-stage).

So a complete, working result is **not** just a `boot.img`. It is:

- **`boot.img`** = our kernel `Image` (no ramdisk; header v4).
- **`vendor_dlkm` / `vendor_boot`** = the matching `.ko` modules.

The Samsung source builds **both** the kernel *and* the modules. Concretely, `docs/FACTS.md §0.3`
records that **all 351 modules present on the device build from this source** — 64 Samsung
per-model modules (`lego.bzl`), ~36 in-tree `=m`, and 47 external Qualcomm driver trees under
`vendor/qcom/opensource/` (Wi-Fi `qcacld-3.0`, Bluetooth, audio, camera, display, touch, video,
DSP, sensors, fingerprint, battery, …). **None** must be reused as a stock binary.

**Why we still need the stock partition images to package:** even though we can *build* every
module, turning the built `Image` + `.ko` set into flashable `init_boot`/`vendor_boot`/
`vendor_dlkm` images means repacking those partitions in their exact on-device format (compression,
layout, footers). The reliable base for that repack is the **stock partition images** from the
matching firmware (`S928BXXU5DZDP`). That is why the owner obtaining the stock firmware is a
prerequisite for the packaging step — it is both the repack scaffold and the rollback path.

**A legitimate simplest-first path:** because our kernel is built with the same compiler/config as
stock, an early boot test can flash **only `boot.img`** (our kernel) while keeping the stock
`vendor_dlkm`/modules — if the ABI matches, it boots with hardware working, using stock modules.
That is the minimal, lowest-risk first flash; the full module rebuild/repack comes after.

---

## 7. Boot images, partitions, and verified boot

| Concept | This device |
|---|---|
| Boot header version | **v4** (`build.config.msm.pineapple:13`) |
| `boot.img` | kernel `Image` only (no ramdisk) |
| `init_boot.img` | the generic ramdisk (first-stage init) — this is where KernelSU's LKM will be injected (Phase 3) |
| `vendor_boot.img` | vendor ramdisk + first-stage vendor modules |
| `vendor_dlkm` | second-stage vendor modules (lives inside `super`) |
| Ramdisk compression | Kleaf default **`lz4`** (`build/kernel/_setup_env.sh`); confirm against the stock image when we first repack |
| AVB / verified boot | `boot.img` is signed with `avbtool add_hash_footer --algorithm SHA256_RSA4096` (`avb_boot_img.bzl`). The **installed ROM already ships a patched/disabled vbmeta**, so a self-built boot/init_boot boots without an extra AVB step — *as long as a stock `vbmeta` is never re-flashed over it*. |
| SEANDROIDENFORCE | A footer string the bootloader looks for; **not** in kernel source — appended by packaging tooling after repack (a "Category B" step; see the skill). |

vbmeta/AVB and SEANDROIDENFORCE are **partition/bootloader-level**, not kernel behaviour, so they
live in packaging (`scripts/package.sh`), never in source — distinct from the Samsung security
modules in §8, which *are* kernel behaviour and are fixed in source.

---

## 8. The Samsung security stack (what will fight a modified kernel)

These are Samsung/Knox protections that block a modified kernel from booting and/or block an
out-of-tree module (the root LKM) from loading. They are neutralized **in source** (we have it),
one per commit. **On this custom-ROM device they must be disabled in Phase 1** — a self-built
kernel with them enabled will not boot at all (owner-confirmed; `DECISIONS.md 2026-08-12`), so
this is not deferred to the root phase. `docs/FACTS.md §0.4` has the exact evidence; the key
structural finding is that **none of them are force-selected** (`select` grep is empty), so each
can be turned off at the **defconfig** level (the cleanest option) rather than needing a C patch.

| Protection | What it does | Symbol(s) | Location | Planned off-switch |
|---|---|---|---|---|
| **UH** (uH / micro-hypervisor) | Samsung's early-boot hypervisor that hosts RKP | `CONFIG_UH` | `common/arch/arm64/Kconfig:2338` | defconfig (`# CONFIG_UH is not set`); ⚠ early-boot, verify at first boot |
| **RKP** (Realtime Kernel Protection) | Read-only kernel/page-table enforcement via uH | `CONFIG_RKP` | `common/arch/arm64/Kconfig:2349` | falls away when UH is off (depends on UH) |
| **KDP** (Kernel Data Protection) | Protects credentials/namespaces/page tables | `CONFIG_KDP`, `KDP_CRED`, `KDP_NS` | `common/arch/arm64/Kconfig:2359+` | depends on UH; or explicit off |
| **DEFEX** | Privilege-escalation defence (LSM) | `CONFIG_SECURITY_DEFEX` | `common/security/samsung/defex_lsm/` (=y at `gki_defconfig:949`) | defconfig off |
| **PROCA** | Process authentication | `CONFIG_PROCA` | `common/security/samsung/proca/` (=y at `gki_defconfig:837`) | defconfig off |
| **FIVE** | Kernel-side file integrity | `CONFIG_FIVE` | `common/security/samsung/five/` (=y at `gki_defconfig:832`) | defconfig off |

Note: UH/RKP/KDP are `default y` in Kconfig (not written in the defconfig), so disabling them
requires *explicitly* adding the `# ... is not set` lines. We do **not** copy the source-blind
byte-patching that source-less tools (Magisk, ExtremeROM's PROCA `sed`) resort to — with source we
remove the mechanism cleanly and visibly in `git log`.

---

## 9. The root and SUSFS plan

- **KernelSU *Next*** (`github.com/KernelSU-Next/KernelSU-Next`), **not** upstream KernelSU, in
  **LKM mode**: root ships as a loadable `.ko` injected into `init_boot.img`, keeping root
  updatable without a kernel rebuild. Viable here because `CONFIG_KPROBES=y` already (LKM hooks via
  kprobes) and module signing is not forced. Fallback if the LKM proves impractical on the Samsung
  KMI: KSU Next *built-in* (source-hooked) integration. See `DECISIONS.md 2026-08-11/12`.
- **SUSFS** (`gitlab.com/simonpunk/susfs4ksu`), branch **`gki-android14-6.1`** (keyed off the KMI,
  §2), applied as a kernel patch after plain KSU Next is confirmed working (Phase 4).

---

## 10. CI/CD — the workflow and the scripts

**Everything builds in GitHub Actions**, never in the dev sandbox (insufficient disk). The
workflow is **manual-trigger only** (`workflow_dispatch`) by design — CI minutes and disk are
never spent automatically. Inputs: `toolchain` (default `reference` → clang `r487747c`), `lto`
(`none|thin|full`), `kernelsu`, `susfs`, `clean`.

Job outline (`.github/workflows/build.yml`): free disk → checkout → **preflight** (the three
scripts must exist and be executable) → install deps → restore ccache + **prebuilts cache** →
`setup-toolchain.sh` → `build.sh` → `package.sh` → upload artifacts + logs.

The three scripts:

| Script | Does | Status |
|---|---|---|
| `scripts/setup-toolchain.sh` | Fetches the `prebuilts/` set (§5) into `kernel_platform/prebuilts/`. Idempotent; sparse clang checkout. | Working (CI run #2). |
| `scripts/build.sh` | Runs `build_with_bazel.py -t pineapple gki --skip abl --lto=$LTO_MODE`, then stages `Image` + `*.ko` + dtbs into `out/dist/`. | Compiles (CI run #2, LTO=none). |
| `scripts/package.sh` | **First version:** bundles the built kernel+modules into a zip so CI has an artifact and the dist layout is visible. The real flashable repack (boot/init_boot/vendor_dlkm, SEANDROIDENFORCE, vbmeta, AnyKernel3) is the next step. | Placeholder; real repack pending stock images. |

**Fail-fast verification (built into the scripts + workflow):** to surface problems early and
clearly rather than after a long compile, the pipeline self-checks at each stage —
`setup-toolchain.sh` verifies every prebuilt is present, that clang runs, and that **no in-tree
symlink into `prebuilts/` is left dangling** (the generalized check for run #1's failure class);
`build.sh` pre-flights the source version, the sysroot symlink, and free disk (≥25 GB) before the
compile, and post-checks that an `Image` and a plausible module count came out; `package.sh`
refuses to bundle a build with zero modules; and the workflow asserts ≥40 GB free before the
fetch. Each failure prints a specific, greppable message naming what and where.

**CI build history (running record):**

| Run | Commit | LTO | Result | Lesson |
|---|---|---|---|---|
| #1 | `8589ece` | none | ❌ bazel analysis | missing `prebuilts/gcc` sysroot → `hermetic_tools_toolchain` unregistered. Fixed by fetching the gcc prebuilt + `--skip abl`. |
| #2 | `4364877` | none | ✅ green | Kernel + modules compiled (~52 min). Produced a 436 MB kernel+modules artifact (not yet flashable). Prebuilts cache saved for future runs. |

**A note on the "Node.js 20 is deprecated" CI warning:** it is **cosmetic and harmless**. GitHub is
migrating the JavaScript runtime that *actions themselves* run on (checkout/cache/upload-artifact)
from Node 20 to Node 24; the runner already forces them onto Node 24 and they run fine. It has
**nothing** to do with the kernel, the compiler, or build correctness, and does not affect
stability or success. No action is required; it resolves itself as those actions publish
Node-24-native releases.

---

## 11. Branch and pull-request model

Settled model (`DECISIONS.md 2026-08-12`):

- **`vanilla`** — import-only. Pristine Samsung source drops, one per firmware, tagged
  (`osrc/S928BXXU5DZDP`). Nothing of ours lands here. Created 2026-08-12 as an orphan branch of
  exactly `kernel_platform/` + `vendor/` + `build_kernel_GKI.sh`. Its purpose is to make
  re-importing a *future* Samsung drop mechanical: import onto `vanilla`, replay our series onto it,
  fail loudly on conflict.
- **`main`** — `vanilla` content + everything of ours (scaffolding, docs, scripts, CI, patches).
  **This is the branch CI builds.**
- **Task branches** — each unit of work on its own short-lived `task/<name>` branch → PR → merge
  into `main`. Build *variants* (toolchain, LTO, KernelSU on/off, SUSFS on/off) are **workflow
  inputs**, not branches.

Merged PRs so far, all into `main`: #1 (Phase-0 + source import), #2 (prebuilts fetch), #3 (build
scripts), #4 (gcc-sysroot fix), #5 (docs: granularity/detail rules, compiler clarification, this
handbook). Commits follow the granularity and detail rules in `CLAUDE.md`.

Historical note: `main` was not rebased onto `vanilla` (its history predates the split); `vanilla`
is the pristine base for future re-imports, not a literal ancestor of today's `main`.

### 11.1 Re-importing a new Samsung firmware drop

Samsung periodically ships new OSRC source drops (e.g. a `DZG1` build after our `DZDP`). The
process is mechanical and scripted — **`scripts/import-vanilla.sh`**:

```
scripts/import-vanilla.sh /path/to/SM-S928B_<n>_Opensource_<BUILD>.zip
```

It (1) verifies the zip and records its SHA256, (2) parses the build string from the filename,
(3) extracts `Kernel.tar.gz` to a scratch dir *outside* the repo, (4) strips the exact same
non-committable bits `vanilla` already excludes (the GCC prebuilt + dangling `bazel-*` symlinks),
(5) rebuilds the `vanilla` branch as a fresh pristine commit **in an isolated git worktree** (your
working checkout is never touched) and tags it `osrc/<BUILD>`. It deliberately does **not** push
and does **not** touch `main`.

Then replay our work onto the new base (deliberate, never forced — per CLAUDE.md):

1. `git diff osrc/<PREV> osrc/<NEW> -- kernel_platform vendor` — see exactly what Samsung changed.
2. On a `task/reimport-<BUILD>` branch off `main`, bring in the new `vanilla` content and rebuild
   via CI (`toolchain=reference`, `lto=thin`).
3. If one of our changes (a defconfig off-switch, a C patch) no longer applies cleanly, that is
   **signal** that Samsung moved something — investigate it, don't force the patch through.
4. Push when satisfied: `git push origin vanilla && git push origin osrc/<BUILD>`.

Values that must be re-read from the new drop (they can change between firmwares): the exact
`SUBLEVEL` (`common/Makefile`), `CLANG_VERSION` (`build.config.constants` — the toolchain fetch
pins it), and the KMI `BRANCH`. Update `docs/FACTS.md` accordingly; `setup-toolchain.sh` reads the
clang id from a constant that must match the new drop.

---

## 12. The phase plan and where we are now

Phases are sequential; each has an **exit gate that requires a real flash on real hardware**
(full detail: `docs/PLAN.md`). Current status in **bold**.

| Phase | Goal | Exit gate | Status |
|---|---|---|---|
| 0 — Discovery | Know the tree with zero assumptions | Owner reads `FACTS.md`; no `TBD` in blocking fields | ✅ **done** |
| 1 — Reproducible stock build that boots | Compile Samsung source; boot with all hardware working | Device boots; Wi-Fi/BT/data/S-Pen/camera/fingerprint all confirmed | 🔧 **in progress** — kernel **compiles green** (CI run #2). Remaining: disable the Samsung boot-blocking protections (moved here from Phase 3 — see §8), LTO→thin, real packaging, owner flash+verify. |
| 2 — Reproducibility hardening | Deterministic builds; documented flash+rollback | Owner can flash, break, and recover unaided | ⏳ pending |
| 3 — Protection neutralization + KernelSU Next (LKM) | Boot a modified kernel; load the root LKM | KSU Next shows active + grants root; full hardware checklist still passes | ⏳ pending |
| 4 — SUSFS | SUSFS on a working KSU Next | SUSFS active; root works; hardware checklist passes | ⏳ pending |
| 5 — Regression checklist | Guard against silent breakage at every gate | Recorded per commit SHA | ⏳ set up in Phase 2 |

**Explicitly out of scope** (reopen only via a new `DECISIONS.md` entry): Qualcomm CLO
backporting; AutoFDO; kernel version bumps beyond the LTS SUBLEVEL.

---

## 13. Reproduce a build from a clean checkout (the exact recipe)

You do not build locally (no disk); this is what CI does, and how to run it by hand from the
GitHub Actions tab:

1. **Actions → "Build kernel" → Run workflow**, on `main`, with inputs (first known-good:
   `toolchain=reference`, `lto=none`, `kernelsu=false`, `susfs=false`, `clean=false`).
2. CI: frees disk → checks out the repo → runs `scripts/setup-toolchain.sh reference` (fetches
   `prebuilts/` per §5, ~6 GB, then cached) → `scripts/build.sh`
   (`build_with_bazel.py -t pineapple gki --skip abl --lto=none`) → `scripts/package.sh`.
3. Output: the run's **artifacts** — `e3q-kernel-<sha>.zip` (kernel + modules) and `logs-<sha>`.

To reproduce identically, the workflow pins `KBUILD_BUILD_TIMESTAMP/USER/HOST`. The reference
toolchain (`r487747c`) and prebuilts revision (`main-kernel-build-2023`) are fixed, so a rebuild
from the same commit uses the same compiler and tools.

---

## 14. Glossary (for the non-programmer)

- **Compiler / Clang** — the program that turns human-readable source code into machine code. Here
  it is Clang `r487747c`, the version Samsung specifies (§5). "LLVM" is the toolchain family Clang
  belongs to.
- **GKI (Generic Kernel Image)** — Google's architecture where one common kernel is shared across
  devices and vendor-specific bits are loadable modules. GKI **2.0** freezes a kernel ABI ("KMI").
- **KMI (Kernel Module Interface)** — the frozen ABI between the GKI kernel and vendor modules. Its
  generation label here is `android14-6.1`. Modules built for one KMI generation load on that
  kernel; mismatches are rejected.
- **ABI (Application Binary Interface)** — the binary contract (symbol names, layouts, calling
  conventions). Compiler/LTO/CFI changes can change it, which is why we pin them.
- **Kleaf / Bazel** — the build system (Bazel is a build tool; Kleaf is Google's kernel layer on
  top). Replaces `make` for GKI 2.0.
- **`.ko` (kernel module)** — a driver compiled as a separate loadable file rather than into the
  kernel. Most hardware support on this device is `.ko`s (§6).
- **LKM (Loadable Kernel Module) mode** — installing KernelSU as a `.ko` loaded at boot, rather
  than compiled into the kernel.
- **kprobes** — a kernel feature to hook functions at runtime; the LKM uses it. `CONFIG_KPROBES=y`
  here.
- **LTO (Link-Time Optimization)** — an optional optimization done at link time; `none/thin/full`.
  A performance/size knob, but ABI-relevant.
- **CFI (Control-Flow Integrity)** — a security hardening (`CONFIG_CFI_CLANG=y`), ABI-relevant.
- **vbmeta / AVB (Android Verified Boot)** — the partition + mechanism that verifies boot images.
  Must be satisfied or disabled to boot a modified image; this ROM already disables it.
- **SEANDROIDENFORCE** — a footer string the bootloader expects on Samsung partition images; added
  after repack.
- **uH / RKP / KDP / DEFEX / PROCA / FIVE** — Samsung/Knox kernel protections (§8).
- **defconfig** — the file of `CONFIG_*` settings that configures the kernel build.
- **OSRC** — Samsung Open Source Release Center, where the kernel source drop comes from.
- **Odin** — Samsung's PC flashing tool for stock firmware (the rollback path).

---

## 15. Where to change what (quick index)

| To change… | Edit… |
|---|---|
| What the toolchain fetch pulls | `scripts/setup-toolchain.sh` (+ record in `FACTS.md §0.5`) |
| The build invocation / LTO handling / artifact staging | `scripts/build.sh` |
| Repack into flashable images | `scripts/package.sh` |
| The CI job (steps, caching, inputs) | `.github/workflows/build.yml` |
| A Samsung protection off-switch | the relevant defconfig / Kconfig / C file, one commit each (Phase 3) |
| A settled decision | append to `docs/DECISIONS.md` |
| A newly learned fact about the tree | `docs/FACTS.md` (then reconcile this handbook) |
| The rules for how work is done | `CLAUDE.md` |
