# Cluster02 Node Inventory Readback 2026-05-31

Purpose: stop queue selection from using queue names as a proxy for speed.
The scheduler now stores node-level hardware and compatibility data before
large CPU-bound production submissions.

## Artifacts

- `codex/workspaces/fortran_modernization/state/CLUSTER02_NODE_INVENTORY.json`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_NODE_INVENTORY.csv`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_NODE_MATRIX.csv`
- `codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_RANKING_WV_HMC_N6_16CPU_12H.csv`

Collection command on cluster:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py inventory \
  --hardware-probe \
  --max-workers 16 \
  --ssh-timeout 5
```

Ranking command on cluster:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py rank-queues \
  --ncpus 16 \
  --mem-gb 32 \
  --walltime 12:00:00 \
  --output-csv codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_RANKING_WV_HMC_N6_16CPU_12H.csv
```

## Inventory Summary

- PBS nodes parsed: 61.
- Hardware probes attempted: 61.
- Hardware probes with node SSH data: 59.
- Missing SSH hardware details: `anode01` and `vnode01`; compute `cnode*`,
  `fnode*`, and `gnode*` nodes were probed.
- Queue-node rows: 194.

CPU families by node inventory:

- `Intel(R) Xeon(R) Gold 6142 CPU @ 2.60GHz`: 21 nodes.
- `Intel(R) Xeon(R) Gold 6242R CPU @ 3.10GHz`: 8 nodes.
- `Intel(R) Xeon(R) Gold 6342 CPU @ 2.80GHz`: 13 nodes.
- `INTEL(R) XEON(R) GOLD 6542Y`: 17 nodes.

Queue hardware map:

- `C16`: 16 nodes, `Gold 6142`, 32 PBS CPUs each.
- `C8` / `C8-LONG`: 8 nodes, `Gold 6242R`, 40 PBS CPUs each.
- `C12` / `C12-LONG` / `C12-LONG2`: 12 nodes, `Gold 6342`, 48 PBS CPUs each.
- `C17` / `C17-LONG`: 17 nodes, `Gold 6542Y`, 48 PBS CPUs each.
- `F`: 1 node, `Gold 6142`, 64 PBS CPUs.
- GPU queues remain excluded for CPU-only production unless explicitly approved.

## Current Compatibility Findings

The current PBS boot guard uses node-local `git`, so node-local `git` availability
is a scheduler compatibility input.

Nodes missing node-local `git` in this inventory:

- `cnode36` in `C12,C36,C12-LONG,C12-LONG2`.
- `cnode38`-`cnode41` in `C5,C17,C17-LONG`.
- `cnode42`-`cnode53` in `C17,C17-LONG`.

Consequences before the gitless WV-HMC source-pin fix:

- `C17` was fast hardware but unsafe as an automatic queue under the old git
  guard because only `cnode37` was compatible.
- `C12` had good hardware but a mixed compatibility risk because `cnode36`
  lacks node-local `git`.
- `C8` and `C8-LONG` are currently uniform compatible CPU queues.
- `C16` is uniform compatible but slower hardware.

Current WV-HMC production now uses a gitless runtime snapshot plus source pin.
For that workflow, missing node-local `git` is no longer a queue blocker.

## WV-HMC N6 Production Observation

For identical `select=1:ncpus=16:mpiprocs=16:mem=32gb walltime=12:00:00`
WV-HMC N6 t=0.03 production chunks:

- `C16/cnode01`: about 1.65k-1.70k cycles after about 1.7 hours.
- `C17/cnode37`: about 4.5k cycles after about 1.7 hours.

This is a performance prior, not a correctness failure. It means `C16` should be
treated as an eligible slow fallback for long CPU-bound WV-HMC jobs. After the
gitless source-pin fix, `C17` should be treated as a preferred queue class when
live queue pressure allows it.

## Ranking Result For 16-CPU 12h CPU Job

With old git-guard safety rules, mixed node compatibility was rejected. After
the WV-HMC source-pin fix, production ranking must be run with
`--gitless-guard`.

For WV-HMC N6 16-core 12h production, queue choice should now prefer:

1. `C17` / `C17-LONG`: fastest CPU hardware; no longer blocked by git for
   source-pinned jobs.
2. `C12` / `C12-LONG`: good CPU hardware; no longer blocked by git for
   source-pinned jobs.
3. `C8` / `C8-LONG`: uniform compatible fallback.
4. `C16`: eligible slow fallback, avoid for 15000-cycle chunks when faster
   queues are available.

## Scheduler Rule

For large production, queue choice must be based on:

1. live `qstat -Qf`;
2. full node inventory;
3. node-local compatibility requirements of the PBS script;
4. hardware speed priors for CPU-bound workloads;
5. production-shape probes when the top choice is ambiguous.

Do not submit long production jobs by queue name alone.
