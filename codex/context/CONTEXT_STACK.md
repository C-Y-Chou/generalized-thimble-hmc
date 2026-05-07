# Context Stack (Multi-Workspace)

## L0: Global boot
- `codex/context/CORE.md`
- `codex/runbooks/GLOBAL_STATUS.md`
- `codex/runbooks/task_registry.tsv`
- `codex/runbooks/LIVE_BOARD.md` (refresh first)

## L1: Task definition
- `codex/workspaces/<task_slug>/context/TASK.md`
- `codex/workspaces/<task_slug>/runbooks/STATUS.md`

## L2: Task live state
- `codex/workspaces/<task_slug>/state/run_manifest.env`
- `codex/workspaces/<task_slug>/state/job_tracker.tsv`
- `codex/workspaces/<task_slug>/context/LAST_REFRESH.txt`
- `codex/workspaces/<task_slug>/state/session_log.md`

## L3: Deep source docs
- `docs/AGENT_GUIDE.md`
- `docs/commands.md`
- `docs/fallback_policy_s1.md`

## Rule
- New conversation must reconstruct from L0 first, then enter one task workspace.
- Do not overwrite another task's state files.
- After queue-affecting actions, refresh live board immediately.
