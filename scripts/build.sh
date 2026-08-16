#!/usr/bin/env bash
#
# Compile the e3q (SM8650 / pineapple) GKI kernel with the fetched toolchain.
#
# This calls the Kleaf builder that Samsung's prepare_vendor.sh ultimately invokes
# (build_with_bazel.py -t pineapple gki --lto=...), deliberately skipping
# prepare_vendor's Android-tree integration (ABL, devicetree overlay, ANDROID_PRODUCT_OUT)
# that a bare CI runner does not have. It produces the GKI Image + vendor .ko modules in
# out/dist/; turning those into flashable images is scripts/package.sh.
#
# Env (set by .github/workflows/build.yml):
#   LTO_MODE   none|thin|full  (default none — stock e3q is built LTO_NONE; see docs/FACTS.md §0.5)
#   KBUILD_BUILD_TIMESTAMP/USER/HOST  reproducibility, honored by kbuild if exported
#
# STATUS: first version. It cannot be run in the dev sandbox (no disk/time for a full
# Kleaf build); the CI run is its verification. If the dist layout differs from what is
# staged below, the run log shows the real paths and we adjust.

set -euo pipefail

ROOT="$PWD"
KP="$ROOT/kernel_platform"
CLANG_ID="r487747c"

[[ -d "$KP" ]] || { echo "ERROR: run from the repo root (no kernel_platform/)." >&2; exit 1; }
[[ -x "$KP/prebuilts/clang/host/linux-x86/clang-$CLANG_ID/bin/clang" ]] \
  || { echo "ERROR: clang prebuilt missing — run scripts/setup-toolchain.sh first." >&2; exit 1; }

LTO="${LTO_MODE:-none}"   # stock e3q builds LTO_NONE (FACTS §0.5); match it for ABI
OUT_DIR="$ROOT/out/kbuild"
DIST_DIR="$ROOT/out/dist"
mkdir -p "$OUT_DIR" "$DIST_DIR"

# --- Pre-flight: fail fast and clearly, before committing to a ~1 hour compile ---
echo "==> Pre-flight checks"
# Source integrity — is this the kernel we expect (guards a broken/partial checkout)?
_ver="$(sed -nE 's/^VERSION = //p; s/^PATCHLEVEL = //p; s/^SUBLEVEL = //p' "$KP/common/Makefile" | paste -sd. -)"
[[ "$_ver" == 6.1.* ]] || { echo "ERROR: unexpected kernel version '$_ver' in common/Makefile (want 6.1.x)." >&2; exit 1; }
# The hermetic-tools sysroot symlink must resolve — this is CI run #1's failure class,
# caught here in a millisecond instead of minutes into bazel analysis.
[[ -e "$KP/build/kernel/build-tools/sysroot" ]] \
  || { echo "ERROR: build/kernel/build-tools/sysroot does not resolve — prebuilts incomplete; run scripts/setup-toolchain.sh." >&2; exit 1; }
# Disk guard — a cold Kleaf build needs tens of GB; fail now, not mid-link with 'No space left'.
_avail_gb="$(df -BG --output=avail "$ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')"
[[ -z "$_avail_gb" || "$_avail_gb" -ge 25 ]] \
  || { echo "ERROR: only ${_avail_gb} GB free on $ROOT; a Kleaf build needs ~25+ GB. Free disk first." >&2; exit 1; }
echo "    kernel=$_ver  sysroot=ok  free=${_avail_gb:-?}GB  LTO=$LTO"

echo "==> Building pineapple/gki  (LTO=$LTO)"
cd "$KP"
# --skip abl: don't build the bootloader (ABL) dist target — it's firmware-coupled and we
# don't repack it. This matches Samsung's own prepare_vendor.sh invocation.
./build_with_bazel.py -t pineapple gki --skip abl --lto="$LTO" --out_dir "$OUT_DIR" \
  2>&1 | tee "$ROOT/out/build.log"

SRC="$OUT_DIR/dist"
if [[ ! -d "$SRC" ]]; then
  echo "ERROR: expected dist dir at $SRC. Actual Image/.ko locations:" >&2
  find "$OUT_DIR" -maxdepth 4 \( -name Image -o -name '*.ko' \) 2>/dev/null | head -20 >&2
  exit 1
fi

echo "==> Staging bootable artifacts into $DIST_DIR (skipping vmlinux/debug)"
# init_boot.img is intentionally NOT staged: the Kleaf build does not emit one. The generic ramdisk
# it would wrap is a prebuilt Samsung does not ship — get_gki_ramdisk_prebuilt_binary() returns None
# (msm-kernel/msm_kernel_extensions.bzl), so there is nothing to build init_boot from. Root on this
# device is delivered separately — by patching init_boot on-device with the KernelSU-Next manager —
# not by the compiler. Do not re-add init_boot.img here expecting a build output.
while IFS= read -r pat; do
  find "$SRC" -maxdepth 2 -name "$pat" -exec cp -a {} "$DIST_DIR/" \; 2>/dev/null || true
done <<'PATS'
Image
Image.lz4
Image.gz
*.ko
modules.load
modules.dep
modules.alias
system_dlkm*
vendor_dlkm*
*.dtb
dtb.img
dtbo.img
boot.img
vendor_boot.img
PATS

echo "==> Staged into $DIST_DIR:"
ls -la "$DIST_DIR"

# --- Post-build sanity: a green bazel exit is not proof the artifacts are usable ---
_img="$(ls "$DIST_DIR"/Image* 2>/dev/null | head -1 || true)"
_nmods="$(find "$DIST_DIR" -maxdepth 1 -name '*.ko' | wc -l)"
echo "==> Result: Image=${_img:-NONE}  modules=$_nmods"
[[ -n "$_img" ]] || { echo "ERROR: no kernel Image staged — the build produced no Image." >&2; exit 1; }
[[ -s "$_img" ]] || { echo "ERROR: staged Image is zero bytes." >&2; exit 1; }
if (( _nmods < 100 )); then
  echo "WARN: only $_nmods modules staged (pineapple gki normally builds ~300+). Possible partial build or config regression — check the log before trusting this artifact." >&2
fi

# --- Verify the Samsung protections we disable in source are actually OFF in the BUILT
#     kernel. This catches a defconfig edit that never reached the final config (e.g. the
#     wrong config file, or a fragment re-enabling it). Stock keeps CONFIG_IKCONFIG=y, so the
#     config is embedded in the Image and extractable. ---
_ikc="$KP/common/scripts/extract-ikconfig"
if [[ -f "$_ikc" ]]; then
  _builtcfg="$ROOT/out/built.config"
  if bash "$_ikc" "$_img" >"$_builtcfg" 2>/dev/null && [[ -s "$_builtcfg" ]]; then
    echo "==> Samsung protections in the BUILT kernel (expect all off):"
    _pfail=0
    for _s in UH RKP KDP SECURITY_DEFEX PROCA FIVE MODULE_SIG_PROTECT; do
      if grep -q "^CONFIG_${_s}=y" "$_builtcfg"; then
        echo "  STILL ON: CONFIG_${_s}=y" >&2; _pfail=1
      else
        echo "  off: CONFIG_${_s}"
      fi
    done
    (( _pfail == 0 )) || { echo "ERROR: a Samsung protection is still enabled in the built kernel — the defconfig disable did not take effect (wrong config file / a fragment re-enables it)." >&2; exit 1; }
    # --- Whole-config parity: beyond the protections being off, prove the BUILT kernel
    #     differs from stock ONLY by the allowlisted protection family — nothing else got
    #     dropped or flipped by a Kconfig ripple. This is the universal regression gate. ---
    echo "==> Whole-config parity vs stock baseline:"
    if ! bash "$ROOT/scripts/check-config-parity.sh" "$_builtcfg"; then
      echo "ERROR: built kernel diverges from stock outside the protection allowlist (see above)." >&2
      echo "       A non-protection CONFIG changed — do not trust this artifact until explained." >&2
      exit 1
    fi
  else
    echo "WARN: could not extract the config from the Image (IKCONFIG off?); skipping config verification." >&2
  fi
fi
