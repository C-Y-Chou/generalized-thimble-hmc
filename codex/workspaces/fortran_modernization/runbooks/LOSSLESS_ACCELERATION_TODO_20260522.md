# Lossless Acceleration TODO

Date: 2026-05-22
Scope: `/Users/ccy/Documents/TLTM_fortran_modernization`

This TODO records acceleration work that should preserve the statistical target,
precision profile, residual gates, reversibility gate, and accept/reject
semantics. Do not treat tolerance loosening, reverse-gate relaxation, or reduced
observable sampling as "lossless" speedups.

## Priority Queue

### 1. Cache phase/action/logdet within Stage2 slot cycles

Status: DONE

Hot path:
- `src/sampler/markovchain_phase.f90`
- `src/sampler/tltm_stage2_driver.f90`

Current issue:
- `measure_slot`, `write_history_sample`, and `write_observable_sample` can
  compute the phase factor for the same slot state in the same cycle.
- `compute_phase_factor(z, j, phi)` calls `log_determinant(j)` and
  `calculate_action(z)`, so repeated calls are expensive.

Lossless acceleration:
- Add cached phase/action/logdet fields to `tltm_slot_t` or a run-level slot
  cache.
- Track a slot state version and invalidate on local update, accepted swap,
  initialization, or explicit state overwrite.
- Writers should reuse a valid cached value produced by measurement instead of
  recomputing.

Validation gate:
- Existing retained-core and Stage2 smoke tests pass.
- For a fixed seed, accept/reject counts, label trace, cold history, observable
  history, and summary fields match except for permitted runtime fields.
- Add a focused test that repeated writer calls do not trigger extra
  `compute_phase_factor` work when the slot version is unchanged.

Implementation:
- Added slot-local `state_version` plus cached phase/action/logdet fields to
  `tltm_slot_t`.
- Invalidates the cache only when the slot state changes: initialization,
  accepted local update, or accepted swap.
- `measure_slot`, phase-history writers, and observable writers now reuse the
  slot cache.
- Optional `TLTM_STAGE2_PHASE_CACHE_STATS_FILE` writes hit/miss counts for
  focused validation without changing standard summaries.

Validation:
- Build: `make -C build ../bin/run_tltm_stage2`.
- Stage2 RNG v2 anchor: `python3 codex/workspaces/fortran_modernization/tasks/scripts/stage2_rng_v2_anchor.py --skip-build`.
- Fixed validation point:
  `t=0.02`, records `0,81`, cycles `40`, burn `5`, `epsilon=0.04`,
  `nstep=4`.
- Before:
  `output/stephanov_flowtime_sign_problem/lossless_parallel_validation_serial_t002_2x40_20260522`.
- After:
  `output/stephanov_flowtime_sign_problem/lossless_cache_validation_serial_t002_2x40_20260522`.
- Parity: label trace, `x_history.dat`, and `observable_history.dat` are
  byte-identical for both records; summaries match after removing runtime
  fields.
- Cache stats: record `0000` had `53` hits / `29` misses; record `0081` had
  `65` hits / `17` misses.
- Local wall time at this point changed from `149.30 s` to `139.89 s`
  (`1.07x`).  This is a small but lossless speedup because the dominant cost
  remains flow/proposal construction.

### 2. Parallelize Stage2 slot local updates

Status: TODO

Hot path:
- `src/sampler/tltm_stage2_driver.f90`
- `scripts/run_stage3_3_multiseed.py`

Current issue:
- Stage2 local updates over slots are serial inside each `run_tltm_stage2`
  process.
- `scripts/run_stage3_3_multiseed.py` warns that `--stage2-threads` only helps
  OpenMP/MKL-enabled code paths, not replica updates.

Lossless acceleration:
- Parallelize per-slot local update work, then synchronize before swap,
  measurement, history, and summary operations.
- Use the existing `stage2_kernel_rng_v2` domain-separated stream contract:
  `stage2:init`, `stage2:local_momentum`, `stage2:local_accept`, and
  `stage2:swap_accept`.
- Keep swap ordering and measurement ordering unchanged.

Validation gate:
- Deterministic replay passes for serial and parallel schedules.
- Stage2 RNG v2 anchor passes.
- Schedule-invariance test shows identical transition decisions and summaries
  modulo runtime fields.
- Swap-kernel contract and post-B RNG reference anchor pass.

### 3. Add batched model-provider RHS hooks

Status: TODO

Hot path:
- `src/physics/model.f90`
- `src/physics/solve_flow.f90`
- `src/physics/model_stephanov.f90`

Current issue:
- `rhs_flow_jac_context` loops over Jacobian columns and calls
  `hessian_vec(z, column, hv)` one column at a time.
- Model providers cannot currently reuse per-`z` setup across `ds` and many
  Hessian-vector products.

Lossless acceleration:
- Add an optional model-provider hook that evaluates `ds(z)` plus batched
  Hessian-vector products for a matrix of tangent columns.
- Keep the current scalar `hessian_vec` path as the reference fallback.
- For Stephanov, use the exact block algebra provider already planned for the
  dense matrix layout; for other models, batch only when the algebra is exactly
  equivalent to repeated scalar calls.

Validation gate:
- Batched provider output matches repeated scalar `hessian_vec` calls to
  roundoff tolerance.
- ODEX flow/Jacobian contract passes.
- Retained-core Newton and RATTLE/RG contracts pass.
- Stephanov exact-reference and observable parity checks pass before using this
  for production scans.

### 4. Reuse real-Jacobian maps and LU factorizations within a step

Status: TODO

Hot path:
- `src/sampler/hmc_kernels.f90`
- `src/sampler/hmc_constraints.f90`
- `src/sampler/hmc_integrator_core.f90`

Current issue:
- Tangent projection maps complex Jacobians to real matrices and factors them
  with `dgetrf`.
- Some proposal paths can use the same Jacobian for multiple projection or
  solve operations within a local step.

Lossless acceleration:
- Add an explicit caller-owned cache for real-Jacobian mapping, LU factor, and
  pivot array.
- Invalidate the cache whenever the complex Jacobian changes.
- Prefer an explicit state-version or call-scope token over implicit pointer
  assumptions.

Validation gate:
- Focused projection tests compare cached and uncached outputs bitwise or to
  roundoff.
- Retained-core RATTLE/RG contract passes.
- Reverse-gate reject identity remains unchanged.

### 5. Make external BLAS/LAPACK linkage real

Status: TODO

Hot path:
- `build/makefile`
- `src/core/lapack_fallback.f90`

Current issue:
- GNU builds expose `GNU_LINALG_LIBS`, but `core/lapack_fallback` is still in
  `CORE_SRC`.
- Local binary inspection showed no OpenBLAS/MKL/Accelerate linkage for
  `bin/run_tltm_stage2`.

Lossless acceleration:
- Make fallback LAPACK/BLAS conditional, so external libraries can provide
  `dgetrf`, `dgetrs`, `dgemv`, `zgetrf`, and related symbols.
- Add a build option such as `USE_EXTERNAL_LINALG=1`.
- Keep fallback as the default portability path unless the selected toolchain
  provides a verified external library.

Validation gate:
- Link inspection confirms the external library is used.
- Linear algebra helper tests pass under fallback and external builds.
- Stage2 tiny smoke, retained-core contracts, and observable parity pass.
- Treat output as roundoff-equivalent, not necessarily bitwise identical across
  BLAS implementations.

### 6. Parallelize scan records, flow times, and seed jobs outside Stage2

Status: DONE

Hot path:
- `codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py`
- `codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py`
- `scripts/run_stage3_3_multiseed.py`

Current issue:
- Stephanov scan scripts call `run_tltm_stage2` one record at a time.
- Flow-time, seed, and bank-record jobs are independent at the process level.

Lossless acceleration:
- Add a process-pool or PBS-array execution mode for independent scan records.
- Keep each child process environment, seed, initial record, and output
  directory deterministic.
- Merge readbacks only after all child jobs complete.

Validation gate:
- Serial and parallel scan manifests contain the same planned records.
- Per-record summaries are identical modulo runtime fields.
- Failed records preserve their individual stdout/stderr and environment
  manifests for provenance.

Implementation:
- Added explicit `--jobs N` process-pool mode to:
  - `codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py`
  - `codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py`
- Default remains `--jobs 1`, preserving existing serial behavior.
- Each child keeps its deterministic seed, initial record, environment, and
  record-local output directory.
- Each scan writes `scan_plan.csv`; summaries include actual flow/case wall
  time and summed record wall time.

Validation:
- Flow-time scan validation point:
  `t=0.02`, records `0,81`, cycles `40`, burn `5`, `epsilon=0.04`,
  `nstep=4`.
- Serial output:
  `output/stephanov_flowtime_sign_problem/lossless_parallel_validation_serial_t002_2x40_20260522`.
- Parallel output:
  `output/stephanov_flowtime_sign_problem/lossless_parallel_validation_jobs2_t002_2x40_20260522`.
- Parity: label trace, `x_history.dat`, and `observable_history.dat` are
  byte-identical; summaries match after removing runtime/provenance-path
  fields.
- Local wall time changed from `149.30 s` to `125.14 s` (`1.19x`) with
  `--jobs 2`.  The speedup is modest on the local machine because child
  processes contend for CPU, but the process-level independence is verified.
- HMC-protocol scan validation point:
  `t=0.02`, records `0,81`, cycles `10`, single `nstep=4` candidate.
- Serial output:
  `output/stephanov_hmc_protocol_scans/lossless_bank_protocol_parallel_serial_t002_2x10_20260522`.
- Parallel output:
  `output/stephanov_hmc_protocol_scans/lossless_bank_protocol_parallel_jobs2_t002_2x10_20260522`.
- Parity: label trace and `x_history.dat` are byte-identical; summaries match
  after removing runtime-derived fields.
- Local wall time changed from `125.98 s` to `105.69 s` (`1.19x`).

### 7. Reuse observable and writer buffers

Status: TODO

Hot path:
- `src/sampler/tltm_stage2_driver.f90`
- `src/physics/model_observables.f90`

Current issue:
- Observable writers allocate temporary observable arrays during sample writes.
- `evaluate_model_observable_by_index` also allocates a full values array for
  one-index access.

Lossless acceleration:
- Add run-level or slot-level observable scratch buffers sized by
  `model_observable_count()`.
- Route sample writers through preallocated buffers.
- Add a no-allocation single-observable fast path only if it is algebraically
  identical to selecting from the full observable vector.

Validation gate:
- Observable history files match the current writer output.
- Allocation-free path is covered by focused tests for all registered
  observables.
- Existing Stage2 summary and evaluate-expectations readbacks remain unchanged.

## Exclusions

These may be useful experiments, but they are not lossless acceleration TODOs:

- Loosening ODE, Newton, QN, or reversibility tolerances.
- Disabling or relaxing the reverse gate.
- Reducing formal observable sample count or estimator history.
- Changing RNG stream order without the Stage2 RNG v2 schedule-invariance gate.
- Replacing ODEX/CVODE/backend behavior without endpoint, residual, and
  reversibility parity evidence.
