# CLAUDE.md — standing rules for this repository

This file is loaded automatically at the start of every Claude Code session in this repo.
It outranks anything said in a single conversation. If a chat instruction conflicts with a
rule here, say so and ask before proceeding.

---

## What this repo is

Android kernel for:

| | |
|---|---|
| Device | Samsung Galaxy S24 Ultra |
| Model | SM-S928B (international) |
| Codename | e3q |
| SoC | Qualcomm SM8650 / Snapdragon 8 Gen 3 (QC target: `pineapple`) |
| Kernel | 6.1 — see `docs/FACTS.md` for the exact SUBLEVEL |
| GKI | 2.0, Android 14 KMI |
| Partition layout | init_boot device: `boot.img` = kernel, `init_boot.img` = generic ramdisk, `vendor_boot`/`vendor_dlkm` = vendor ramdisk + modules. Confirm in FACTS. |
| Build system | See `docs/FACTS.md`. Assume Kleaf/Bazel until proven otherwise. |
| Owner status | Bootloader unlocked, custom ROM, rooted. No warnings needed on that front. |

Goals, in priority order:
1. A reproducible build of **unmodified** Samsung source that boots with all hardware working.
2. **KernelSU Next in LKM mode**, patched into `init_boot.img`, plus the Samsung/Knox
   patching required to make a modified kernel boot and to let the LKM load at all.
3. **SUSFS** (susfs4ksu) on top of a working KernelSU Next.

Goal 1 gates everything. There is no point in 2 or 3 until 1 is boringly reliable.

Qualcomm CLO backporting is **out of scope for now** (dropped 2026-08-11). Do not add CLO
remotes, do not cherry-pick from CLO, do not reintroduce it without an explicit new decision
recorded in `docs/DECISIONS.md`.

---

## Hard rules

### Never invent
- **Never write a `CONFIG_` symbol you have not grepped for in this tree.** Kernel config
  names differ between vendors and versions. `grep -rn 'CONFIG_FOO' kernel_platform/` before use.
- **Never cite a file path, build target, or script name from memory.** `ls` it first.
- **Never state what Samsung's code does without reading it.** This tree is heavily forked;
  upstream knowledge does not transfer reliably.
- If you don't know, write `TBD` and say so. `TBD` is always acceptable. A plausible
  fabrication is never acceptable.

### Never claim it works
You have no device. Compiling is not testing. Do not write "this should boot", "this fixes
the issue", or "everything works now". The correct phrasing is: *"Built successfully. To
verify, flash X and check Y. If Z happens, that means W."*

### Firmware-coupled subsystems — do not touch without explicit approval
These drivers talk to blobs in partitions we are not replacing. Changing them breaks the
device in ways that look like unrelated bugs:
- Display / DPU / panel drivers
- KGSL (Adreno GPU)
- Camera (`techpack/camera`, CAMSS)
- Audio (`techpack/audio`, ADSP)
- Modem, IPA, remoteproc / subsystem restart
- Anything under `drivers/soc/qcom/` that loads firmware images

### Samsung security modules — neutralize in source, one at a time
DEFEX, PROCA, RKP/uH, KDP, FIVE and friends will block a modified kernel from booting and
block the KernelSU LKM from loading. We have the source, so neutralize them **at the source**,
in this order of preference:
1. **Defconfig** — drop the `CONFIG_*` symbol if the subsystem can simply be disabled.
2. **Targeted C patch** — if the symbol is force-selected or disabling it breaks the build,
   patch the enforcement function itself to be inert.
3. **Post-build image patch** — only as a last resort, for a protection that has no workable
   source off-switch. This is what source-blind tools (Magisk, ExtremeROM's PROCA `sed`) are
   forced to do; we prefer it only when source genuinely can't reach the mechanism cleanly.

The right level is decided per symbol from the §0.4 grep evidence, not by a blanket rule.
Each protection is its own commit with a note on what it protected and which level was used.
Never a single "disable Knox" mega-patch. Read the exact symbols from `docs/FACTS.md` §0.4;
don't guess them.

Note: **SEANDROIDENFORCE and vbmeta/AVB are not in this list.** They are not kernel behaviour
— see the packaging rules in the skill — and correctly live as post-build steps regardless of
source access.

### One change per commit
No omnibus commits. Every commit must be independently revertible and bisectable.

---

## Repo layout and branch model

```
vanilla            import-only. One commit per Samsung OSRC drop. Tagged by firmware
                   build string (e.g. `osrc/S928BXXU5CXK1`). NOTHING ELSE EVER LANDS HERE.
main               vanilla + our patch series. This is what CI builds.
patches/           our changes as a rebasable series (git format-patch output):
                   Samsung protection neutralization, kprobes/config enablement,
                   later the SUSFS kernel patch.
```

There are **no** per-feature branches. Build variants (toolchain, LTO mode, KernelSU on/off,
later SUSFS on/off) are **workflow inputs**, not branches.

KernelSU Next (LKM) and the SUSFS userspace module are packaging/artifact steps, not kernel
source — they produce a patched `init_boot.img`, not commits on `main`. The kernel-side
pieces they require (kprobes enabled, protections neutralized, SUSFS kernel patch) do live in
`patches/`.

Every new Samsung source drop: import onto `vanilla`, then replay `patches/` onto it. If a
patch no longer applies, that is signal — investigate, don't force.

---

## Writing for the reader

This applies to every piece of text meant for another human: commit messages, code comments,
`docs/`, PR descriptions, handoff notes.

Before writing, shift out of your own perspective. Ask: what is this for, who reads it, what
do they already know, what do they actually need? Write from their vantage point. Your session
history, your discovery process, your edit path, and your internal narrative are invisible to
the reader and usually irrelevant to them. When editing existing text, match its style and
structure and keep what's still relevant to the reader rather than preserving everything by
default; don't give your own additions disproportionate weight or let them read as obviously
foreign. Re-read once from a cold reader's seat before finishing.

**Never include a Claude Code session link, or any reference to the assistant, in a commit
message or its description.**

### Commit message format

```
<subsystem>: <imperative summary>

<why, not what — from the reader's perspective>

Verified: <not-flashed | boots | boots+all-hw | regressed:...>
```

The `Verified:` trailer is filled in by the human after flashing. If you write a commit, set
it to `not-flashed`.

---

## Working conventions

- **`docs/FACTS.md` is ground truth.** Read it at session start. If FACTS contradicts your
  assumptions, FACTS wins. If you learn something new about the tree, write it there.
- **`docs/DECISIONS.md`** records settled choices with dates and reasoning. Read before
  reopening an old debate. Append when something new is settled.
- **`.claude/skills/e3q-kernel/SKILL.md`** holds the build, Samsung-patching, KSU-LKM, SUSFS,
  and repack procedures. Consult it for anything involving compiling, patching, packaging, or
  flashing artifacts.
- **Files that do not exist yet, by design.** `scripts/build.sh` and `scripts/package.sh` are
  written in Phase 1 (they depend on FACTS §0.2); `scripts/patch-init-boot.sh` in Phase 3;
  `docs/FLASHING.md` in Phase 2; `docs/MEASUREMENTS.md` when the first checklist runs. Their
  absence is expected, not a bug — the CI preflight step names them explicitly. Do not stub
  them with guessed content.
- Do not run full kernel builds in this sandbox — insufficient disk. Builds run in GitHub
  Actions. Local work is source edits, scripts, config grepping, and log triage.
- **Workflows are manual-only** (`workflow_dispatch`). Never add `push`/`pull_request`/`schedule`
  triggers — CI minutes and disk are not to be spent automatically.
- Never commit toolchains, firmware archives, `.ko` blobs, `.img` files, or anything over
  50 MB. See `.gitignore`.

## Talking to the owner

Non-programmer. Explain reasoning briefly, then give literal commands. For every action
requested of them, state the expected good outcome and the failure signature. Prefer "run
this, paste me the output" over "check whether X is configured correctly".
