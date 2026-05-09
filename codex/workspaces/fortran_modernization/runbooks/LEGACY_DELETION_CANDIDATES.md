# Legacy Deletion Candidates

Updated: 2026-05-08
Scope: planning-only registry of code paths that may be removed after Stage3_4/TLTM judgment, characterization baseline, and user confirmation.

## Rule

Nothing in this file is approved for deletion yet. This registry prevents legacy paths from being mistaken as canonical architecture.

## Confirmed Legacy / Deletion Candidates

### Non-p28 quasi routes

Candidate group:

- DFO-GN paper route.
- Broyden/line-search route.
- Global continuation/restart fallback routes outside current p28 production settings.
- Other non-p28 quasi variants.

Current decision:

- p28 DFO-LS BTN/backflow rescue residual route is the only production-canonical quasi route.
- Non-p28 routes are legacy/deletion candidates.

Deletion gate:

- Stage3_4/TLTM judgment complete.
- Characterization baseline records whether any production config touches these paths.
- Dependency search confirms no production wrapper/test requires them.

### Post-refine

Candidate group:

- `evaluate_constraint_residual_newton_loss` route and post-refine machinery.

Current decision:

- Under observation.
- May be removed depending on refine-vs-norefine evidence.

Deletion gate:

- Stage3_4 refine-vs-norefine evidence reviewed.
- User decides final production route.
- Baseline and comparison confirm removal behavior is intended.

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
- Until that validation gate passes, DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants remain legacy/quarantine candidates rather than approved deletions.
