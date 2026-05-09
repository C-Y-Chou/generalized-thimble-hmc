# Legacy Deletion Candidates

Updated: 2026-05-09
Scope: registry of legacy code paths, including candidates and implemented source deletions.

## Rule

Entries marked as implemented have already passed the relevant user decision and validation gate. Remaining candidates must not be mistaken as canonical architecture.

## Confirmed Legacy / Deletion Candidates

### Non-p28 quasi routes

Implemented source deletion:

- DFO-GN paper route.
- Broyden/line-search route.
- Global continuation/restart fallback routes outside current p28 production settings.
- Post-refine Newton-loss residual route.

Current decision:

- p28 DFO-LS BTN/backflow rescue residual route is the only production-canonical quasi route.
- Non-p28 routes are legacy/deletion candidates; the known DFO-GN/Broyden/global-continuation implementations have been removed from active source.

Deletion gate satisfied:

- Stage3_4/TLTM judgment and QN-clean ODEX/solver-assist validation accepted the canonical p28 `fb_norefine` route.
- Dependency search confirmed active production wrappers call only `solve_constraint_quasi_newton(evaluate_constraint_residual, ...)`.
- Source cleanup removed the legacy solver-family implementations and the `QN_QUASI_GLOBAL_FALLBACK_ENABLED` runtime control.

### Post-refine

Candidate group:

- `evaluate_constraint_residual_newton_loss` route and post-refine machinery.

Current decision:

- Removed from active source after `fb_norefine` was promoted as canonical.

Deletion gate satisfied:

- Stage3_4 refine-vs-norefine evidence reviewed.
- User selected deletion.
- Active code no longer exposes the post-refine solver attempt, counters, output columns, or Newton-loss residual function.

### Flow rescue stack

Implemented source deletion:

- Radau rescue.
- fixed/chunked Radau rescue.
- JFNK support paths.

Current decision:

- Canonical flow policy is ODEX primary integration plus solver-internal residual assist plus strict final proposal flow.
- Radau/JFNK secondary-integrator rescue code has been removed from active source.
- Final physical proposal acceptance through non-strict rescue remains forbidden by strict final-flow gates.
- Solver-internal assist is retained and still reported through legacy `final_resort` compatibility counter/API names until output schema versioning.

Deletion gate satisfied:

- Stage3_4/TLTM judgment complete.
- ODEX-only comparison showed physical-observable compatibility but avoidable robustness loss.
- Solver-assist 10k -> 50k -> 100k validation supported retaining assist only inside NT/QN residual evaluation.
- State/status propagation gates now require strict final `flow(...)` for proposal/live-state construction.
- Active source cleanup removed the Radau/JFNK implementation from `src/physics/solve_flow.f90`.

### Stage-specific workflow scripts

Candidate group:

- Stage2/Stage3/Stage3_4 experiment-specific wrappers and PBS conventions.

Current decision:

- Transitional scaffolding.
- Long-term target is unified TLTM wrapper/runner.

Deletion/deprecation gate:

- Unified wrapper exists.
- Output schema versioning exists.
- Compatibility layer covers current workflows or user approves deprecation.

## Future Registry Additions

- Dead helpers after source inventory.
- Unused config keys after config audit.
- Deprecated output/report fields after wrapper schema design.
- Duplicate scripts after wrapper migration.

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine has been removed from active source and should not be part of the final canonical p28 route unless explicitly re-promoted later.

## Historical flow backend decision - 2026-05-08
- Historical note: pure ODEX-only was considered the canonical long-term flow backend target before the 2026-05-09 solver-assist validation revised the decision.
- Radau rescue, fixed/chunked Radau rescue, and JFNK support paths have been removed from active source.
- Solver-internal residual assist is retained explicitly because pure ODEX-only showed avoidable solver robustness loss.
- Future flow cleanup should rename compatibility `final_resort` labels only with output-schema versioning.

## Revised flow backend decision - 2026-05-09
- Pure ODEX-only is not the final deletion basis.
- Current candidate keeps solver-internal ODE assist for NT/QN residual evaluation while requiring strict final proposal flow.
- Radau/JFNK legacy stacks have been deleted after explicit state/status contracts proved assist cannot finalize proposals.
- Remaining cleanup should rename legacy `final_resort` compatibility names only when output schema versioning is ready.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- That validation gate has since passed for the QN-clean canonical route; DFO-GN paper, Broyden/line-search, and global continuation/restart source paths were deleted on 2026-05-09.
