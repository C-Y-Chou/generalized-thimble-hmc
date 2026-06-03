# WV-HMC n=6 Solver Cap A/B Summary

Date: 2026-05-31

Purpose: verify the trace-derived Newton cap candidate before using it for
Stephanov `n=6` WV-HMC epsilon and movement scans.

## Inputs

```text
model = Stephanov n=6, nf=1, m=0.004, mu=0.6, tau=0
safe bank = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260531/stephanov_n6_wv_hmc_t0_bank_16x5000_t0001_20260531_18328.anode01/safe_bank_t0p0001/x_bank.dat
T0 = 1e-4
T1 = 1e-3
d0 = 1e-4
d1 = 2.5e-4
initial_flow_time = 5.5e-4
W(t) = paper_wall
gamma = 0.2
epsilon = 0.001
nstep = 5
constraint_tol = 1e-10
adaptive_newton_stop_enabled = 0
```

## Trace Basis

The fixed-tolerance trace was intentionally truncated after enough solves:

```text
job = 18329.anode01
solves = 73137
converged = 68673
boundary_exit = 4462
residual_error = 1
unknown = 1
max_iter failures = 0
converged_iter_q90 = 4
converged_iter_q99 = 6
converged_iter_max = 17
converged_iter_gt_24 = 0
```

Boundary exits are resolved reflections, not Newton failures.

## A/B Check

```text
max_iter=96 job = 18330.anode01
max_iter=24 job = 18331.anode01
cycles requested = 300
paired completed seeds before intentional truncation = 10
paired seeds = 8820000, 8820001, 8820003, 8820004, 8820005, 8820010, 8820011, 8820012, 8820013, 8820015
```

For the paired completed seeds, the following summary fields were identical
between `max_iter=96` and `max_iter=24`:

```text
cycles_completed
accepted
rejected
proposal_failure
reverse_gate_reject
boundary_bounce
solver_stop_converged_count
solver_stop_max_iter_count
solver_stop_boundary_exit_count
solver_stop_residual_error_count
last_solver_stop_reason
phase_coherence
chiral_condensate_re
chiral_condensate_im
number_density_re
number_density_im
```

## Decision

Use `WV_HMC_CONSTRAINT_MAX_ITER=24` for the next n=6 epsilon and movement
scans.  Keep `WV_HMC_ADAPTIVE_NEWTON_STOP_ENABLED=0` until a separate
predicate-based fail-fast gate is justified by residual traces.

Do not use the trace or A/B walltime as production timing.  Both were
intentionally truncated to avoid long-tail diagnostic cost after the solver
cap decision was already determined.
