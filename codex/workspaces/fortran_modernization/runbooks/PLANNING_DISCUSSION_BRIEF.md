# Planning Discussion Brief

Updated: 2026-05-09
Scope: historical Fortran modernization planning checkpoint, with superseding decisions noted where later source work changed the state.

## Current Understanding Of TLTM Code Structure

Runtime dependency shape:

- App/driver layer: `run_tltm_stage2.f90` -> `tltm_stage2_driver.f90`.
- Chain layer: Stage2 slots -> local updates -> `markovchain_metropolis.metropolis_step` -> `hmc.integrate_hmc_proposal`.
- Integrator layer: `hmc.rattle` -> `hmc_integrator_core.rattle_step_core`.
- Constraint layer: Newton first via `hmc_constraints`, then quasi fallback via `quasi_newton_solver` if enabled.
- Flow layer: `solve_flow` provides `flowz`, `flowzr`, and `flow`, backed by ODEX-like integration plus rescue policy.
- Physics/model layer: `model*.f90` supplies action, gradient, Hessian, and Hessian-vector operations.
- Diagnostics layer: `constraint_solver_stats`, `solve_flow` counters/traces, and Stage2 summary output tie into Stage3_4 auditing.

Important coupling:

- `rattle_step_core` is the central coupling point. It mixes force evaluation, Newton projection, quasi fallback, post-refine, reverse gate, flow/Jacobian update, momentum projection, and diagnostics.
- `solve_flow.f90` is not only an ODEX implementation. It is flow mapping plus ODEX-like integration plus solver-internal residual-assist policy and diagnostics.
- `quasi_newton_solver.f90` is not only a quasi-Newton solver. It contains the canonical p28 DFO-LS/BTN residual, route traces, watchdog-style accounting, compatibility counters, and solver-status surfaces.
- `tltm_stage2_driver.f90` is not only orchestration. It defines production output contracts and aggregates solver-route evidence used to judge Stage3_4 correctness.

## Main Risks Identified

- Algorithm definitions are embedded in low-level subroutine details, especially residual signs, `xi` layout, `Jl` meaning, flow direction, and `del_z` construction.
- Production fallback policies are interleaved with numerical mechanisms, making naive module extraction risky.
- Many module-level `save` workspaces and counters are convenient but not thread-safe or reentrant.
- RNG draw order is fragile: momentum, Metropolis draw, swap draw, and route-dependent retries can change results if code is reorganized carelessly.
- Stage2 summary fields and counters are part of the scientific audit surface, not mere logging.
- The current QN fallback route still carries a documented proposal symmetry/volume risk; modernization must preserve, expose, or help audit this risk rather than hiding it.

## Proposed Modernization Stage Order

Stage M0: Planning and algorithm audit, current stage.

- Finish reference-to-implementation maps.
- Freeze behavior-preservation rules.
- Define baseline matrix and discussion decisions.
- No Fortran source edits.

Stage M1: Baseline harness and output contracts.

- Create deterministic flow, Newton/RATTLE, QN, Metropolis, and Stage2 small-run baselines.
- Formalize summary schema and route-counter comparison.
- Add tests around residual definitions and mapping conventions.

Stage M2: Mechanism/policy classification.

- Mark each subroutine as mechanism, policy, diagnostics, workspace, or orchestration.
- Decide canonical vs research/legacy solver routes.
- Draft target module boundaries without changing source behavior.

Stage M3: Low-risk internal cleanup.

- Comments/equation docs near residuals and critical route decisions.
- Naming cleanup only where baselines prove no behavior change.
- Extract pure helper tests first; avoid route-order changes.

Stage M4: Structural refactor wave 1.

- Separate ODEX mechanism from flow rescue policy.
- Separate RATTLE mechanism from quasi/fallback diagnostics.
- Separate quasi residual definitions from solver route policy.
- Preserve existing public entry points while internal modules mature.

Stage M5: Structural refactor wave 2.

- Reduce module-global state with explicit workspaces/context objects.
- Improve reentrancy where scientifically and performance-wise safe.
- Version output schemas if needed after Stage3_4 is complete.

Stage M6: Publication/product readiness.

- Clean architecture documentation.
- Reproducible tests and benchmarks.
- Reference algorithm notes linked to code modules.
- Release-quality runbooks and result contracts.

## What Is Safe Now

- Planning docs, reference maps, code-read notes, and baseline designs.
- Read-only source audits.
- Adding non-production test plans or scripts that are not run by production jobs.
- Defining target architecture and naming conventions for later confirmation.

## What Must Wait For Stage3_4 Or Explicit Approval

- Any Fortran source edits that can affect current production paths.
- Solver thresholds, route ordering, fallback enablement, final-resort policy, reverse gate, or Metropolis acceptance changes.
- Changes to ODEX step sequence, order bounds, tolerance floors, rescue order, or flow sign convention.
- Changes to Stage2 summary output schema consumed by Stage3 scripts.
- Refactors that move RNG calls or alter when branches call flow/solver routines.

## Minimum First Implementation Deliverable After Confirmation

The smallest mature first implementation deliverable should not be a solver refactor. It should be a baseline/test artifact package:

- `BASELINE_VERIFICATION_MATRIX.md` finalized with selected configs.
- A deterministic baseline runner design for flow, Newton/RATTLE, QN, and Stage2 smoke.
- Residual microtest specifications for standard QN residual and post-refine Newton-loss residual.
- A summary schema contract for Stage2 outputs.

Historical note: source modernization has since begun after these planning gates were resolved or superseded.

## Decisions Needed From You

Decision recorded: canonical name is `BTN`; `BTM` is only a historical typo/alias and should not be used in new docs or code comments.

Decision recorded and implemented: p28 is the only production-canonical quasi route. Non-p28 quasi routes and post-refine have been removed from active source after staged validation and user approval.

Decision recorded: current stage-specific workflow is transitional. After TLTM construction/Stage3_4 judgment is complete, the modernization target is a unified TLTM wrapper/product interface rather than exposing Stage2/Stage3/Stage3_4 as separate user-facing workflows.

Decision recorded: official modernization baselines will be regenerated after Stage3_4/TLTM judgment completes. Existing `output/tests` artifacts are historical/reference evidence only, not official baselines.

1. Canonical naming: should the fallback formulation be called BTN, with BTM recorded only as a historical typo?
2. Canonical quasi route: resolved and implemented. p28 DFO-LS BTN/backflow rescue residual route is production-canonical; all other known quasi routes and post-refine have been removed from active source.
3. Output contract: short-term freeze current Stage3_4-facing outputs; long-term replace stage-specific contracts with a unified TLTM wrapper output schema.
4. Baseline source: resolved. Regenerate fresh official baselines after Stage3_4/TLTM judgment; existing `output/tests` are historical/reference evidence only.
5. Reverse gate status: resolved. Permanent algorithmic requirement for production/publishable p28 route.
6. Flow rescue/final-resort policy: revised and implemented. Current flow policy is ODEX primary plus solver-internal residual assist for NT/QN evaluation plus strict final proposal/live-state flow; Radau/JFNK source has been removed.
7. Thread-safety target: resolved. Long-term target is in-process parallel/OpenMP-capable execution via explicit context/workspace state.

## Current Planning Artifacts

- `runbooks/FORTRAN_MODERNIZATION_MASTER_PLAN.md`
- `runbooks/SUBROUTINE_API_REDESIGN_GUIDE.md`
- `runbooks/TEST_AND_BENCHMARK_ROADMAP.md`
- `runbooks/ALGORITHM_TO_IMPLEMENTATION_REVIEW_MAP.md`
- `runbooks/BEHAVIOR_PRESERVING_ALGORITHM_AUDIT_PLAN.md`
- `runbooks/ODEX_FLOW_REVIEW_NOTES.md`
- `runbooks/SIMPLIFIED_NEWTON_RATTLE_REVIEW_NOTES.md`
- `runbooks/QUASI_NEWTON_PROJECTION_REVIEW_NOTES.md`
- `runbooks/HMC_METROPOLIS_TLTM_REVIEW_NOTES.md`
- `runbooks/BASELINE_VERIFICATION_MATRIX.md`
- `runbooks/PLANNING_DISCUSSION_BRIEF.md`
- `references/REFERENCES_INDEX.md`
- `references/ODEX_LOCATION_GUIDE.md`

## Recommended Discussion Agenda

1. Confirm the architecture understanding and whether any physics-level relationship is missing.
2. Confirm the baseline matrix and comparison strictness.
3. Resolve the seven decisions above.
4. Decide whether the next task is baseline harness design or deeper paper-by-paper algorithm extraction.
5. Only then authorize the first implementation wave.

## Reverse Gate Decision - 2026-05-08
- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It is not merely a temporary debug guard or optional diagnostic mode.
- Modernization must preserve reverse-gate semantics, tolerance behavior, Jacobian comparison, replay accounting suppression, and live-slot identity on reject.
- Any future wrapper should expose this as part of the canonical p28 algorithm contract, not as an experimental add-on.

## Flow Backend Direction Decision - 2026-05-08
- Historical tentative target: ODEX-only flow backend.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and ODE final-resort acceptance are legacy robustness layers/deletion candidates.
- Do not remove or change them before Stage3_4/TLTM judgment completes.
- Later decision: pure ODEX-only is a comparison artifact; current policy is ODEX primary plus solver-internal residual assist and strict final proposal/live-state flow.
- Radau/JFNK rescue source has been deleted; solver-internal assist remains explicit and schema-compatible.

## Thread-Safety / Reentrancy Decision - 2026-05-08
- Long-term modernization target: support in-process parallelism/OpenMP-capable TLTM execution.
- Hidden module-level `save` workspaces, counters, RNG state, traces, and solver policies should be progressively moved behind explicit context/workspace objects.
- Short-term production behavior remains serial/process-level until Stage3_4/TLTM judgment and fresh baselines are complete.
- No source-level context refactor should start until affected baseline rows are covered.
- Final wrapper design should make per-run/per-replica state explicit enough for deterministic parallel execution.
