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
7. For large or long CPU-bound production, refresh node inventory and queue
   ranking. Queue names are not enough: the same queue class can hide very
   different CPU generations or node-local tool availability.
8. If the batch is large or queue pressure is ambiguous, run short production-shape probes before bulk optimization.
9. Verify there is a request row in `CLUSTER02_SCHEDULER_REQUESTS.tsv`, export
   the scheduler authority variables, then run the dynamic launcher or a
   job-specific launcher that consumes the same knowledge file.
10. Record the manifest, queue plan, and any follow-up observations.

## Current Long-Term Policy

- CPU-only TLTM chunks use `C8`, `C12`, `C16`, `C8-LONG`, `C12-LONG`, or `F` by default.
- GPU queues are excluded for CPU-only chunks unless explicitly approved.
- `C24` and `C36` are excluded for one-node jobs because their manual node ranges start above one node.
- Current WV-HMC production uses a gitless runtime snapshot plus source pin.
  Compute nodes no longer need node-local `git` for this workflow.
- `C17` and `C17-LONG` are now preferred WV-HMC production candidates when live
  queue pressure allows it. The 2026-05-31 full inventory found `C17` hardware
  is fast (`Gold 6542Y`); the previous node-local `git` blocker is bypassed by
  the source-pin workflow.
- The same inventory found `C16` is uniformly compatible but older/slower
  (`Gold 6142`). A 16-core WV-HMC N6 t=0.03 production run was about 2.6x
  slower on `C16/cnode01` than on `C17/cnode37`. Treat C16 as an eligible slow
  fallback, not as an equal substitute for long CPU-bound production.
- `C8`/`C8-LONG` are currently uniform `Gold 6242R` CPU queues and passed the
  current node-local git compatibility check in the inventory.
- `C12`/`C12-LONG` are faster `Gold 6342` CPU queues. They are usable for
  gitless source-pin jobs; legacy PBS scripts that still call `git` on compute
  nodes must keep treating `cnode36` as a placement risk.
- One-core probes do not validate an 8-core TLTM chunk shape; use production-shape probes when revalidating a queue or node placement.
- Probe-passed queues are preferred only as compatibility priors. Current queue pressure still comes from fresh `qstat -Qf` and, when useful, new probes.
- For WV-HMC production health checks, count exact Fortran kernels with
  `pgrep -x run_wv_hmc`. Do not use `pgrep -af bin/run_wv_hmc` as a process
  count, because wrapper Python commands include `--binary bin/run_wv_hmc` in
  their arguments.

## Utility Commands

Show current persistent policy:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py show-policy
```

Capture a live cluster queue snapshot from the cluster worktree:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py snapshot
```

Refresh full node inventory and queue-to-node matrix from the cluster worktree:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py inventory \
  --hardware-probe \
  --max-workers 16 \
  --ssh-timeout 5
```

This writes:

- `codex/workspaces/fortran_modernization/state/CLUSTER02_NODE_INVENTORY.json`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_NODE_INVENTORY.csv`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_NODE_MATRIX.csv`

Create a gitless runtime snapshot and source pin before large production:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py runtime-snapshot \
  --snapshot-root /lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/<run-id> \
  --allow-dirty \
  --delete
```

The production PBS script must set:

```bash
TLTM_WORKTREE=/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/<run-id>
TLTM_REQUIRE_SOURCE_PIN=1
TLTM_SOURCE_PIN_FILE=/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/<run-id>/codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env
```

Rank queues for a gitless production-shaped CPU job:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py rank-queues \
  --ncpus 16 \
  --mem-gb 32 \
  --walltime 12:00:00 \
  --gitless-guard \
  --output-csv codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_RANKING_WV_HMC_N6_16CPU_12H.csv
```

Default ranking still protects legacy PBS scripts that require node-local
`git`. Use `--gitless-guard` only for jobs that run from a source-pinned
runtime snapshot and do not call `git` as a correctness gate on compute nodes.

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
