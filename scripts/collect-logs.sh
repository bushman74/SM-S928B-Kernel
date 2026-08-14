#!/system/bin/sh
#
# collect-logs.sh — capture the kernel + hardware logs for the e3q first-boot test.
#
# This runs ON THE PHONE (in Termux), not on a PC. It needs root — Magisk grants it the
# first time via `su` (tap "Allow" / "Grant" on the prompt). It writes everything to
# /sdcard/e3q-logs/<tag>/ and also bundles that into one file, /sdcard/e3q-logs/<tag>.tar,
# so there is a single thing to upload and share.
#
# Usage (run each one at the right moment):
#   sh collect-logs.sh stock       # NOW, on the working BeyondROM — the baseline
#   sh collect-logs.sh newkernel   # AFTER flashing our kernel, IF it boots — to compare
#   sh collect-logs.sh bootfail    # after a bootloop + rollback — grabs the saved panic
#
# Why a baseline: BeyondROM (stock kernel) is the known-good reference. The difference
# between the "stock" and "newkernel" captures is the diagnosis — above all, any driver
# that loads on stock but not on our kernel (that is what missing hardware looks like).
#
# The two facilities this relies on are confirmed present in this kernel:
#   - /proc/config.gz  (CONFIG_IKCONFIG_PROC=y) — proves WHICH kernel booted.
#   - pstore/ramoops   (CONFIG_PSTORE_RAM=y)     — a panic survives a reboot, so a
#                                                  bootloop can still be diagnosed.

TAG="${1:-capture}"
BASE=/sdcard/e3q-logs
OUT="$BASE/$TAG"

echo "Capturing '$TAG' … a Magisk root prompt will appear the first time — tap Allow."

# One su call does the whole privileged capture and can also write to /sdcard.
# $BASE/$OUT/$TAG are expanded here (by Termux) before su runs; the single quotes inside
# just protect the paths in the root shell.
su -c "
mkdir -p '$OUT' '$OUT/pstore'
uname -a                              > '$OUT/uname.txt' 2>&1
cat /proc/config.gz                   > '$OUT/config.gz'  2>/dev/null
lsmod                                 > '$OUT/lsmod.txt'  2>&1
wc -l < '$OUT/lsmod.txt'              > '$OUT/lsmod-count.txt' 2>/dev/null
cat /vendor/lib/modules/modules.load  > '$OUT/modules.load.txt' 2>/dev/null
dmesg                                 > '$OUT/dmesg.txt'  2>&1
dmesg | grep -iE 'version magic|disagrees about version|unknown symbol|failed to load|probe.*(fail|error)|denied' > '$OUT/dmesg-errors.txt' 2>&1
# The dmesg ring buffer is small and wraps within minutes; the kernel logcat buffer keeps the
# whole boot with timestamps, so it (not dmesg) is where boot-time module-load errors survive.
logcat -b kernel -d                   > '$OUT/logcat-kernel.txt' 2>&1
logcat -d 2>/dev/null | grep -iE 'insmod|modprobe|\.ko|unknown symbol|cfg80211|mac80211|wlan|wifi|bluetooth|hci|nfc|avc: *denied' > '$OUT/logcat-hw.txt' 2>&1
ip addr                               > '$OUT/net-links.txt' 2>&1
getprop | grep -iE 'boot.?reason|reset|debug_level' > '$OUT/bootreason.txt' 2>&1
cp /sys/fs/pstore/* '$OUT/pstore/'    2>/dev/null
ls -la /sys/fs/pstore/                > '$OUT/pstore-list.txt' 2>&1
# --- Records that SURVIVE reboots (dmesg/logcat are wiped each boot; a bootloop's cause
#     lives here). DropBox is Android's persistent store of system_server/HAL crashes,
#     kernel panics and reboot causes; tombstones are native crashes; both live on /data. ---
logcat -b crash  -d                   > '$OUT/logcat-crash.txt'  2>&1
logcat -b events -d                   > '$OUT/logcat-events.txt' 2>&1
logcat -b system -d                   > '$OUT/logcat-system.txt' 2>&1
cat /proc/last_kmsg                   > '$OUT/last_kmsg.txt'      2>/dev/null
cat /proc/reset_reason                > '$OUT/reset_reason.txt'   2>/dev/null
cp -a /data/system/dropbox            '$OUT/dropbox'             2>/dev/null
ls -la /data/system/dropbox           > '$OUT/dropbox-list.txt'   2>&1
cp -a /data/tombstones                '$OUT/tombstones'          2>/dev/null
ls -la /data/tombstones               > '$OUT/tombstones-list.txt' 2>&1
ls -laR /data/log                     > '$OUT/samsung-log-list.txt' 2>&1
# EVERY module-load list (not just vendor_dlkm) — the true set of what should load at boot.
find /vendor /odm /system /system_dlkm /vendor_dlkm -name modules.load -exec cat {} + > '$OUT/modules.load.all.txt' 2>/dev/null
chmod -R a+r '$BASE' 2>/dev/null
tar cf '$BASE/$TAG.tar' -C '$BASE' '$TAG' 2>/dev/null
chmod a+r '$BASE/$TAG.tar' 2>/dev/null
"

echo ""
echo "Done. Saved to:  $OUT"
su -c "ls -la '$OUT'" 2>/dev/null
echo ""
echo "ONE FILE TO SEND ME:  $BASE/$TAG.tar"
echo "Open a file manager -> Internal storage -> e3q-logs -> $TAG.tar,"
echo "upload it to Google Drive and share the link (same as before)."
