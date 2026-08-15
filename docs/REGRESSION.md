# REGRESSION — the hardware/behaviour checklist run at every gate

Purpose: catch **silent breakage**. Every phase that changes kernel behaviour (Phase 3
KernelSU, Phase 4 SUSFS, and every new Samsung source drop) must re-pass this whole list on a
real flash before it is called done. It is not a performance program — it is a guard.

**How to run it (owner, ~10 min):**
1. Flash the new `boot.img` (+ `init_boot.img` from Phase 3 on), Magisk modules disabled for the
   first boot.
2. In Termux: `su -c 'sh verify-hw.sh <tag>'` and `sh collect-logs.sh <tag>` — send both.
3. Do the hands-on items below.
4. Results are recorded in `docs/MEASUREMENTS.md` against the commit SHA.

## Checklist

| # | Item | How checked | Automated? |
|---|---|---|---|
| 1 | Boots to home | owner | verify-hw [8] confirms it's our kernel |
| 2 | Module count ≈ stock (541) | `verify-hw [1]` | ✅ |
| 3 | Whole-config parity vs stock | CI `check-config-parity.sh` + `verify-hw [8]` | ✅ |
| 4 | Wi-Fi connects | owner | verify-hw [5][6] HALs/wlan0 up |
| 5 | Bluetooth pairs | owner | verify-hw [5] BT HAL up |
| 6 | Hotspot | owner | — |
| 7 | Mobile data / calls (both-way audio) | owner | verify-hw [3] MSS running |
| 8 | Audio playback **and** recording | owner | verify-hw [2] sound card + PCM |
| 9 | Camera (photo+video, front/back) | owner | verify-hw [5] camera HAL up |
| 10 | Fingerprint unlock | owner | verify-hw [5] fingerprint HAL up |
| 11 | GPS lock | owner | verify-hw [5] gnss HAL up |
| 12 | Sensors (auto-rotate, proximity) | owner | verify-hw [5] sensor HAL up |
| 13 | S-Pen | owner | — |
| 14 | No new native crashes / DSPs up | `verify-hw [3][4]` | ✅ |
| 15 | No new bootloader warning screens | owner | — |
| 16 | Play Integrity / SafetyNet status unchanged-or-expected | owner | — |
| 17 | Battery/thermals not obviously worse under a fixed workload | owner | see note |

**Note on #17 (battery/thermals).** Judge at **steady state**, not in the first ~10 min after a
flash: a fresh boot runs dexopt + first-launch + Zygisk/LSPosed re-hooking and pegs the CPU
(measured 92% CPU-pressure decaying to 15% over 5 min on the Build-#9 capture), which makes any
device hot and sluggish briefly. A userspace VPN/proxy stack (clash/protonvpn/wireguard/…) is a
separate, kernel-independent heat source. To attribute heat to the kernel, compare **idle,
settled** (30+ min post-boot, same apps) against stock — not a just-booted capture.

## Baseline — Build #9 (`aedaf28`, protections off, no KernelSU/SUSFS)

Recorded 2026-08-15. This is the reference every later gate is compared against.

| Item | Result |
|---|---|
| 1 Boots | ✅ owner-confirmed |
| 2 Modules 541 | ✅ (=stock; see MEASUREMENTS 2026-08-15) |
| 3 Config parity | ✅ 48 protection symbols only |
| 4–6 Wi-Fi/BT/Hotspot | ✅ owner-confirmed |
| 7 Mobile data/calls | ✅ owner-confirmed ("all functionalities work") |
| 8 Audio play+record | ✅ owner-confirmed (recording explicitly confirmed) |
| 9 Camera | ✅ owner-confirmed |
| 10 Fingerprint | ✅ owner-confirmed |
| 11 GPS | ✅ owner-confirmed |
| 12 Sensors | ✅ owner-confirmed |
| 13 S-Pen | ✅ owner-confirmed ("everything works") |
| 14 No crashes / DSPs up | ✅ tombstones empty, ADSP/MSS/CDSP running |
| 15 Bootloader warnings | (unlocked bootloader — expected Samsung "custom" splash, no change) |
| 16 Play Integrity | not yet checked — will matter more at Phase 3 |
| 17 Battery/thermals | owner noted subjective warmth/sluggishness; traced to post-boot load +
      userspace VPN stack, **not** the kernel (config identical to stock on all perf/thermal
      knobs; disabled protections only remove work). Re-judge at steady state. |

**Phase-1 exit gate: MET** — reproducible build of unmodified Samsung source (protections-off
only) boots with all hardware working.
