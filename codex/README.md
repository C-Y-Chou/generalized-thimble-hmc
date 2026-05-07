# TLTM Codex Workspace

This folder is a shared Codex control plane for TLTM work.

## Goal
- Provide one stable entrypoint for new conversations.
- Support multiple parallel tasks without overwriting each other's live state.
- Keep queue status and task state continuously refreshable from one command.

## Workspace model
- Shared layer: `context/`, `knowledge/`, `runbooks/`, `tasks/`, `state/registry/`
- Task layer: `workspaces/<task_slug>/...`
- Live production or investigation work must happen inside a named task workspace.

## First command in any new chat
```bash
cd /home/cychou/TLTM/codex
bash tasks/bootstrap.sh
bash tasks/refresh_live_board.sh
```

## Always-read live status
- `/home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md`

## Always-read source audit context
- `/home/cychou/TLTM/codex/runbooks/SOURCE_AUDIT_BOOTSTRAP.md`
- `/home/cychou/TLTM/codex/knowledge/CODEBASE_SCAN_MANIFEST.md`
- `/home/cychou/TLTM/codex/knowledge/FULL_PROGRAM_MAP_CHECK.md`

## Task entry
1. Read `/home/cychou/TLTM/codex/context/HANDOFF_MIN.txt`
2. Pick the target task from `/home/cychou/TLTM/codex/runbooks/task_registry.tsv`
3. Enter that workspace and read its `context/TASK.md`, `runbooks/STATUS.md`, and `state/` files

## Policy
- Read `/home/cychou/TLTM/docs/AGENT_GUIDE.md` first.
- Run heavy jobs only via PBS on compute nodes.
- Commit and push production-relevant changes before validation or production submission.
- Do not treat top-level `state/` as a single live run state.
- Record task-specific execution in `workspaces/<task_slug>/state/`.
