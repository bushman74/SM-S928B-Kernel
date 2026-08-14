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
nmiss=$(grep -c . "$TMP/miss")
echo "      loaded=$nload  in-modules.load=$nwant  not-loaded=$nmiss"
if [ "$nmiss" -eq 0 ]; then ok "every module in modules.load is loaded"
else bad "$nmiss module(s) in modules.load did NOT load:"; sed 's/^/          - /' "$TMP/miss"; fi

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
  if [ "$st" = "running" ]; then ok "${nm:-$d} = running"
  else bad "${nm:-$d} = '${st:-?}' (not running — audio=ADSP, sensors=SLPI/ADSP depend on this)"; fi
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
echo ""; echo "[5] Key HAL services (init.svc.* should be 'running')"
getprop 2>/dev/null | grep -iE '\[init\.svc\.(vendor\.)?[^]]*(audio|wifi|cnss|wlan|bluetooth|_bt_|camera|sensor|gnss|nfc)' > "$TMP/svc"
if [ -s "$TMP/svc" ]; then
  while IFS= read -r line; do
    nm=$(echo "$line" | sed -n 's/^\[init\.svc\.\([^]]*\)\].*/\1/p')
    st=$(echo "$line" | sed -n 's/.*: \[\([^]]*\)\].*/\1/p')
    [ -z "$nm" ] && continue
    if [ "$st" = "running" ]; then echo "  PASS  svc $nm = running"; else echo "  FAIL  svc $nm = '$st'"; fi
  done < "$TMP/svc"
  PASS=$((PASS + $(grep -cE ': \[running\]' "$TMP/svc")))
  FAIL=$((FAIL + $(grep -vE ': \[running\]' "$TMP/svc" | grep -c .)))
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
