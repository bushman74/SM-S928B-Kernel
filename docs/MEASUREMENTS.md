# MEASUREMENTS — on-device comparisons

Records real device captures and their analysis. Each entry: what was compared, the method,
and every difference found with a verdict. The rule: a difference is not dismissed until it is
explained.

---

## 2026-08-15 — Build #9 vs stock, exhaustive A/B (same scripts, same device)

**Setup.** Owner captured `verify-hw.sh` + `collect-logs.sh` on Build #9 (`main` @ `aedaf28`,
all 7 protections off), then restored the **stock** `boot.img` and captured again with the
identical scripts. Both booted from TWRP (`bootreason=recovery`, `reset_reason=RPON`).
Kernels: ours `6.1.145-android14-11---ab`, stock `6.1.145-android14-11-33419968-abS928BXXU5DZDP`.

**Method.** Every artifact in the two captures was diffed (modules, config, remoteproc, ALSA,
net interfaces, init.svc states, dmesg error signatures, logcat crash/system/events, dropbox,
tombstones, pstore, boot reasons). Findings below.

### Identical (no difference beyond capture timestamps)
| Artifact | Result |
|---|---|
| Loaded modules | **541 = 541, identical set** — 0 on stock missing from ours, 0 extra on ours |
| `modules.load` / `modules.load.all` | identical (472 / 592 lines) |
| Remoteproc DSPs | identical: SPSS `attached`, ADSP/MSS/CDSP `running` (SPSS `attached` is normal on stock too) |
| ALSA (`/proc/asound` cards/pcm/tree) | identical — `pineapple-mtp-snd-card`, 49 PCM devices, same codec tree |
| Network interfaces (`ip addr`) | identical set |
| HAL service *states* | **zero** services changed state between stock and ours |
| tombstones / pstore | both empty (no native crashes, no kernel panics) |
| boot/reset reason | identical |

### Config
- **48 symbols differ, all in the protection family** (UH/RKP/KDP, SECURITY_DEFEX, PROCA, FIVE,
  MODULE_SIG_PROTECT + the GAF/INTEGRITY/SIGNATURE cascade FIVE selects). Zero non-protection
  differences; our config is a strict subset of stock. (`check-config-parity.sh` PASS.)

### Differences found — every one explained, none our-kernel-caused
| Difference | Investigation | Verdict |
|---|---|---|
| `logcat-crash`: stock 0, ours 32 lines | A modded **Deezer** (`com.coocoo.CooCooAppShell`, an LSPosed/CooCoo hook) → `LinkageError: overrides final method`. | App/LSPosed. Stock's buffer was 0 only because Deezer wasn't launched that session. **Not kernel.** |
| dropbox +`data_app_crash` | same Deezer crash | App. Not kernel. |
| dropbox +`system_app_anr` | `com.android.systemui` ANR at 77 s uptime under memory pressure (`/proc/pressure/memory some avg10=10.4`) | Transient boot-time ANR. Not kernel. |
| `vaultkeeper` messages (stock 40 / ours 46; last_kmsg 125 / 230) + one `vaultkeeper read error(-1)` on ours | `vaultkeeper_aidl` crash-loops on **both**: *"Could not find …ISehVaultKeeper/default in the VINTF manifest"* → exit 255 → SIGKILL → restart | **ROM/vendor VINTF-manifest issue, identical on stock.** Expected on an unlocked bootloader (broken secure-vault chain). **Not kernel.** |
| `kiwi_v2 [TWT] wlan_twt_get_session_state: Peer object not found ff:ff:ff:…` (ours 3, stock 0) | WiFi Target-Wake-Time power-save query for a broadcast MAC | Benign driver chatter; appears only because WiFi was active during our capture. **Not an error.** |
| `BiometricService: Enabled callback binder died` / `LockoutResetTracker: … dead callback for com.android.systemui` (ours only) | Fired at 11:32:37, right after the SystemUI ANR/restart — the framework cleaning up SystemUI's dead biometric callbacks | Downstream of the SystemUI ANR. `vendor.fingerprint-default` HAL **running**, `fingerprint`/`fingerprint_sysfs` modules loaded. **Not a fingerprint fault.** |
| `dmesg-audio` 12 vs 1 line | stock window caught benign SELinux `avc: denied {find}` audits (an untrusted app querying camera/soundtrigger); ours caught an `adsp_sleepmon` tick | Ring-buffer timing. No audio error in either. |
| init.svc +`vendor.dumpstate-default: stopped` (ours) | the one-shot dumpstate that the log capture itself triggered | Capture artifact. |
| No new `dumpstate_booting_delay` for Build #9 | the zip in the capture is the stale Aug-14 one (Build #7) | **Build #9 booted without triggering a boot-delay dumpstate** — a positive signal. |

**Conclusion.** Every difference between Build #9 and stock is either (a) one of the 48 intended
protection config symbols, or (b) benign runtime/app/LSPosed/ROM noise not caused by our kernel
(the VaultKeeper crash-loop is demonstrably present on stock too). **No kernel-caused driver or
hardware regression was found anywhere in the exhaustive comparison.** All hardware HALs,
modules, and DSP subsystems are present and in the same state as stock. Owner hands-on
spot-checks still pending to close the last mile: camera capture, fingerprint unlock, call
audio (both directions), GPS lock, auto-rotate/proximity. (Voice recording: owner-confirmed
working.)
