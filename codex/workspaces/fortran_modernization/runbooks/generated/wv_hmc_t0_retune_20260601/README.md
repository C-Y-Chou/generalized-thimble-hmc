# WV-HMC T0=0 W(t) and HMC Retune

Date: 2026-06-01

Model: Stephanov `n=6`, `mu=0.6`, sampler interval `[T0,T1]=[0,0.03]`.

Initial bank:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/current_stephanov_n6_t0_state_bank/state_bank_tau0/x_bank.dat
```

## Decision Status

`T0=0` invalidated the previous WV-HMC `W(t)` and HMC settings.

The retune produced a mechanically reasonable candidate:

```text
W profile = paper_wall
gamma = 65
epsilon = 0.009
nstep = 10
L = 0.09
constraint_tol = 1.0e-10
constraint_max_iter = 192
adaptive Newton fail-fast = off
large-residual fail-fast = off
```

This candidate is **not production-approved**.  It passed the histogram /
transport-shaped tuning checks but failed the short observable validation.

## Gamma / Epsilon Scan

Run:

```text
output/wv_hmc_t0_retune_20260601/wv_hmc_n6_t0_retune_gamma_eps_20260601
```

Scale:

```text
gamma = 0,35,55,75,95,125
epsilon = 0.004,0.006,0.008,0.010
nstep = 8
8 seeds x 250 cycles per point
```

Key rows:

| gamma | eps | nstep | acc | t_mean | hist ratio | eff_x | eff_t |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0.008 | 8 | 0.713 | 0.011833 | 7.565 | 0.002540 | 0.004824 |
| 55 | 0.010 | 8 | 0.772 | 0.016686 | 2.951 | 0.003671 | 0.006245 |
| 75 | 0.008 | 8 | 0.8515 | 0.018055 | 2.588 | 0.002647 | 0.005777 |
| 95 | 0.008 | 8 | 0.868 | 0.021046 | 6.158 | 0.002524 | 0.005843 |
| 125 | 0.008 | 8 | 0.871 | 0.022203 | 9.909 | 0.002351 | 0.005484 |

Readback table:

```text
gamma_eps_scan_summary.csv
```

Interpretation for tuning only:

- `gamma=0` leaves the sampler too low-flow-heavy.
- `gamma=95` and `125` over-tilt toward high flow and worsen histogram flatness.
- `gamma=55` and `75` are the useful range.

## Nstep / Movement Scan

Candidate scan rows:

| gamma | eps | nstep | acc | t_mean | hist ratio | eff_x | eff_t |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 55 | 0.010 | 8 | 0.7671 | 0.016503 | 3.312 | 0.003720 | 0.006110 |
| 55 | 0.010 | 10 | 0.6771 | 0.015469 | 8.209 | 0.004837 | 0.006238 |
| 75 | 0.008 | 8 | 0.8725 | 0.019130 | 2.735 | 0.002617 | 0.005862 |
| 75 | 0.008 | 10 | 0.8196 | 0.018541 | 4.771 | 0.003750 | 0.006504 |
| 65 | 0.009 | 8 | 0.8163 | 0.016739 | 2.591 | 0.003249 | 0.006211 |
| 65 | 0.009 | 10 | 0.8058 | 0.018594 | 3.032 | 0.004620 | 0.006852 |

Selected validation candidate:

```text
gamma = 65
epsilon = 0.009
nstep = 10
```

Reason: it keeps histogram flatness close to the best rows while increasing
configuration-space movement compared with the `nstep=8` candidates.

## Short Validation

Run:

```text
output/wv_hmc_t0_retune_20260601/wv_hmc_n6_t0_retuned_g65e009n10_validation_32x1500_20260601
```

Scale:

```text
32 seeds x 1500 cycles
observable_history = on
final_state = on
cyclic_snapshot = on
```

Transition summary:

```text
acceptance = 0.8034
transitions_failed_per_cycle = 0.1829
reverse_gate_rejected_per_cycle = 0.01052
flow_time_mean = 0.018398
flow_time_max = 0.034999
measurement_hist_max_min_ratio = 1.566
effective_x_jump_sq_mean = 0.004640
effective_flow_time_jump_abs_mean = 0.006788
```

Observable prefix result:

| prefix | C | chiral Re | chiral z | density Re | density z |
|---:|---:|---:|---:|---:|---:|
| 250 | 0.11462 | 0.012013987 | -3.484 | 1.0463724 | 3.360 |
| 500 | 0.10731 | 0.013582304 | -3.673 | 0.96584267 | 3.649 |
| 750 | 0.11139 | 0.012910487 | -5.043 | 0.85150852 | 2.779 |
| 1000 | 0.094401 | 0.015159862 | -3.445 | 0.81037621 | 2.201 |
| 1250 | 0.090102 | 0.016786280 | -3.357 | 0.72572887 | 1.404 |
| 1500 | 0.092601 | 0.016344778 | -3.654 | 0.79081800 | 2.218 |

Exact references:

```text
chiral_condensate = 0.0244771983
number_density = 0.5661155667
```

Flow-bin check:

- highest bin `[0.028125,0.03]` gives density Re `z=0.199`;
- same highest bin gives chiral Re `z=-1.681`;
- low and mid bins remain visibly biased, and the pooled estimator does not
  pass the observable gate.

## Result

The retuned candidate is suitable for further debugging, not production.

Passed tuning-style checks:

- `W(t)` histogram is much flatter than the previous low-flow-heavy setup;
- HMC acceptance is not artificially near one;
- configuration-space movement is improved relative to `nstep=8` candidates;
- cyclic snapshots and final states were produced in the validation run.

Failed validation gate:

- `chiral_condensate` Re remains about `-3.65 sigma` at 1500 cycles;
- `number_density` Re remains about `+2.22 sigma` at 1500 cycles;
- prefix trend does not show stable convergence to zero z-score.

Next diagnostic direction:

- do not productionize this candidate yet;
- inspect WV weight / ratio-estimator construction and flow-bin contribution;
- compare against fixed-tau/high-flow conditional observables;
- if the kernel is confirmed, use this candidate as the baseline for longer
  statistics, but not before the observable-gate failure is understood.

## Artifacts

Local readback files:

```text
gamma_eps_scan_summary.csv
nstep_g55e010_summary.csv
nstep_g75e008_summary.csv
nstep_g65e009_summary.csv
validation_g65e009n10_scan_summary.csv
validation_g65e009n10_prefix_sweep.csv
validation_g65e009n10_flow_bins.csv
```

Remote output roots:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_retune_20260601
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_t0_retune_20260601
```
