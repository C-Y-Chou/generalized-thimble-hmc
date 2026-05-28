# nofb Runtime Optimization Readback

Generated: 2026-05-28.

## Current Finding

The current TLTM nofb production is slow per record because it performs real work on the full 13-replica ladder, not only on the highest-flow replica.

Current measured medians from remote summaries:

| run | records | cycles/record | elapsed s/cycle | local update s/cycle | swap s/cycle | inferred 32x1 node record-cycles/s |
|---|---:|---:|---:|---:|---:|---:|
| fixed-tau nofb single high-flow replica | 512 | 10000 | 0.4240 | 0.4239 | 0.0000 | 75.47 |
| TLTM nofb ladder13 current production | 2503 | 2500 | 12.6892 | 8.8324 | 3.8496 | 2.52 |

For TLTM nofb, the timed loop is essentially fully accounted:

- Local updates: about 69.5% of wall time.
- Swap sweep: about 30.4% of wall time.
- Swap reflow is almost all of swap time.
- Observable measurement, history I/O, label trace, and progress logging are negligible at this scale.

The current production command uses `threads=1`. The Fortran Stage2 code has opt-in OpenMP paths for local updates and swap reflow, but `threads=1` means the active production shape is record-parallel, not replica-parallel.

## Important Distinction

Replica OpenMP can reduce the wall time of one chain, but it may not improve node throughput. The production question for nofb is:

`record_cycles_per_wall_sec` at fixed node resources,

not only single-record wall time.

Example: if a 32-core node is changed from `32 records x 1 thread` to `2 records x 16 threads`, each record must become more than 16x faster to improve total record-cycles/hour. The fixed-tau timing shows there is single-record speedup potential, but it does not prove node-throughput improvement.

## Bottleneck Interpretation

No obvious I/O bug is visible in current summaries.

The two real bottlenecks are:

1. Local updates across all 13 replicas.
2. Swap reflow calls, currently about 10.9 flow calls per cycle per record with the direct backend.

The local-update cost is partly fundamental for TLTM, because each replica is an active Markov chain. The swap-reflow cost is the cleaner algorithmic target because it is 30% of production wall time and is dominated by repeated flow evaluations.

## Implemented Preparation

Two nofb runtime tools were added locally:

- `run_stephanov_n6_tltm_ladder.py --blas-threads N`
  - Keeps `OMP_NUM_THREADS=--threads`.
  - Separately controls `MKL_NUM_THREADS`, `OPENBLAS_NUM_THREADS`, and `VECLIB_MAXIMUM_THREADS`.
  - This prevents hidden nested BLAS oversubscription when testing OpenMP replica/swap parallelism.

- `benchmark_stephanov_n6_nofb_runtime_layouts.py`
  - Runs layouts such as `32x1,16x2,8x4,4x8,2x16,1x32`.
  - Reports `record_cycles_per_wall_sec` and timing components.
  - Uses the same ladder13 nofb production setup and dense flow-bank initialization.

## Next Benchmark

Use an isolated remote worktree so active production jobs are not affected by rebuilding `bin/run_tltm_stage2`.

Recommended first benchmark:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/benchmark_stephanov_n6_nofb_runtime_layouts.py \
  --cycles 40 \
  --layouts 32x1,16x2,8x4,4x8,2x16,1x32 \
  --blas-threads 1 \
  --total-ncpus 32 \
  --run-name stephanov_n6_nofb_runtime_layouts_40cyc_20260528 \
  --force
```

Decision rule:

- If `32x1` wins, the current scheduler layout is throughput-optimal and further nofb runtime work should target swap-reflow algorithmic cost.
- If a threaded layout wins in `record_cycles_per_wall_sec`, update production chunking to that layout.
- If a threaded layout only improves single-record wall time but loses throughput, keep `32x1` for production and use threaded layouts only for latency-sensitive probes.
