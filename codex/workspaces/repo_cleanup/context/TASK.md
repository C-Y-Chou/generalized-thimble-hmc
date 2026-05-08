# Repo Cleanup And Structure Task

Created: 2026-05-08 JST
Status: planned, blocked by active Stage3_4 test completion

## Purpose
- After the current Stage3_4 test round finishes, clean and restructure both the local and remote TLTM worktrees so future Codex sessions can navigate the project without relying on long chat context.
- Scope includes not only root-level clutter, but also `docs/`, logs, old PBS scripts, archived experiments, and generated reports.

## Current Blocker
- Do not change `/home/cychou/TLTM` until the active 128seed x 100k Stage3_4 test and its merge/report job finish.
- The remote worktree is intentionally pinned to commit `b6bb800` for the active merge job. Moving it, dirtying it, or adding untracked files may break the job gate.

## Cleanup Goals
- Make `/Users/ccy/Documents/New project` a thin navigation folder instead of an accidental second TLTM worktree.
- Keep the repository root minimal and predictable.
- Move old or one-off PBS scripts into task-specific `codex/workspaces/<task>/tasks/pbs/` or an archive area.
- Move outdated diagnostic scripts, reports, and logs into structured task workspaces.
- Separate source code, documentation, reproducible experiment configs, runtime output, and Codex control-plane notes.
- Ensure new conversations can start from `codex/README.md`, `codex/context/HANDOFF_MIN.txt`, and `codex/runbooks/task_registry.tsv`.

## Non-Goals
- Do not delete scientific results before they are indexed or archived.
- Do not rewrite source behavior as part of cleanup unless the user explicitly requests it.
- Do not invalidate queued/running PBS jobs or their expected commit gates.

## Completion Criteria
- Local `/Users/ccy/Documents/New project` root contains only navigation-level files and the canonical `TLTM_repo/` worktree, with scattered old TLTM copies moved to an archive.
- Remote `/home/cychou/TLTM` root contains only intentional tracked project files plus ignored runtime directories.
- `docs/` has an index and clear separation between papers, design notes, run protocols, and obsolete drafts.
- `output/` and log areas have a documented retention policy.
- `codex/runbooks/GLOBAL_STATUS.md` and task registry accurately describe the final structure.
