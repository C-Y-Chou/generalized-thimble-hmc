# Cluster02 Scheduler Agent

Status: active shared operational agent.

Current implementation lives in the Fortran modernization workspace because it was created during M6 reference dataset generation:

- `codex/workspaces/fortran_modernization/runbooks/CLUSTER02_SCHEDULING_AGENT.md`
- `codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`

Workflow rule:

- Any cluster02 PBS scheduling, work splitting, queue choice, or failed-job repair must consult this agent first.
- The agent reads persistent queue knowledge before live `qstat -Qf`.
- Remote worktree safety still comes from the shared control-plane registries in `codex/state/`.

Migration note:

- The next cleanup pass may move the implementation into this shared `codex/agents/cluster02_scheduler/` directory.
- Until then, this directory is the shared pointer that prevents the agent from being treated as modernization-only.
