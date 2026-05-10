# TLTM Codex Global Status

Updated: 2026-05-10 JST

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
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`

## Refresh commands

- Remote/PBS state: `bash codex/tasks/refresh_remote_state.sh`
- L0 render: `bash codex/tasks/render_l0_boot.sh`
- Validator: `bash codex/tasks/validate_control_plane.sh`

## Active or important workstreams

- `fortran_modernization`: active code-refine/modernization workstream with accepted M6 reference baselines; use `context/STATE_BRIEF.md`.
- `tltm_production_comparison`: parallel provisional `nofb` vs `withfb` production-comparison workstream; legacy alias `stage3_4`; old queue playbook is superseded.
- `repo_cleanup`: planned control-plane/local/remote cleanup; no deletion without registry/readback.
- `kernel_correctness_audit`, `stage3_3_rg_redo`, and `ngport_rg_single_replica_t03_nstep_grid`: existing workspaces; read their task briefs/status only when entering those tasks.

## Shared rules
- Use PBS-only execution for heavy runs.
- For cluster02 queue decisions, use the cluster02 scheduling agent before live queue choice.
- Refresh remote state before SSH/PBS/git cleanup work.
- Do not fast-forward or clean active pinned remote worktrees.
- Record manifests, job trackers, and session logs in the matching workspace.
- Do not delete generated outputs/logs until summarized, registered, or archived.
