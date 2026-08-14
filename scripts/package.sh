#!/usr/bin/env bash
#
# Package the build output into a flashable boot.img (Phase 1 first-boot artifact).
#
# What this produces, and why:
#   The Phase 1 goal is to boot a *self-built* GKI kernel on this device with the least
#   possible risk and a trivial rollback. On an init_boot device (boot header v4) the
#   boot partition is KERNEL ONLY — the generic ramdisk lives in init_boot, the vendor
#   ramdisk + real kernel cmdline live in vendor_boot (docs/FACTS.md §0.6). So the only
#   thing our build changes is the kernel Image, and the only image we need to repack and
#   flash for a first boot is boot.img. init_boot (Magisk / later KernelSU), vendor_boot,
#   and vendor_dlkm (stock modules) are left untouched on the device.
#
#   We rebuild boot.img from scratch with mkbootimg rather than reusing whatever the Kleaf
#   `gki` target emits, so the header fields and the SEANDROIDENFORCE footer are guaranteed
#   to match the stock partition exactly (values parsed from the owner's stock boot.img and
#   recorded in FACTS §0.6), instead of depending on Kleaf's build-time defaults.
#
# Boot image recipe — every value here is transcribed from docs/FACTS.md §0.6, which was
# derived by parsing the owner's real stock boot.img (BeyondROM_images/boot.img):
#   header_version 4 · kernel-only (ramdisk_size=0) · os_version 14.0.0 ·
#   os_patch_level 2026-04 · empty cmdline · SEANDROIDENFORCE appended after the kernel.
# The stock kernel payload is an UNCOMPRESSED arm64 Image (starts with the "MZ" EFI magic),
# so we feed out/dist/Image, not a compressed variant — matching the stock structure.
#
# Category-B packaging steps (SEANDROIDENFORCE footer, vbmeta guidance) live here, never in
# the kernel source. AVB: the owner's ROM already ships a patched/disabled vbmeta
# (FACTS §0.6), so an unsigned boot.img boots as-is; we do NOT add an AVB hash footer (we
# have no signing key and none is needed). The --disable-verity/--disable-verification
# vbmeta guidance is printed below as a safety net and detailed in docs/FLASHING.md (Phase 2).
#
# Env:
#   WITH_KERNELSU / WITH_SUSFS  consumed in later phases (Phase 3/4); acknowledged, not used here.
#
# STATUS: first real version. Cannot be exercised in the dev sandbox (no build output here);
# the CI run that follows scripts/build.sh is its verification. The self-check below re-parses
# the boot.img we just wrote and fails the job if any field drifts from the stock recipe.

set -euo pipefail

ROOT="$PWD"
DIST="$ROOT/out/dist"
KP="$ROOT/kernel_platform"
MKBOOTIMG="$KP/tools/mkbootimg/mkbootimg.py"

# --- Stock boot.img header values (docs/FACTS.md §0.6 — do not guess; change only if a new
#     source drop changes the stock partition, re-parsed from the owner's images). ---
HDR_VERSION=4
OS_VERSION="14.0.0"
OS_PATCH_LEVEL="2026-04"
SEANDROID="SEANDROIDENFORCE"

# --- Pre-flight: refuse to package a missing or broken build, with a clear reason. ---
[[ -d "$DIST" ]] || { echo "ERROR: $DIST missing — scripts/build.sh did not stage artifacts." >&2; exit 1; }
[[ -f "$MKBOOTIMG" ]] || { echo "ERROR: mkbootimg not found at $MKBOOTIMG (source tree incomplete?)." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required to run mkbootimg." >&2; exit 1; }

# We need the UNCOMPRESSED Image (stock boot.img carries an uncompressed arm64 Image; a
# compressed Image.lz4/Image.gz would change the boot.img structure vs stock — refuse to
# silently substitute one, since we could not then claim it matches the verified stock layout).
IMAGE="$DIST/Image"
if [[ ! -f "$IMAGE" ]]; then
  echo "ERROR: $IMAGE (uncompressed) not found. Staged Image variants:" >&2
  ls -la "$DIST"/Image* 2>/dev/null >&2 || echo "  (none)" >&2
  echo "The stock boot.img uses an uncompressed Image (FACTS §0.6); refusing to substitute a compressed one." >&2
  exit 1
fi
[[ -s "$IMAGE" ]] || { echo "ERROR: $IMAGE is zero bytes." >&2; exit 1; }

# Confirm it really is an arm64 Image: the arm64 kernel header carries the literal magic
# "ARM\x64" at byte offset 0x38 (and begins with the "MZ" EFI stub). Guards against feeding
# mkbootimg a truncated file or the wrong artifact.
python3 - "$IMAGE" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(0x40)
if d[:2] != b'MZ':
    sys.exit(f"ERROR: {sys.argv[1]} does not start with the arm64 'MZ' EFI magic (got {d[:2]!r}); not a kernel Image.")
if d[0x38:0x3c] != b'ARM\x64':
    sys.exit(f"ERROR: {sys.argv[1]} lacks the arm64 magic 'ARM\\x64' at offset 0x38 (got {d[0x38:0x3c]!r}).")
print(f"    Image OK: arm64 kernel, {__import__('os').path.getsize(sys.argv[1])} bytes")
PY

echo "==> Building flashable boot.img (header v$HDR_VERSION, kernel-only, os $OS_VERSION / $OS_PATCH_LEVEL)"
BOOT="$DIST/boot.img"
rm -f "$BOOT"
# No --ramdisk: on this init_boot device boot.img is kernel-only (ramdisk_size=0). No
# --cmdline: the real cmdline lives in vendor_boot (kept stock). No AVB signing key: the
# ROM's patched vbmeta makes an unsigned boot.img boot.
python3 "$MKBOOTIMG" \
  --header_version "$HDR_VERSION" \
  --os_version "$OS_VERSION" \
  --os_patch_level "$OS_PATCH_LEVEL" \
  --kernel "$IMAGE" \
  -o "$BOOT"

# Append the SEANDROIDENFORCE footer that stock boot.img carries right after the kernel.
# mkbootimg (v4, kernel-only) writes exactly [4096-byte header][page-aligned kernel] and
# stops, so this lands the footer at the same page-aligned offset as stock.
printf '%s' "$SEANDROID" >> "$BOOT"

echo "==> Wrote $BOOT ($(stat -c %s "$BOOT" 2>/dev/null || wc -c <"$BOOT") bytes)"

# --- Self-check: re-parse the boot.img we just produced and assert every field matches the
#     stock recipe. A green mkbootimg exit is not proof the bytes are right; this is. ---
echo "==> Verifying boot.img against the stock recipe (FACTS §0.6)"
python3 - "$BOOT" "$OS_VERSION" "$OS_PATCH_LEVEL" "$HDR_VERSION" "$SEANDROID" <<'PY'
import struct, sys
path, want_osv, want_osp, want_hv, seandroid = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
d = open(path, 'rb').read()
errs = []
if d[:8] != b'ANDROID!':
    errs.append(f"magic is {d[:8]!r}, expected b'ANDROID!'")
kernel_size, ramdisk_size, os_word, header_size = struct.unpack('<IIII', d[8:24])
header_version = struct.unpack('<I', d[40:44])[0]
if header_version != want_hv:
    errs.append(f"header_version={header_version}, expected {want_hv}")
if ramdisk_size != 0:
    errs.append(f"ramdisk_size={ramdisk_size}, expected 0 (boot.img is kernel-only on this device)")
# decode packed os_version (top 21 bits: a.b.c, 7 each) and os_patch_level (11 bits: y,m)
osv = os_word >> 11
a, b, c = (osv >> 14) & 0x7f, (osv >> 7) & 0x7f, osv & 0x7f
osp = os_word & 0x7ff
y, m = (osp >> 4) & 0x7f, osp & 0xf
got_osv, got_osp = f"{a}.{b}.{c}", f"{2000+y}-{m:02d}"
if got_osv != want_osv:
    errs.append(f"os_version={got_osv}, expected {want_osv}")
if got_osp != want_osp:
    errs.append(f"os_patch_level={got_osp}, expected {want_osp}")
# cmdline (offset 44, 1536 bytes) must be empty — the real cmdline lives in vendor_boot
cmdline = d[44:44+1536].split(b'\x00', 1)[0]
if cmdline:
    errs.append(f"cmdline is {cmdline!r}, expected empty")
# kernel payload starts at page 1; confirm the arm64 Image magic survived the pack
if d[0x1000:0x1002] != b'MZ' or d[0x1038:0x103c] != b'ARM\x64':
    errs.append("kernel payload at page 1 is not a valid arm64 Image (MZ / ARM64 magic missing)")
# SEANDROIDENFORCE must sit exactly at the page-aligned end of the kernel
pagesize = 4096
end = pagesize + ((kernel_size + pagesize - 1) // pagesize) * pagesize
footer = d[end:end+len(seandroid)]
if footer != seandroid.encode():
    errs.append(f"SEANDROIDENFORCE not at page-aligned kernel end (offset {end}); found {footer!r}")
if len(d) != end + len(seandroid):
    errs.append(f"trailing bytes after footer: file is {len(d)}, expected {end+len(seandroid)}")
if errs:
    print("ERROR: produced boot.img does not match the stock recipe:", file=sys.stderr)
    for e in errs:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
print(f"    OK: header v{header_version}, kernel-only, os {got_osv} / {got_osp}, "
      f"empty cmdline, SEANDROIDENFORCE @ {end}, total {len(d)} bytes")
PY

# --- Odin-flashable wrapper. This is a Samsung device; the owner flashes with Odin, which
#     takes a .tar (AP slot), not a raw .img. Produce the standard Samsung `.tar.md5`: a ustar
#     tar containing boot.img, with an md5 checksum line appended and the file renamed to
#     .tar.md5 (exactly the format Odin/Heimdall and Samsung firmware use). The raw boot.img is
#     also kept for the root-`dd`/Heimdall path. See docs/FLASHING.md. ---
echo "==> Wrapping boot.img as an Odin-flashable boot.tar.md5"
BOOTTAR="$DIST/boot.tar.md5"
(
  cd "$DIST"
  rm -f boot.tar boot.tar.md5
  # -H ustar: the POSIX/ustar format Odin expects; archive holds just boot.img at the root.
  tar -H ustar -cf boot.tar boot.img
  # Samsung .tar.md5 = the tar with "<md5>  boot.tar" appended, then renamed. Compute first
  # into a variable to avoid reading and appending the same file in one redirection.
  _md5line="$(md5sum boot.tar)"
  printf '%s\n' "$_md5line" >> boot.tar
  mv -f boot.tar boot.tar.md5
)
# Verify the wrapper: it must contain exactly boot.img and carry the trailing md5 line.
if ! tar -tf "$BOOTTAR" 2>/dev/null | grep -qx 'boot.img'; then
  echo "ERROR: $BOOTTAR does not contain boot.img — Odin wrapper is malformed." >&2
  exit 1
fi
python3 - "$BOOTTAR" <<'PY'
import sys, re, hashlib
d = open(sys.argv[1], 'rb').read()
# The Samsung .tar.md5 ends with the appended "<32 hex>  <name>\n" line. A tar is binary with
# NUL padding, so anchor the search at end-of-file rather than splitting on newlines.
m = re.search(rb'([0-9a-f]{32})  boot\.tar\n?$', d)
if not m:
    sys.exit(f"ERROR: {sys.argv[1]} has no valid trailing md5 line (Odin would reject it).")
tar_body = d[:m.start()]
want = m.group(1).decode()
got = hashlib.md5(tar_body).hexdigest()
if got != want:
    sys.exit(f"ERROR: {sys.argv[1]} md5 line ({want}) does not match the tar body ({got}).")
print(f"    Odin wrapper OK: boot.tar.md5 ({len(d)} bytes), md5 {want} verified against tar body")
PY

# --- AnyKernel3 flashable zip (the owner's chosen format; TWRP/recovery-flashable). ---
# We assemble the zip from osm0sis's pinned submodule engine (anykernel3/, UNMODIFIED) plus
# our device config (anykernel/anykernel.sh) and our kernel Image. AnyKernel3, on-device,
# unpacks the current boot.img, swaps in this Image, repacks with matching compression, and
# re-applies SEANDROIDENFORCE and the vbmeta flag itself — so nothing but the kernel changes.
AK3_SRC="$ROOT/anykernel3"
AK3_CFG="$ROOT/anykernel/anykernel.sh"
# AnyKernel3's own bundled tools (busybox, magiskboot, magiskpolicy) are 32-bit ARM. The e3q is
# a 64-bit-ONLY device (ro.product.cpu.abilist32 is empty), so recovery cannot exec them — TWRP
# aborts with "busybox: not executable: 32-bit ELF file". We swap in the arch-correct arm64
# binaries from a pinned, checksummed Magisk release. Only the tool BINARIES are replaced; his
# flashing scripts (ak3-core.sh, update-binary) are untouched. (FACTS §0.6; DECISIONS 2026-08-14.)
MAGISK_VER="v28.1"
MAGISK_URL="https://github.com/topjohnwu/Magisk/releases/download/${MAGISK_VER}/Magisk-${MAGISK_VER}.apk"
MAGISK_SHA256="8bfd3346b3da5814f82eff6f1b1b5fedd0ad585f39a25709b23eb54aac45691d"

if [[ -f "$AK3_SRC/tools/ak3-core.sh" && -f "$AK3_CFG" ]]; then
  echo "==> Building AnyKernel3 flashable zip (with arm64 tools from Magisk $MAGISK_VER)"
  AK3ZIP="$DIST/e3q-kernel-$(date -u +%Y%m%d)-AK3.zip"
  _mapk="$(mktemp)"; _mdir="$(mktemp -d)"; _tools_ok=1
  # Fetch + verify + extract the arm64 tools before assembling; on any failure, skip the AK3 zip
  # rather than ship one with the wrong-arch tools (boot.img / boot.tar.md5 are unaffected).
  if curl -fsSL -o "$_mapk" "$MAGISK_URL" 2>/dev/null \
     && echo "${MAGISK_SHA256}  ${_mapk}" | sha256sum -c - >/dev/null 2>&1 \
     && ( cd "$_mdir" && unzip -oq "$_mapk" 'lib/arm64-v8a/libbusybox.so' 'lib/arm64-v8a/libmagiskboot.so' 'lib/arm64-v8a/libmagiskpolicy.so' ); then
    :
  else
    _tools_ok=0
    echo "WARN: could not fetch/verify pinned Magisk ($MAGISK_VER) for arm64 tools — skipping the AnyKernel3 zip." >&2
    echo "      boot.img / boot.tar.md5 are unaffected; flash boot.img via TWRP 'Install Image' or Odin." >&2
  fi

  if (( _tools_ok )); then
    AK3_WORK="$(mktemp -d)"
    # His engine, verbatim, minus VCS metadata and his demo config (we supply our own).
    cp -a "$AK3_SRC"/. "$AK3_WORK"/
    rm -rf "$AK3_WORK/.git" "$AK3_WORK/.github" "$AK3_WORK/.gitattributes"
    rm -f "$AK3_WORK/anykernel.sh"
    cp "$AK3_CFG" "$AK3_WORK/anykernel.sh"
    # Our kernel. Uncompressed Image, matching the stock boot's uncompressed kernel; AnyKernel3
    # repacks it into the current boot.img in the same format.
    cp "$IMAGE" "$AK3_WORK/Image"
    # Replace ONLY the wrong-arch tool binaries with arm64 ones (scripts stay his).
    install -m0755 "$_mdir/lib/arm64-v8a/libbusybox.so"      "$AK3_WORK/tools/busybox"
    install -m0755 "$_mdir/lib/arm64-v8a/libmagiskboot.so"   "$AK3_WORK/tools/magiskboot"
    install -m0755 "$_mdir/lib/arm64-v8a/libmagiskpolicy.so" "$AK3_WORK/tools/magiskpolicy"
    rm -f "$AK3ZIP"
    ( cd "$AK3_WORK" && zip -r9 -q "$AK3ZIP" . -x '.git*' )
    rm -rf "$AK3_WORK"
    # Verify: our config (not his demo) + our kernel + his engine, AND the tools are arm64 ELF
    # (the whole point of this rebuild — never ship a 32-bit-tools zip again).
    python3 - "$AK3ZIP" <<'PY'
import sys, zipfile, struct
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
need = ["anykernel.sh", "Image", "tools/ak3-core.sh", "META-INF/com/google/android/update-binary",
        "tools/busybox", "tools/magiskboot"]
missing = [n for n in need if n not in names]
if missing:
    sys.exit(f"ERROR: AnyKernel3 zip missing {missing}. Has: {sorted(names)[:20]}")
cfg = z.read("anykernel.sh").decode("utf-8", "replace")
if "device.name1=e3q" not in cfg or "BLOCK=boot;" not in cfg:
    sys.exit("ERROR: AnyKernel3 zip's anykernel.sh is not our e3q config (device.name1=e3q / BLOCK=boot missing).")
if "ExampleKernel by osm0sis" in cfg or "maguro" in cfg:
    sys.exit("ERROR: AnyKernel3 zip still carries the demo config (osm0sis example / maguro) — our config did not overlay.")
for t in ("tools/busybox", "tools/magiskboot", "tools/magiskpolicy"):
    b = z.read(t)[:20]
    if b[:4] != b"\x7fELF":
        sys.exit(f"ERROR: {t} is not an ELF binary.")
    if b[4] != 2:
        sys.exit(f"ERROR: {t} is 32-bit (EI_CLASS={b[4]}) — this 64-bit-only device cannot exec it.")
    mach = struct.unpack('<H', b[18:20])[0]
    if mach != 0xB7:
        sys.exit(f"ERROR: {t} e_machine=0x{mach:x}, expected 0xB7 (AArch64).")
print(f"    AnyKernel3 zip OK: {sys.argv[1].split('/')[-1]} — e3q config, Image + engine, arm64 tools ({len(names)} entries)")
PY
  else
    AK3ZIP=""
  fi
  rm -rf "$_mapk" "$_mdir"
else
  echo "WARN: anykernel3 submodule or anykernel/anykernel.sh missing — skipping AnyKernel3 zip." >&2
  echo "      (In CI, actions/checkout must use submodules: recursive to fetch anykernel3.)" >&2
  AK3ZIP=""
fi

# --- Secondary artifact: the modules built against THIS kernel, for a later vendor_dlkm
#     rebuild or inspection. Not needed for the boot.img-only first flash, but cheap to keep. ---
_nmods="$(find "$DIST" -maxdepth 1 -name '*.ko' | wc -l)"
if (( _nmods > 0 )); then
  STAMP="$(date -u +%Y%m%d)"
  MODZIP="$DIST/e3q-modules-${STAMP}.zip"
  echo "==> Bundling $_nmods kernel modules -> $MODZIP"
  ( cd "$DIST" && rm -f "$MODZIP" \
      && zip -q "$MODZIP" ./*.ko modules.load modules.dep modules.alias 2>/dev/null || true )
  [[ -f "$MODZIP" ]] && ls -la "$MODZIP"
else
  echo "WARN: no .ko modules staged — stock modules must be kept on-device for hardware to work." >&2
fi

echo
echo "==> Flashable artifacts:"
ls -la ${AK3ZIP:+"$AK3ZIP"} "$BOOT" "$BOOTTAR"
echo
echo "First-boot flash plan (full procedure: docs/FLASHING.md):"
echo "  * SIMPLEST (recovery): TWRP -> Install -> 'Install Image' -> boot.img -> Boot partition."
echo "  * OR the AnyKernel3 zip (e3q-kernel-*-AK3.zip) in TWRP -> Install (arm64 tools, this device)."
echo "  * OR (needs a PC) Odin -> AP -> boot.tar.md5."
echo "    Do NOT flash vendor_boot.img / vendor_dlkm.img / system_dlkm* — build byproducts."
echo "  * Leave init_boot (Magisk), vendor_boot, and vendor_dlkm (stock modules) untouched —"
echo "    this kernel keeps the android14-6.1 KMI, so stock modules load."
echo "  * Rollback = re-flash your backed-up stock boot.img. Nothing else was changed."
echo "  * vbmeta safety net: the ROM already ships a patched vbmeta, so no AVB step is needed."
echo "    If a bootloader ever rejects the image, flash a vbmeta patched with"
echo "    'avbtool make_vbmeta_image --flags 3' (i.e. --disable-verity --disable-verification)."
echo "    NEVER re-flash a stock vbmeta over this — that re-enables verification and will fail."
