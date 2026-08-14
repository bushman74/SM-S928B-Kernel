#!/usr/bin/env bash
#
# check-config-parity.sh — assert a kernel config differs from the stock baseline ONLY by
# the allowlisted protection symbols, across the WHOLE config (every resolved symbol), not
# just the defconfig lines we hand-edited.
#
# This is the universal, foresight version of check-defconfig-parity.sh: that one guards the
# source defconfig; this one guards the FINAL config (built or running), which is what
# actually determines whether a driver is present. If disabling a protection silently drops
# some unrelated symbol via a Kconfig `select`/`depends on` ripple, THIS catches it — for any
# subsystem, not just the ones we thought to check. It would flag, e.g., a lost CONFIG for a
# codec, a sensor, a filesystem, or a netdev the moment it diverged from stock.
#
# Usage:
#   scripts/check-config-parity.sh <config>        # baseline defaults to the committed stock
#   scripts/check-config-parity.sh <config> <baseline>
#   <config> may be a plain .config, a config.gz, or /proc/config.gz (gz auto-detected).
#
# Exit 0 = only allowlisted protections differ. Exit 1 = an unexpected symbol diverged.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="${1:?usage: check-config-parity.sh <config> [baseline]}"
BASE="${2:-$HERE/../docs/baseline/config-S928BXXU5DZDP.stock}"

# Allowlist: the protection roots AND everything they select / depend on (the cascade),
# derived from the measured stock-vs-ours delta (all 42 differing symbols were in this set).
#   UH/RKP/KDP           Samsung hypervisor + Realtime Kernel Protection + KDP
#   SECURITY_DEFEX/DEFEX Samsung DEFEX LSM (+ its sub-options)
#   PROCA                Samsung process authentication (+ certs/debug sub-options)
#   FIVE                 Samsung file integrity (+ certs/hash sub-options)
#   GAF                  Samsung GAF (selected in the same family)
#   MODULE_SIG_PROTECT   Android GKI module protection
#   INTEGRITY_ASYMMETRIC_KEYS / INTEGRITY_TRUSTED_KEYRING / SIGNATURE
#                        generic capabilities FIVE `select`s — collaterally off when FIVE is off
ALLOW_RE='^CONFIG_(UH|RKP|KDP|PROCA|FIVE|GAF|SECURITY_DEFEX|DEFEX|MODULE_SIG_PROTECT|INTEGRITY_ASYMMETRIC_KEYS|INTEGRITY_TRUSTED_KEYRING|INTEGRITY_SIGNATURE|SIGNATURE)([_=]|$)'

[ -r "$BASE" ] || { echo "ERROR: baseline not found: $BASE"; exit 2; }

_read() { # emit one "CONFIG_X=<value>" per symbol (unset -> =n), EXACT values preserved
  local f="$1"
  if [ "${f%.gz}" != "$f" ] || head -c2 "$f" 2>/dev/null | od -An -tx1 2>/dev/null | grep -q '1f 8b'; then
    zcat "$f" 2>/dev/null
  else
    cat "$f"
  fi | grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' \
     | sed -E 's/^# (CONFIG_[A-Za-z0-9_]+) is not set$/\1=n/' \
     | sort -u
}

[ -r "$CFG" ] || { echo "ERROR: config not readable: $CFG"; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
_read "$BASE" > "$TMP/base"
_read "$CFG"  > "$TMP/cur"

# Every symbol-line present in exactly one of the two (state differs).
comm -3 "$TMP/base" "$TMP/cur" | sed -E 's/^\t//' | sed -E 's/=.*//' | sort -u > "$TMP/diffsyms"

ndiff=$(grep -c . "$TMP/diffsyms" || true)
echo "config parity: $CFG  vs  ${BASE##*/}  — $ndiff symbol(s) differ"

bad=0
while IFS= read -r sym; do
  [ -z "$sym" ] && continue
  if ! printf '%s\n' "$sym" | grep -qE "$ALLOW_RE"; then
    echo "  ✗ UNEXPECTED: $sym differs from stock and is NOT an allowlisted protection"
    bad=1
  fi
done < "$TMP/diffsyms"

if [ "$bad" -ne 0 ]; then
  echo ""
  echo "FAIL: the built/running kernel differs from stock in a NON-protection symbol."
  echo "      That is a regression: we are supposed to change only the protections. Investigate"
  echo "      before trusting this kernel (a driver may have been dropped by a Kconfig ripple)."
  echo "      If intentional, extend ALLOW_RE and record why in docs/DECISIONS.md."
  exit 1
fi

echo "PASS: every difference from stock is an allowlisted protection symbol ($ndiff total)."
