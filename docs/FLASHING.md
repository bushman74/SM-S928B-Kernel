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

---

## 1. Before you flash — prerequisites (do not skip)

| # | Prerequisite | Why | How to confirm |
|---|---|---|---|
| 1 | **Bootloader unlocked** | An unsigned custom kernel only flashes on an unlocked bootloader. | You already run BeyondROM — it's unlocked. Nothing to do. |
| 2 | **Your current `boot.img` saved off-device** | This is your one-file rollback. | You already have it: `BeyondROM_images/boot.img` on your Drive. Keep it somewhere you can find it fast. |
| 3 | **Full stock `S928BXXU5DZDP` firmware stashed off-device** *(strongly recommended)* | The ultimate "get me back to normal" if anything unexpected happens. Its `AP_*.tar.md5` holds pristine `boot`, `init_boot`, `vendor_boot`, and `super`. | Download the 4-file firmware for build `S928BXXU5DZDP` (e.g. via Frija/Samfw) and keep the `AP`, `BL`, `CP`, `CSC` files. You do **not** flash them now — they're the safety net. |
| 4 | **Battery ≥ 50%, a working USB cable, and (for Odin) a Windows PC** | A flash interrupted by a dead battery or bad cable is how avoidable problems happen. | — |

> For **this** kernel-only flash, prerequisite #2 alone is a complete rollback (we only change
> `boot`). #3 is belt-and-suspenders for peace of mind and for the later phases where we *do*
> touch `init_boot`/`vendor_dlkm`.

---

## 2. Get the artifact

1. Open the build that produced your kernel:
   **Actions → the green "Build kernel" run → Artifacts → `e3q-kernel-<sha>`**.
   (Direct page for build #4: `https://github.com/bushman74/SM-S928B-Kernel/actions/runs/31734526823`.)
2. Download and unzip it. Inside you will find several files. **You flash exactly one of these:**

   | File | Flash it? |
   |---|---|
   | **`boot.tar.md5`** | **YES — this is the Odin file.** (Present from build #5 onward.) |
   | **`boot.img`** | YES — the raw kernel image, if you flash by `dd`/Heimdall instead of Odin. |
   | `e3q-modules-<date>.zip` | No. Reference copy of the modules built against this kernel; not flashed in this test. |
   | `vendor_boot.img`, `vendor_dlkm.img`, `system_dlkm*.img` | **NO. Do not flash these.** They are build byproducts. Flashing them is untested and can break hardware. |

> If your artifact only has `boot.img` and no `boot.tar.md5`, it's from build #4 (before the
> Odin-tar change). Either use the `dd` method in §4, or wait for the next build's artifact,
> which includes `boot.tar.md5`.

---

## 3. Flash — Method A: Odin (recommended)

Odin is the Samsung-native tool and gives you a clear **PASS**/**FAIL**. You've used it for
BeyondROM's Odin pack.

1. On the PC, open **Odin** (3.14.x or newer).
2. Put the phone in **Download Mode**: power off, then hold **Volume-Down + Volume-Up** and plug
   in the USB cable; press **Volume-Up** to continue past the warning. (Or, from an adb shell:
   `adb reboot download`.)
3. In Odin, click **AP** and select **`boot.tar.md5`**. Leave **BL**, **CP**, **CSC** empty.
4. In **Options**, make sure **Auto Reboot** is on and **Re-Partition** is **OFF**.
5. Click **Start**.

**Expected good outcome:** Odin shows a green **PASS**, the phone reboots on its own.

**Failure signatures:**
- Odin says **FAIL** → nothing was changed on a FAIL of a single AP file, but **stop and send me
  the Odin log**. Do not retry blindly.
- Phone sits in Download Mode after → unplug, hold Volume-Down + Power to leave Download Mode,
  and tell me.

---

## 4. Flash — Method B: root `dd` (alternative, no PC)

Because you're already rooted, you can write the kernel directly. This needs care — writing to
the wrong partition is the one way to cause real trouble — so copy the commands exactly.

1. Put `boot.img` on the phone (e.g. `/sdcard/Download/boot.img`).
2. In a terminal app or `adb shell`, become root and flash **the `boot` partition only**:
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

**Failure signature:** any `dd` error (`Permission denied`, `No such file`) → **stop**, do not
reboot, paste me the exact message. `Permission denied` usually means root wasn't granted to the
shell.

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
| **Bootloop** (never reaches the animation, or loops the boot animation) | The kernel didn't come up — most likely one of the disabled protections matters on early boot, or a kernel problem. | **Roll back (§7)**, then send me anything from §8. |
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

You changed only `boot`, so rollback is one flash.

- **Via Odin:** wrap your saved stock kernel `BeyondROM_images/boot.img` the same way (or use the
  stock `AP` from prerequisite #3), and Odin-flash it to **AP** exactly as in §3.
- **Via root `dd`:** `dd if=/sdcard/Download/BeyondROM-boot.img of=/dev/block/by-name/boot` then
  `reboot` (use the backup `dd` made in §4, or your saved `BeyondROM_images/boot.img`).
- **If the phone won't boot at all:** boot into **Download Mode** (§3 step 2) — it's always
  reachable regardless of kernel state — and Odin-flash the stock `boot` (or the full stock `AP`
  from prerequisite #3). Download Mode does not depend on the kernel, so a bad kernel can always
  be undone this way.

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
