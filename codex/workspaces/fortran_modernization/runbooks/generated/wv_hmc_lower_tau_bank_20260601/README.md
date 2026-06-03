# WV-HMC Lower-Tau Bank Decision

Date: 2026-06-01

Purpose: record the fixed-tau builder scans used to decide the default lower
endpoint and build a WV-HMC state bank for Stephanov `n=6`, `T1=0.03`.

## Decision

Default WV-HMC `T0 = 0`.

`T0` is the physical-manifold lower endpoint.  It is not a numerical safety knob
for solver/reflow failures.  `D0` remains an independent positive wall-profile
width for `paper_wall`.

If a positive lower `tau_bank` is intentionally used for initialization, it must
remain failure-free at the already selected fixed-tau builder `epsilon` and
`L`.  If it fails, lower `tau_bank`; do not lower `epsilon` to hide the issue.

## HMC Builder Tuning

Fixed-tau builder scan, 16 records x 300 cycles:

| tau | epsilon | nstep | L | acceptance | proposal failure | step rms/coord |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0.08 | 2 | 0.16 | 0.896875 | 0 | 0.150894 |
| 0 | 0.08 | 4 | 0.32 | 0.835417 | 0 | 0.279435 |
| 0 | 0.08 | 6 | 0.48 | 0.802292 | 0 | 0.384180 |
| 0 | 0.08 | 8 | 0.64 | 0.778750 | 0 | 0.461202 |
| 0 | 0.08 | 10 | 0.80 | 0.759375 | 0 | 0.504000 |

Selected builder setting:

```text
tau_bank = 0
epsilon = 0.08
nstep = 8
L = 0.64
```

This setting has acceptance near `0.78`, nontrivial configuration-space
movement, and zero proposal/reflow solver failures.

## Positive-Tau Safety Check

Fixed `epsilon=0.08`, `nstep=8`, `L=0.64`, 16 records x 300 cycles:

| tau | acceptance | proposal failure | step rms/coord |
|---:|---:|---:|---:|
| 0 | 0.778750 | 0 | 0.461202 |
| 1e-8 | 0.781458 | 0 | 0.461776 |
| 3e-8 | 0.778958 | 0 | 0.460760 |
| 1e-7 | 0.776458 | 0 | 0.460080 |
| 3e-7 | 0.778125 | 0.000208333 | 0.460635 |
| 1e-6 | 0.783750 | 0.000416667 | 0.462825 |
| 1e-5 | 0.778542 | 0.00395833 | 0.461214 |
| 1e-4 | 0.752500 | 0.033125 | 0.451918 |

This supports using `T0=0` as the default.  Small positive `tau` exists, but it
does not improve the default design and introduces a solver-safety boundary.

## Built State Bank

Builder run:

```text
chunks = 4
records = 64
cycles per record = 3000
burn_records = 500
stride = 10
```

Aggregate builder diagnostics:

```text
attempts = 192000
acceptance = 0.7716979167
proposal_failure = 0
reverse_gate_reject = 0
metropolis_reject = 43834
chunk acceptance range = 0.7702708333 .. 0.7734791667
step rms/coord range = 0.4590859046 .. 0.4604930611
max record sec/cycle = 0.00904696897
```

Packed bank:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat
records = 16064
record_width = 73
layout = flow_time + x
flow_time = 0
```

Current symlink:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/current_stephanov_n6_t0_state_bank
```

## Loader Smoke

Cluster smoke:

```text
job = 18634.anode01
run = wv_hmc_t0_bank_loader_smoke_16x20_r2_20260601
seeds = 16
cycles per seed = 20
T0 = 0
T1 = 0.03
gamma = 55
epsilon = 0.010
nstep = 8
constraint_max_iter = 192
init_mode = state_bank
```

Smoke result:

```text
return_code = 0 for 16 / 16 seeds
summary_present = 16 / 16
observable_present = 16 / 16
final_state_present = 16 / 16
observable_history_present = 16 / 16
cycles_completed = 320 / 320
measurement_failed = 0
max_constraint_residual <= 9.994552124176383e-11
runtime_sec median = 27.96479105949402
runtime_sec max = 53.46045398712158
```

This is a bank-loader and output-path smoke only.  The 20-cycle run is too short
to serve as WV-HMC production validation or physics evidence.

## Cycle-Sufficiency Gate

For an initialization bank, cycle sufficiency is judged by bank coverage and
sampler health, not by production observable correctness.

Minimum required checks:

- zero proposal/reflow solver failures at the selected builder `epsilon/L`;
- stable acceptance and movement across chunks/seeds;
- post-burn first-half versus second-half stability for state summaries;
- seed-to-seed scatter and no single-seed dominance in harvested records;
- enough post-burn records after stride for downstream random initialization;
- downstream WV-HMC solver/HMC validation rerun using the packed bank.

The current 64 x 3000 builder satisfies the failure, acceptance, movement, and
record-count gates.  Downstream WV-HMC validation is still required before using
the bank for production claims.

## Artifacts

Scan summaries:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/lower_tau_fixed_builder_scan_20260601/lower_tau_fixed_builder_nstep_scan_tau0_eps080_20260601/lower_tau_fixed_builder_scan_summary.csv
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/lower_tau_fixed_builder_scan_20260601/lower_tau_fixed_builder_tiny_positive_tau_eps080_n8_20260601/lower_tau_fixed_builder_scan_summary.csv
```

Bank builder summaries:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/lower_tau_fixed_builder_scan_20260601/lower_tau_fixed_builder_bank_tau0_eps080_n8_chunk00_20260601/lower_tau_fixed_builder_scan_summary.csv
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/lower_tau_fixed_builder_scan_20260601/lower_tau_fixed_builder_bank_tau0_eps080_n8_chunk01_20260601/lower_tau_fixed_builder_scan_summary.csv
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/lower_tau_fixed_builder_scan_20260601/lower_tau_fixed_builder_bank_tau0_eps080_n8_chunk02_20260601/lower_tau_fixed_builder_scan_summary.csv
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/lower_tau_fixed_builder_scan_20260601/lower_tau_fixed_builder_bank_tau0_eps080_n8_chunk03_20260601/lower_tau_fixed_builder_scan_summary.csv
```
