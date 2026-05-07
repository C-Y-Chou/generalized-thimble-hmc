# Codex Workflow (TLTM)

## 0. Required pre-read
1. `/home/cychou/TLTM/docs/AGENT_GUIDE.md`
2. `/home/cychou/TLTM/docs/commands.md`
3. `/home/cychou/TLTM/docs/fallback_policy_s1.md`

## 1. Session start
```bash
cd /home/cychou/TLTM/codex
bash tasks/bootstrap.sh
bash tasks/refresh_live_board.sh
```

## 2. Pick a task workspace
- Read `/home/cychou/TLTM/codex/runbooks/task_registry.tsv`
- Read `/home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md`
- Enter `/home/cychou/TLTM/codex/workspaces/<task_slug>`
- Read `context/TASK.md`, `runbooks/STATUS.md`, and the files under `state/`

## 3. Fix the task contract
Write task-specific execution state into:
- `workspaces/<task_slug>/state/run_manifest.env`
- `workspaces/<task_slug>/state/session_log.md`
- `workspaces/<task_slug>/state/ownership.tsv`

## 4. Execute on compute nodes
- Use PBS templates or task-local scripts.
- Submit via `qsub`.
- Monitor via `qstat`.

## 5. Continuous state maintenance
- After every submit/cancel/requeue/merge action, run:
  - `bash /home/cychou/TLTM/codex/tasks/refresh_live_board.sh`
- If a task-specific status changed, append the change to that workspace `state/session_log.md`.

## 6. Reproducibility rule
- No ad-hoc hidden knobs.
- Every task env var must be recorded in that task's `run_manifest.env`.
