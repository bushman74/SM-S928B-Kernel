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
#   LTO_MODE   none|thin|full  (default thin)
#   WITH_KERNELSU / WITH_SUSFS consumed in later phases; ignored here
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

LTO="${LTO_MODE:-thin}"
OUT_DIR="$ROOT/out/kbuild"
DIST_DIR="$ROOT/out/dist"
mkdir -p "$OUT_DIR" "$DIST_DIR"

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
init_boot.img
PATS

echo "==> Staged into $DIST_DIR:"
ls -la "$DIST_DIR"
echo "==> $(find "$DIST_DIR" -maxdepth 1 -name '*.ko' | wc -l) modules, Image present: $(ls "$DIST_DIR"/Image* 2>/dev/null | head -1 || echo NO)"
