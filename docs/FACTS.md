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

## 0.3 Module inventory *(blocking — resolved)*

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

**Device-side (from `/vendor/lib/modules/` on BeyondROM 5.0 DZDP, owner-supplied):** **351** distinct
`.ko`; `modules.load` lists 472 lines (351 distinct — the ROM repeats the audio/wlan blocks in its load
order, which is harmless).

**Cross-reference result: 351 of 351 device modules are buildable from this source — zero stock-only
modules.** Method: every device `.ko` basename was matched against the tree's `*.c` stems, `Kbuild`/`Makefile`
object tokens (`+= x.o`, `x-objs`, `x-y`), and `lego.bzl`. 350 matched directly; the single non-match,
`qca_cld3_kiwi_v2.ko` (Wi-Fi), was confirmed by hand — it is built from
`vendor/qcom/opensource/wlan/qcacld-3.0/` with `MODNAME=qca_cld3_kiwi_v2`, and the tree ships
`qcacld-3.0/configs/pineapple_gki_kiwi-v2_defconfig` for exactly this target.

| Module group (examples) | Count | Source in archive? | Action |
|---|---|---|---|
| Samsung device drivers (`sec_*`, battery `max777xx`/`sec-battery`, `fingerprint`/`qfs4008`, sensors, `sec_input`/`stm_ts_spi`/`synaptics`, `wez02` wacom, `nfc_nxp_sec`, `kperfmon`, muic/`pdic`) | ~90 | **Yes** — `msm-kernel/drivers/*` + `lego.bzl` (64 named) | Build from source |
| Qualcomm audio DLKM (`q6_*`, `lpass_cdc_*`, `wcd93xx`, `swr_*`, `machine_dlkm`, `snd-soc-*`) | ~55 | **Yes** — `vendor/qcom/opensource/audio-kernel`, `dsp-kernel` | Build from source |
| Qualcomm connectivity/WLAN/BT (`cnss2`, `qca_cld3_kiwi_v2`, `cfg80211`, `mac80211`, `btpower`, `bt_fm_slim`) | ~15 | **Yes** — `wlan/qcacld-3.0`, `bt-kernel` | Build from source |
| Qualcomm data path (`rmnet_*`, `ipa*`, `datarmnet*`) | ~15 | **Yes** — `dataipa`, `datarmnet(+ext)` | Build from source |
| Firmware-coupled (see CLAUDE.md — **build unmodified**): `msm_kgsl`, `msm_drm`, `camera`, `msm_video`, `msm-eva`, `frpc-adsprpc`, `q6_*`/adsp, modem via `rmnet`/`cnss` | ~40 | **Yes** — `graphics-kernel`, `display-drivers`, `camera-kernel`, `video-driver`, `eva-kernel`, `dsp-kernel` | Build from source, **do not modify** |
| Qualcomm platform/SoC (coresight, clocks `*cc-*`, thermal, regulators, glink/rpmsg, `qcom_q6v5*`, geni i2c/spi, usb) | ~135 | **Yes** — `msm-kernel/drivers/*` in-tree (`=m`) | Build from source |
| **Total distinct** | **351** | **351 buildable** | **0 must-reuse-stock** |

Summary: **351 of 351** modules buildable from source; **none** must be copied through from stock. (We may
still *choose* to reuse selected stock `.ko` to minimize ABI risk during Phase 1 bring-up, but source exists
for all of them — the module pipeline is not blocked by any missing source.) Full authoritative load order is
the device's own `modules.load` (owner-supplied, archived with this discovery).

### 0.3.1 Will STOCK modules load on our (protections-off) kernel? — MOSTLY, but MODULE_SIG_PROTECT rejected 61 of them (confirmed by flash 2026-08-14; fixed)

The Phase 1 first flash is `boot.img` only, keeping the **stock** `vendor_boot`/`vendor_dlkm` modules.
Whether those load against our modified kernel was analyzed from the source and the owner's real
partition images (baseline capture `2026-08-14`, stock kernel `6.1.145-android14-11-33419968-abS928BXXU5DZDP`,
541 modules loaded). Findings:

- **The kernel version string does NOT need to match.** `kernel/module/version.c:same_magic()` skips the
  first vermagic token (the release string) whenever the module carries CRCs — and `CONFIG_MODVERSIONS=y`,
  so all these modules do. Only the *rest* of the vermagic (`SMP preempt mod_unload modversions <arch>`) plus
  per-symbol CRCs are checked. Our kernel keeps the same SMP/PREEMPT/MODULE_UNLOAD/MODVERSIONS/arch, so that
  part matches. (This refutes the common "you must match Samsung's build string" assumption for this device.)
- **Disabling KDP does NOT change `struct cred` layout.** In `include/linux/cred.h`, `struct cred` closes
  (`} __randomize_layout;`) *before* the `#ifdef CONFIG_KDP` block, which only adds a separate internal
  wrapper `struct cred_kdp`. So the CRCs of the widely-imported cred functions (`commit_creds`, `prepare_creds`,
  `override_creds`, …) are unchanged. UH/RKP don't touch `task_struct`/`mm_struct`; DEFEX/PROCA/FIVE don't
  touch cred/sched. So the disabled protections don't shift the core exported-symbol CRC surface.
- **No stock vendor module imports a symbol the disabled protections provide.** Scanning the owner's
  `vendor_dlkm.img` and `vendor_boot.img` for `uh_*`/`rkp_*`/`kdp_*`/`proca_*`/`five_*`/`defex_*` finds only
  **`uh_call`**, once each — and that is **`hdm.ko`'s own local symbol**: with `CONFIG_UH=y` the HDM Makefile
  builds `hdm-objs = main.o uh_entry.o`, so `hdm.ko` bundles its own `uh_call` (`uh_entry.S`,
  `SYM_CODE_START(uh_call)`) instead of importing the kernel's. So it resolves on our UH-off kernel too.
  The `kdp_usecount_*`/`kdp_set_cred_non_rcu` helpers (called from the `get_cred`/`put_cred` inlines under
  `CONFIG_KDP_CRED`) appear in **zero** stock modules — hardware drivers don't refcount creds.

**Conclusion (vermagic/CRC/symbols):** no vermagic, CRC, or undefined-symbol blocker exists; those are not
why anything failed. That part of the analysis held up on the real flash — the ~480 vendor modules that load
prove version-string, MODVERSIONS-CRC and cred-layout compatibility. Separately unresolved and orthogonal:
the early-boot effect of `CONFIG_UH=off` (the EL2 uH firmware is loaded by the bootloader regardless).

**What this analysis MISSED — MODULE_SIG_PROTECT (confirmed by the 2026-08-14 flash).** The CRC/vermagic
lens above is not the whole gate. `CONFIG_MODULE_SIG_PROTECT=y` ("Android GKI module protection",
`kernel/module/Kconfig:134`) adds a **signature-based** check independent of MODVERSIONS: a module whose
signature is not valid against *this kernel's* key (`mod->sig_ok == false`, set in `kernel/module/signing.c:96`)
is rejected with `-EACCES` if it **exports a protected GKI KMI symbol**:

```
kernel/module/main.c:1298  verify_exported_symbols()
    if (!mod->sig_ok && gki_is_module_protected_export(name)) {
        pr_err("%s: exports protected symbol %s\n", ...);
        return -EACCES;
    }
kernel/module/main.c:1128   (symmetric import-side -EACCES gate)
```

Our build signs with its **own** auto-generated key (`CONFIG_MODULE_SIG_KEY` unset → defaults to the absent
`certs/signing_key.pem`, so the build generates a fresh key; no `CONFIG_SYSTEM_TRUSTED_KEY` pinned). The owner
kept the **stock, Samsung-signed** `system_dlkm` → those GKI modules fail `sig_ok` on our kernel. The result,
measured on the real flash (`newkernel2` capture, clean boot, Magisk modules off):

| | stock baseline | our kernel |
|---|---|---|
| modules loaded | **541** | **480** |

The **61 missing** are exactly the GKI *network-protocol-family* modules that export protected symbols, plus
their dependents: `cfg80211`, `mac80211`, `qca_cld3_kiwi_v2`, `wonder` (Wi-Fi); `bluetooth`, `hci_uart`,
`btqca`, `btbcm`, `btpower`, `rfcomm`, `hidp`, `bt_fm_slim` (BT); `nfc`, `rfkill`, `can*`, `ieee802154*`,
`6lowpan`/`nhc_*`, `tipc`, `l2tp*`, `ppp*`/`pptp`, `usbnet` + USB-ethernet drivers, `diag`, `wwan`. Userspace
symptom: `wificond: Failed to get NL80211 family info` (no `cfg80211` → no `nl80211` family). The ~480
vendor_dlkm modules load because they export only vendor symbols (not in the GKI protected-export set), so the
gate never fires for them — which is why NFC/GPS/mobile-data appeared to work while Wi-Fi/BT/Hotspot did not.

**Fix applied:** disable `CONFIG_MODULE_SIG_PROTECT` in `gki_defconfig` (protection #7 — see §0.4 and the
`defconfig: disable Android GKI module protection` commit). With it unset, `gki_is_module_protected_export()`
returns `false` and `gki_is_module_unprotected_symbol()` returns `true` (`kernel/module/internal.h:311-317`),
so both `-EACCES` gates are inert and the foreign-signed stock modules load (with a benign
`TAINT_UNSIGNED_MODULE` notice). Keeps every stock partition; owner re-flashes only `boot.img`.
**Fallback (not needed unless disabling breaks the build):** flash our *matched* `system_dlkm.img` +
`vendor_dlkm.img` — our own modules are signed with our key, so they pass the gate with the protection left on.
**Verification:** re-flash the new `boot.img`, `lsmod | wc -l` should reach ~541, and Wi-Fi/BT/Hotspot toggle
on. If any module still misses, capture `dmesg` for `exports protected symbol` / `Unknown symbol`.

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
| **#7 GKI module protection** | `CONFIG_MODULE_SIG_PROTECT` (Android GKI addition; `depends on MODULE_SIG && !MODULE_SIG_FORCE`) | `common/kernel/module/{Kconfig:134, main.c:1128/:1298, gki_module.c, internal.h:308-317, signing.c:96}` | **YES** — `=y` at `gki_defconfig:105` | **No** (grep `select MODULE_SIG_PROTECT` → none) | **defconfig** — `# CONFIG_MODULE_SIG_PROTECT is not set`. Not a boot-blocker — it silently rejected the **stock, Samsung-signed** GKI net modules (Wi-Fi/BT/NFC; `!sig_ok` + protected export → `-EACCES`) because our kernel signs with its own key. Confirmed on the 2026-08-14 flash (§0.3.1). Would also have blocked `kernelsu.ko` (Phase 3). |
| Other (present in tree) | `security/samsung/{dsms, kumiho, mz, mz_tee_driver, ddar}` also exist. No `CONFIG_DSMS=y` seen in `gki_defconfig`. | `common/security/samsung/…` | relevance TBD | — | Primary boot/LKM blockers are UH/RKP/KDP + DEFEX + PROCA (+FIVE). Others recorded for completeness; revisit only if a boot log implicates them. |

## 0.5 Toolchain & module-loading config

| Field | Value |
|---|---|
| Clang version referenced by Samsung's scripts | **`r487747c`** *(blocking — resolved)* |
| Where referenced (file:line) | `common/build.config.constants:2` and `msm-kernel/build.config.constants:2` (`CLANG_VERSION=r487747c`); path form `prebuilts/clang/host/linux-x86/clang-${CLANG_VERSION}/bin` at `common/build.config.common:7` |
| AOSP prebuilt still available? / URL | To confirm in Phase 1. Candidates: AOSP `prebuilts/clang/host/linux-x86` (`clang-r487747c`) at `android.googlesource.com`; Samsung also hosts toolchains at `opensource.samsung.com/uploadSearch?searchValue=toolchain` (per README). The **id `r487747c` is the blocking value and is known** — this matches the example already in `scripts/setup-toolchain.sh`. |
| `CONFIG_LTO_CLANG_*` in e3q defconfig | Not a defconfig value — LTO is a **Kleaf `--lto` build flag**. **The stock kernel is built with `--lto=none`**: the device's live `/proc/config.gz` shows `CONFIG_LTO_NONE=y` (and `CONFIG_CC_VERSION_TEXT` = clang `r487747c`). So to match stock module ABI we build with **`lto=none`**, and that is the default of `build.sh` / the workflow input. (The clang *binary* is itself built with LTO/PGO/BOLT — the `+lto` in CC_VERSION_TEXT — but the *kernel* is `LTO_NONE`.) *(blocking — resolved: stock = none)* |
| `CONFIG_CFI_CLANG` | **`=y`** (`common/gki_defconfig:99`; `msm-kernel/gki_defconfig:97`) *(blocking — resolved)* |
| `CONFIG_MODVERSIONS` | **`=y`** (`common/gki_defconfig:102`; `msm-kernel/gki_defconfig:100`) *(blocking — resolved)* |
| `CONFIG_MODULE_SIG` / `CONFIG_MODULE_SIG_FORCE` / `CONFIG_MODULE_SIG_PROTECT` | `MODULE_SIG=y` (`common/gki_defconfig:104`), `MODULE_SIG_FORCE` NOT set (only the unrelated `vendor/neo*.config` set it). **`MODULE_SIG_PROTECT` was `=y` and is now `# … is not set`** (`:105`) — see §0.3.1. The `⚠ flag` on `MODULE_SIG_PROTECT` was correct: it does **not** care whether signing is *forced* — its two `-EACCES` gates (`main.c:1128`, `:1298`) reject any `!sig_ok` module that touches a protected GKI KMI symbol. That silently killed Wi-Fi/BT/NFC (61 stock GKI modules) on the 2026-08-14 flash. Disabling it is protection #7. **Same gate would have rejected the out-of-tree `kernelsu.ko` in Phase 3** had we left it on. *(blocking — resolved: MODULE_SIG_PROTECT off; unsigned/foreign-signed `.ko` now load with a taint)* |
| `CONFIG_KPROBES` / `HAVE_KPROBES` / `KPROBE_EVENTS` | **`KPROBES=y`** already (`common/gki_defconfig:96`). `HAVE_KPROBES` is arch-selected (`common/arch/arm64/Kconfig:213 select HAVE_KPROBES`). `KPROBE_EVENTS` not in defconfig (tracing-only, not required for KSU LKM hooks). ✅ **No kprobes-enablement patch needed** — the LKM's hooking prerequisite is satisfied out of the box. *(blocking — resolved)* |
| `CONFIG_WERROR` | Not found in `gki_defconfig` (may be applied via build flag). Non-blocking. |

### Build prerequisites the OSRC drop does NOT ship (Phase 1 blocker to solve)

The Samsung drop contains **no `kernel_platform/prebuilts/` directory**, but the Kleaf build loads its
toolchain and host tools from bazel packages under `//prebuilts/…`. So the source is **not self-contained**;
CI must reconstruct the android14-6.1 kernel `prebuilts/` set before it can build. Referenced projects (from
`grep -oE '//prebuilts/…'` over `build/` and `msm-kernel/`):

| Bazel path | Purpose | Refs |
|---|---|---|
| `//prebuilts/clang/host/linux-x86` | Clang `r487747c` **+ the `kleaf/` registration** (`register.bzl`, `versions.bzl`) that `build/kernel/kleaf/workspace.bzl:27` loads | 9 |
| `//prebuilts/kernel-build-tools` | mkbootimg/avbtool/lz4/etc. host tools | 15 |
| `//prebuilts/build-tools` | general host build tools + `py_toolchain` | 10 |
| `//prebuilts/clang-tools` | `bindgen` (`kernel_env.bzl:457`) | 1 |
| `//prebuilts/rust/linux-x86` | Rust toolchain | 1 |
| `//prebuilts/bazel`, `//prebuilts/jdk/jdk11/linux-x86` | bazel `remote_java_tools`, JDK11 (`workspace.bzl:120-135`) | — |

**Resolved from ground truth — the AOSP GKI manifest** `android.googlesource.com/kernel/manifest`, branch
**`common-android14-6.1`** (`default.xml`). It pins every prebuilt at revision **`main-kernel-build-2023`**,
each `clone-depth=1`, from `android.googlesource.com`. The exact projects `scripts/setup-toolchain.sh` fetches
into `kernel_platform/prebuilts/`:

| Fetched into `prebuilts/` | googlesource repo | Notes |
|---|---|---|
| `clang/host/linux-x86` | `platform/prebuilts/clang/host/linux-x86` | sparse checkout: `clang-r487747c` + `kleaf/` only (full repo is ~40 GB) |
| `build-tools` | `platform/prebuilts/build-tools` | |
| `clang-tools` | `platform/prebuilts/clang-tools` | `bindgen` |
| `kernel-build-tools` | `kernel/prebuilts/build-tools` | mkbootimg/avbtool/lz4/… |
| `bazel/linux-x86_64` | `platform/prebuilts/bazel/linux-x86_64` | |
| `jdk/jdk11` | `platform/prebuilts/jdk/jdk11` | |
| `ndk-r23` | `toolchain/prebuilts/ndk/r23` | referenced by `workspace.bzl` |
| `gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8` | `platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8` | host glibc **sysroot** for the hermetic tools |

The gcc entry is easy to miss: nothing in a BUILD file references `prebuilts/gcc` (grep is clean), but the tree
reaches its `sysroot` via the symlink `build/kernel/build-tools/sysroot -> ../../../prebuilts/gcc/.../sysroot`.
Omitting it made `//build/kernel`'s `sysroot` glob empty and the `hermetic_tools_toolchain` fail to register —
CI run #1's failure. Method to catch such cases: enumerate every in-tree symlink whose target is under
`prebuilts/` (that set is exactly `build-tools`, `kernel-build-tools`, `clang-tools`, and this `gcc` sysroot).

**Not fetched:** `prebuilts/rust` (the GKI manifest doesn't include it → `CONFIG_RUST` is off for us).
Samsung's own `kernel_platform/gcc/` (a different path, a full GCC toolchain) stays excluded — unreferenced.
`build/`, `common/`, `external/` are already in the Samsung tree. `prebuilts/bazel/common` is referenced by
`workspace.bzl` but not in the manifest — still flagged, though run #1 got past bazel startup so it may be
optional. The workflow caches `kernel_platform/prebuilts/` so the ~6 GB fetch is a one-time cost.

## 0.6 Boot images, ramdisk & verified boot *(blocking — resolved)*

| Field | Value |
|---|---|
| Separate `init_boot` partition? | **YES** — `BOOT_IMAGE_HEADER_VERSION=4` (`msm-kernel/build.config.msm.pineapple:13`). Boot header v4 moves the generic ramdisk out of `boot` into `init_boot`. *(blocking — resolved from source; device confirmation trivial)* |
| Where the generic ramdisk lives | **`init_boot`** (header v4). `boot.img` = kernel only; vendor ramdisk lives in `vendor_boot`. Matches the CLAUDE.md partition table. *(blocking — resolved)* |
| Ramdisk compression | **`lz4`** — CONFIRMED by parsing the owner's stock `init_boot.img`: its ramdisk (at page 1) starts with the lz4 legacy magic `02 21 4c 18`. Repack tooling for `init_boot` (Phase 3) must use lz4. |
| SEANDROIDENFORCE footer present on stock images? | **`boot.img`: YES** — the literal `SEANDROIDENFORCE` string is appended right after the kernel (at byte 38,010,880 of the owner's stock `boot.img`). **`init_boot.img` / `vendor_boot.img`: NO.** So our repacked `boot.img` **must** re-append `SEANDROIDENFORCE`; our repacked `init_boot` (Phase 3) does not need it. Not in kernel source (a packaging/Category-B step). |
| vbmeta / AVB: what must be disabled to boot a modified image | Source signs `boot.img` via `avbtool add_hash_footer --algorithm SHA256_RSA4096 --partition_name boot` (`msm-kernel/avb_boot_img.bzl`). **Owner-confirmed: the current ROM already ships a patched/disabled vbmeta**, so a self-built `boot`+`init_boot` boots without an extra AVB step — *provided a stock `vbmeta` is never re-flashed over it*. `scripts/package.sh`/`FLASHING.md` will still emit the `--disable-verity --disable-verification` vbmeta guidance as the safety net. *(resolved)* |
| Does the current custom ROM already disable verity/verification? | **YES** — BeyondROM 5.0 (DZDP) ships with vbmeta already patched (owner-confirmed). *(resolved)* |
| KMI / Android version string | **`android14-6.1`** (`common/build.config.constants:1` and `msm-kernel/build.config.constants:1`, `BRANCH=android14-6.1`). This is the SUSFS branch key → target `susfs4ksu` branch `gki-android14-6.1`. (Platform is Android 16, but the KMI generation is android14-6.1.) *(needed for SUSFS branch match — resolved)* |

**Our `boot.img` rebuild recipe (from parsing the owner's stock images, `BeyondROM_images/`):** the stock
`boot.img` is header **v4**, kernel-only (`ramdisk_size=0`), `os_version 14.0.0`, `os_patch_level 2026-04`,
empty cmdline; the real kernel cmdline lives in `vendor_boot.img`
(`video=vfb:… printk.devkmsg=on firmware_class.path=/vendor/firmware_mnt/image bootconfig loop.max_part=7`),
which we keep stock. So `scripts/package.sh` builds our boot image as
`mkbootimg --header_version 4 --os_version 14.0.0 --os_patch_level 2026-04 --kernel <our Image> -o boot.img`
then appends the `SEANDROIDENFORCE` footer. **No stock `boot.img` is needed in CI** — these header values are
the only inputs, and they are recorded here. (`init_boot.img` = kernel-less, lz4 ramdisk ~1.44 MB carrying the
generic ramdisk + the owner's Magisk, which is where KernelSU's LKM goes in Phase 3.)

**Full stock `boot.img` trailer, and why we reproduce only the first part.** Parsing the whole stock
partition (not just the SEANDROIDENFORCE offset) shows three appended blocks after the page-aligned kernel:

| Offset | Block | Size | We reproduce it? |
|---|---|---|---|
| `38,010,880` | `SEANDROIDENFORCE` | 16 B | **Yes** — SELinux-enforce marker the bootloader reads right after the kernel. `package.sh` appends it. |
| `38,010,896` | **Samsung `SignerVer02`** | 512 B | **No.** Samsung's own signed footer — ASCII header `SignerVer02` + build metadata (`S928BXXU5DZDP`, `SM-S928B_EUR_XX_QKEY2`, `SRPWG28B005`, `boot.img`, timestamp `20260423172902`) followed by an RSA signature. We do **not** have Samsung's private key, so this is **not reproducible**, and on an **unlocked** bootloader it is **not verified**. |
| `38,014,976` | **AVB** (`AVB0` vbmeta + `AVBf` footer at partition end) | 2112 B + 64 B | **No.** Android Verified Boot metadata; not checked because the ROM's `vbmeta` is patched (`--disable-verification`). |

So our repacked `boot.img` is **byte-for-byte identical to stock through the SEANDROIDENFORCE footer**
(38,010,896 B — verified by reconstructing it from the stock kernel and diffing) and deliberately omits the
Samsung signature and the AVB footer. **Precedent this device already gives us:** the owner's Magisk-patched
`init_boot` carries no valid Samsung signature and boots — direct evidence that this unlocked, patched-vbmeta
device boots images lacking Samsung's `SignerVer02`. Not a guarantee our `boot.img` boots (only a flash proves
that), but the mechanism is established, not assumed.

## 0.7 Device / flashing environment *(owner-supplied)*

| Field | Value |
|---|---|
| Current ROM (name + version) | **BeyondROM 5.0**, firmware base **DZDP** (thread: `xdaforums.com/t/…4654134/`). Base firmware **matches this source drop** (`S928BXXU5DZDP`) — good for module ABI. |
| Current root method | **Magisk Alpha** (`e8a58776-alpha`), a closed-source Magisk fork prepatched into the ROM. Owner plans to remove it before we install KernelSU Next. |
| Kernel flasher app in use | **TWRP** (`twrp_e3q` 3.7.1, owner-confirmed working via recovery.log 2026-08-14). Simplest method: *Install Image* of the raw `boot.img` → Boot (`FLASHING.md` §3a). The **AnyKernel3** zip also works from **build ≥ #7** — build #6's zip aborted because AK3 ships 32-bit tools and **this device is 64-bit-only** (`ro.product.cpu.abilist32` empty); `package.sh` now overlays arm64 tools from pinned Magisk v28.1 (`DECISIONS.md` 2026-08-14). Odin `boot.tar.md5` = PC fallback. |
| Stock images backed up? (`boot` / `init_boot` / `vendor_boot` / `vendor_dlkm`) | **No independent backup.** Rollback currently relies on the ROM's own images + Magisk's uninstall/restore. **See the risk note below — this is not yet a complete rollback path.** *(blocking before any flash)* |
| Location of backups | `TBD` |
| Coresight/ETM present? | **Present** — `coresight-*.ko` are in `modules.load` (informational only; AutoFDO already dropped). |

> **ROLLBACK-PATH RISK (must resolve before the first flash — not before build work).**
> The proposed fallback (uninstall Magisk Alpha to "restore original images") only covers **`boot`/`init_boot`**
> — the partitions Magisk itself patched. Our module pipeline also repacks **`vendor_boot`/`vendor_dlkm`**, and
> those live inside `super` — **Magisk never backs them up**, so a Magisk restore cannot undo a bad
> `vendor_dlkm` flash. The complete, reliable rollback is the **stock `S928BXXU5DZDP` firmware** (which matches
> this source): download the official 4-file firmware for this exact build and keep the `AP_*.tar.md5` (it
> contains pristine `boot.img`, `init_boot.img`, `vendor_boot.img`, and `super.img`→`vendor_dlkm`). Odin-flashing
> that stock AP is the guaranteed recovery. **Recommended owner action before Phase 1's flash step:** obtain and
> stash that stock DZDP firmware off-device. (Build/CI work in Phase 1 does not need it; the flash step does.)

## Open questions

- Exact internal bazel `_dist` label produced by `prepare_vendor.sh pineapple gki` (non-blocking — the
  documented `prepare_vendor.sh` invocation is the canonical build entry that `scripts/build.sh` will wrap).
- ~~Effect of `CONFIG_MODULE_SIG_PROTECT=y` on loading the out-of-tree `kernelsu.ko`~~ — **RESOLVED 2026-08-14**:
  the protection was rejecting the *stock* GKI modules (Wi-Fi/BT/NFC, 61 of them) on our own-key-signed kernel,
  which would equally have blocked `kernelsu.ko`. Now disabled in `gki_defconfig` (protection #7, §0.3.1/§0.5).
- Effect of disabling `CONFIG_UH` on early boot (uH is Samsung's micro-hypervisor, initialized before the
  kernel) — the standard custom-kernel approach, but verify at first boot in Phase 3.
- Doc drift (Android 16 platform vs `android14-6.1` KMI): **recorded in `DECISIONS.md` 2026-08-12.**
- Stock `init_boot` ramdisk compression: source default is `lz4`; confirm by unpacking the real image
  (deferred to Phase 3 when we first repack `init_boot`).
- Rollback path: owner has no independent stock backup; the stock DZDP firmware must be stashed before the
  first flash (`DECISIONS.md` 2026-08-12, §0.7).
