# FLASHING.md — how to flash the self-built kernel and how to undo it

This is the owner-facing flashing guide for the **Phase 1 first-boot test**: flashing our
self-built, protections-off kernel as `boot.img` **only**, keeping everything else stock. It
also covers the exact rollback and the vbmeta safety net.

> **Ground rules (read once).** You have no device-side way to prove a kernel boots except by
> flashing it. Nothing in this file *guarantees* a boot — it tells you the expected good outcome
> and the exact failure signature for each step, so you always know whether to continue or roll
> back. If a step's result doesn't match what's written here, **stop and paste me the output**;
> do not improvise.

---

## 0. What this flash is, in one paragraph

On this phone the `boot` partition is **the kernel only** (Android "init_boot" layout). Your
Magisk (root), the generic ramdisk, and every hardware driver live in *other* partitions
(`init_boot`, `vendor_boot`, `vendor_dlkm`) that we are **not touching**. So this test changes
exactly one thing — the kernel — and the way back is to re-flash one file. That is the whole
point of doing the kernel-only flash first: smallest possible change, one-flash rollback.

**What we built:** a stock Samsung `S928BXXU5DZDP` kernel, unmodified except that the six
Samsung boot-blocking protections (uH/RKP/KDP, DEFEX, PROCA, FIVE) are turned off — which a
*self-built* kernel needs in order to boot at all on this custom-ROM phone. No root is added by
this step; your existing Magisk stays exactly where it is.

**How we flash it:** the primary method is an **AnyKernel3 zip** flashed in a custom recovery
(TWRP/OrangeFox). AnyKernel3 takes the current `boot.img` on the phone, swaps in just our kernel,
repacks it, and re-applies the Samsung `SEANDROIDENFORCE` marker and the vbmeta flag by itself —
so only the kernel changes. If you don't have a working recovery, §4 gives the Odin and `dd`
fallbacks (they flash the same kernel a different way).

---

## 1. Before you flash — prerequisites (do not skip)

| # | Prerequisite | Why | How to confirm |
|---|---|---|---|
| 1 | **Bootloader unlocked** | An unsigned custom kernel only flashes on an unlocked bootloader. | You already run BeyondROM — it's unlocked. Nothing to do. |
| 2 | **Your current `boot.img` saved off-device** | This is your one-file rollback. | You already have it: `BeyondROM_images/boot.img` on your Drive. Keep it somewhere you can find it fast. |
| 3 | **A working custom recovery** (TWRP / OrangeFox) that can flash a zip, for the primary method | The AnyKernel3 zip is flashed *from recovery*. If you don't have one, use the Odin/`dd` fallback in §4 instead — those don't need a recovery. | Boot to recovery once and confirm it comes up and has an "Install zip" / "Apply update → sideload" option. |
| 4 | **Full stock `S928BXXU5DZDP` firmware stashed off-device** *(strongly recommended)* | The ultimate "get me back to normal" if anything unexpected happens. Its `AP_*.tar.md5` holds pristine `boot`, `init_boot`, `vendor_boot`, and `super`. | Download the 4-file firmware for build `S928BXXU5DZDP` (e.g. via Frija/Samfw) and keep the `AP`, `BL`, `CP`, `CSC` files. You do **not** flash them now — they're the safety net. |
| 5 | **Battery ≥ 50%, and a USB cable + a PC** (for `adb sideload`, or the Odin/`dd` fallback) | A flash interrupted by a dead battery or bad cable is how avoidable problems happen. | — |

> For **this** kernel-only flash, prerequisite #2 alone is a complete rollback (we only change
> `boot`). #4 is belt-and-suspenders for peace of mind and for the later phases where we *do*
> touch `init_boot`/`vendor_dlkm`. **You told me your current rollback is only the BeyondROM
> `boot.img`** — that is enough to undo *this* kernel-only flash, but I still recommend grabbing
> the full stock firmware (#4) before we get to the phases that touch other partitions.

---

## 2. Get the artifact

1. Open the build that produced your kernel:
   **Actions → the green "Build kernel" run → Artifacts → `e3q-kernel-<sha>`**.
2. Download and unzip it. Inside are these files:

   | File | Use it? |
   |---|---|
   | **`e3q-kernel-<date>-AK3.zip`** | **YES — this is the one you flash (AnyKernel3, §3).** Do *not* unzip it; flash the zip as-is. |
   | `boot.tar.md5` | Fallback only — the Odin file (§4), if you have no recovery. |
   | `boot.img` | Fallback only — the raw kernel image, for the `dd` method (§4). |
   | `e3q-modules-<date>.zip` | No. Reference copy of the modules built against this kernel; not flashed in this test. |

> The artifact contains only these four files by design — the build no longer ships
> `vendor_boot.img` / `vendor_dlkm.img` / `system_dlkm*` (they are build byproducts you must not
> flash). The AnyKernel3 zip appears from build #6 onward; older artifacts only have the boot
> files.

---

## 3. Flash — the AnyKernel3 zip in recovery (primary method)

The zip is built from osm0sis's AnyKernel3 (his flashing code, unchanged) plus a small config
for this device. On the phone it unpacks the current `boot.img`, swaps in our kernel, repacks,
and re-applies `SEANDROIDENFORCE` and the vbmeta flag automatically — so only the kernel changes.

1. Copy **`e3q-kernel-<date>-AK3.zip`** to the phone (internal storage or an SD card), **or**
   keep it on the PC to use `adb sideload`.
2. Boot into your **custom recovery** (TWRP / OrangeFox). Typically: power off, then hold
   **Volume-Up + Power** (with the phone plugged into the PC) until recovery appears — your
   recovery's exact key combo may differ.
3. Flash the zip:
   - **From storage:** *Install* → pick `e3q-kernel-<date>-AK3.zip` → swipe/confirm to flash.
   - **Or by sideload:** in recovery choose *Advanced → ADB Sideload* (TWRP) / *Apply update →
     ADB sideload* (OrangeFox), then on the PC run `adb sideload e3q-kernel-<date>-AK3.zip`.
4. When it finishes, **Reboot → System**.

**Expected good outcome:** the recovery log shows AnyKernel3 unpacking the boot image, writing the
new kernel, and finishing without error (you'll see lines about "Repacking & flashing" the boot
image). The device reboots.

**Failure signatures:**
- The log says the **device check failed** (wrong device) → stop and tell me; the zip's device
  name may not match your phone's — I set it to `e3q`, and I'll correct it if your recovery
  reports a different codename. Nothing was flashed.
- Any **error during "Repacking & flashing"** → stop, do not reboot before you can, and send me
  the recovery log (in TWRP: *Advanced → Copy Log*). Nothing partial should have been written,
  but I want to see it.

---

## 4. Flash — fallback methods if you have no recovery

Both fallbacks flash the **same kernel**; use them only if the AnyKernel3 path in §3 isn't
available. Unlike AnyKernel3 these write a pre-built `boot.img` rather than patching the current
one — that's fine here because our `boot.img` reproduces the stock boot layout exactly.

### 4a. Odin (Windows PC)

1. Open **Odin** (3.14.x or newer) on the PC.
2. Put the phone in **Download Mode**: power off, then hold **Volume-Down + Volume-Up** and plug
   in the USB cable; press **Volume-Up** to continue past the warning. (Or `adb reboot download`.)
3. In Odin, click **AP** and select **`boot.tar.md5`**. Leave **BL**, **CP**, **CSC** empty.
4. In **Options**, **Auto Reboot** on, **Re-Partition** **OFF**. Click **Start**.

**Expected good outcome:** green **PASS**, the phone reboots. **Failure:** Odin **FAIL** → nothing
was changed on a single-AP FAIL, but stop and send me the Odin log; don't retry blindly.

### 4b. Root `dd` (on the phone, no PC)

Because you're already rooted, you can write the kernel directly — but writing the wrong partition
is the one way to cause real trouble, so copy the commands exactly.

```sh
su
# Confirm the boot partition path first — expected output is a symlink under .../by-name/boot
ls -l /dev/block/by-name/boot
# Back up what's there right now (extra safety), then write the new kernel:
dd if=/dev/block/by-name/boot of=/sdcard/Download/boot-backup-$(date +%s).img
dd if=/sdcard/Download/boot.img of=/dev/block/by-name/boot
sync
reboot
```

**Expected good outcome:** both `dd` commands print a byte count with no error; the phone reboots.
**Failure:** any `dd` error → stop, do not reboot, paste me the exact message.

---

## 5. First boot — what to expect

- **The "unlocked bootloader / custom" warning screen at power-on is normal** — you already see
  it with BeyondROM. It is not a failure.
- First boot after a kernel change can take **a few minutes longer** than usual. Give it up to
  ~5 minutes before treating it as stuck.

**Three possible results:**

| What you see | What it means | What to do |
|---|---|---|
| Boots to the lock screen, everything normal | The kernel booted. Now run the hardware checklist (§6). | Continue to §6. |
| **Bootloop** (never reaches the animation, or loops the boot animation) | The kernel didn't come up — most likely one of the disabled protections matters on early boot, or a kernel problem. | **Roll back (§7)**, then send me anything from §9. |
| Boots, but **some hardware is missing** (no Wi-Fi / Bluetooth / mobile data / S-Pen / camera / fingerprint) | The kernel booted but a **stock driver module didn't load** against our kernel (an ABI/symbol mismatch — possibly from a removed protection). This is diagnostic gold, not a disaster. | Note *which* things are broken, then roll back (§7) and tell me. |

I will **not** claim this will boot cleanly — only your flash proves it. The table above is so
you can tell the three cases apart without guessing.

---

## 6. Hardware checklist (the Phase 1 exit gate)

If it boots, confirm **each** of these and tell me the result. A partial pass ("boots but no
Bluetooth") means the module pipeline needs work before we go further — so please check them all:

- [ ] **Wi-Fi** connects
- [ ] **Bluetooth** turns on and pairs
- [ ] **Mobile data** works (toggle Wi-Fi off, load a page)
- [ ] **S-Pen** (hover + a button action)
- [ ] **Camera** opens and takes a photo (front and rear)
- [ ] **Fingerprint** unlock works
- [ ] No *new* warning screens beyond the usual unlocked-bootloader one
- [ ] Root still works (Magisk app still shows installed — we didn't touch it)

---

## 7. Rollback — how to undo this flash

You changed only `boot`, so rollback is one flash. **Tip:** before you flash in §3, make a TWRP
**backup of the Boot partition** — then rollback is a one-tap *Restore* in recovery.

- **Via recovery (TWRP):** *Restore* the Boot backup you made before flashing. (AnyKernel3 also
  keeps a backup of the boot image it replaced, under `/data` — but your own TWRP backup is the
  one to rely on.)
- **Via Odin:** wrap your saved stock kernel `BeyondROM_images/boot.img` into a `.tar` and
  Odin-flash it to **AP** (Download Mode as in §4a). Or Odin the full stock `AP` from prereq #4.
- **Via root `dd`:** `dd if=/sdcard/Download/BeyondROM-boot.img of=/dev/block/by-name/boot` then
  `reboot` (use the backup `dd` made in §4b, or your saved `BeyondROM_images/boot.img`).
- **If the phone won't boot at all:** boot into **Download Mode** (power off, Volume-Down +
  Volume-Up, plug in USB) — it's always reachable regardless of kernel state — and Odin-flash the
  stock `boot` (or the full stock `AP` from prereq #4). A bad kernel can always be undone this way.

Rolling back the kernel does **not** touch your data, Magisk, or the ROM.

---

## 8. vbmeta / verified boot (safety net — you should not need it)

Your BeyondROM already ships a **patched vbmeta** with verification disabled, which is why an
unsigned custom `boot.img` flashes and boots. So for this test you do **nothing** with vbmeta.

- **Do NOT re-flash a stock `vbmeta`** over your setup — that turns verification back on and a
  custom kernel will then be rejected. (This is the one way to turn an easy rollback into a hard
  one, so: leave vbmeta alone.)
- **Only if** a flash is rejected specifically for a verification reason: flash a vbmeta image
  built with verification disabled —
  `avbtool make_vbmeta_image --flags 3 --padding_size 4096 --output vbmeta.img`
  (`--flags 3` = disable-verity + disable-verification) — to the `vbmeta` partition. Ask me first;
  you almost certainly won't need this.

---

## 9. If it fails — what to capture (so we can fix it, not guess)

Per the triage order we use for this device:

1. **Did it reach the boot animation?** Bootloop *before* the animation points at the kernel /
   early boot; *after* points at userspace or a module.
2. If it boots at all: `adb logcat` and `adb shell dmesg` (or `su -c dmesg`).
3. After a bootloop, once you're back on the stock kernel: check
   `su -c 'ls -la /sys/fs/pstore/'` — a `dmesg-ramoops-*` file there holds the **previous boot's
   panic**, which usually names the exact cause. Send me that file.
4. Missing hardware: `su -c lsmod` compared against what's expected — a driver that's in the
   stock `modules.load` but not in `lsmod` is the culprit, and it's almost always a module/kernel
   ABI mismatch, not a kernel bug.

Give me at least one of these before we theorize about causes.
