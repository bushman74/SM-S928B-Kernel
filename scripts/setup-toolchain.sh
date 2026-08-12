#!/usr/bin/env bash
#
# Populate kernel_platform/prebuilts/ with the toolchain and host tools the Kleaf
# build needs. The Samsung OSRC drop ships the kernel source but NOT prebuilts/, so
# without this step the bazel build fails loading //prebuilts/clang/... and friends.
#
# Ground truth: the AOSP GKI manifest (android.googlesource.com/kernel/manifest,
# branch common-android14-6.1) pins each prebuilt project at revision
# main-kernel-build-2023. See docs/FACTS.md §0.5. Nothing here is guessed — the repo
# names, paths, and revision are read from that manifest.
#
# STATUS: first version. It cannot be exercised in the dev sandbox (no disk/time for a
# multi-GB fetch + build); the first CI run is its verification. Reference Clang is
# r487747c (build.config.constants:2) — do not guess it.
#
# Usage: scripts/setup-toolchain.sh [reference|<clang-build-id>]

set -euo pipefail

REFERENCE_CLANG_BUILD_ID="r487747c"          # kernel_platform/common/build.config.constants:2
MANIFEST_REV="main-kernel-build-2023"        # pinned by the common-android14-6.1 manifest
GOOGLESOURCE="https://android.googlesource.com"

KP="${KP:-$PWD/kernel_platform}"
PREBUILTS="$KP/prebuilts"

CLANG_ID="${1:-reference}"
[[ "$CLANG_ID" == "reference" ]] && CLANG_ID="$REFERENCE_CLANG_BUILD_ID"

[[ -d "$KP" ]] || { echo "ERROR: $KP not found — run from the repo root." >&2; exit 1; }
mkdir -p "$PREBUILTS"

# Retry git over flaky networks: 4 tries, exponential backoff (2/4/8s).
git_retry() {
  local n=0
  until git "$@"; do
    n=$((n + 1))
    (( n >= 4 )) && { echo "ERROR: 'git $*' failed after $n attempts." >&2; return 1; }
    local d=$((2 ** n)); echo "  git failed, retry $n in ${d}s..." >&2; sleep "$d"
  done
}

# shallow_clone <googlesource-repo-name> <dest-under-prebuilts>
shallow_clone() {
  local name="$1" dest="$PREBUILTS/$2"
  if [[ -d "$dest/.git" ]]; then echo "==> prebuilts/$2 present, skipping"; return; fi
  echo "==> fetching $name @ $MANIFEST_REV -> prebuilts/$2"
  rm -rf "$dest"; mkdir -p "$(dirname "$dest")"
  git_retry clone --depth=1 --branch "$MANIFEST_REV" "$GOOGLESOURCE/$name" "$dest"
}

# Clang lives in one enormous repo (every version). Fetch only clang-$CLANG_ID and the
# kleaf/ registration via a blobless sparse checkout instead of the ~40 GB full tree.
fetch_clang() {
  local dest="$PREBUILTS/clang/host/linux-x86"
  if [[ -x "$dest/clang-$CLANG_ID/bin/clang" ]]; then
    echo "==> clang-$CLANG_ID present, skipping"; return
  fi
  echo "==> fetching clang-$CLANG_ID + kleaf registration (sparse) @ $MANIFEST_REV"
  rm -rf "$dest"; mkdir -p "$(dirname "$dest")"
  git_retry clone --filter=blob:none --no-checkout --depth=1 --branch "$MANIFEST_REV" \
    "$GOOGLESOURCE/platform/prebuilts/clang/host/linux-x86" "$dest"
  git -C "$dest" sparse-checkout init --cone
  git -C "$dest" sparse-checkout set "clang-$CLANG_ID" kleaf
  git_retry -C "$dest" checkout
  [[ -x "$dest/clang-$CLANG_ID/bin/clang" ]] || {
    echo "ERROR: clang-$CLANG_ID is not in the $MANIFEST_REV tree." >&2; exit 1; }
  "$dest/clang-$CLANG_ID/bin/clang" --version
  if [[ -f "$dest/kleaf/versions.bzl" ]] && ! grep -q "$CLANG_ID" "$dest/kleaf/versions.bzl"; then
    echo "WARN: $CLANG_ID absent from kleaf/versions.bzl — bazel may not register it." >&2
  fi
}

fetch_clang
shallow_clone "platform/prebuilts/build-tools"        "build-tools"
shallow_clone "platform/prebuilts/clang-tools"        "clang-tools"
shallow_clone "kernel/prebuilts/build-tools"          "kernel-build-tools"
shallow_clone "platform/prebuilts/bazel/linux-x86_64" "bazel/linux-x86_64"
shallow_clone "platform/prebuilts/jdk/jdk11"          "jdk/jdk11"
shallow_clone "toolchain/prebuilts/ndk/r23"           "ndk-r23"
# Host glibc sysroot for the hermetic tools. Not referenced in any BUILD file, so easy to
# miss — the tree reaches it via the symlink build/kernel/build-tools/sysroot ->
# ../../../prebuilts/gcc/.../sysroot. Without it, //build/kernel's `sysroot` glob is empty
# and the hermetic_tools_toolchain never registers (first CI failure, run #1).
shallow_clone "platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8" \
              "gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8"

# --- Verify the fetch, loudly, before the build wastes time on a broken toolchain ---
echo "==> Verifying prebuilts..."
fail=0

# 1. Every project we expect is present and non-empty.
for d in "clang/host/linux-x86/clang-$CLANG_ID/bin" \
         "build-tools" "clang-tools" "kernel-build-tools" \
         "bazel/linux-x86_64" "jdk/jdk11" "ndk-r23" \
         "gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot"; do
  if [[ ! -e "$PREBUILTS/$d" || -z "$(ls -A "$PREBUILTS/$d" 2>/dev/null)" ]]; then
    echo "  FAIL: prebuilts/$d is missing or empty" >&2; fail=1
  fi
done

# 2. Clang actually executes (not just present).
if ! "$PREBUILTS/clang/host/linux-x86/clang-$CLANG_ID/bin/clang" --version >/dev/null 2>&1; then
  echo "  FAIL: clang-$CLANG_ID is present but does not run" >&2; fail=1
fi

# 3. The generalized check for CI run #1's failure class: every in-tree symlink that points
#    into prebuilts/ must now resolve. This catches a *missing* prebuilt (e.g. the gcc
#    sysroot) here — at fetch time, with the exact dangling path named — instead of as a
#    cryptic bazel "glob didn't match anything" error minutes into the build.
mapfile -t _dangling < <(find "$KP" -type l -lname '*prebuilts*' '!' -exec test -e {} ';' -print 2>/dev/null)
if (( ${#_dangling[@]} )); then
  echo "  FAIL: ${#_dangling[@]} in-tree symlink(s) into prebuilts/ do not resolve:" >&2
  for _l in "${_dangling[@]}"; do echo "    $_l -> $(readlink "$_l")" >&2; done
  echo "    (a prebuilt project is missing from the fetch list above)" >&2
  fail=1
fi

if (( fail )); then
  echo "ERROR: prebuilts verification FAILED (see FAIL lines). The build would fail later; stopping now." >&2
  exit 1
fi

echo "==> prebuilts OK under $PREBUILTS"
echo "    clang: $PREBUILTS/clang/host/linux-x86/clang-$CLANG_ID"
