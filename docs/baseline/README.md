# Baseline artifacts

Ground-truth snapshots used by the verification harness to prove our kernel differs from
stock **only** where we intend it to. These are references, not build inputs.

## `config-S928BXXU5DZDP.stock`

The **stock** kernel config for firmware `S928BXXU5DZDP`, captured from the owner's device
(`/proc/config.gz`, `CONFIG_IKCONFIG_PROC=y`) while running the unmodified Samsung `boot.img`
(BeyondROM ships the stock kernel). Sorted, `CONFIG_` lines only (`grep -E '^(CONFIG_|# CONFIG_)' | sort`).

Used by `scripts/check-config-parity.sh` (in CI against the freshly built config, and on-device
in `verify-hw.sh` against `/proc/config.gz`) to assert that every symbol which differs from
stock is an **allowlisted protection** (UH/RKP/KDP, DEFEX, PROCA, FIVE, MODULE_SIG_PROTECT, and
the cascade those `select`/`depends on`: GAF, INTEGRITY_ASYMMETRIC_KEYS, INTEGRITY_TRUSTED_KEYRING,
SIGNATURE). Empirically, our Build-#7 running config differed from this baseline by exactly 42
symbols, **all** in that family and **zero** additions — see `docs/FACTS.md` §0.3.x.

Update this only when a new Samsung OSRC drop changes the stock config (new firmware string ⇒
new baseline file), and record the change in `docs/DECISIONS.md`.
