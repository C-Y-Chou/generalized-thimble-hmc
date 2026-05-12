# Full Hairer ODEX Endpoint Reopen Plan

Date: 2026-05-12 JST
Scope: `fortran_modernization`
Status: active blocker for F14 production regeneration until larger assist-on/off observable gate readback

## Why This Is Reopened

`CV-007` was previously accepted as a reduced-scope ODEX endpoint backend:

- Hairer `IWORK(3)=3` step sequence.
- Endpoint extrapolation only.
- `stability_control=none`.
- No dense-output contract.
- Solver-internal assist treated as TLTM residual-evaluation policy.
- Deterministic result/workspace/status and flow/Jacobian guardrails.
- Representative official DFO-LS assist-on/off readback.

The new requested target is stronger: complete standalone/full Hairer ODEX endpoint package plus a direct test of whether disabling solver assist causes actual observable degeneracy. Therefore the reduced-scope acceptance is no longer sufficient.

Dense output is explicitly out of scope by user decision on 2026-05-12 JST. Do not block F1/F14 on dense-output API or tests.

## Current Implementation State

- `src/physics/odex_backend.f90` now owns the standalone endpoint backend boundary: explicit `odex_options`, `odex_workspace`, `odex_result`, status/failure mapping, Hairer `IWORK(3)=3` sequence, endpoint-only API, and conservative stability-control surface.
- `src/physics/solve_flow.f90` is now the TLTM wrapper layer. It injects TLTM tolerances and keeps final-flow, solver assist, diagnostics, counters, trace state, and failure-capture policy outside the package backend.
- `tests/test_odex_backend_package_contract.f90` directly links the backend package and checks sequence, endpoint accuracy, forward/backward consistency, conservative stability-control behavior, and invalid-option failure.
- Existing TLTM ODEX guardrails still cover wrapper result/status behavior and flow/Jacobian preservation.

## Current Known Gap

The 10seed x 10k assist-on/off readback shows assist-off increases unresolved failures, but it is not enough by itself to conclude an observable degeneracy.

## Required Implementation Slices

1. Standalone package boundary
   - Move the Hairer ODEX mechanism into a package-style module with explicit options, workspace, result, and status contracts.
   - Keep TLTM-specific wrappers outside the package.
   - Keep final-flow and solver-assist policy outside or explicitly injected as policy.
   - Status: done locally; guardrail `test_odex_backend_package_contract` passes.

2. Hairer package behavior
   - Preserve the selected Hairer `IWORK(3)=3` step sequence.
   - Implement and test stability-control behavior, or document a deliberate policy if it remains disabled.
   - Keep dense output excluded from the claim surface unless the user reopens it later.
   - Status: done locally for endpoint package; default remains `stability_control=none` to preserve behavior, with explicit conservative stability-control mode covered by package test.

3. Deterministic package tests
   - Endpoint accuracy on analytic scalar/vector systems.
   - Stability-control route/status behavior on a stiff or high-frequency probe.
   - Signed-step forward/backward consistency.
   - Workspace reuse and status/result contract stability.
   - TLTM wrapper equivalence against the pre-extraction flow guardrails.
   - Status: done locally for package and wrapper guardrails.

4. Assist-off observable gate
   - Re-read current 10seed x 10k official DFO-LS assist-on/off evidence as provisional diagnostics only.
   - Add a readback that separates solver health degeneration from actual observable degeneration.
   - If the 10seed evidence is too weak, run a larger official DFO-LS assist-on/off gate before F14.
   - Status: 10seed readback done; it proves solver-health degradation but not observable degeneracy. A 32seed x 50k official DFO-LS paired gate is prepared as the next evidence step.

## Production Rule

Do not start final production regeneration from modernization while this row is active unless the user explicitly re-scopes ODEX back to reduced scope.
