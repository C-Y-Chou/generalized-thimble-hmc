# TLTM Codex Global Status

Updated: 2026-05-11 JST

## Workspace mode
- `codex` is the shared control plane; execution state is tracked per workspace.
- New conversations must read compact L0/L1 context and then enter exactly one task workspace.
- Long runbooks are triggered reads, not always-read files.

## Compact state sources

- L0 boot: `codex/context/L0_BOOT.md`
- L1 index: `codex/indexes/L1_INDEX.tsv`
- Open items: `codex/state/OPEN_ITEMS.tsv`
- Decisions: `codex/state/DECISIONS.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`

## Refresh commands

- Remote/PBS state: `bash codex/tasks/refresh_remote_state.sh`
- Local worktree state: `bash codex/tasks/refresh_local_state.sh`
- L0 render: `bash codex/tasks/render_l0_boot.sh`
- Validator: `bash codex/tasks/validate_control_plane.sh`

## Active or important workstreams

- Canonical local entry for new conversations is `/Users/ccy/Documents/TLTM_qn_error_handling` on `codex/fortran-modernization`.
- `fortran_modernization`: active official-DFO-LS modernization and production-redo execution target; use `context/STATE_BRIEF.md`.
- `tltm_production_comparison`: production-comparison workflow/docs; current redo execution defaults to the `fortran_modernization` remote target unless legacy comparison is explicitly requested.
- `remote_control_plane`: `/home/cychou/TLTM` is now an official-DFO-LS mirror branch, not the default local source of truth.
- Legacy Stage1 to Stage3_4 raw outputs/logs were cleared on 2026-05-10 after preserving key summaries; new provisional runs should use `output/production_comparison/provisional/...`.
- Obsolete ODEX validation raw data was cleared after confirming accepted M6 modernization reference datasets exist.
- Accepted M6 reference datasets may be reused as production-calibration aliases before launching new production-comparison seed/cycle grids.
- `repo_cleanup`: planned control-plane/local/remote cleanup; no deletion without registry/readback.
- `kernel_correctness_audit` and `ngport_rg_single_replica_t03_nstep_grid`: existing workspaces; read their task briefs/status only when entering those tasks.
- `stage3_3_rg_redo`: historical workspace only; raw output was cleared after summary preservation.
- Local `/Users/ccy/Documents/New project/TLTM_repo` is a legacy checkout; do not select it by default for new work.

## Shared rules
- Use PBS-only execution for heavy runs.
- For cluster02 queue decisions, use the cluster02 scheduling agent before live queue choice.
- Refresh remote state before SSH/PBS/git cleanup work.
- Refresh local state before local TLTM `git pull`, branch switch, cleanup, or overwrite.
- If the user asks to "continue this work" without naming legacy/control-plane, continue from the canonical official-DFO-LS line.
- Do not fast-forward or clean active pinned remote worktrees.
- Record manifests, job trackers, and session logs in the matching workspace.
- Do not delete generated outputs/logs until summarized, registered, or archived.
