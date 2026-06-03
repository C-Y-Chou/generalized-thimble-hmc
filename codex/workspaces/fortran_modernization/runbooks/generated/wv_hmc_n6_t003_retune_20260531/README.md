# WV-HMC n=6 t=0.03 Retune

Date: 2026-05-31

Purpose: retune WV-HMC after the first `T1=0.03` validation attempt showed
that carrying over the small-interval Newton cap and trajectory was invalid.

## Fixed Inputs

```text
model = Stephanov n=6, nf=1, m=0.004, mu=0.6, tau=0
parameters_file = data/parameters_stephanov_n6_mu06_t0.dat
T0 = 0.0001
T1 = 0.03
D0 = 0.0001
D1 = 0.005
measurement interval = [T0,T1]
W(t) = paper_wall
gamma = 0
ODE backend = dop853
constraint_tol = 1e-10
adaptive_newton_stop = off
init bank = n=6 safe t=0.0001 bank; warm state-bank available after smoke
```

## Why Retuning Was Required

The previous long-validation attempt used:

```text
epsilon = 0.015
nstep = 10
L = 0.15
constraint_max_iter = 24
```

It was stopped because an early completed seed had:

```text
accepted = 0 / 5000
transitions_failed = 4966 / 5000
solver_stop_max_iter = 4414
flow_time_min = flow_time_max = 0.001
```

This showed that `constraint_max_iter=24` was too small for the larger
`T1=0.03` geometry, and that the trajectory was too aggressive for some
initial-bank records.

## Hard-Record Mobility Scan

Hard record: init-bank record `70`.

Scan:

```text
constraint_max_iter = 128
epsilon/nstep candidates:
  0.004/4, 0.005/4, 0.005/6, 0.005/8,
  0.0075/4, 0.0075/6, 0.0075/8,
  0.010/4, 0.010/6, 0.010/8,
  0.0125/6, 0.0125/8
```

Key result: the hard record is movable with smaller trajectories.  This means
the large-flow geometry is not completely unusable, but the previous
`epsilon=0.015, nstep=10` was too aggressive.

Best practical hard-record candidates:

```text
epsilon=0.0075, nstep=8:
  acceptance ~= 0.909
  effective_x_jump_sq ~= 0.00281
  failure/cycle ~= 0.041

epsilon=0.010, nstep=8:
  acceptance ~= 0.739
  effective_x_jump_sq ~= 0.00385
  failure/cycle ~= 0.084
```

## Random-Bank Mobility Scan

Random-bank scan compared the practical candidates using successful manifest
seeds only.

Key random-bank results:

```text
epsilon=0.0075, nstep=8, max_iter=128:
  successful seeds = 13 / 16
  acceptance ~= 0.951
  effective_x_jump_sq ~= 0.00293
  failure/cycle ~= 0.031

epsilon=0.010, nstep=8, max_iter=128:
  successful seeds = 16 / 16
  acceptance ~= 0.914
  effective_x_jump_sq ~= 0.00471
  failure/cycle ~= 0.062

epsilon=0.010, nstep=4, max_iter=128:
  successful seeds = 16 / 16
  acceptance ~= 0.953
  effective_x_jump_sq ~= 0.00133
  failure/cycle ~= 0.028
```

Decision: use `epsilon=0.010, nstep=8`.  It gives the best
configuration-space movement among the practical candidates while preserving
usable acceptance on both random-bank draws and the hard record.

## Solver Cap Check

For the selected `epsilon=0.010, nstep=8`, cap check on matched random seeds:

```text
max_iter=96:
  acceptance ~= 0.916
  effective_x_jump_sq ~= 0.00474
  max_iter/cycle ~= 0.0198

max_iter=128:
  acceptance ~= 0.914
  effective_x_jump_sq ~= 0.00471
  max_iter/cycle ~= 0.0148

max_iter=192:
  acceptance ~= 0.921
  effective_x_jump_sq ~= 0.00475
  max_iter/cycle ~= 0.00875
```

Decision: use `constraint_max_iter=192` for the next validation.  It reduces
max-iter truncation relative to 128 and did not show a wall-clock penalty in
the matched scan.

## Current Retuned Candidate

```text
T0 = 0.0001
T1 = 0.03
D0 = 0.0001
D1 = 0.005
W(t) = paper_wall
gamma = 0
epsilon = 0.010
nstep = 8
L = 0.080
constraint_tol = 1e-10
constraint_max_iter = 192
adaptive_newton_stop = off
large_residual_stop = off by default
reverse gate = on
```

## Validation Smoke

Submitted:

```text
run_root =
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_retuned_g0_eps010_n8_max192_32x1000_20260531

jobs = 18415.anode01 ... 18418.anode01
scale = 32 seeds x 1000 cycles
measurement_start_cycle = 201
observable_history = on
final_state = on
```

This validation is a smoke/parameter gate, not the final production run.

Result:

```text
completed seeds = 32 / 32
cycles = 32000
measurements = 24147
acceptance = 0.9061875
transitions_failed = 1977 / 32000
reverse_gate_rejected = 672 / 32000
phase_coherence = 0.0507131
```

Movement/runtime summary:

```text
effective_x_jump_sq_mean = 0.004697
effective_z_jump_sq_mean = 0.005360
effective_flow_time_jump_abs_mean = 0.006575
flow_time_mean = 0.01195
flow_time_max = 0.03499
median runtime per seed = 1710 sec
```

Exact-reference smoke z-scores:

```text
chiral_condensate:
  Re = 0.0268379661 +/- 0.00835624, z_Re = 0.283
  Im = -0.0096144518 +/- 0.0108853, z_Im = -0.883

number_density:
  Re = 0.478038071 +/- 0.271389, z_Re = -0.325
  Im = 0.150257375 +/- 0.349886, z_Im = 0.429
```

Conclusion: this retuned parameter set passes the immediate WV-HMC
`T1=0.03` smoke gate.  It is not yet a final production setting because the
run is only `32 x 1000` cycles, but it fixes the earlier zero-accept / max-iter
failure mode and gives exact-reference z-scores below 1 in the smoke sample.

## Warm State Bank

Built from the 32 successful final states of the validation smoke:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_retuned_g0_eps010_n8_max192_32x1000_20260531/warm_bank/x_bank.dat
records = 32
record format = flow_time + x
init mode = state_bank
state_size = 72 x-components
```

Important: this bank is not an x-only bank.  Use
`WV_OBS_INIT_MODE=state_bank`, not `bank`; the x-only loader correctly rejects
this file with a record-size mismatch.

## Large-Residual Newton Gate

Implemented a configurable Newton fail-fast gate:

```text
WV_HMC_LARGE_RESIDUAL_STOP_ENABLED
WV_HMC_LARGE_RESIDUAL_THRESHOLD
WV_HMC_LARGE_RESIDUAL_MIN_ITER
WV_HMC_LARGE_RESIDUAL_PATIENCE
WV_HMC_LARGE_RESIDUAL_MIN_REL_IMPROVEMENT
```

The default remains disabled.  When enabled, the solver exits with
`wv_newton_stop_large_residual` only after the minimum iteration count has
passed, the best/current residual are still above the threshold, and the
residual has failed to improve enough for the requested patience window.

Trace calibration:

```text
run =
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_large_residual_trace_off_statebank_8x100_20260531

scale = 8 seeds x 100 cycles
solves = 12347
converged = 11854
boundary_exit = 445
residual_error = 41
max_iter = 7
```

Key observation: current failures are not mostly "max_iter stuck at large
residual".  Residual-error cases already fail within a few iterations at large
residual, while max-iter cases are rare and often have already reduced the
residual far below `1e-4`.

A/B check:

```text
off run =
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_large_residual_ab_off_8x200_20260531

on run =
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_large_residual_ab_on_8x200_20260531

gate-on setting:
  threshold = 1e-3
  min_iter = 16
  patience = 4
  min_rel_improvement = 5e-4
```

Both runs used matched seeds and the warm state bank.  The accepted/rejected
counts, final flow times, denominators, and movement metrics matched between
gate off and gate on:

```text
cycles = 1600
accepted = 1454
rejected = 146
effective_x_jump_sq_mean = 0.0047604303
effective_flow_time_jump_abs_mean = 0.0064200041
phase_coherence = 0.1410046534
```

The gate converted some would-be max-iter stops into large-residual stops
without changing the chain state:

```text
gate off:
  solver_stop_max_iter = 19
  reverse_solver_stop_max_iter = 5
  solver_stop_large_residual = 0
  reverse_solver_stop_large_residual = 0

gate on:
  solver_stop_max_iter = 4
  reverse_solver_stop_max_iter = 1
  solver_stop_large_residual = 21
  reverse_solver_stop_large_residual = 5
```

The solver-iteration reduction was small:

```text
gate off total Newton iterations = 223990
gate on total Newton iterations = 223529
saved iterations ~= 0.2%
```

Conclusion: keep this gate available as a diagnostic/fail-fast knob, but do not
treat it as a meaningful production speedup for the current warm-bank
`T1=0.03` setup.  The observed wall-clock difference in the A/B run was
dominated by node placement (`cnode01` vs `cnode37`), not by Newton iteration
count.

## Artifacts

```text
hard70_mobility_final/wv_hmc_scan_summary.md
retune_final/wv_hmc_scan_summary.md
validation_smoke/history_readback/wv_hmc_history_readback.md
validation_smoke/scan_summary/wv_hmc_scan_summary.md
large_residual_trace_off_statebank_8x100/newton_trace_analysis
large_residual_ab_off_8x200/scan_summary
large_residual_ab_on_8x200/scan_summary
```
