#!/usr/bin/env bash
#
# Import a new Samsung OSRC kernel source drop onto the pristine `vanilla` branch.
#
# The `vanilla` branch is import-only (see CLAUDE.md and docs/DECISIONS.md 2026-08-12): it
# holds ONLY unmodified Samsung source, one commit per firmware drop, tagged osrc/<build>.
# This script encodes exactly how a drop is parsed and committed there, so re-importing is
# mechanical and reproducible rather than a hand process.
#
# What it does:
#   1. Verifies the zip, derives the build string from its name, records its SHA256.
#   2. Extracts Kernel.tar.gz to a scratch dir OUTSIDE the repo.
#   3. Strips the bits we never commit (the GCC prebuilt + dangling build-machine bazel
#      symlinks) — matching what lives on `vanilla` today.
#   4. Builds the new `vanilla` commit in an ISOLATED git worktree (your working checkout is
#      never touched), then points `vanilla` + the osrc/<build> tag at it.
#   5. Prints the replay-onto-main steps; it does NOT push and does NOT modify `main`.
#
# Usage:
#   scripts/import-vanilla.sh /path/to/SM-S928B_<n>_Opensource_<BUILD>.zip
#
# After it runs, review and push:
#   git log --stat vanilla -1
#   git push origin vanilla && git push origin "osrc/<BUILD>"
# then replay our series (see docs/HANDBOOK.md "Re-importing a new Samsung drop").

set -euo pipefail

ZIP="${1:-}"
[[ -n "$ZIP" && -f "$ZIP" ]] || { echo "usage: scripts/import-vanilla.sh <opensource-drop.zip>" >&2; exit 1; }
ZIP="$(readlink -f "$ZIP")"

REPO="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
cd "$REPO"

# Derive the build string: ..._Opensource_<BUILD>.zip  ->  <BUILD>
BUILD="$(basename "$ZIP" .zip | sed -E 's/.*_[Oo]pensource_//')"
[[ -n "$BUILD" && "$BUILD" != "$(basename "$ZIP" .zip)" ]] \
  || { echo "ERROR: could not parse a build string from '$(basename "$ZIP")' (expected ..._Opensource_<BUILD>.zip)." >&2; exit 1; }
SHA="$(sha256sum "$ZIP" | awk '{print $1}')"
echo "==> Drop: build=$BUILD"
echo "==> SHA256: $SHA"

SCRATCH="$(mktemp -d)"
cleanup() { git worktree remove --force "$SCRATCH/wt" 2>/dev/null || true; rm -rf "$SCRATCH"; }
trap cleanup EXIT

echo "==> Extracting outside the repo ($SCRATCH)"
unzip -q "$ZIP" -d "$SCRATCH"
[[ -f "$SCRATCH/Kernel.tar.gz" ]] || { echo "ERROR: no Kernel.tar.gz inside $ZIP (unexpected drop layout)." >&2; exit 1; }
mkdir -p "$SCRATCH/k"
tar -xzf "$SCRATCH/Kernel.tar.gz" -C "$SCRATCH/k"
SRC="$SCRATCH/k"
for p in kernel_platform vendor build_kernel_GKI.sh; do
  [[ -e "$SRC/$p" ]] || { echo "ERROR: '$p' missing from the drop (unexpected layout)." >&2; exit 1; }
done

echo "==> Stripping non-committable bits (GCC prebuilt, dangling bazel-* symlinks)"
rm -rf "$SRC/kernel_platform/gcc"
find "$SRC/kernel_platform" -maxdepth 1 -type l -name 'bazel-*' -delete

echo "==> Building the new 'vanilla' commit in an isolated worktree"
WT="$SCRATCH/wt"
git worktree add -q --detach "$WT"
(
  cd "$WT"
  git checkout -q --orphan _import
  git reset -q
  find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
  cp -a "$SRC/kernel_platform" "$SRC/vendor" "$SRC/build_kernel_GKI.sh" .
  git add kernel_platform vendor build_kernel_GKI.sh
  git commit -q -F - <<EOF
vanilla: import Samsung OSRC ${BUILD} (pristine kernel source)

Pristine, unmodified Samsung Open Source Release Center drop. Import-only per the
CLAUDE.md branch model; excludes the GCC prebuilt and dangling bazel symlinks.

Archive SHA256: ${SHA}

Verified: not-flashed
EOF
)
NEW="$(git -C "$WT" rev-parse HEAD)"
git branch -f vanilla "$NEW"
git tag -f -a "osrc/${BUILD}" "$NEW" -m "Samsung OSRC drop ${BUILD} (pristine import)"

echo
echo "==> Done. 'vanilla' now points at $NEW and is tagged osrc/${BUILD}."
echo "    Files on vanilla: $(git ls-tree -r --name-only "$NEW" | wc -l)"
echo
echo "NEXT (not automated — replaying our work is deliberate, per CLAUDE.md):"
echo "  1. Diff against the previous drop:  git diff <prev-osrc-tag> osrc/${BUILD} -- kernel_platform vendor | less"
echo "  2. On a task branch off main, bring in the new vanilla content and rebuild via CI."
echo "  3. If any of our patches no longer apply, that is SIGNAL — investigate, don't force."
echo "  4. Push when satisfied:  git push origin vanilla && git push origin osrc/${BUILD}"
