# ODEX Backend Completion Plan

Updated: 2026-05-11 JST

Scope: define the work needed to turn the current ODEX-like endpoint integrator inside `src/physics/solve_flow.f90` into a publication-grade TLTM ODEX backend contract. This document is not a physics change and does not claim that source extraction is complete.

## Current State

The current source has:

- an explicit midpoint / extrapolation kernel in `odex_step`;
- Hairer ODEX `IWORK(3)=3` step sequence through `build_nsteps`;
- signed-step integration with positive work estimates;
- strict final `flow(...)` policy for proposal/live-state construction;
- solver-internal residual assist that is gated to Newton/QN residual contexts;
- compatibility counters and status labels inherited from earlier rescue-policy history.

The current source does not yet have a clean standalone ODEX backend boundary. `solve_flow.f90` still mixes:

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
- This cannot remain a hidden caveat. The next source slice must either:
  - implement an explicit stability-control mode and tests; or
  - record an accepted reduced-scope decision that TLTM uses an endpoint extrapolation backend with validation evidence, not a full ODEX package.

The default forward path is to implement an explicit `stability_control = none | conservative` option and start with `none` as behavior-preserving default, then add tests before enabling any behavior-changing mode.

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
```

The new test covers:

- Hairer `IWORK(3)=3` sequence: `2,4,6,8,12,16,24,32,48,64,96`;
- strict-success predicate: only strict success and zero-time no-op are strict;
- zero-time endpoint contract;
- forward/backward endpoint composition on an analytic exponential ODE;
- invalid-RHS / h-min failure in unknown context cannot be converted into solver-assist success;
- solver-assist policy visibility.

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
- `runbooks/ODEX_ASSIST_REVALIDATION_CONCLUSION_20260511.md`

Correction: this is not a fresh current-code ODEX policy test and must not be
treated as a current revalidation conclusion. It shows that historical pure
ODEX-only was a comparison artifact with a robustness loss, and that the
historical solver-assist run recovered robustness. A real current-code ODEX
assist-on/off or equivalent policy test remains required before closing the
policy question. M6 reference datasets are not official DFO-LS evidence; they
can only serve as historical/internal behavior anchors for observing assist-off
degeneracy.

## Next Source Slice

The next ODEX source slice is allowed only after accepting this contract:

1. Introduce an internal `odex_status`/`odex_result` type or equivalent non-public structure.
2. Keep `intode(...)` public behavior compatible.
3. Add backend result mapping inside `intode` without changing existing status values.
4. Preserve current tests and M6 affected baseline comparisons.
5. Do not enable new stability-control behavior until a separate behavior-changing decision and reference comparison exist.
