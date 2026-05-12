# Full Hairer ODEX Endpoint Reopen Plan

Date: 2026-05-12 JST
Scope: `fortran_modernization`
Status: accepted reduced-scope for pre-redo; solver assist default-off and scheduled for later deletion

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
- 2026-05-12 user decision: solver assist is not part of the pre-redo canonical line. `INTODE_SOLVER_ASSIST_ENABLED` now defaults off; `=1` is an explicit diagnostic/historical comparison override only.
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
   - Status: pre-redo scope explicitly reduced by user decision. The 10seed and 16seed x 10k readbacks are retained as diagnostics; a larger observable gate is no longer required before the pre-redo because assist is default-off and scheduled for deletion.

## Production Rule

Pre-redo production may proceed with solver assist default-off once the exact F14 production redo scope/scale, target commit/worktree, and promotion boundary are recorded. F3/F4/F7/F8 are now complete for the pre-redo gate without reduced-scope acceptance.
