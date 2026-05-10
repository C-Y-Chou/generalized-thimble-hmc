# Task: fortran_modernization

- Task type: governance
- Status: active
- Owner: unassigned
- Root: /home/cychou/TLTM/codex/workspaces/fortran_modernization
- Goal: establish and maintain the master engineering plan for turning the TLTM Fortran codebase into a mature, publishable scientific software project without changing the underlying physics.
- Write scope: this workspace planning documents, trackers, and modernization governance notes.

## Cluster/PBS Scheduling Responsibility

- Any fortran_modernization work involving iTHEMS cluster02 queues, PBS submission, reference dataset generation, or failed-job repair must route through the cluster02 scheduling agent.
- Read `runbooks/CLUSTER02_SCHEDULING_AGENT.md` before choosing queues or splitting work.
- Consult persistent scheduler memory before live queue decisions:
  - `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
  - `state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`
- Use live `qstat -Qf` only after loading the persistent policy, so scheduling decisions build on prior observations instead of restarting from scratch.
