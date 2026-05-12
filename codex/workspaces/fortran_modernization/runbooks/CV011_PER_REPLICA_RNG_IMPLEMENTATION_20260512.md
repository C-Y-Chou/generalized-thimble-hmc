# CV-011 Per-Replica RNG Implementation

Date: 2026-05-12 JST

## Decision

The selected CV-011 RNG contract is route B: per-replica/per-slot RNG now.

This is an intentional stochastic stream-contract change. It preserves the HMC,
RATTLE, QN, reverse-gate, Metropolis, and swap kernels, but it does not preserve
the old finite-seed serial trajectory.

## Implemented Scope

1. `src/core/mt95.f90` now exposes `mt95_state_t`, `mt95_seed_state`,
   `mt95_get_state`, and `mt95_set_state`.
2. The explicit RNG state covers both the MT vector/index and the hidden
   `gaussrnd` Box-Muller spare state.
3. `sgrnd` now resets the Gaussian spare state when reseeding.
4. `tltm_replica_t` owns an RNG state for Stage1 local updates.
5. `tltm_slot_t` owns an RNG state for Stage2 local updates.
6. Stage1 and Stage2 initialization seed each replica/slot stream and then save
   the post-initialization state.
7. Stage1 and Stage2 local-update loops load the replica/slot state before
   Metropolis updates and save it back after local updates.
8. Stage2 swap acceptance now uses a separate deterministic swap RNG stream.
9. Stage1/Stage2 summaries and Stage2 v1 manifests record
   `rng_stream_contract=per_replica_rng_v1`.

## Product Meaning

Old behavior:

- replica/slot initialization used derived seeds;
- local updates and Stage2 swaps used one shared global serial RNG stream after
  initialization.

New behavior:

- each replica/slot owns its local-update stream;
- Stage2 swaps draw from an independent swap stream;
- finite-run trajectories, local counters, reverse-gate counts, failure counts,
  runtimes, and observed `Ohat` values can differ from older same-seed runs.

This is not evidence of a physics-kernel change by itself. It is the expected
consequence of changing the stochastic stream contract.

## Verification

Passed locally:

- `make -C build FC=gfortran LDFLAGS= test_mt95_state_contract`
- `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage1 ../bin/run_tltm_stage2 test_tltm_swap_kernel_contract`
- `make -C build FC=gfortran LDFLAGS= CHAIN_RNG_SEED=12345 TLTM_STAGE1_CYCLES=1 TLTM_STAGE1_NUM_REPLICAS=2 TLTM_STAGE1_LOCAL_UPDATES=1 TLTM_STAGE1_MAX_FLOW_TIME=0.1 TLTM_STAGE1_SUMMARY_FILE=../output/tests/cv011_stage1_smoke_summary.dat test_tltm_stage1`
- `make -C build FC=gfortran LDFLAGS= CHAIN_RNG_SEED=12345 TLTM_STAGE2_CYCLES=1 TLTM_STAGE2_NUM_REPLICAS=2 TLTM_STAGE2_LOCAL_UPDATES=1 TLTM_STAGE2_MAX_FLOW_TIME=0.1 TLTM_STAGE2_SWAP_ENABLED=1 TLTM_STAGE2_SUMMARY_FILE=../output/tests/cv011_stage2_smoke_summary.dat TLTM_STAGE2_LABEL_TRACE_FILE=../output/tests/cv011_stage2_smoke_label_trace.dat test_tltm_stage2`

Smoke summaries confirm the new provenance headers:

- `output/tests/cv011_stage1_smoke_summary.dat`
- `output/tests/cv011_stage2_smoke_summary.dat`

## Remaining CV-011 Work

CV-011 is not fully closed yet. The RNG stream contract is implemented, but the
codebase still has non-RNG module `SAVE` workspaces, counters, diagnostics, and
policy state in flow/solver/HMC/QN modules.

Close CV-011 only after:

1. the remaining module workspace/state ownership is migrated or explicitly
   scoped out;
2. deterministic serial/reentrant checks exist for the selected contract;
3. production/readback documentation treats pre-B and post-B finite-seed
   trajectories as different RNG contracts.
