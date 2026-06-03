# WV-HMC N6 Problem Diagnosis 2026-06-01

Data source:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_production_20260601/wv_hmc_n6_t003_prod768x15000_gitless_r3_20260601`

## Finding

The current WV-HMC `n=6`, `t in [0.0001, 0.03]`, `gamma=0` production is not failing because the chains are frozen at the initial bank. The concrete failure mode is that `gamma=0` leaves `W(t)` flat, so the transition samples too much low flow time. The full `[T0,T1]` estimator is then dominated by low-flow regions where the sign/ratio estimator is much worse, and chiral condensate stays persistently low.

For the implemented `paper_wall` profile inside the sampling interval,

```text
W(t) = -gamma * (t - T0)
```

so positive `gamma` increases the sampled density toward high flow time by the factor

```text
exp[-W(T1)] / exp[-W(T0)] = exp(gamma * (T1 - T0)).
```

With `T1 - T0 ~= 0.03`, changing the high/low visitation ratio by about five requires `gamma ~= log(5)/0.03 ~= 54`. Therefore small values such as `gamma = 0.2` or `1` are not meaningful tests at this interval length.

The diagnostic problem is visible with short prefixes:

| prefix | measurement cut | chiral Re | SE | z |
|---:|---:|---:|---:|---:|
| 1500 | `t >= 0.0001` | 0.0209108 | 0.00105 | -3.386 |
| 2500 | `t >= 0.0001` | 0.0208820 | 0.000954 | -3.770 |
| 5000 | `t >= 0.0001` | 0.0227544 | 0.000844 | -2.041 |
| 10000 | `t >= 0.0001` | 0.0223663 | 0.000487 | -4.336 |
| 15000 | `t >= 0.0001` | 0.0225948 | 0.000378 | -4.973 |

The same completed data becomes consistent when the measurement is restricted to high flow time:

| prefix | measurement cut | chiral Re | SE | z |
|---:|---:|---:|---:|---:|
| 5000 | `t >= 0.020` | 0.0231567 | 0.00188 | -0.703 |
| 5000 | `t >= 0.025` | 0.0251672 | 0.00339 | 0.203 |
| 10000 | `t >= 0.025` | 0.0235091 | 0.00161 | -0.600 |
| 10000 | `t >= 0.028` | 0.0253610 | 0.00390 | 0.227 |
| 15000 | `t >= 0.028` | 0.0242426 | 0.00257 | -0.091 |

The flow-time histogram confirms the mechanism. The lowest bin has 14.1% of all measurements and phase coherence `C=0.039`, while the highest bin has only 2.8% and `C=0.116`. With flat `W(t)`, the run spends too much measurement mass in the low-flow region.

## What This Rules Out

- Not just a no-movement failure: final-state displacement from the selected bank has `dx2_per_dim` median `0.144773`.
- Not just a seed-bank clustering artifact: jackknife over the 32 initial-bank records gives chiral Re `0.0225948`, SE `0.0003337`, z `-5.642`.
- Not a simple measurement-factor conjugation or missing-alpha variant at `gamma=0`: tested variants were worse than the current factor.

## Working Diagnosis

The immediate WV-HMC issue is `W(t)` / `gamma` tuning:

1. `gamma=0` leaves `W(t)` flat.
2. Flat `W(t)` samples too strongly near small flow time.
3. Full-window measurement `[0.0001, 0.03]` includes low/mid-flow regions where the finite-sample ratio estimator gives a persistent low chiral condensate.
4. High-flow measurement cuts are consistent with the exact chiral condensate but need enough samples because only a small fraction of the run lives there.

This is not yet proof that every WV kernel formula is perfect, but it identifies the first concrete failure mode to fix before matrix-free/BiCGStab work. The next correction should tune `gamma` so the sampler actually visits high flow time often enough; a high-flow measurement cut is only a diagnostic view of the same data, not the primary fix.

Follow-up gamma-scan correction: choose `gamma` first from the flow-time
histogram on the fixed measurement interval.  The `gamma=55` scan point is the
current count-flat baseline; `gamma=80` is a high-flow-biased upper-bracket
diagnostic.  Better short-run phase coherence at larger `gamma` is not a
selection criterion if it is produced by suppressing low-flow visits.

## Short-Cycle Diagnostic Policy

Future tests should not repeat 15k-cycle blind validation.

- To detect the current full-window failure: 1500-2500 cycles with many seeds is already enough.
- To test whether high-flow measurement fixes the chiral observable: use at least 5000 cycles for `t >= 0.025`, preferably 10000 if the run is meant to decide precision.
- For quick iteration, use the completed 15k data as the reference and compare new runs against:
  - full interval: expected to show the low chiral warning quickly;
  - high-flow cut `t >= 0.025` or `t >= 0.028`: expected to be statistically compatible with exact but noisier.

## Next Fix Direction

Before further long validation:

1. Tune `W(t)` / `gamma` so transition sampling supplies enough high-flow measurements without feeding measurement results back into the Markov transition.
2. Use full `[T0,T1]` measurement during gamma scans to verify that the corrected transition histogram repairs the full-window estimator.
3. Keep high-flow measurement subintervals, for example `measurement_t0 = 0.025`, `measurement_t1 = 0.03`, as diagnostics and possible production measurement policy after `W(t)` is tuned.
4. Keep transition `[T0,T1]` and measurement `[T0,T1]` explicitly separate in run manifests.
5. Use prefix-grid diagnostics after each short run to decide whether a longer run is justified.

Initial short gamma scan submitted after this diagnosis:

```text
gamma = 30, 55, 80, 120
seeds = 16 per gamma
cycles = 2500
epsilon = 0.010
nstep = 8
measurement = [0.0001, 0.03]
```

The primary decision variable is the flow-time histogram and acceptance/movement health, not just observable z-score at this short cycle count.

## Artifacts

- `prefix_sweep_summary.csv`
- `flow_cut_summary.csv`
- `prefix_flow_cut_grid.csv`
- `flow_bin_summary.csv`
- `bank_record_pooled_all.csv`
- `final_displacement_from_bank.csv`
