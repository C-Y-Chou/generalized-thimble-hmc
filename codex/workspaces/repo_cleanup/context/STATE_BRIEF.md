# Repo Cleanup State Brief

Updated: 2026-05-10 JST

## Current Position

- Repo cleanup is planned and now belongs to the shared control-plane cleanup workflow.
- It includes local `New project` scattered files, stale docs, old PBS scripts, generated logs, and remote root hygiene.

## Hard Rules

- Do not delete local scattered files blindly.
- Unique files must be archived with an index before removal.
- Do not clean remote roots or outputs without refreshed remote/job/worktree state.
- Do not delete production evidence until summarized or registered.

## Key Files

- `runbooks/STATUS.md`
- `state/local_new_project_inventory.md`
- `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- `codex/state/DATASETS.tsv`
- `codex/state/REMOTE_TARGETS.tsv`

## Next Action

Use the new L0/L1/remote registry workflow before any physical file deletion or archive move.
