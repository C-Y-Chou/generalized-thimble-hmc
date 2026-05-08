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

- p28 DFO-LS standard residual route is the only production-canonical quasi route.
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
