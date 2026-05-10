# TLTM Production Comparison State Brief

Updated: 2026-05-10 JST

## Current Position

- `tltm_production_comparison` is the canonical workspace for TLTM `nofb` vs `withfb` production-comparison work.
- Legacy name: `stage3_4`. Treat old `stage3_4` paths, configs, and output roots as historical/provisional artifacts, not the long-term workspace identity.
- This workstream is separate from `fortran_modernization`.
- Current production-comparison status is provisional-discussion, not final publication data. It may be used for collaborator discussion, workflow rehearsal, queue scaling, and physical trend checks; final datasets should be regenerated after modernization converges.
- Existing long `runbooks/STATUS.md` contains historical production and validation details. Read `runbooks/SOFT_DECOUPLING_AND_PROVISIONAL_CONTRACT.md` for the current boundary.
- Cleanup of legacy production-comparison outputs/logs is allowed only after dataset/job/worktree registry refresh and summary/archive decisions.

## Important Correction

- `runbooks/QUEUE_OPTIMIZATION.md` is superseded for current queue decisions.
- Use the shared cluster02 scheduler policy instead of the old Stage3_4 queue playbook.

## Decoupled Worktree Model

- Production comparison remote target: `tltm_production_comparison_provisional`.
- Production comparison branch: `codex/tltm-production-comparison`.
- Production comparison remote worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Modernization remote target: `fortran_modernization`.
- Modernization branch: `codex/fortran-modernization`.
- Modernization remote worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.

## Next Action

Before cleanup or production continuation:

1. Run `bash codex/tasks/refresh_remote_state.sh`.
2. Register relevant production-comparison outputs in `codex/state/DATASETS.tsv`.
3. Confirm no active pinned jobs depend on the target worktree.
4. Archive or summarize evidence before deleting generated outputs/logs.
5. For any new provisional run, write outputs under a production-comparison namespace, preferably `output/production_comparison/provisional/...`, not a new `output/tests/stage3_4/...` namespace.
