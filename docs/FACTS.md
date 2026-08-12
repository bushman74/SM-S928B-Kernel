# FACTS — ground truth about this tree

Every value here must be **read out of the source tree or off the device**, never recalled
from general knowledge. If a value is unknown, leave `TBD` — never fill a field with something
plausible. Fields marked *(blocking)* must be resolved before Phase 1 starts.

Last updated: `2026-08-12` · By: `Phase 0 discovery (read from the OSRC source tree)`

Evidence convention: paths below are relative to the extracted kernel root
`<extracted>/kernel/` (the archive's `Kernel.tar.gz`), whose top level is
`build_kernel_GKI.sh`, `kernel_platform/`, `vendor/`. `file:line` citations are from that tree.

> **Doc-drift flag (read this first).** `CLAUDE.md` and `docs/PLAN.md` describe the device as
> "Android 14 KMI". This archive is an **Android 16 / One UI 8** firmware (archive name
> `..._16_...`; `README_Platform.txt` says "version info - Android 16.0"). The **GKI kernel is
> still 6.1 with KMI `android14-6.1`** (see §0.2, §0.6) — that string is a KMI generation, not
> the platform Android version, and it is what SUSFS branch selection keys on. Nothing about the
> plan breaks; the "Android 14" wording in the docs is just imprecise. Suggest a one-line
> `DECISIONS.md` note so it isn't re-litigated.

---

## 0.1 Source archive

| Field | Value |
|---|---|
| Archive filename | `SM-S928B_16_Opensource_S928BXXU5DZDP.zip` *(blocking — resolved)* |
| Firmware build string | `S928BXXU5DZDP` *(blocking — resolved)* |
| Build target (from README) | `e3q_eur_openx` → MODEL=`e3q`, REGION=`eur`, CARRIER=`openx`, VARIANT=`user` |
| Download date | `2026-08-12` (fetched from owner's Google Drive; archive mtime inside zip: 2026-06-09) |
| SHA256 (outer zip) | `512c0a0b74646ddbb64ac8adea7c396c90458c2c12cf7f437e9d20282a33fa3c` |
| Outer zip size | `666,994,585` bytes (636 MB) |
| Zip contents | `Kernel.tar.gz` (640,508,672 B), `Platform.tar.gz` (40,021,204 B), `README_Kernel.txt`, `README_Platform.txt` |
| Extracted kernel tree size | `~3.6 GB` (`Kernel.tar.gz` unpacked) |

## 0.2 Tree layout

| Field | Value |
|---|---|
| `kernel_platform/` present? | **YES** *(blocking — resolved)* |
| Subdirectories under it | `build/`, `common/` (GKI 6.1 kernel, Samsung-modified), `msm-kernel/` (QC SoC kernel + build configs + bazel + `lego.bzl`), `external/`, `gcc/` (host x86_64 GCC + lcov — **no clang here**), `qcom/`, `tools/`; symlinks `WORKSPACE`→`msm-kernel/bazel.WORKSPACE`, `build_with_bazel.py`→`msm-kernel/…`, `vendor`→`../vendor`; file `build.config` |
| Build system | **Kleaf / Bazel (GKI 2.0)**, not legacy *(blocking — resolved)*. `kernel_platform/build.config` sources `msm-kernel/build.config.msm.pineapple`; `WORKSPACE` + `build_with_bazel.py` present |
| Build entry point script(s) | Top wrapper `build_kernel_GKI.sh <BUILD_TARGET> <VARIANT> <CHIPSET>` → runs `RECOMPILE_KERNEL=1 ./kernel_platform/build/android/prepare_vendor.sh pineapple gki gki`. README's canonical form: `RECOMPILE_KERNEL=1 ./kernel_platform/build/android/prepare_vendor.sh sec gki`. *(blocking — resolved)* |
| Bazel target for e3q | No hand-invoked `//…:…_dist` label; the model is wired through **`kernel_platform/msm-kernel/lego.bzl`** (`lego_model = 'e3q'`, a 64-entry `lego_module_list`, and the `e3q_eur_openx_*` dtbo list). The build is driven by `prepare_vendor.sh pineapple gki`, which generates/invokes the bazel targets. The `prepare_vendor.sh` invocation is the ground-truth entry; the exact internal bazel label is lego-generated (open item, non-blocking — `scripts/build.sh` will wrap `prepare_vendor.sh`). |
| Defconfig path(s) matching e3q/pineapple | **GKI Image config (holds Samsung security + module config):** `kernel_platform/common/arch/arm64/configs/gki_defconfig`. **SoC/vendor:** `kernel_platform/msm-kernel/arch/arm64/configs/gki_defconfig`, `.../vendor/pineapple_GKI.config`. **Samsung OEM defconfigs:** `.../oem/pineapple_sec_defconfig` (user), `pineapple_sec_eng_defconfig`, `pineapple_sec_userdebug_defconfig`. **Model wiring:** `msm-kernel/lego.bzl`. There is **no standalone `e3q_defconfig`** — model differentiation is via lego on top of the pineapple/sec configs. *(blocking — resolved)* |
| VERSION / PATCHLEVEL / SUBLEVEL | **6 / 1 / 145** (`kernel_platform/common/Makefile:2-4`; `msm-kernel/Makefile:2-4`; NAME "Curry Ramen") *(blocking — resolved)* |
| `CONFIG_LOCALVERSION` value | **Unset** in `gki_defconfig` (no `CONFIG_LOCALVERSION` line). GKI stamps the version via scmversion/KMI (`android14-6.1-…`). |
| Vendored toolchain under `prebuilts/`? | **NO** — there is no `kernel_platform/prebuilts/` directory. `gcc/` holds only host x86_64 GCC + lcov; **no clang is shipped**. Toolchain must be fetched (see §0.5). |

### Samsung's shipped build instructions (verbatim)

`README_Kernel.txt`:

```
################################################################################
1. How to Build
        - get Toolchain
                get the proper toolchain packages from AOSP or CodeSourcery or ETC.
                (Download link : https://opensource.samsung.com/uploadSearch?searchValue=toolchain )
                Please decompress in 'kernel_platform' folder
                (toolchain path : kernel_platform\prebuilts)

        - Set and export target config
                1. target config
                        BUILD_TARGET=e3q_eur_openx
                        export MODEL=$(echo ${BUILD_TARGET} | cut -d'_' -f1)
                        export PROJECT_NAME=${MODEL}
                        export REGION=$(echo ${BUILD_TARGET} | cut -d'_' -f2)
                        export CARRIER=$(echo ${BUILD_TARGET} | cut -d'_' -f3)
                        export TARGET_BUILD_VARIANT= user

                2. Chipset common config
                        CHIPSET_NAME=pineapple
                        export ANDROID_BUILD_TOP=$(pwd)
                        export TARGET_PRODUCT=gki
                        export TARGET_BOARD_PLATFORM=gki

                        export ANDROID_PRODUCT_OUT=${ANDROID_BUILD_TOP}/out/target/product/${MODEL}
                        export OUT_DIR=${ANDROID_BUILD_TOP}/out/msm-kernel-${CHIPSET_NAME}-${TARGET_PRODUCT}

                        # for Lcd(techpack) driver build
                        export KBUILD_EXTRA_SYMBOLS="<...long list of Module.symvers under out/vendor/qcom/opensource/...>"
                        # for Audio(techpack) driver build
                        export MODNAME=audio_dlkm

                        export KBUILD_EXT_MODULES="../vendor/qcom/opensource/mm-drivers/msm_ext_display ../vendor/qcom/opensource/mm-drivers/sync_fence ../vendor/qcom/opensource/mm-drivers/hw_fence ../vendor/qcom/opensource/mmrm-driver ../vendor/qcom/opensource/securemsm-kernel ../vendor/qcom/opensource/display-drivers/msm ../vendor/qcom/opensource/audio-kernel ../vendor/qcom/opensource/camera-kernel "

        - Start to trigger build
                3. build kernel
                        RECOMPILE_KERNEL=1 ./kernel_platform/build/android/prepare_vendor.sh sec ${TARGET_PRODUCT}

2. Output files
        - Kernel : arch/${__arch_name}/boot/Image
        - module : drivers/*/*.ko

3. How to Clean
        Change to OUTPUT_DIR folder
        EX) /home/dpi/qb5_8814/workspace/P4_1716/android/out/target/product/e3q/out
        $ make clean
################################################################################
```

(The top-level `build_kernel_GKI.sh` is a thin wrapper around the same flow; its
`KBUILD_EXT_MODULES` list is `display-drivers/msm camera-kernel audio-kernel dsp-kernel`.)

## 0.3 Module inventory *(blocking — PARTIAL: needs device `modules.load`)*

**Source-side buildable surface (read from the tree):**

- **64** Samsung per-e3q modules listed in `kernel_platform/msm-kernel/lego.bzl` (`lego_module_list`) —
  categories: `drivers/{battery, fingerprint, firmware/cirrus, input/sec_input(+wacom,stm,synaptics),
  mfd/maxim, muic, nfc, optics, regulator, samsung, sdp, sec_panel_notifier_v2, sensors, staging, sti,
  usb, uwb, vibrator, kperfmon, input_boost, hall}`.
- **36** in-tree modules marked `=m` in `common/arch/arm64/configs/gki_defconfig`.
- **47** external Qualcomm module trees under `vendor/qcom/opensource/`:
  `agm, audio-hal, audio-kernel, bt-kernel, camera-kernel, commonsys, commonsys-intf, core-utils(+sys,vendor),
  data-ipa-cfg-mgr, dataipa, datarmnet(+ext), dataservices, display, display-drivers, dsp-kernel, eva-kernel,
  fst-manager, graphics-kernel, healthd-ext, interfaces, lights, location, mm-drivers, mm-sys-kernel, mmc-utils,
  mmrm-driver, pal, power, recovery-ext, securemsm-kernel, softap, spu-kernel, synx-kernel, thermal-engine,
  thermal-hal, time-services, tools, touch-drivers, usb, vibrator, video-driver, wfd, wigig, wlan`.

**Interim conclusion:** the great majority of drivers (Wi-Fi, BT, audio, camera, display, touch, video, DSP,
sensors, fingerprint, battery) appear buildable from source. The authoritative "buildable vs must-reuse-stock"
split, load order, and any `.ko` present on the device with **no** matching source can only be settled against
the device's actual `modules.load`.

> **OWNER ACTION (device, needed to finish this table):** on the phone (root shell), run and paste back:
> ```
> ls -1 /vendor/lib/modules/
> cat /vendor/lib/modules/modules.load
> cat /vendor/lib/modules/modules.blocklist 2>/dev/null
> ```
> (If you also have `/vendor_dlkm/lib/modules/`, list that too.) I'll cross-reference each `.ko` against the
> source above and fill the table below.

| Module (.ko) | Source in archive? | Action |
|---|---|---|
| `TBD — pending device modules.load` | | |

Summary: `TBD` of `TBD` modules buildable from source; remainder copied through from stock.

## 0.4 Samsung security stack *(blocking — resolved from source)*

**Key structural finding:** grep for `select (UH|RKP|KDP|PROCA|SECURITY_DEFEX|FIVE)` across `common/` and
`msm-kernel/` returned **nothing** — **none of these are force-selected**. Per CLAUDE.md's preference order,
that means each can be handled at the **defconfig** level (level 1), not a forced C patch. The "chosen level"
below is the planned Phase-3 approach given that evidence; it is confirmed only when we actually build + boot.

Enablement is read from `common/arch/arm64/configs/gki_defconfig` (the GKI Image config Samsung ships their
security in). UH/RKP/KDP are **not** written in that defconfig — they are `default y` in
`common/arch/arm64/Kconfig`, so they are effectively on for e3q (a retail, non-`SEC_FACTORY`, non-`ARCH_QTI_VM`
build).

| Feature | CONFIG symbol(s) as found | Path(s) | Enabled for e3q? | Force-selected by? | Chosen level + why |
|---|---|---|---|---|---|
| DEFEX | `CONFIG_SECURITY_DEFEX` (+ `_USER`, `_IMR_V2`; also `_GKI`, `_NOBOOTPART`, `DEFEX_KERNEL_ONLY`) | `common/security/samsung/defex_lsm/` (Kconfig line 1 `SECURITY_DEFEX`, default n) | **YES** — `=y` at `common/arch/arm64/configs/gki_defconfig:949` (+`:954`, `:959`) | **No** | **defconfig** — `# CONFIG_SECURITY_DEFEX is not set`. Not force-selected; clean off-switch. |
| PROCA | `CONFIG_PROCA` (+ `PROCA_S_OS`, `PROCA_CERTIFICATES_DB`, `PROCA_GKI_10`) | `common/security/samsung/proca/` (Kconfig:5) + `msm-kernel/security/samsung/proca/` mirror | **YES** — `=y` at `gki_defconfig:837` (+`:842`, `:847`, `:867`) | **No** | **defconfig** — `# CONFIG_PROCA is not set`. (We explicitly do **not** copy the source-blind ExtremeROM byte/offset `sed` patch — we have source.) |
| RKP / uH | `CONFIG_UH`, `CONFIG_RKP` (+ `RKP_TEST`) | `common/arch/arm64/Kconfig:2338 (UH)`, `:2349 (RKP)`; msm mirror `:2350`, `:2361`; driver source `common/drivers/uh/` (+ `msm-kernel/drivers/uh/`) | **YES (effective)** — `UH` & `RKP` are `default y` (UH `depends on !SEC_FACTORY && !ARCH_QTI_VM`; RKP `depends on UH`); not in the defconfig file. `RKP_TEST` is `# not set` at `gki_defconfig:822`. | **No** | **defconfig** — add `# CONFIG_UH is not set` (cascades RKP/KDP off via `depends on UH`). ⚠ uH is Samsung's early-boot micro-hypervisor; disabling in source is the standard approach but **must be verified at boot**. |
| KDP | `CONFIG_KDP` (+ `KDP_CRED`, `KDP_NS`, `KDP_TEST`) | `common/arch/arm64/Kconfig:2359`, `:2369`, `:2379`; msm mirror `:2371`+ | **YES (effective)** — `KDP/KDP_CRED/KDP_NS` `default y`, `depends on UH`. `KDP_TEST` `# not set` at `gki_defconfig:827`. | **No** | **defconfig** — removing `UH` drops KDP (depends on UH); or explicit `# CONFIG_KDP is not set`. |
| FIVE | `CONFIG_FIVE` (+ `FIVE_GKI_10`; `FIVE_TEE_DRIVER`/`FIVE_PA_FEATURE` not set) | `common/security/samsung/five/` (Kconfig:3) + `msm-kernel/security/samsung/five/` | **YES** — `=y` at `gki_defconfig:832` (+`:862`) | **No** | **defconfig** — `# CONFIG_FIVE is not set`. |
| Other (present in tree) | `security/samsung/{dsms, kumiho, mz, mz_tee_driver, ddar}` also exist. No `CONFIG_DSMS=y` seen in `gki_defconfig`. | `common/security/samsung/…` | relevance TBD | — | Primary boot/LKM blockers are UH/RKP/KDP + DEFEX + PROCA (+FIVE). Others recorded for completeness; revisit only if a boot log implicates them. |

## 0.5 Toolchain & module-loading config

| Field | Value |
|---|---|
| Clang version referenced by Samsung's scripts | **`r487747c`** *(blocking — resolved)* |
| Where referenced (file:line) | `common/build.config.constants:2` and `msm-kernel/build.config.constants:2` (`CLANG_VERSION=r487747c`); path form `prebuilts/clang/host/linux-x86/clang-${CLANG_VERSION}/bin` at `common/build.config.common:7` |
| AOSP prebuilt still available? / URL | To confirm in Phase 1. Candidates: AOSP `prebuilts/clang/host/linux-x86` (`clang-r487747c`) at `android.googlesource.com`; Samsung also hosts toolchains at `opensource.samsung.com/uploadSearch?searchValue=toolchain` (per README). The **id `r487747c` is the blocking value and is known** — this matches the example already in `scripts/setup-toolchain.sh`. |
| `CONFIG_LTO_CLANG_*` in e3q defconfig | **Not set in the defconfig** (absent from `gki_defconfig` and `build.config.common`/`build.config.gki`). LTO is a **Kleaf `--lto` build flag** (GKI default `thin`), which is why the CI workflow exposes an `lto` input. *(blocking — resolved: not a defconfig value)* |
| `CONFIG_CFI_CLANG` | **`=y`** (`common/gki_defconfig:99`; `msm-kernel/gki_defconfig:97`) *(blocking — resolved)* |
| `CONFIG_MODVERSIONS` | **`=y`** (`common/gki_defconfig:102`; `msm-kernel/gki_defconfig:100`) *(blocking — resolved)* |
| `CONFIG_MODULE_SIG` / `CONFIG_MODULE_SIG_FORCE` | `MODULE_SIG=y` (`common/gki_defconfig:104`) and `MODULE_SIG_PROTECT=y` (`:105`). **`MODULE_SIG_FORCE` is NOT set for pineapple** (only `vendor/neo.config`/`neo_le.config` set it — a different SoC). `MODULE_SIG_ALL` not set (`vendor/pineapple_GKI.config:94`). ⇒ unsigned `.ko` should load. ⚠ **`MODULE_SIG_PROTECT=y`** is an Android GKI addition — flag it: verify at LKM load time that it does not reject the out-of-tree `kernelsu.ko`. *(blocking — resolved: signing is NOT forced)* |
| `CONFIG_KPROBES` / `HAVE_KPROBES` / `KPROBE_EVENTS` | **`KPROBES=y`** already (`common/gki_defconfig:96`). `HAVE_KPROBES` is arch-selected (`common/arch/arm64/Kconfig:213 select HAVE_KPROBES`). `KPROBE_EVENTS` not in defconfig (tracing-only, not required for KSU LKM hooks). ✅ **No kprobes-enablement patch needed** — the LKM's hooking prerequisite is satisfied out of the box. *(blocking — resolved)* |
| `CONFIG_WERROR` | Not found in `gki_defconfig` (may be applied via build flag). Non-blocking. |

## 0.6 Boot images, ramdisk & verified boot *(blocking — source parts resolved; device parts pending)*

| Field | Value |
|---|---|
| Separate `init_boot` partition? | **YES** — `BOOT_IMAGE_HEADER_VERSION=4` (`msm-kernel/build.config.msm.pineapple:13`). Boot header v4 moves the generic ramdisk out of `boot` into `init_boot`. *(blocking — resolved from source; device confirmation trivial)* |
| Where the generic ramdisk lives | **`init_boot`** (header v4). `boot.img` = kernel only; vendor ramdisk lives in `vendor_boot`. Matches the CLAUDE.md partition table. *(blocking — resolved)* |
| Ramdisk compression | Kleaf default **`lz4`** (`build/kernel/_setup_env.sh:287-289`: `RAMDISK_COMPRESS="lz4 -c -l …"`, `RAMDISK_EXT="lz4"`; gzip is the alternate branch). This is the "lz4_legacy" magiskboot must match. **Confirm against the stock `init_boot` by unpacking it device-side** (see OWNER ACTION §0.7). |
| SEANDROIDENFORCE footer present on stock images? | **Not represented in kernel source** (grep across `kernel_platform/` = empty) — it is appended by Samsung's packaging tooling, so it must be re-appended after any repack (Category B). Presence on the stock `init_boot`/`boot` to confirm by unpacking device-side. |
| vbmeta / AVB: what must be disabled to boot a modified image | Source signs `boot.img` via `avbtool add_hash_footer --algorithm SHA256_RSA4096 --partition_name boot` (`msm-kernel/avb_boot_img.bzl`). A self-built/modified `boot`+`init_boot` needs AVB **satisfied or disabled** — typically flashing a patched `vbmeta` with `--disable-verity --disable-verification`. Whether this is actually required depends on what the current custom ROM already does — **OWNER to confirm** (below). *(blocking — device/ROM-dependent)* |
| Does the current custom ROM already disable verity/verification? | `TBD` — **OWNER ACTION** (device/ROM-side). |
| KMI / Android version string | **`android14-6.1`** (`common/build.config.constants:1` and `msm-kernel/build.config.constants:1`, `BRANCH=android14-6.1`). This is the SUSFS branch key → target `susfs4ksu` branch `gki-android14-6.1`. (Platform is Android 16, but the KMI generation is android14-6.1.) *(needed for SUSFS branch match — resolved)* |

## 0.7 Device / flashing environment *(blocking — device-side, OWNER ACTION)*

None of these are in the source archive; they must come off the phone. Please run and paste back.

| Field | Value |
|---|---|
| Current ROM (name + version) | `TBD` |
| Current root method (Magisk? KSU? version) | `TBD` |
| Kernel flasher app in use | `TBD` |
| Stock images backed up? (`boot` / `init_boot` / `vendor_boot` / `vendor_dlkm`) | `TBD` *(blocking — this is the rollback path)* |
| Location of backups | `TBD` |
| Coresight/ETM present? (`ls /sys/bus/coresight`) | `TBD` (informational; AutoFDO already dropped) |

> **OWNER ACTION (device):**
> 1. Confirm you have **known-good stock copies** of `boot.img`, `init_boot.img`, `vendor_boot.img`, and
>    `vendor_dlkm.img` for build `S928BXXU5DZDP` saved somewhere off the phone. This is the rollback path and
>    is **blocking** — do not flash anything until it exists. (These come from the stock firmware `AP_*.tar.md5`
>    for this exact build.)
> 2. Tell me: current ROM name/version, current root (Magisk/KSU + version), and which flasher you use.
> 3. Paste the outputs from the §0.3 and §0.6 device commands.

## Open questions

- Exact internal bazel `_dist` label produced by `prepare_vendor.sh pineapple gki` (non-blocking — the
  documented `prepare_vendor.sh` invocation is the canonical build entry that `scripts/build.sh` will wrap).
- Effect of `CONFIG_MODULE_SIG_PROTECT=y` on loading the out-of-tree `kernelsu.ko` — verify at LKM load time.
- Effect of disabling `CONFIG_UH` on early boot (uH is Samsung's micro-hypervisor, initialized before the
  kernel) — the standard custom-kernel approach, but verify at first boot in Phase 3.
- Doc drift: `CLAUDE.md`/`PLAN.md` say "Android 14"; actual platform is Android 16, GKI kernel 6.1 KMI
  `android14-6.1`. Recommend a short `DECISIONS.md` note so it isn't reopened.
- Stock `init_boot` ramdisk compression: source default is `lz4`; confirm by unpacking the real image.
