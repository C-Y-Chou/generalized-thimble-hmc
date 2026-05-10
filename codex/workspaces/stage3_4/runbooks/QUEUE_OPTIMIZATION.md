# Stage3_4 Queue Optimization Playbook

SUPERSEDED: This file is historical and must not be used for current cluster02 queue decisions.

Current queue decisions must use the shared cluster02 scheduling agent and persistent scheduler knowledge:

- `codex/agents/cluster02_scheduler/README.md`
- `codex/workspaces/fortran_modernization/runbooks/CLUSTER02_SCHEDULING_AGENT.md`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`

Reason: this playbook predates the 2026-05-10 manual-backed scheduler update and conflicts with current policy for GPU queues, `C17/C17-LONG`, and job repair.

Last updated: 2026-04-30 22:12 JST

## Objective
Minimize wall-clock completion for Stage3_4 1024-seed campaigns while preserving:
- unified flow policy (`nofb/withfb -> RG -> Metropolis`)
- no duplicate chunk runs
- deterministic merge dependency chains

## Queue constraints observed
- `C24/C36`: not suitable for 1-node chunk jobs due `resources_min.nodect` constraints.
- `C12`: can appear idle but still reject 32-core jobs with `Qlist` shortage.
- `C12-LONG`: often saturated; per-user cap applies.
- `C17`: best throughput for 32-core chunk jobs in current cluster state.
- `C17-LONG`: good overflow queue; per-user `max_run_res.nodect=[u:PBS_GENERIC=4]`.

## Current optimized strategy
1. Keep in-flight nofb jobs on existing queues (avoid churn on running subjobs).
2. Pre-stage next p28 rerun as held arrays on `C17` + `C17-LONG` with dependency on current nofb arrays.
3. Use split:
   - `C17`: 24 chunks (`chunk_00..23`)
   - `C17-LONG`: 8 chunks (`chunk_24..31`)
4. Keep merge jobs explicit and separate per campaign.

## Decision algorithm for future passes
1. Snapshot:
   - `qstat -u cychou`
   - `qstat -Qf C12 C12-LONG C17 C17-LONG C16 C8`
2. Probe queued reason:
   - pick one queued subjob per active array, check `qstat -f <subjob> | grep comment`.
3. Move only queued (not running) subjobs if needed.
4. Refresh merge dependency whenever array IDs change.

## Escalation rule
If queued subjobs in target queue remain stalled >90 minutes with unchanged `Qlist` reason:
- move queued tail from lower-throughput queue to `C17`/`C17-LONG` where feasible,
- preserve chunk mapping and idempotent skip logic.
