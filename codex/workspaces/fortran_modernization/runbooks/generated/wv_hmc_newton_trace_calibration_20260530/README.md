# WV-HMC Newton Trace Calibration

Date: 2026-05-30

Scope: Stephanov `n=2` dense WV-HMC pilot before matrix-free trajectory
wiring.  This file records an empirical Newton-stop calibration for the current
model, bank, `W(t)`, and HMC parameter range only.  It is not a universal
Newton policy.

## Code State

- Branch: `codex/nofb-runtime-optimization-20260528`
- Trace instrumentation commits:
  - `2fb8d11` instrumented WV Newton stop reasons and residual traces.
  - `bedb134` fixed the trace-context public declaration for ifx.
  - `809f2c5` added the trace analysis readback script.
  - `85726a6` fixed trace writes for negative `newunit=` values.
  - `cc11f24` exposed `WV_SCAN_CONSTRAINT_MAX_ITER` and
    `WV_SCAN_CONSTRAINT_TOL` in the scan/PBS harness.

## Cluster Runs

All runs used scheduler-gated cluster execution.  No local Fortran simulation
evidence is used here.

| Job | Run name | Purpose | Result |
|---|---|---|---|
| `17933.anode01` | `wv_hmc_newton_trace_bank_n2_dense_20260530_rerun2` | stress trace on `wall_epsilon_acceptance`, 120 cycles, bank init, `max_iter=16` | pass |
| `17934.anode01` | `wv_hmc_newton_trace_working_grid_n2_dense_20260530` | working-range trace on `wall_epsilon`, 200 cycles, bank init, `max_iter=16` | pass |
| `17935.anode01` | `wv_hmc_newton_maxiter10_working_grid_n2_dense_20260530` | repeat working range with `max_iter=10` | pass |

## Main Artifacts

- Stress trace:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_pilot_20260529/wv_hmc_newton_trace_bank_n2_dense_20260530_rerun2_17933.anode01/newton_trace_analysis/wv_newton_trace_analysis.md`
- Working-grid trace:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_pilot_20260529/wv_hmc_newton_trace_working_grid_n2_dense_20260530_17934.anode01/newton_trace_analysis/wv_newton_trace_analysis.md`
- Working-grid `max_iter=10` check:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_pilot_20260529/wv_hmc_newton_maxiter10_working_grid_n2_dense_20260530_17935.anode01/dense_pilot_scan_summary.csv`

## Observations

Working grid (`wall_epsilon`, bank init, 200 cycles):

- `4400/4400` first-constraint Newton solves converged.
- No `max_iter` stops occurred.
- Converged iteration maxima by candidate:
  - `eps=0.001,s1`: 4
  - `eps=0.002,s1`: 4
  - `eps=0.003,s1`: 5
  - `eps=0.005,s1`: 7
  - `eps=0.008,s1`: 9
  - `eps=0.002,s2`: 5
  - `eps=0.003,s2`: 5
  - `eps=0.005,s2`: 8

Stress grid (`wall_epsilon_acceptance`, bank init, 120 cycles):

- `5588/6084` traced solves converged.
- `387` hit `max_iter=16`.
- Converged solves can still require iteration `16` in the high-epsilon stress
  region.  Therefore lowering the cap globally would reject valid proposals.

`max_iter=10` working-grid validation:

- With the same seed, bank, and working grid as `17934`, `17935` produced
  identical values for cycles, accepted/rejected counts, reverse-gate rejects,
  transition failures, solver max-iteration counts, flow-time mean/max, phase
  coherence, and return codes.
- Runtime changed only slightly; this is a safety/cost cap, not a major
  acceleration by itself for the current small dense model.

## Calibration Decision

For the current Stephanov `n=2` dense working range only, it is safe to use:

```text
WV_SCAN_CONSTRAINT_MAX_ITER=10
WV_SCAN_CONSTRAINT_TOL=1.0e-8
WV_SCAN_ADAPTIVE_NEWTON_STOP_ENABLED=0
```

The source/app default remains `constraint_max_iter=16`.  Any new model,
larger `n`, action parameter change, bank change, `W(t)` retuning, `T0/T1`
change, `epsilon/nstep` change, or DOP853 controller/tolerance change must
rerun the residual trace calibration before changing this cap.

No residual-shape adaptive fail-fast rule is adopted yet.  The stress grid
shows that late convergence is real in harder parameter regions, so a
shape-based rule would need a separate false-reject audit against eventually
convergent solves before use.

## Pre-Matrix-Free Status

The dense WV-HMC path now has:

- first-constraint Newton stop reason counters;
- per-iteration residual trace output;
- scan/PBS controls for constraint tolerance and max iteration;
- a reproducible trace aggregation readback;
- one calibrated dense working-range cap.

Proceeding to matrix-free trajectory wiring should keep the same diagnostics
and must compare matrix-free residual/stop behavior against the dense oracle on
small cases before using the cap in high-dimensional runs.
