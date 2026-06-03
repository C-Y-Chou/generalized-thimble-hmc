# WV-HMC T0=0 Slow-Mixing vs Bug Diagnostic

Date: 2026-06-01

Scope: Stephanov `n=6`, dense explicit-J WV-HMC, current `T0=0` candidate
`gamma=65`, `epsilon=0.009`, `nstep=10`, `T1=0.03`.

Remote source:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_retune_20260601/wv_hmc_n6_t0_retuned_g65e009n10_validation_32x1500_20260601
```

## Question

The full-interval validation failed the observable gate.  This diagnostic asks
whether the failure is more consistent with an algebraic/kernel bug or with
finite-chain thermalization, low-flow measurement contamination, and slow
mixing from the `T0=0` bank.

## Checks Run

1. Recomputed alternative offline weights from the existing observable history.
2. Recomputed window, suffix, and flow-time-cut ratio estimators from the same
   trajectory, preserving the complex ratio structure and using seed
   jackknife errors.
3. Compared against the already recorded deterministic nonzero-`W`
   measurement identity and transition gates.

Generated table:

```text
window_tcut_summary.csv
```

## Current Evidence

The failed full-interval estimator is:

| cut | samples | C | chiral z | density z |
|---|---:|---:|---:|---:|
| `tmin_0_all` | 40208 | 0.0926 | -3.654 | 2.218 |

Late-cycle cuts are much less biased:

| cut | samples | C | chiral z | density z |
|---|---:|---:|---:|---:|
| `cycle_501_1500` | 26793 | 0.0851 | -1.762 | 0.763 |
| `cycle_751_1500` | 20094 | 0.0742 | -0.484 | 0.625 |

Late and high-flow cuts are also compatible within current low statistics:

| cut | samples | C | chiral z | density z |
|---|---:|---:|---:|---:|
| `cycle_1001_1500_tmin_0.020` | 5128 | 0.1214 | -1.075 | 1.136 |
| `cycle_1001_1500_tmin_0.025` | 2788 | 0.1131 | -0.468 | 0.531 |
| `cycle_1001_1500_tmin_0.028` | 1208 | 0.1155 | -0.838 | 0.703 |

The alternative-weight check does not identify a simple measurement-factor
bug.  Removing `exp(W)` does not repair the full-interval estimator:

| weight variant | chiral z | density z |
|---|---:|---:|
| current `exp(W) phase / alpha` | -3.654 | 2.218 |
| `phase / alpha` | -3.894 | 2.331 |

The deterministic nonzero-`W` identity from the existing WV-HMC production gate
already verifies the local algebra:

```text
exp(-Re S - W) * alpha * |det J|
  * [exp(W) * exp(-i Im S) * detJ/|detJ| / alpha]
= exp(-S) * detJ
```

That makes a plain `exp(W)` sign or `alpha^{-1}` algebra error unlikely.

## Interim Conclusion

This is not enough to prove final correctness, but the current evidence is more
consistent with slow thermalization / low-flow measurement contamination than
with an immediate deterministic measurement-formula bug.

The failed number from the 32 x 1500 validation should not be used as a final
WV-HMC production gate because it measures the full `[0,T1]` interval starting
from a `T0=0` bank.  The low-flow part has the worst sign/ratio behavior and
dominates the early full-interval diagnostic.

The strongest discriminator is now:

1. keep the transition interval `[0,0.03]`;
2. do not feed measurement cuts back into the transition;
3. validate with a high-flow measurement subinterval, initially
   `measurement_t0 = 0.025` or `0.028`;
4. use either a target-matched WV equilibrium bank or a declared burn-in before
   measurement;
5. require first/second-window, suffix, and flow-time-cut consistency.

If that high-flow/late measurement passes while the full interval fails, the
issue is finite-chain variance/thermalization, not a kernel bug.  If it still
fails after a target-matched bank and adequate burn-in, reopen the nonzero-`W`
transition-kernel audit at production-scale `gamma`.

## Decision Status

Current status: no production approval yet.

Do not tune `W(t)` or HMC parameters based on the full-interval observable
failure alone.  The next validation gate must explicitly separate transition
coverage from measurement subinterval quality.
