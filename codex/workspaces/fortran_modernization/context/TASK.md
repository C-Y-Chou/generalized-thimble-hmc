# Task: fortran_modernization

- Task type: governance
- Status: active
- Owner: unassigned
- Root: /Users/ccy/Documents/TLTM_qn_error_handling/codex/workspaces/fortran_modernization
- Goal: maintain the official-DFO-LS modernization and production-redo code line while preserving TLTM physics and output contracts.
- Write scope: this workspace planning documents, trackers, and modernization governance notes.

## Cluster/PBS Scheduling Responsibility

- Any fortran_modernization work involving iTHEMS cluster02 queues, PBS submission, reference dataset generation, or failed-job repair must route through the cluster02 scheduling agent.
- Read `runbooks/CLUSTER02_SCHEDULING_AGENT.md` before choosing queues or splitting work.
- Consult persistent scheduler memory before live queue decisions:
  - `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
  - `state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`
- Use live `qstat -Qf` only after loading the persistent policy, so scheduling decisions build on prior observations instead of restarting from scratch.
