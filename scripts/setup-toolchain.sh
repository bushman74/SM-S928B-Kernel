#!/usr/bin/env bash
#
# Fetch the Clang toolchain used to build this kernel.
#
# STATUS: SKELETON. The reference Clang build id is unknown until Phase 0 discovery
# fills in docs/FACTS.md §0.5. Do not guess it — a mismatched toolchain silently
# changes module ABI. This script fails loudly rather than picking something plausible.
#
# Usage: ./scripts/setup-toolchain.sh <reference|clang-build-id>

set -euo pipefail

TOOLCHAIN_ARG="${1:-reference}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$PWD/toolchain}"

# Filled in during Phase 0 from Samsung's own build scripts. See docs/FACTS.md §0.5.
REFERENCE_CLANG_BUILD_ID=""   # e.g. "r487747c" — READ IT, DON'T GUESS IT

AOSP_CLANG_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main"

if [[ "$TOOLCHAIN_ARG" == "reference" ]]; then
  if [[ -z "$REFERENCE_CLANG_BUILD_ID" ]]; then
    cat >&2 <<'EOF'
ERROR: REFERENCE_CLANG_BUILD_ID is not set.

This is intentional. Phase 0 discovery must determine which Clang Samsung's build
scripts reference, and record it in docs/FACTS.md §0.5, before any build happens.

To find it, grep the extracted source archive:

    grep -rn 'clang-r[0-9]' <extracted>/ | head
    grep -rn 'prebuilts/clang' <extracted>/ | head

Then set REFERENCE_CLANG_BUILD_ID above to the value you actually saw.
EOF
    exit 1
  fi
  CLANG_BUILD_ID="$REFERENCE_CLANG_BUILD_ID"
else
  CLANG_BUILD_ID="$TOOLCHAIN_ARG"
fi

echo "==> Toolchain: clang-${CLANG_BUILD_ID}"
mkdir -p "$TOOLCHAIN_DIR"

if [[ -x "$TOOLCHAIN_DIR/clang-${CLANG_BUILD_ID}/bin/clang" ]]; then
  echo "==> Already present, skipping download."
else
  echo "==> Downloading..."
  # NOTE: many Samsung/Qualcomm trees vendor their own toolchain under
  # kernel_platform/prebuilts/. If Phase 0 finds one there, prefer it over
  # downloading — it is guaranteed to be the version the tree was tested with.
  # Record which path we took in docs/DECISIONS.md.
  mkdir -p "$TOOLCHAIN_DIR/clang-${CLANG_BUILD_ID}"
  curl -fsSL "${AOSP_CLANG_BASE}/clang-${CLANG_BUILD_ID}.tar.gz" \
    | tar -xz -C "$TOOLCHAIN_DIR/clang-${CLANG_BUILD_ID}"
fi

"$TOOLCHAIN_DIR/clang-${CLANG_BUILD_ID}/bin/clang" --version

# CLANG_PATH goes in the env file; the PATH prepend MUST go in GITHUB_PATH.
# Writing PATH= into GITHUB_ENV clobbers the runner's PATH for every later step
# and breaks tools installed by earlier steps.
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "CLANG_PATH=$TOOLCHAIN_DIR/clang-${CLANG_BUILD_ID}/bin" >> "$GITHUB_ENV"
fi
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$TOOLCHAIN_DIR/clang-${CLANG_BUILD_ID}/bin" >> "$GITHUB_PATH"
fi

echo "==> Toolchain ready."
