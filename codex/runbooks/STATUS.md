# TLTM Codex Status

Updated: 2026-05-01 10:22 JST

## Control-plane objective
- Keep multi-task queue and state management continuously synchronized in `codex`.

## Managed active tasks
- `stage3_4`: p28 unified-RG 1024-seed redo queue/merge.
- `stage3_3_rg_redo`: 50-seed 200k RG redo queue/merge.
- `ngport_rg_single_replica_t03_nstep_grid`: protocol-prepared, pending queue submission.

## Single live status source
- `/home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md`
- Refresh command: `bash /home/cychou/TLTM/codex/tasks/refresh_live_board.sh`

## Operating rule
1. After submit/cancel/requeue/merge, refresh live board immediately.
2. Keep workspace `run_manifest.env` and `session_log.md` aligned with queue state.
3. Use workspace-local `tasks/refresh_context.sh` for task-specific updates.
