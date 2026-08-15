#!/usr/bin/env bash
# patch-init-boot.sh — produce a KernelSU-Next (LKM) init_boot.img for the S24 Ultra (e3q).
#
# Phase 3 packaging step. Category: artifact/packaging, NOT kernel source — like package.sh it
# only repacks a partition image; it never edits the kernel tree.
#
# Pipeline (every step was validated on the owner's real init_boot.img, 2026-08-15; see FACTS §0.6):
#   1. Restore. The owner's stock init_boot is Magisk-patched, and `ksud` REFUSES a Magisk-patched
#      image. We first reverse Magisk with magiskboot (`cpio restore`), which recovers the stock
#      generic ramdisk from the embedded .backup/ (original `init`, no overlay.d, no .backup).
#   2. Patch. `ksud boot-patch -m <our kernelsu.ko>` installs the LKM: it renames init -> init.real,
#      drops in ksuinit as the new `init`, adds our kernelsu.ko + ksu_config, and repacks
#      (header v4, lz4_legacy). ksud embeds ksuinit + magiskboot; its x86_64 host binary runs in CI.
#   3. Verify. Assert the output ramdisk carries init.real (the stock init) AND our exact
#      kernelsu.ko (by sha256) — so we know ksud injected OUR module, not its bundled fallback.
#
# CRITICAL: --kmod MUST be a kernelsu.ko built against THIS kernel (CONFIG_KSU=m) so its
# vermagic/symbol-CRCs match. The generic prebuilt android14-6.1_kernelsu.ko will very likely
# refuse to load on our Samsung KMI. This script does not build the module — CI builds it, then
# feeds it here. (MODULE_SIG_PROTECT is off, protection #7, so the unsigned .ko is allowed to load.)
#
# Not tested = not flashed. This produces an artifact; booting is proven only on the device.

set -euo pipefail

# ---- pinned tool versions (do not float) --------------------------------------------------
KMI="${KMI:-android14-6.1}"                        # our KMI generation (FACTS §0.2 / §0.6)
KSUN_TAG="v3.3.0"                                  # KernelSU-Next, pinned (DECISIONS 2026-08-15)
KSUD_URL="https://github.com/KernelSU-Next/KernelSU-Next/releases/download/${KSUN_TAG}/ksud-x86_64-unknown-linux-musl"
KSUD_SHA256="f450a7f60990e761cbf884018aea1b03317d85a7929e1572c0ed68e6b42bc953"
MAGISK_VER="v28.1"                                 # same pin as scripts/package.sh
MAGISK_URL="https://github.com/topjohnwu/Magisk/releases/download/${MAGISK_VER}/Magisk-${MAGISK_VER}.apk"
MAGISK_SHA256="8bfd3346b3da5814f82eff6f1b1b5fedd0ad585f39a25709b23eb54aac45691d"

# ---- args ---------------------------------------------------------------------------------
INIT_BOOT=""; KMOD=""; OUT_DIR="./out"; OUT_NAME="init_boot_ksu.img"; ALLOW_SHELL=1
usage() {
  cat >&2 <<EOF
Usage: $0 --init-boot <stock init_boot.img> --kmod <kernelsu.ko> [options]
  --init-boot PATH   Stock init_boot.img (Magisk-patched is fine; it is restored first). REQUIRED.
  --kmod PATH        kernelsu.ko built against OUR kernel (CONFIG_KSU=m). REQUIRED.
  --out DIR          Output directory (default: ./out).
  --out-name NAME    Output filename (default: init_boot_ksu.img).
  --kmi KMI          KMI version (default: ${KMI}).
  --no-allow-shell   Do not force-allow root shell (default: allow).
Tool overrides (skip download): env MAGISKBOOT=/path/to/magiskboot, KSUD=/path/to/ksud.
EOF
  exit 2
}
while [ $# -gt 0 ]; do
  case "$1" in
    --init-boot) INIT_BOOT="${2:-}"; shift 2;;
    --kmod)      KMOD="${2:-}"; shift 2;;
    --out)       OUT_DIR="${2:-}"; shift 2;;
    --out-name)  OUT_NAME="${2:-}"; shift 2;;
    --kmi)       KMI="${2:-}"; shift 2;;
    --no-allow-shell) ALLOW_SHELL=0; shift;;
    -h|--help)   usage;;
    *) echo "Unknown arg: $1" >&2; usage;;
  esac
done
[ -n "$INIT_BOOT" ] && [ -f "$INIT_BOOT" ] || { echo "ERROR: --init-boot missing or not a file" >&2; usage; }
[ -n "$KMOD" ] && [ -f "$KMOD" ] || { echo "ERROR: --kmod missing or not a file (must be OUR kernelsu.ko)" >&2; usage; }

command -v curl     >/dev/null || { echo "ERROR: curl not found" >&2; exit 1; }
command -v unzip    >/dev/null || { echo "ERROR: unzip not found" >&2; exit 1; }
command -v sha256sum>/dev/null || { echo "ERROR: sha256sum not found" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT_DIR"; OUT_DIR="$(cd "$OUT_DIR" && pwd)"
INIT_BOOT="$(cd "$(dirname "$INIT_BOOT")" && pwd)/$(basename "$INIT_BOOT")"
KMOD="$(cd "$(dirname "$KMOD")" && pwd)/$(basename "$KMOD")"

fetch_verify() { # url sha256 dest
  curl -fsSL -o "$3" "$1"
  echo "$2  $3" | sha256sum -c - >/dev/null
}

# ---- resolve tools (pinned + sha256-gated, or env override) -------------------------------
if [ -n "${MAGISKBOOT:-}" ] && [ -x "${MAGISKBOOT:-}" ]; then
  MB="$MAGISKBOOT"; echo "==> Using MAGISKBOOT override: $MB"
else
  echo "==> Fetching magiskboot (x86_64) from Magisk ${MAGISK_VER}"
  fetch_verify "$MAGISK_URL" "$MAGISK_SHA256" "$WORK/magisk.apk"
  ( cd "$WORK" && unzip -oq magisk.apk 'lib/x86_64/libmagiskboot.so' )
  MB="$WORK/lib/x86_64/libmagiskboot.so"; chmod +x "$MB"
fi
if [ -n "${KSUD:-}" ] && [ -x "${KSUD:-}" ]; then
  KSUD_BIN="$KSUD"; echo "==> Using KSUD override: $KSUD_BIN"
else
  echo "==> Fetching ksud (x86_64) from KernelSU-Next ${KSUN_TAG}"
  fetch_verify "$KSUD_URL" "$KSUD_SHA256" "$WORK/ksud"
  KSUD_BIN="$WORK/ksud"; chmod +x "$KSUD_BIN"
fi

# ---- step 1: restore a clean stock init_boot ----------------------------------------------
echo "==> Step 1/3: restore stock generic ramdisk (reverse Magisk if present)"
CLEAN="$WORK/init_boot_clean.img"
cp "$INIT_BOOT" "$WORK/in.img"
( cd "$WORK" && "$MB" unpack in.img >/dev/null 2>&1 )
RD="$WORK/ramdisk.cpio"
[ -f "$RD" ] || { echo "ERROR: magiskboot produced no ramdisk (is this an init_boot image?)" >&2; exit 1; }
if "$MB" cpio "$RD" ls 2>/dev/null | grep -Eq 'init\.real|kernelsu\.ko'; then
  echo "ERROR: input already looks KernelSU-patched; supply a stock or Magisk init_boot." >&2
  exit 1
fi
if "$MB" cpio "$RD" ls 2>/dev/null | grep -q '\.backup'; then
  echo "    input is Magisk-patched -> reversing Magisk (cpio restore)"
  "$MB" cpio "$RD" restore >/dev/null
else
  echo "    input has no Magisk backup -> treating as already clean"
fi
( cd "$WORK" && "$MB" repack in.img "$CLEAN" >/dev/null 2>&1 )
[ -f "$CLEAN" ] || { echo "ERROR: repack of clean init_boot failed" >&2; exit 1; }

# ---- step 2: install the KernelSU-Next LKM (OUR module) -----------------------------------
echo "==> Step 2/3: ksud boot-patch (KMI ${KMI}) with our kernelsu.ko"
PATCH_ARGS=( boot-patch -b "$CLEAN" -m "$KMOD" --kmi "$KMI" -o "$OUT_DIR" --out-name "$OUT_NAME" )
[ "$ALLOW_SHELL" -eq 1 ] && PATCH_ARGS+=( --allow-shell )
"$KSUD_BIN" "${PATCH_ARGS[@]}"
OUT_IMG="$OUT_DIR/$OUT_NAME"
[ -f "$OUT_IMG" ] || { echo "ERROR: ksud did not produce $OUT_IMG" >&2; exit 1; }

# ---- step 3: verify OUR module actually went in -------------------------------------------
echo "==> Step 3/3: verify patched image"
V="$WORK/verify"; mkdir -p "$V"; cp "$OUT_IMG" "$V/out.img"
( cd "$V" && "$MB" unpack out.img >/dev/null 2>&1 )
VRD="$V/ramdisk.cpio"
for e in init init.real kernelsu.ko ksu_config; do
  "$MB" cpio "$VRD" ls 2>/dev/null | grep -q "$e" \
    || { echo "ERROR: patched image is missing '$e'" >&2; exit 1; }
done
"$MB" cpio "$VRD" "extract kernelsu.ko $V/ko.out" >/dev/null 2>&1
got="$(sha256sum "$V/ko.out" | awk '{print $1}')"
want="$(sha256sum "$KMOD"     | awk '{print $1}')"
[ "$got" = "$want" ] \
  || { echo "ERROR: injected kernelsu.ko ($got) != our --kmod ($want): ksud used a bundled module!" >&2; exit 1; }

echo
echo "OK: $OUT_IMG"
echo "    ramdisk: init=ksuinit, init.real=stock init, kernelsu.ko=OUR module (sha256 ${got:0:16}...), ksu_config"
echo
echo "REMINDERS (not-flashed — this is an artifact, not a boot proof):"
echo "  * --kmod must be built against THIS kernel (vermagic). The generic prebuilt likely won't load."
echo "  * Flash BOTH our boot.img (kernel) and this ${OUT_NAME}. Back up your current init_boot first."
echo "  * Do not re-flash a stock vbmeta over the device afterwards (FACTS §0.6)."
echo "  * Verify: the KernelSU-Next manager shows the module active and grants root; then re-run REGRESSION.md."
