# Repo Cleanup Status

NOTE: Repo cleanup is now part of the shared control-plane memory/cleanup workflow. Read `context/STATE_BRIEF.md` and refresh `codex/state/REMOTE_LIVE_CACHE.json` before deleting, moving, or archiving files.

Updated: 2026-05-08 JST

## State
- Planned, not started.
- Waiting for current Stage3_4 `judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine` test to complete.

## Important Guardrails
- Do not modify `/home/cychou/TLTM` while held/running jobs expect commit `b6bb800`.
- Do not clean remote root before checking `qstat`, merge job status, and `git status --short`.
- Do not delete outputs/logs until they have been either summarized in `codex/` or moved to a named archive.

## Known Clutter To Address
- Local `/Users/ccy/Documents/New project` has TLTM files scattered outside `TLTM_repo/`; see `state/local_new_project_inventory.md`.
- Remote `/home/cychou/TLTM` root contains old root-level PBS scripts and ignored PBS stdout/stderr files.
- `docs/` needs indexing and separation into papers, design notes, protocols, and archived/obsolete notes.
- Runtime logs and reports need a documented retention/archive policy.

## First Pass Plan
1. Confirm all active PBS jobs are complete and no merge/report job is waiting on the current worktree.
2. Snapshot local and remote root trees before moving anything.
3. Classify files into `keep-root`, `move-to-codex-workspace`, `move-to-docs`, `archive`, and `delete-generated`.
4. Move files in small commits, verifying `git status` after each pass.
5. Update `codex/README.md`, `HANDOFF_MIN.txt`, and `GLOBAL_STATUS.md` with the final navigation map.
