# Task: fortran_modernization

- Task type: governance
- Status: active
- Owner: unassigned
- Root: /Users/ccy/Documents/TLTM_qn_error_handling/codex/workspaces/fortran_modernization
- Goal: maintain the official-DFO-LS modernization and production-redo code line while preserving TLTM physics and output contracts.
- Write scope: this workspace planning documents, trackers, and modernization governance notes.

## Read Before Next Solver-Policy Step

- Solver assist is scheduled for deletion, not promotion.  The canonical handoff
  is official DFO-LS `npt5_r0055`, true Stage2 RNG v2, and method-level assist
  off.
- Before changing solver assist, deleting assist code, changing defaults, or
  continuing source work that touches `flowz` / `flowzr`, QN residual
  evaluation, final `flow(...)`, reverse gate, or Metropolis, read:
  - `runbooks/ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md`
- `runbooks/NAVIGATION_ASSIST_STRICT_CERTIFICATION_POLICY_20260513.md` is
  historical diagnostic context only after the 2026-05-15 assist-deletion
  decision.

## Cluster/PBS Scheduling Responsibility

- Any fortran_modernization work involving iTHEMS cluster02 queues, PBS submission, reference dataset generation, or failed-job repair must route through the cluster02 scheduling agent.
- Read `runbooks/CLUSTER02_SCHEDULING_AGENT.md` before choosing queues or splitting work.
- Consult persistent scheduler memory before live queue decisions:
  - `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
  - `state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`
- Use live `qstat -Qf` only after loading the persistent policy, so scheduling decisions build on prior observations instead of restarting from scratch.
