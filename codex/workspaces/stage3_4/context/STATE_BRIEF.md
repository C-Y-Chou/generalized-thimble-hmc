# Stage3_4 State Brief

Updated: 2026-05-10 JST

## Current Position

- Stage3_4 is a parallel production-comparison workstream, separate from Fortran modernization.
- Existing long `runbooks/STATUS.md` contains historical production and validation details.
- Cleanup of Stage3_4 outputs/logs is allowed only after dataset/job/worktree registry refresh and summary/archive decisions.

## Important Correction

- `runbooks/QUEUE_OPTIMIZATION.md` is superseded for current queue decisions.
- Use the shared cluster02 scheduler policy instead of the old Stage3_4 queue playbook.

## Next Action

Before cleanup or production continuation:

1. Run `bash codex/tasks/refresh_remote_state.sh`.
2. Register relevant Stage3_4 outputs in `codex/state/DATASETS.tsv`.
3. Confirm no active pinned jobs depend on the target worktree.
4. Archive or summarize evidence before deleting generated outputs/logs.
