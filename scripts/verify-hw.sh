#!/system/bin/sh
#
# verify-hw.sh — on-device PASS/FAIL health check for a freshly flashed e3q kernel.
#
# Runs ON THE PHONE (Termux), needs root. Unlike collect-logs.sh (which dumps raw logs for
# offline analysis), this prints a verdict you can read on the spot: for each hardware
# subsystem it says PASS / FAIL / WARN and why.
#
#   su -c 'sh verify-hw.sh'              # print the report
#   su -c 'sh verify-hw.sh newkernel3'   # same, and also save to /sdcard/e3q-logs/<tag>-verify.txt
#
# (If `su -c` gives a permissions error, run `su` first to get a root shell, then `sh verify-hw.sh`.)
#
# Why this exists: "it booted" is NOT "all hardware works". A driver can load and still fail to
# bring up its hardware — the audio HAL mixer-init crash is exactly that: every audio .ko is in
# lsmod, yet there is no working sound card. These checks test the *result* (is there a sound
# card, are the DSPs running, did any HAL crash), not just whether a .ko loaded. Every check is
# absolute (needs no baseline) except [1], which uses the device's OWN modules.load as the
# reference for what should have loaded.
#
# Read the SUMMARY at the end. Any FAIL is a real problem — capture it with collect-logs.sh.

TMP=/data/local/tmp/verifyhw.$$
PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $*"; }
warn() { WARN=$((WARN+1)); echo "  WARN  $*"; }

report() {
mkdir -p "$TMP" 2>/dev/null
echo "=================================================================="
echo " e3q kernel hardware verification"
echo " kernel: $(uname -r)"
echo " date:   $(date)"
echo "=================================================================="

# ------------------------------------------------------------ [1] modules
echo ""; echo "[1] Kernel modules — loaded vs the device's own modules.load"
lsmod 2>/dev/null | awk 'NR>1{print $1}' | sed 's/-/_/g' | sort -u > "$TMP/load"
find /vendor /odm /system /system_dlkm /vendor_dlkm -name modules.load 2>/dev/null \
  -exec cat {} + 2>/dev/null | sed 's#.*/##; s/\.ko$//; s/-/_/g' | sort -u > "$TMP/want"
nload=$(grep -c . "$TMP/load"); nwant=$(grep -c . "$TMP/want")
comm -23 "$TMP/want" "$TMP/load" > "$TMP/miss" 2>/dev/null
# Test/debug/selftest modules are listed in modules.load but do NOT load at boot even on
# stock (verified: ipclite_test, kheaders, llcc_perfmon are all absent on the stock kernel
# too). Don't cry wolf over those — separate them from a real driver that failed to load.
optpat='(^kheaders$|_test$|_perfmon$|_selftest$|_kunit$)'
grep -vE "$optpat" "$TMP/miss" > "$TMP/miss_real" 2>/dev/null || true
grep -E  "$optpat" "$TMP/miss" > "$TMP/miss_opt"  2>/dev/null || true
nreal=$(grep -c . "$TMP/miss_real"); nopt=$(grep -c . "$TMP/miss_opt")
echo "      loaded=$nload  in-modules.load=$nwant  not-loaded=$((nreal+nopt))"
if [ "$nreal" -eq 0 ]; then ok "all functional modules loaded (only optional test/debug not loaded, same as stock)"
else bad "$nreal driver module(s) did NOT load:"; sed 's/^/          - /' "$TMP/miss_real"; fi
[ "$nopt" -gt 0 ] && echo "        (optional test/debug not loaded — benign, matches stock: $(tr '\n' ' ' < "$TMP/miss_opt"))"

# ------------------------------------------------------------ [2] audio / sound card
echo ""; echo "[2] Audio — ALSA sound card + PCM devices"
if [ -r /proc/asound/cards ]; then
  echo "      /proc/asound/cards:"; sed 's/^/        /' /proc/asound/cards
  ncard=$(grep -cE '^[[:space:]]*[0-9]+[[:space:]]' /proc/asound/cards)
  npcm=$(grep -c . /proc/asound/pcm 2>/dev/null)
  if [ "${ncard:-0}" -ge 1 ] && [ "${npcm:-0}" -ge 1 ]; then
    ok "sound card present ($ncard) with $npcm PCM device(s)"
  else
    bad "no usable sound card/PCM (cards=$ncard pcm=${npcm:-0}) — this is the audio-HAL failure"
  fi
else
  bad "/proc/asound/cards missing — no ALSA sound card registered"
fi

# ------------------------------------------------------------ [3] remoteproc DSPs
echo ""; echo "[3] Remote subsystems (ADSP/CDSP/MODEM/SLPI/WPSS) — must be 'running'"
found=0
for d in /sys/class/remoteproc/remoteproc*; do
  [ -d "$d" ] || continue
  found=1
  nm=$(cat "$d/name" 2>/dev/null); st=$(cat "$d/state" 2>/dev/null)
  # "running" = kernel booted the firmware; "attached" = firmware booted externally (TZ) and
  # the kernel attached to it — normal for SPSS (the secure subsystem). Both are healthy.
  case "$st" in
    running|attached) ok "${nm:-$d} = $st" ;;
    *) bad "${nm:-$d} = '${st:-?}' (not up — audio=ADSP, sensors=SLPI/ADSP depend on this)" ;;
  esac
done
[ "$found" -eq 0 ] && warn "no /sys/class/remoteproc entries found (check 'dmesg | grep -i adsp')"

# ------------------------------------------------------------ [4] native crashes since boot
echo ""; echo "[4] Native crashes since boot (tombstones)"
now=$(date +%s 2>/dev/null || echo 0)
upt=$(cut -d. -f1 /proc/uptime 2>/dev/null); upt=${upt:-0}
boot=$((now - upt))
ncrash=0
for f in /data/tombstones/tombstone_*; do
  [ -f "$f" ] || continue
  mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  [ "$mt" -ge "$boot" ] || continue
  ncrash=$((ncrash+1))
  exe=$(grep -m1 -E '^(Cmdline|Process|>>>|Executable)' "$f" 2>/dev/null | head -1 | tr -s ' ')
  echo "          - ${f##*/}: $exe"
done
if [ "$ncrash" -eq 0 ]; then ok "no tombstones since this boot"
else bad "$ncrash native crash(es) since boot (a HAL/service aborted — see names above)"; fi

# ------------------------------------------------------------ [5] key HAL services
echo ""; echo "[5] Key HAL services (running = good; restarting = crash loop; stopped = one-shot/off)"
getprop 2>/dev/null | grep -iE '\[init\.svc\.(vendor\.)?[^]]*(audio|wifi|cnss|wlan|bluetooth|_bt_|camera|sensor|gnss|nfc)' \
  | grep -vE '\[init\.svc_debug_pid\.' > "$TMP/svc"
if [ -s "$TMP/svc" ]; then
  while IFS= read -r line; do
    nm=$(echo "$line" | sed -n 's/^\[init\.svc\.\([^]]*\)\].*/\1/p')
    st=$(echo "$line" | sed -n 's/.*: \[\([^]]*\)\].*/\1/p')
    [ -z "$nm" ] && continue
    case "$st" in
      running)    echo "  PASS  svc $nm = running" ;;
      restarting) echo "  FAIL  svc $nm = restarting (crash loop)" ;;
      *)          echo "  WARN  svc $nm = '$st' (one-shot/disabled — only a problem if that feature is dead)" ;;
    esac
  done < "$TMP/svc"
  PASS=$((PASS + $(grep -cE ': \[running\]' "$TMP/svc")))
  FAIL=$((FAIL + $(grep -cE ': \[restarting\]' "$TMP/svc")))
  WARN=$((WARN + $(grep -vE ': \[(running|restarting)\]' "$TMP/svc" | grep -c .)))
else
  warn "no matching init.svc.* properties (naming differs — inspect 'getprop | grep init.svc')"
fi

# ------------------------------------------------------------ [6] net interfaces
echo ""; echo "[6] Network interfaces"
wl=$(ls /sys/class/net 2>/dev/null | grep -E '^wlan' | tr '\n' ' ')
if [ -n "$wl" ]; then ok "wlan interface present: $wl"; else bad "no wlan* netdev — Wi-Fi driver did not register"; fi
if ls /sys/class/bluetooth/hci* >/dev/null 2>&1; then ok "bluetooth hci present"
else warn "no /sys/class/bluetooth/hci* (may attach later over UART)"; fi

# ------------------------------------------------------------ [7] dmesg red flags
echo ""; echo "[7] Kernel log red flags (dmesg — partial if it already wrapped)"
for pat in 'exports protected symbol' 'Unknown symbol' 'disagrees about version' 'Direct firmware load.*failed' 'probe.*fail'; do
  n=$(dmesg 2>/dev/null | grep -icE "$pat")
  [ "${n:-0}" -gt 0 ] && warn "dmesg: $n line(s) match \"$pat\""
done
echo "      (detail:  dmesg | grep -iE 'protected symbol|Unknown symbol|firmware.*fail')"

# ------------------------------------------------------------ [8] identity: is this OUR kernel?
echo ""; echo "[8] Kernel identity — the flashed kernel is our protections-off build"
# NOTE: decompress via a temp FILE, trying several tools. Reading /proc/config.gz straight into
# a shell var with `zcat` returned EMPTY on this device — which silently made every kernel look
# "protections off" (a false 'this is our kernel', even for stock). collect-logs works because it
# copies the compressed bytes and decompresses off-device; do the same here, and if decompression
# yields nothing, WARN — never claim identity from an empty read.
cat /proc/config.gz > "$TMP/kcfg.gz" 2>/dev/null
( zcat "$TMP/kcfg.gz" 2>/dev/null || gzip -dc "$TMP/kcfg.gz" 2>/dev/null \
  || gunzip -c "$TMP/kcfg.gz" 2>/dev/null || toybox zcat "$TMP/kcfg.gz" 2>/dev/null ) > "$TMP/kcfg"
if [ -s "$TMP/kcfg" ]; then
  onlist=""
  for s in UH RKP KDP SECURITY_DEFEX PROCA FIVE MODULE_SIG_PROTECT; do
    grep -q "^CONFIG_${s}=y" "$TMP/kcfg" && onlist="$onlist $s"
  done
  if [ -z "$onlist" ]; then ok "all 7 protections off in /proc/config.gz (this is our kernel)"
  else bad "protection(s) STILL ON:$onlist — this is STOCK / not our kernel (wrong boot.img flashed)"; fi
  # Full whole-config parity if the baseline + checker are placed next to this script.
  base="$(dirname "$0")/config-S928BXXU5DZDP.stock"
  if [ -r "$base" ] && [ -f "$(dirname "$0")/check-config-parity.sh" ]; then
    if sh "$(dirname "$0")/check-config-parity.sh" "$TMP/kcfg" "$base" >/dev/null 2>&1; then
      ok "whole-config parity: running kernel differs from stock only by protections"
    else
      warn "whole-config parity reported a non-protection difference (run check-config-parity.sh manually)"
    fi
  fi
else
  warn "could not decompress /proc/config.gz on-device (no working zcat/gzip, or IKCONFIG off) — kernel identity unconfirmed"
fi
# Secondary identity signal that needs no decompression: the release string.
case "$(uname -r)" in
  *S928B*|*abS928*) warn "uname '$(uname -r)' carries the Samsung firmware string — looks like STOCK, not our build" ;;
  *) : ;;
esac

# ------------------------------------------------------------ summary
echo ""; echo "=================================================================="
echo " SUMMARY:  PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
if [ "$FAIL" -eq 0 ]; then
  echo " VERDICT:  no automated FAILs. Still spot-check by hand: play + record audio,"
  echo "           Wi-Fi / BT / Hotspot, camera, fingerprint, sensors, calls."
else
  echo " VERDICT:  $FAIL check(s) FAILED — see the FAIL lines above, then run:"
  echo "               sh collect-logs.sh ${TAG:-verifyfail}"
  echo "           and send me the .tar."
fi
echo "=================================================================="
rm -rf "$TMP" 2>/dev/null
}

# ---- entry: ensure root, run report, optionally save ----
TAG="$1"
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  case "$0" in /*) SELF="$0";; *) SELF="$PWD/$0";; esac
  exec su -c "sh '$SELF' '$TAG'"
fi

if [ -n "$TAG" ]; then
  mkdir -p /sdcard/e3q-logs 2>/dev/null
  R="$(report)"
  printf '%s\n' "$R"
  printf '%s\n' "$R" > "/sdcard/e3q-logs/${TAG}-verify.txt" 2>/dev/null && \
    echo "" && echo "Saved report to: /sdcard/e3q-logs/${TAG}-verify.txt"
else
  report
fi
