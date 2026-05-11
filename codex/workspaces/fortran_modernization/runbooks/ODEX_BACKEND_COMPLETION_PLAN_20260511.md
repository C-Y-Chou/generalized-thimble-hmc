# ODEX Backend Completion Plan

Updated: 2026-05-11 JST

Scope: define the work needed to turn the current ODEX-like endpoint integrator inside `src/physics/solve_flow.f90` into a publication-grade TLTM ODEX backend contract. This document is not a physics change and does not claim that source extraction is complete.

## Current State

The current source has:

- an explicit midpoint / extrapolation kernel in `odex_step`;
- Hairer ODEX `IWORK(3)=3` step sequence through `build_nsteps`;
- signed-step integration with positive work estimates;
- internal `odex_options`, `odex_workspace`, and `odex_result` contracts;
- ODEX mechanism-to-`intode` status mapping for strict success, zero-time no-op, and mechanism failures;
- strict final `flow(...)` policy for proposal/live-state construction;
- solver-internal residual assist that is gated to Newton/QN residual contexts;
- compatibility counters and status labels inherited from earlier rescue-policy history.

The current source now has a first internal ODEX contract layer, but does not
yet have a clean standalone ODEX backend boundary. `solve_flow.f90` still mixes:

- ODEX mechanism;
- TLTM `flowz`, `flowzr`, and `flow` wrappers;
- solver-assist/final-flow policy;
- diagnostics, counters, last-failure capture, and trace state;
- module-global workspaces.

## Required Backend Contract

The completed ODEX backend must expose, either as a dedicated module or a sharply separated internal API:

1. `odex_options`
   - absolute and relative tolerance;
   - `k_min`, `k_max`, step-number sequence selector;
   - `h_min` policy constants;
   - stability-control mode;
   - endpoint-only vs dense-output mode;
   - max-step limit.

2. `odex_workspace`
   - extrapolation tableau;
   - midpoint row work arrays;
   - current/next state arrays;
   - no hidden per-run mutable state required for correctness.

3. `odex_result`
   - status code;
   - final endpoint state;
   - accepted/rejected step counts;
   - final order and last step size when exposed;
   - failure reason;
   - no TLTM solver-assist decision hidden inside the ODEX result.

4. `odex_integrate_endpoint`
   - integrates `y'=f(t,y)` or the current autonomous `f(y)` wrapper to one endpoint;
   - returns only ODEX mechanism status;
   - does not know whether it is called from Newton, QN, final proposal flow, reverse replay, or a debug probe.

## Stability And Dense-Output Decision

Dense output:

- TLTM currently needs endpoint values for `flowz`, `flowzr`, and `flow`.
- Therefore dense output is not required for the first completed backend.
- The backend must document this as `endpoint_only` rather than silently implying a full Hairer ODEX package clone.

Stability control:

- A full Hairer ODEX-style stability control surface is not currently implemented as a separate contract.
- This cannot remain a hidden caveat. The accepted production scope is now the
  reduced-scope endpoint backend policy below.

Accepted decision, 2026-05-11 JST: do not implement conservative stability
control before production redo. TLTM should be described as using an endpoint
extrapolation backend with `stability_control = none` by default, not as a full
Hairer ODEX package clone.

## Mechanism vs Policy Split

ODEX mechanism:

- step sequence;
- midpoint/extrapolation table;
- error estimate;
- step/order proposal;
- max-step, invalid-RHS, and h-min failure statuses.

TLTM policy:

- when solver-internal residual assist may complete a residual evaluation;
- strict final proposal/live-state flow success criteria;
- reverse replay accounting;
- diagnostics/counter schema;
- whether failed integration means proposal rejection or diagnostic capture.

The source split must preserve current behavior by first moving policy decisions out of the backend result path without changing their order.

## Deterministic Evidence Added In This Slice

Added target:

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_foundation_contract
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_result_contract
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_flow_jacobian_contract
```

The new test covers:

- Hairer `IWORK(3)=3` sequence: `2,4,6,8,12,16,24,32,48,64,96`;
- strict-success predicate: only strict success and zero-time no-op are strict;
- zero-time endpoint contract;
- forward/backward endpoint composition on an analytic exponential ODE;
- invalid-RHS / h-min failure in unknown context cannot be converted into solver-assist success;
- solver-assist policy visibility.

The result/workspace/status contract test covers:

- `odex_default_options`, including `endpoint_only = .true.` and `stability_control = none`;
- `odex_workspace` tableau/vector allocation and no-shrink reuse;
- `odex_result` reset, success, zero-time, and failure mapping;
- `odex_status_from_failure_reason` for max-steps, invalid-RHS, and h-min failures;
- separation between ODEX mechanism statuses and TLTM policy statuses such as solver assist.

The flow/Jacobian contract test covers:

- zero-flow endpoint/Jacobian identity;
- `flow(...)` endpoint consistency with `flowz(...)`;
- `flowzr(...)` inverse replay on a deterministic endpoint;
- `flow(...)` Jacobian consistency with finite differences of `flowz(...)`;
- no fallback/assist use in the deterministic contract case.

Existing target retained:

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_solver
```

## Assist Policy Historical Readback

Added readback script:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/odex_assist_revalidation.py
```

This script recomputes the ODEX-only vs solver-assist historical readback from
the recorded 50k/100k QN-clean validation artifacts and writes:

- `state/ODEX_ASSIST_REVALIDATION_SUMMARY.tsv`
- `runbooks/ODEX_ASSIST_HISTORICAL_READBACK_20260511.md`

Correction: this is not a fresh current-code ODEX policy test and must not be
treated as a current revalidation conclusion. It shows that historical pure
ODEX-only was a comparison artifact with a robustness loss, and that the
historical solver-assist run recovered robustness. A real current-code ODEX
assist-on/off or equivalent policy test remains required before closing the
policy question. M6 reference datasets are not official DFO-LS evidence; they
can only serve as historical/internal behavior anchors for observing assist-off
degeneracy.

## Current Assist Policy Gate

Added target:

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_assist_policy
```

The target runs the current source twice:

- default policy, with solver-internal assist enabled;
- `INTODE_SOLVER_ASSIST_ENABLED=0`, with solver-internal assist disabled.

This proves the current `intode` policy gate is explicit and testable without
changing default behavior. It does not prove production-scale ODEX behavior;
that still required a representative current-code assist-on/off Stage/TLTM
validation before the policy question could be read back.

## Representative Assist On/Off Readback

Added PBS gate and readback script:

```bash
qsub -v TLTM_EXPECTED_GIT_COMMIT=<commit>,TLTM_EXPECTED_GIT_BRANCH=codex/fortran-modernization \
  codex/workspaces/fortran_modernization/tasks/pbs/odex_official_dfols_assist_onoff_10seed_10k_20260511.pbs
python3 codex/workspaces/fortran_modernization/tasks/scripts/odex_official_assist_onoff_readback.py
```

This ran current-code `fb_norefine` with embedded official DFO-LS at
`10 seeds x 10000 cycles`, changing only:

- `INTODE_SOLVER_ASSIST_ENABLED=1`
- `INTODE_SOLVER_ASSIST_ENABLED=0`

Readback:

- assist-on solver counters: Newton `682682`, QN `1858`;
- assist-off solver counters: Newton `0`, QN `0`;
- unresolved failures increased `1179 -> 1542`;
- h-min failures changed from Newton/QN `0/0` to `14515/118`.

Conclusion: current-code solver-internal assist is a real robustness mechanism
at this representative scale. Disabling it creates a robustness degradation.
This resolves the representative assist-on/off policy readback slice, but it
does not complete the ODEX backend source contract.

## Source Slice Completed

Completed source changes:

1. Introduced internal `odex_options`, `odex_workspace`, and `odex_result` types.
2. Kept `intode(...)` public behavior compatible.
3. Added backend result mapping inside `intode` without changing existing status values.
4. Added `test_odex_result_contract`.
5. Added `test_odex_flow_jacobian_contract`.
6. Included the new targets in M4 guardrails.

Verification:

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_result_contract test_odex_flow_jacobian_contract test_odex_foundation_contract test_odex_solver test_odex_assist_policy
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''
```

Both commands passed on 2026-05-11 JST.

## Accepted Reduced-Scope Production Policy

Production wording must use this scope unless a future behavior-changing
stability-control/dense-output implementation is explicitly approved:

- TLTM uses an endpoint extrapolation backend with Hairer `IWORK(3)=3` step sequence.
- Dense output is not part of the accepted backend scope.
- Conservative stability control is not enabled.
- Solver-internal assist remains a TLTM residual-evaluation policy, not part of the ODEX mechanism result.
- Final proposal/live-state flow remains strict.

`CV-007` is therefore closed only as accepted reduced scope. A future full
Hairer-package ODEX claim would reopen this row and require stability-control
and dense-output work.
