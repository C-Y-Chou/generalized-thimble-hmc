# Fortran Modernization State Brief

Updated: 2026-05-10 JST

## Current Position

- Current position is `Completed foundation -> Active M6 reference baseline gate -> Remaining modernization blocks`.
- M6 is not "modernization complete"; it is the active reference-baseline/product-readiness gate before larger source refactors resume.
- The compact source of truth for this positioning is `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`.
- M3/M4/M5 modernization infrastructure work is treated as completed, partial, or explicitly deferred by workstream in that matrix.
- M6 R1-R4 reference generation is active on the cluster and must be read through remote/job registries before further repair or cleanup.
- The active remote target is semantically `fortran_modernization_m6_active`, but the physical path/branch still carry the legacy `qn_error_handling_validation` name until pinned jobs finish.

## Hard Rules

- Do not fast-forward the active remote worktree while pinned PBS jobs are running.
- For PBS queue selection or repair, use the cluster02 scheduler agent.
- Do not delete reference outputs/logs until registry/readback is complete.

## Key Files

- `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`: compact status matrix and current position.
- `runbooks/STATUS.md`: long history.
- `runbooks/CLUSTER02_SCHEDULING_AGENT.md`: scheduler agent.
- `runbooks/M6_REFERENCE_DATASET_READBACK_PLAN.md`: readback gate.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Refresh remote state, inspect M6 jobs/readback outputs, then update `codex/state/JOBS.tsv`, `codex/state/DATASETS.tsv`, and M6 registry rows. After accepted M6 baseline, resume the remaining modernization blocks according to the workstream matrix rather than treating M6 as completion.
