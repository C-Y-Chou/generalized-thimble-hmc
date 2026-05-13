# Task: fortran_modernization

- Task type: governance
- Status: active
- Owner: unassigned
- Root: /Users/ccy/Documents/TLTM_qn_error_handling/codex/workspaces/fortran_modernization
- Goal: maintain the official-DFO-LS modernization and production-redo code line while preserving TLTM physics and output contracts.
- Write scope: this workspace planning documents, trackers, and modernization governance notes.

## Read Before Next Solver-Policy Step

- The previous solver-assist default-off / later-deletion direction is superseded for the next solver-policy slice.
- Before changing solver assist, deleting assist code, changing defaults, or continuing source work that touches `flowz` / `flowzr`, QN residual evaluation, final `flow(...)`, reverse gate, or Metropolis, read:
  - `runbooks/NAVIGATION_ASSIST_STRICT_CERTIFICATION_POLICY_20260513.md`
- Current handoff policy: `nofb` remains author-faithful comparison/control; canonical fallback-on candidate is `strict NT -> QN navigation assist -> unassisted certification -> strict final flow -> RG -> Metropolis`.
- NT assist is not canonical in this handoff; NT+QN assist is diagnostic-only unless the user explicitly approves a new policy.

## Cluster/PBS Scheduling Responsibility

- Any fortran_modernization work involving iTHEMS cluster02 queues, PBS submission, reference dataset generation, or failed-job repair must route through the cluster02 scheduling agent.
- Read `runbooks/CLUSTER02_SCHEDULING_AGENT.md` before choosing queues or splitting work.
- Consult persistent scheduler memory before live queue decisions:
  - `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
  - `state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`
- Use live `qstat -Qf` only after loading the persistent policy, so scheduling decisions build on prior observations instead of restarting from scratch.
