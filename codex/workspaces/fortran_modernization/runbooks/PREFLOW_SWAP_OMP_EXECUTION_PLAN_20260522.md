# Preflow, Swap Reflow, And OpenMP PBS Execution Plan

Date: 2026-05-22
Scope: Stephanov `n=6` TLTM ladder work on `/Users/ccy/Documents/TLTM_fortran_modernization`.

## Diagnosis

The aborted sparse-ladder pilot is not a valid speed benchmark.  The Stage2
local-update OpenMP gate was enabled, but the PBS shape was MPI-like:

```text
select=1:ncpus=8:mpiprocs=8:mem=16gb
OMP_NUM_THREADS=7
```

Four jobs then showed low CPU use and overlapping CPU bindings.  Reverse-gate
cost alone cannot explain this.  Treat the run only as diagnostic evidence.

## Goals

1. Keep preflow as initialization/annealing, not as a sampler transition.
2. Prevent adaptive preflow from grinding indefinitely when a bank point cannot
   reach a target flow time.
3. Keep the production sampler reverse gate on while forcing only the preflow
   warmup/annealing route to run with reverse gate off.
4. Parallelize adjacent-pair swap reflow inside one odd/even swap sweep.
5. Hand PBS resource-shape changes to the cluster02 scheduler boundary, rather
   than embedding submit authority in the modernization code path.

## Phase 1: Preflow Correction

Files:

- `src/sampler/markovchain_mod.f90`
- `src/sampler/hmc.f90` only if a small helper API is cleaner
- focused tests under `tests/`

Implementation:

1. Give `relax_with_zero_momentum` its own local `hmc_policy_context_t`.
2. Mark that policy as already loaded before calling `integrate_hmc_warmup`, so
   `QN_REVERSE_GATE_ENABLED` from the production sampler does not leak into
   preflow.
3. Force preflow reverse gate off.  This is a hard route separation, not a
   tunable production option.
4. Add bounded adaptive-preflow guards:
   - `TLTM_STAGE2_INIT_PREFLOW_MAX_STAGES`
   - `TLTM_STAGE2_INIT_PREFLOW_MAX_SHRINKS`
   - optional elapsed-time guard only if tests show stage/shrink limits are
     not enough
5. On guard exhaustion, return `success=.false.` with a clear log line.  Do not
   silently keep shrinking `dt_try`.
6. Keep zero-momentum RATTLE semantics: no Metropolis, no reverse gate, no
   detailed-balance claim.
7. Keep production `metropolis_step` / Stage2 local updates on the production
   HMC policy, where `QN_REVERSE_GATE_ENABLED=1` is required for the current
   Stephanov ladder work.

Validation:

1. Unit test that `QN_REVERSE_GATE_ENABLED=1` does not activate reverse-gate
   replay during `adaptive_preflow_to_target`.
2. Unit or smoke test that a deliberately unreachable target exits by the new
   guard instead of looping until walltime.
3. Existing HMC/RATTLE tests still pass.

Acceptance:

- Production `metropolis_step` reverse-gate behavior is unchanged.
- Production Stage2 logs show `reverse_gate_enabled=T` when
  `QN_REVERSE_GATE_ENABLED=1`.
- Preflow logs explicitly show its reverse-gate policy.
- Preflow logs show reverse gate off even when the production sampler env has
  `QN_REVERSE_GATE_ENABLED=1`.
- A failed preflow is a bounded initialization failure, not a hung run.

## Phase 2: Swap Pair Reflow Parallelization

Files:

- `src/sampler/tltm_stage2_driver.f90`
- `tests/test_tltm_swap_kernel_contract.f90`
- existing Stage2 RNG-v2 anchor/schedule-invariance scripts

Implementation:

1. Split swap acceptance into two parts:
   - serial/random preparation, preserving the existing swap RNG sequence
   - pair-local reflow/energy/accept-apply work
2. Add optional `accept_uniform` to `attempt_adjacent_swap`, matching the
   existing `markovchain_metropolis` pattern.  Existing callers can keep using
   the old RNG path.
3. In `perform_swap_sweep`, build the active odd/even pair list first.
4. For `stage2_kernel_rng_v2`, compute pair uniforms from the deterministic
   `stage2:swap_accept` domain.
5. For legacy swap RNG modes, precompute uniforms serially before the OpenMP
   region if parallel swap is enabled.  This preserves RNG order and avoids
   shared global RNG calls inside OpenMP.
6. Run the non-overlapping odd/even pairs with `!$omp parallel do
   schedule(static)`.
7. Each pair may mutate only:
   - `slots(idx)`
   - `slots(idx+1)`
   - `pair_stats(idx)`
   - `run_contexts(idx)`
   - `run_contexts(idx+1)`
8. Keep measurement, label-position refresh, round-trip bookkeeping, summaries,
   and history writing serial after the swap sweep.
9. Gate it with explicit runtime flag `TLTM_STAGE2_PARALLEL_SWAPS=1`.
10. Keep `TLTM_STAGE2_PARALLEL_LOCAL_UPDATES` disabled whenever production
    reverse gate is enabled until reverse-gate diagnostic counters are proven
    schedule-invariant.  The physical transition/label trace path was invariant
    in smoke tests, but the reverse-gate diagnostic counters were not; lossless
    production runs must not use that mode yet.

Validation:

1. `make -B -C build OMP=1 ../bin/run_tltm_stage2 test_tltm_swap_kernel_contract`
2. Stage2 RNG-v2 anchor:
   `python3 codex/workspaces/fortran_modernization/tasks/scripts/stage2_rng_v2_anchor.py --skip-build`
3. Serial-vs-parallel Stage2 smoke:
   - same seed
   - same ladder
   - same cycle count
   - `TLTM_STAGE2_PARALLEL_LOCAL_UPDATES=0/1`
   - `TLTM_STAGE2_PARALLEL_SWAPS=0/1`
   - compare label trace and summary after excluding runtime fields
4. Local timing smoke:
   - 7 replicas
   - 50 to 100 cycles
   - `swap_enabled=0` to confirm local-update scaling
   - `swap_enabled=1` to measure swap overhead after pair reflow parallelism

Acceptance:

- Swap proposal counts, accept/reject counts, labels, and deterministic RNG-v2
  traces match serial results.
- OpenMP CPU use rises when both local updates and swap pair reflows are
  enabled.
- If timing remains poor, the remaining serial fraction is measurement or
  single-pair work, not avoidable adjacent-pair reflow.

## Phase 3: PBS Scheduler Request

Owner: cluster02 scheduler agent.

Modernization may prepare dry-runs, manifests, and request rows, but real
`qsub` must pass through:

```bash
codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh
```

Required scheduler request:

```text
purpose: Stephanov n=6 TLTM OpenMP ladder benchmark
resource_shape_candidate: select=1:ncpus=8:mpiprocs=1:ompthreads=7:mem=16gb
env:
  OMP_NUM_THREADS=7
  OMP_PROC_BIND=close
  OMP_PLACES=cores
  MKL_NUM_THREADS=1
  OPENBLAS_NUM_THREADS=1
  BLIS_NUM_THREADS=1
  VECLIB_MAXIMUM_THREADS=1
  QN_REVERSE_GATE_ENABLED=1
  TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2
  TLTM_STAGE2_PARALLEL_LOCAL_UPDATES=0
  TLTM_STAGE2_PARALLEL_SWAPS=1
  TLTM_STAGE2_SWAP_ENABLED=1
```

Probe before any long run:

1. Submit one short OpenMP-shaped job through scheduler authority.
2. Verify `qstat -f` reports `mpiprocs=1` and `ompthreads=7` or the cluster's
   accepted equivalent.
3. Verify with `ps -L` or `/proc/<pid>/task/*/status` that one process owns
   distinct worker CPUs and does not overlap with sibling jobs.
4. Verify `resources_used.cput / resources_used.walltime` is consistent with
   multi-core use during the parallel sections.

Acceptance:

- Scheduler records the OpenMP resource shape in the request ledger and queue
  observations.
- Modernization runbooks do not hard-code real submission authority.
- A long ladder pilot starts only after the short probe proves CPU binding.

## Phase 4: Re-enter Flow-Time Selection

After Phases 1 to 3 pass, rerun only a short ladder benchmark first:

```text
ladder: 0,1e-4,1e-3,3e-3,1e-2,2e-2,3e-2
n: 6
t_high: 0.03
epsilon: 0.04
nstep: 4
cycles: 50-100 for timing validation, not physics
initial bank: t=0 checkpoint bank
preflow: adaptive, bounded, reverse gate off
production sampler: reverse gate on
parallel: local updates off under production reverse gate, swap pair reflow on
```

Only after timing and CPU binding are correct should we run the longer ladder
needed for endpoint and bottleneck decisions.

## Execution Order

1. Implement Phase 1.
2. Run local focused preflow tests.
3. Implement Phase 2.
4. Run local OMP build, swap contract, RNG anchor, and serial-vs-parallel smoke.
5. Commit and push.
6. Prepare scheduler request row for Phase 3.
7. Scheduler performs the OpenMP-shaped PBS probe.
8. Read back CPU binding and timing.
9. Resume high-flow ladder selection.

## Execution Readback

Implemented in this workspace:

- Preflow now passes an already-loaded local HMC policy to warmup RATTLE with
  `qn_reverse_gate_enabled=F`.
- Production Stage2 still loads the normal HMC bridge policy; with
  `QN_REVERSE_GATE_ENABLED=1`, logs show `reverse_gate_enabled=T`.
- Adaptive preflow now has bounded guards:
  `TLTM_STAGE2_INIT_PREFLOW_MAX_STAGES` and
  `TLTM_STAGE2_INIT_PREFLOW_MAX_SHRINKS`.
- Swap pair reflow has opt-in OpenMP parallelization through
  `TLTM_STAGE2_PARALLEL_SWAPS=1`.
- Swap accept uniforms are prepared before the OpenMP region, preserving swap
  RNG order.
- `TLTM_STAGE2_PARALLEL_LOCAL_UPDATES=1` is now refused while production
  reverse gate is enabled, because the smoke test found reverse-gate diagnostic
  counter drift even though label traces stayed identical.

Local validation completed:

- `make -C build OMP=1 ../bin/run_tltm_stage2 test_tltm_swap_kernel_contract`
- Preflow policy smoke with `QN_REVERSE_GATE_ENABLED=1`: preflow logged
  `reverse_gate_enabled=F`; production logged `reverse_gate_enabled=T`.
- Preflow guard smoke with `TLTM_STAGE2_INIT_PREFLOW_MAX_STAGES=1`: bounded
  initialization failure with `adaptive preflow guard hit`.
- Swap-only serial-vs-parallel smoke: normalized summary and label trace matched.
- Local-update serial-vs-parallel smoke with reverse gate off: normalized
  summary and label trace matched, preserving the previous opt-in use case.
- Production request smoke with `QN_REVERSE_GATE_ENABLED=1`,
  `TLTM_STAGE2_PARALLEL_LOCAL_UPDATES=1`, and
  `TLTM_STAGE2_PARALLEL_SWAPS=1`: local parallel was refused, swap parallel ran,
  and normalized summary plus label trace matched serial.
- Stage2 RNG-v2 anchor passed with reverse gate on and parallel swap requested:
  `python3 codex/workspaces/fortran_modernization/tasks/scripts/stage2_rng_v2_anchor.py --skip-build --output-root output/tests/stage2_rng_v2_anchor_prefswap_rg`
