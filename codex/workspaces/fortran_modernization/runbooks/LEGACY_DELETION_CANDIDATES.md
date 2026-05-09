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

Candidate group:

- Radau rescue.
- fixed/chunked Radau rescue.
- JFNK support paths.
- ODE final-resort acceptance.

Current decision:

- Tentative long-term target is ODEX-only flow backend.
- Rescue stack is legacy robustness/deletion candidate.

Deletion gate:

- Stage3_4/TLTM judgment complete.
- Characterization baseline records current rescue counters.
- ODEX-only comparison run shows acceptable behavior or user approves algorithm-version change.

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
- Post-refine is a deletion candidate and should not be part of the final canonical p28 route unless explicitly re-promoted later.
- M2c implementation may remove or disable post-refine after comparison harness coverage.

## Historical flow backend decision - 2026-05-08
- Historical note: pure ODEX-only was considered the canonical long-term flow backend target before the 2026-05-09 solver-assist validation revised the decision.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and ODE final-resort acceptance are deletion candidates.
- M2c implementation may remove or disable the rescue stack after flow-level characterization and ODEX-only comparison coverage.
- If ODEX-only failure rate is unacceptable, improve ODEX/step control/failure handling rather than preserving a hidden secondary integrator stack by default.

## Revised flow backend decision - 2026-05-09
- Pure ODEX-only is not the final deletion basis.
- Current candidate keeps solver-internal ODE assist for NT/QN residual evaluation while requiring strict final proposal flow.
- Delete only final-proposal rescue acceptance and unused legacy stacks after explicit state/status contracts prove assist cannot finalize proposals.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- That validation gate has since passed for the QN-clean canonical route; DFO-GN paper, Broyden/line-search, and global continuation/restart source paths were deleted on 2026-05-09.
