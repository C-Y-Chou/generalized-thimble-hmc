# Cluster02 Scheduling Agent

Purpose: make cluster use a persistent optimization workflow rather than ad hoc queue guessing.

This is not just a submit helper. It is the operating memory for splitting TLTM work, choosing PBS queues, recording failures, and improving future submissions on iTHEMS cluster02.

## Shared-Cluster Model

Cluster02 is a shared resource used by many people. Queue availability, node pressure, and start latency are time-dependent and can change between sessions.

The scheduler agent must therefore treat its memory as priors, not as a fixed truth:

- The manual defines hard eligibility constraints.
- Historical observations define compatibility and failure priors for a job shape.
- Live `qstat -Qf` defines the current resource pressure.
- Short production-shape probes are used when the current best queue choice is uncertain, the batch is large, or recent observations may be stale.
- A queue that worked last time is not automatically optimal next time.
- A queue that was slow last time is not necessarily bad next time unless it has a compatibility failure.

## Persistent Memory

- Knowledge base: `codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
- Observation log: `codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`
- Queue policy: `codex/workspaces/fortran_modernization/runbooks/M6_DYNAMIC_QUEUE_POLICY_20260510.md`
- Agent utility: `codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py`
- M6 launcher using agent knowledge: `codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_dynamic.py`

## Agent Responsibilities

- Preserve manual-derived queue constraints so they are not rediscovered every session.
- Keep long-lived blacklists and policy exclusions separate from one-off job scripts.
- Split work into chunks that match the physical workflow and queue constraints.
- Use live `qstat -Qf` to score queue pressure at submission time.
- Treat live queue state as perishable. Do not reuse an old snapshot as current availability evidence.
- Use historical success observations as compatibility evidence, not as guaranteed immediate-start evidence.
- Record queue plans and snapshots so future choices can learn from this run.
- Treat failures as data: job id, queue, node, resource shape, exit status, action, and note.
- Repair by cancel/resubmit/rebuild-merge, not by moving existing jobs.

## Authority Boundary

The scheduler agent owns queue mechanics. A modernization/source agent owns
physics intent and readiness, but it must not become the scheduler.

Modernization/source agents may:

- define the science task, config, scale, methods, expected output root, and
  acceptance/readback checks;
- ensure the local and remote worktrees are on the intended branch/commit and
  are clean;
- run submitter `--dry-run` modes to verify the request shape;
- add or update a request row in
  `codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_REQUESTS.tsv`.

Modernization/source agents may also submit PBS jobs when explicitly acting
through the scheduler protocol.  This is allowed only if they:

- create or update a request row in `CLUSTER02_SCHEDULER_REQUESTS.tsv`;
- refresh live queue state with the scheduler agent before submission;
- export `TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler` and the
  matching `TLTM_SCHEDULER_REQUEST_ID`;
- call through `codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh` or a
  launcher that enforces the same authority/request-ledger contract;
- record submitted job ids, output roots, and follow-up observations in the
  scheduler state files.

Modernization/source agents must not:

- choose queues outside the scheduler policy and live snapshot;
- submit bare `qsub` jobs, cancel/requeue/repair jobs, or rebuild merge dependencies
  outside the scheduler protocol;
- bypass the scheduler by running a job-specific submitter directly;
- fast-forward an execution worktree while pinned jobs from that worktree are
  active.

Actual PBS submission requires both environment variables below. They are the
technical guard that marks the caller as the scheduling authority:

```bash
export TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler
export TLTM_SCHEDULER_REQUEST_ID=<request-id-from-request-ledger>
```

Without these variables, active submit launchers must allow dry-runs but refuse
real `qsub`.

The final real-submit boundary is intentionally a small POSIX shell gate:

```bash
codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh
```

Higher-level wrappers may be Python or another language for planning and
readback, but the last step that calls PBS should stay low-dependency and easy
to audit.  A compiled Go/Rust scheduler CLI can be reconsidered only if the
planning layer outgrows shell/Python; it should still call through the same
authority gate or preserve the same environment/request-ledger contract.

## Submission Protocol

1. Confirm the local branch and commit are the intended source.
2. Commit and push changes.
3. SSH to `cychou@ithems_fe02.intra.riken.jp`.
4. Fast-forward the target cluster worktree only if no pinned jobs from that worktree are running.
5. Verify branch, commit, clean status, and `qsub`.
6. Run the scheduler agent snapshot.
7. If the batch is large or queue pressure is ambiguous, run short production-shape probes before bulk optimization.
8. Verify there is a request row in `CLUSTER02_SCHEDULER_REQUESTS.tsv`, export
   the scheduler authority variables, then run the dynamic launcher or a
   job-specific launcher that consumes the same knowledge file.
9. Record the manifest, queue plan, and any follow-up observations.

## Current Long-Term Policy

- CPU-only TLTM chunks use `C8`, `C12`, `C16`, `C8-LONG`, `C12-LONG`, or `F` by default.
- GPU queues are excluded for CPU-only chunks unless explicitly approved.
- `C24` and `C36` are excluded for one-node jobs because their manual node ranges start above one node.
- `C17` and `C17-LONG` are conditional only: cnode37 passed current Stephanov N6 withfb DOP853/DFO-LS 8-core probes, but cnode38/cnode39 placements lack node-local `git` and fail the current PBS git guard with `Exit_status=127`. Do not use them automatically until placement is constrained or the guard is gitless.
- One-core probes do not validate an 8-core TLTM chunk shape; use production-shape probes when revalidating a queue or node placement.
- Probe-passed queues are preferred only as compatibility priors. Current queue pressure still comes from fresh `qstat -Qf` and, when useful, new probes.

## Utility Commands

Show current persistent policy:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py show-policy
```

Capture a live cluster queue snapshot from the cluster worktree:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py snapshot
```

Summarize jobs:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py check-jobs 14657 14658
```

Append a new scheduling observation:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py record-observation \
  --queue C8 \
  --resource-shape 'select=1:ncpus=8:mpiprocs=8:mem=16gb' \
  --outcome completed \
  --exit-status 0 \
  --node cnode21 \
  --job-id 14659 \
  --action keep_candidate \
  --note 'M6 R4 fb chunk ran with production shape'
```

## Design Boundary

The scheduler agent optimizes queue usage and repair mechanics. It does not decide physics policy, reference acceptance, or whether a dataset is scientifically valid. Those remain governed by the modernization reference dataset checklist and behavior-preservation protocol.
