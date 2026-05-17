# M6 Dynamic Queue Policy - 2026-05-10

Scope: PBS queue policy for modernization M6 reference dataset generation on iTHEMS cluster02.

Manual source: `ithems_cluster02_users_guide_rev10.0_en.pdf` supplied by the user on 2026-05-10.

## Governing Rules

- Use PBS Professional commands from the manual: `qsub`, `qstat`, and `qdel`.
- Treat `-q` and `-l select=...` as required submission fields.
- Use one-node chunk jobs for TLTM M6 reference data: `select=1:ncpus=N:mpiprocs=N:mem=16gb`.
- Do not use `qmove` as the official repair mechanism. Replacement means cancel the bad queued/held job if needed, remove partial output/log directories, resubmit a new chunk, and rebuild the merge dependency.
- Do not fast-forward the active cluster worktree while submitted jobs are running, because PBS jobs are pinned by `TLTM_EXPECTED_GIT_COMMIT`.

## Queue Eligibility

Automatic CPU-only candidates:

- `C8`: one to eight nodes, 40 cores/node, 12h.
- `C8-LONG`: one to eight nodes, 40 cores/node, 48h.
- `C12`: one to twelve nodes, 48 cores/node, 12h.
- `C12-LONG`: one to twelve nodes, 48 cores/node, 72h.
- `C16`: one to sixteen nodes, 32 cores/node, 12h.
- `F`: one fat node, 64 cores/node, 12h.

Excluded by default:

- `G`, `G-LONG`, `G-A100`: GPU queues. The manual defines GPU allocation separately, and live jobs showed GPU resources are reserved for these queues.
- `C24`, `C36`: manual node ranges start at 17 and 25 nodes respectively; M6 chunks are one-node jobs.
- `C12-LONG2`: observed stopped in live queue state; do not use automatically.
- `C17`, `C17-LONG`: 8-core TLTM production-shape chunks observed `Exit_status=127`; a one-core probe is not sufficient evidence for this job shape.

## Dynamic Selection

The launcher must score queues from live `qstat -Qf` state when available:

- reject disabled or stopped queues;
- reject queues whose manual limits do not support the requested one-node `ncpus` and walltime;
- penalize queued/held/waiting backlog;
- penalize queues already assigned many chunks in the current launch;
- keep long queues and `F` as valid but more expensive fallback choices;
- record the final queue plan in a manifest and JSON plan under `output/logs/fortran_modernization/reference_datasets/submit/`.

## Shared Resource Assumption

Cluster02 is shared with other users. Queue state and start latency are not stable properties of a queue.

Queue decisions must therefore combine three evidence types:

- Manual constraints: hard eligibility and maximum walltime/node/core limits.
- Persistent observations: compatibility priors for a specific TLTM job shape, such as `Exit_status=0` or `Exit_status=127`.
- Live state: current `qstat -Qf`, current user jobs, and optional short production-shape probes.

Operational consequences:

- A successful probe proves that the queue can run the job shape; it does not prove the queue is always the fastest future choice.
- A queue backlog is a time-local observation; it should not become a permanent blacklist.
- Large batches should use probe-first optimization when live pressure is ambiguous or when stale priors would dominate the plan.
- Scheduler snapshots should be refreshed immediately before queue selection, not reused across sessions as current availability evidence.

The active launcher is:

```bash
bash codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_datasets.sh
```

Modernization/source agents may run the launcher with `--dry-run` to verify the
requested work shape. Real PBS submission is scheduler-owned and requires:

```bash
export TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler
export TLTM_SCHEDULER_REQUEST_ID=<request-id-from-CLUSTER02_SCHEDULER_REQUESTS.tsv>
```

If those variables are absent, the launcher must refuse real `qsub` instead of
letting modernization act as its own scheduler.

The real PBS call should go through the shared shell gate:

```bash
codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh
```

That shell entrypoint delegates to:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_dynamic.py
```

The persistent scheduler memory is:

```bash
codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json
codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_OBSERVATIONS.tsv
codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_REQUESTS.tsv
codex/workspaces/fortran_modernization/runbooks/CLUSTER02_SCHEDULING_AGENT.md
```

Future queue/work splitting decisions must originate from a request row, consult
this scheduler memory first, then live `qstat -Qf`.

## Probe Update - 2026-05-10 19:45 JST

- Production-shape probes passed on `C8` (`14664`), `C12` (`14665`), and `C12-LONG` (`14668`) with `Exit_status=0`.
- `C16` (`14666`) and `F` (`14667`) were canceled while queued after successful probes elsewhere; they are not blacklisted, but they did not provide immediate-start evidence for this run.
- Stuck `C8-LONG` replacement chunks were superseded through cancel/resubmit/rebuild-merge:
  - R3 replacement: `14669` on `C12`, merge `14670`.
  - R4 replacements: `14671` on `C8`, `14672` on `C12-LONG`, `14673` on `C12`, `14674` on `C8`, merge `14675`.
- Scheduler memory now treats `C8` and `C12` as preferred M6 production-shape compatibility priors, with `C12-LONG` as a validated long-queue pressure release. These are not fixed future availability guarantees.

Dry-run:

```bash
bash codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_datasets.sh --dry-run
```

## Repair Policy

If a chunk fails before producing valid chunk outputs:

- inspect `qstat -x -f JOBID` for `Exit_status`, queue, and `exec_host`;
- inspect `pbs_boot.log` if it exists;
- remove only that chunk's partial output/log directory;
- resubmit a replacement chunk through a CPU-eligible queue;
- submit a replacement merge job depending on the full valid chunk job set;
- do not mutate active running jobs or fast-forward the pinned worktree.

If a queue/node combination fails with production-shape `select=1:ncpus=8:mpiprocs=8`, record it as a policy observation before reusing that queue class.
