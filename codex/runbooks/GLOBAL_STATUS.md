# TLTM Codex Global Status

Updated: 2026-05-01 10:22 JST

## Workspace mode
- `codex` is the shared control plane; execution state is tracked per workspace.
- New conversations must read L0 context and then enter exactly one task workspace.

## Active operations tasks
- `stage3_4`: `reverse_gate_p28_unifiedrg_redo` 1024-seed queue and merge tracking.
- `stage3_3_rg_redo`: 50-seed, 200k, RG-enabled redo (`nofb/withfb` both pass RG).
- `ngport_rg_single_replica_t03_nstep_grid`: protocol prep for single-replica matched-control grid (`tau=0.3`, `L=2`, `nstep` scan).

## Governance task
- `fortran_modernization`: behavior-preserving modernization planning.

## Required live status source
- Always refresh and read `/home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md` via:
  - `bash /home/cychou/TLTM/codex/tasks/refresh_live_board.sh`

## Shared rules
- Use PBS-only execution for heavy runs.
- Do not treat top-level `state/` as a single live run source.
- Record manifests, job trackers, and session logs in the matching workspace.
