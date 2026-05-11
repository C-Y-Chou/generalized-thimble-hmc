# Fortran Modernization State Brief

Updated: 2026-05-11 JST

## Current Position

- Current position is `Completed foundation -> Accepted M6 reference baseline -> Remaining modernization blocks`.
- M6 is not "modernization complete"; it is the accepted reference-baseline/product-readiness gate before larger source refactors resume.
- The compact source of truth for this positioning is `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`.
- M3/M4/M5 modernization infrastructure work is treated as completed, partial, or explicitly deferred by workstream in that matrix.
- M6 R1-R4 reference packages are accepted after readback: expected per-method rows are present and protocol audit status is `pass` for R1-R4.
- The remote target is now semantically `fortran_modernization`, with branch `codex/fortran-modernization` and worktree `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- The old `qn_error_handling_validation` remote path/branch is historical and should not be the active target for new modernization work.
- Latest refresh shows no active pinned M6 jobs.
- Embedded official DFO-LS is now the default QN backend. `QN_SOLVER_BACKEND=internal` is only for controlled legacy comparison.
- The default local source of truth is `/Users/ccy/Documents/TLTM_qn_error_handling`, not `/Users/ccy/Documents/New project/TLTM_repo`.

## Hard Rules

- Do not fast-forward the active remote worktree while pinned PBS jobs are running.
- Even when no pinned jobs are recorded, refresh remote state before fast-forward, rename, or cleanup.
- For PBS queue selection or repair, use the cluster02 scheduler agent.
- Do not delete reference outputs/logs until registry/readback is complete.

## Key Files

- `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`: compact status matrix and current position.
- `runbooks/STATUS.md`: long history.
- `runbooks/CLUSTER02_SCHEDULING_AGENT.md`: scheduler agent.
- `runbooks/M6_REFERENCE_DATASET_READBACK_PLAN.md`: readback gate.
- `runbooks/M6_REFERENCE_DATASET_READBACK_20260510.md`: accepted M6 R1-R4 readback.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Use `runbooks/MODERNIZATION_FORWARD_WORKSTEPS_20260511.md` as the active forward queue. The immediate modernization step is implementation-truth caveat cleanup: DFO-LS wording must distinguish historical in-house/DFO-LS-style evidence from official package evidence, and ODEX wording must say ODEX-primary with solver-internal residual assist and strict final flow rather than pure/complete ODEX. Do not start behavior-relevant source refactors until the relevant caveat and baseline gates are satisfied.
