#!/usr/bin/env bash
#
# Package the build output.
#
# FIRST VERSION — bundles the compiled kernel + modules into a zip so CI has an
# uploadable artifact and we can inspect the real dist layout from a green run. The
# actual flashable repack (boot.img / init_boot.img / vendor_dlkm, SEANDROIDENFORCE
# footer, vbmeta guidance, AnyKernel3) is written once the first compile succeeds and we
# know the artifact set — see docs/PLAN.md Phase 1 and the e3q-kernel skill. Category-B
# steps (SEANDROIDENFORCE, vbmeta, lz4 ramdisk) live here, not in the kernel source.
#
# Env: WITH_KERNELSU / WITH_SUSFS are consumed by later phases; ignored in this version.

set -euo pipefail

ROOT="$PWD"
DIST="$ROOT/out/dist"

[[ -d "$DIST" ]] || { echo "ERROR: $DIST missing — build.sh did not stage artifacts." >&2; exit 1; }
if ! ls "$DIST"/Image* >/dev/null 2>&1; then
  echo "ERROR: no kernel Image in $DIST — build likely failed." >&2
  exit 1
fi

# Sanity — refuse to package an obviously broken/partial build.
_nmods="$(find "$DIST" -maxdepth 1 -name '*.ko' | wc -l)"
(( _nmods > 0 )) || { echo "ERROR: no .ko modules staged in $DIST — a kernel with no modules is not usable." >&2; exit 1; }
_empty="$(find "$DIST" -maxdepth 1 -type f -empty ! -name '*.zip' 2>/dev/null)"
if [[ -n "$_empty" ]]; then
  echo "WARN: zero-byte artifact(s) present — build may be incomplete:" >&2
  echo "$_empty" >&2
fi
echo "==> packaging Image + $_nmods modules"

STAMP="$(date -u +%Y%m%d)"
ZIP="e3q-kernel-${STAMP}.zip"

echo "==> Bundling kernel + modules -> $DIST/$ZIP"
( cd "$DIST" && rm -f "$ZIP" && zip -q -r "$ZIP" . -x '*.zip' )

echo "==> Artifact:"
ls -la "$DIST/$ZIP"
echo "NOTE: this is a raw kernel+module bundle, not yet a flashable image. Full repack is"
echo "      the next Phase 1 step, after this first compile confirms the artifact layout."
