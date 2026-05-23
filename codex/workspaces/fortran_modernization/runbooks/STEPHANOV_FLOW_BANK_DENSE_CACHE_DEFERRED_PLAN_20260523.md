# Stephanov Flow Bank And Dense Cache Plan - 2026-05-23

Status: active.  The DOP853 backend has a target-time dense-output API,
`solve_flow` exposes a model-general dense target helper, a dense flow-bank
builder exists, and Stage2 can initialize directly from a fixed-target
flow-bank cache.

Scope: initialization and restart acceleration for Stephanov `n=6` and future
high-dimensional models.  This plan is model-general: model choice belongs in
provider metadata and bank manifests, not in canonical Stage2 control logic.

## Current Position

The first `t_high=0.03` production readback is complete.  Cache/restart work is
now allowed, but remains an initialization/restart acceleration layer only.  The
canonical production transition kernel is unchanged.

The current production output root may or may not contain physical `x` states:

- If final Stage2 snapshots or `x_history.dat` streams exist, extract a
  high-flow physical-`x` bank from them.
- If neither exists, run a shorter follow-up production segment with
  `--write-cold-x-history` and `--write-final-snapshot`, then build the bank
  from that segment.

Do not try to reconstruct `x` from observables or from `z` alone.

## Goal

Reduce repeated adaptive-preflow cost without changing the canonical TLTM
transition kernel.

The acceleration target is initialization/restart only:

- avoid reflowing every `t=0` bank point independently to every ladder slot on
  every run;
- preserve the current production reverse gate, swap acceptance, and endpoint
  flow semantics;
- keep failures and reachability information visible rather than silently
  filtering difficult configurations;
- make the mechanism reusable for future models that provide action,
  derivatives, flow, and observables through the model provider surface.

## Non-Goals

- Do not make cached, dense-output, or continuation reflow the production
  default until endpoint-equivalence and walltime gates certify the selected
  ladder.
- Do not treat a high-flow bank as an independent physics estimator.
- Do not add Stephanov-only logic to canonical Stage2 code paths.
- Do not replace the `t=0` bank as the canonical sampling source.
- Do not broaden the DOP853 backend claim to a full dense-output product before
  dense output has its own tests.

## Proposed Layers

### Layer 1: Canonical `t=0` Bank

The `t=0` bank remains the base physical-state bank.  It stores physical
coordinates only; flow time is metadata, not packed state.

Required metadata:

```text
schema_version
model_provider_id
model_parameters
physical_state_size
observable_schema
derivative_mode
source_sampler_protocol
source_rng_contract
source_commit
source_output_root
bank_record_count
coverage_diagnostics
```

Minimum coverage diagnostics:

- per-chain acceptance and failure counts;
- basic action/observable summaries;
- split-chain diagnostics for tracked scalar projections;
- tail occupancy checks for important observables;
- disjoint-subset stability when the bank is promoted beyond development use.

### Layer 2: Target-Time Flow-Lift Cache

Input:

```text
t0_bank
target_times = final TLTM ladder
flow_backend = dop853
ode_tolerances
model_provider_id
```

Implemented cache layout:

```text
flow_bank/
  manifest.txt
  diagnostics.csv
  records/
    record_000000/
      slot_000000.bin
      slot_000001.bin
      ...
```

The first implementation should support fixed target times, not arbitrary dense
interpolation.  One DOP853 solve may produce all requested target-time outputs
for a single `t=0` record, but the stored cache is keyed by the discrete ladder
times used by TLTM.

Required diagnostics per cached record:

```text
t0_bank_index
target_flow_time
flow_status
rhs_evals
accepted_steps
rejected_steps
failure_status
phase_phi
log_abs_jacobian
effective_energy_if_available
source_backend
source_tolerances
```

If a record cannot reach a target time, store the failure.  Do not drop the
record without accounting.

Builder:

```text
bin/build_flow_bank_dense INPUT_X_BANK OUTPUT_DIR TARGET_TIMES RECORD_START RECORD_COUNT [RECORD_STRIDE]
```

Set `TLTM_FLOW_BANK_VALIDATE_ENDPOINTS=1` for endpoint validation against
ordinary `flow_at` on small jobs.  For production cache generation this can be
left off to avoid doubling cost.

### Layer 3: TLTM Large-Flow Restart Bank

After a fixed ladder is available, TLTM itself can generate better large-flow
restart banks.  This bank is not merely the deterministic image of the `t=0`
bank; it reflects the actual replica-exchange dynamics at the target ladder.

Use cases:

- reduce future startup time for the same ladder;
- seed repeated production attempts from already ladder-equilibrated states;
- study whether large-flow slots have poor support coverage or pathological
  failure pressure.

Required provenance:

```text
parent_t0_bank
parent_flow_lift_cache_if_used
source_tltm_run
ladder
cycle_range
sample_boundary
slot_id
label_id_policy
observable_stream_policy
```

This bank is allowed only as an initializer/restart source unless a separate
analysis proves that using it does not bias the production estimator.

### Layer 4: DOP853 Dense Output

Dense output is an optimization layer for cache/initialization.  Hairer DOP853
supports order-7 dense output.  As of 2026-05-23, this repo implements a local
DOP853 target-time dense-output API:

```text
odex_integrate_dop853_dense_targets
odex_integrate_dop853_dense_targets_context
```

The API integrates once to the largest requested target time and evaluates
requested intermediate target times from the accepted DOP853 trajectory.  It is
currently a backend/cache primitive only.

Stage2-facing integration is now fixed target-time caching:

```text
TLTM_STAGE2_INIT_MODE=flow_bank
TLTM_STAGE2_INITIAL_FLOW_BANK_DIR=/path/to/flow_bank
TLTM_STAGE2_INITIAL_FLOW_BANK_RECORD=<bank-record-index>
```

The loader is fail-closed: each requested slot must have an exact target-time
cache record, matching physical state size, matching slot id, matching bank
record id, matching flow time, finite `x/z/jac`, and an available target.

Current boundary:

- dense output is wired into cache generation and Stage2 initialization;
- dense single-target and continuation/cache swap reflow are opt-in production
  diagnostics, not the default;
- endpoint DOP853 behavior and existing `odex_integrate_endpoint*` APIs are
  unchanged;
- Stage2 flow-bank init does not silently fall back to adaptive preflow.

Optional swap reflow backends:

```text
TLTM_STAGE2_SWAP_REFLOW_BACKEND=direct
TLTM_STAGE2_SWAP_REFLOW_BACKEND=dop853_dense
TLTM_STAGE2_SWAP_REFLOW_BACKEND=continue_cache
TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE=none
TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE=lower_neighbor
TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE=all_lower
```

`continue_cache` has two pieces:

- low-to-high adjacent reflow continues the already-known `(z(t_low), J(t_low))`
  endpoint forward to `t_high`, instead of restarting from physical `x` at
  `t=0`;
- high-to-low adjacent reflow first checks endpoint cache/history for the same
  physical state.  Flow-bank initialization seeds all same-record ladder
  endpoints into each slot cache, snapshots and initialization seed each slot's
  current endpoint, and accepted swaps seed the opposite endpoint history for
  the newly received state.  If no valid same-state history exists, the backend
  falls back to ordinary direct endpoint reflow.

Important limitation: an accepted local HMC move changes the physical state and
invalidates prior endpoint history.  Therefore high-to-low cache hits are
expected mainly from flow-bank initialized states, rejected local moves, and
states that have just crossed a swap boundary.

As a lossless production optimization, `continue_cache` defaults
`TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE` to `lower_neighbor`.  After an accepted
local HMC update, Stage2 keeps the accepted `z/J` returned by the HMC kernel
unchanged, then seeds the same new physical state at the nearest lower ladder
time with one DOP853 dense-target call.  This changes cache availability and
timing only; it does not alter the local proposal trajectory or Metropolis
decision.  Set the mode to `none` to disable the extra seed, or `all_lower` to
populate every lower ladder endpoint reachable before the nearest lower maximum.

## Operational Workflow

Extract a high-flow physical-`x` bank from a Stage2 run:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/extract_stage2_highflow_x_bank.py \
  --run-root output/stephanov_tltm_production/RUN_NAME \
  --records 0,1,2,3 \
  --source auto \
  --slot-id max \
  --output-root output/stephanov_flow_banks \
  --run-name RUN_NAME_highflow_x_bank
```

If the production run has no snapshot or `x_history.dat`, first run a shorter
segment with the wrapper flags:

```text
--write-cold-x-history --write-final-snapshot
```

Build the dense target-time cache from the extracted bank:

```bash
TLTM_PARAMETERS_FILE=data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat \
TLTM_ODE_BACKEND=dop853 \
TLTM_DOP853_HINIT_ENABLED=1 \
TLTM_DOP853_STIFFNESS_CHECK_ENABLED=1 \
bin/build_flow_bank_dense \
  output/stephanov_flow_banks/RUN_NAME_highflow_x_bank/bank/x_bank.dat \
  output/stephanov_flow_banks/RUN_NAME_dense_cache \
  '0,0.00003,0.0001,...,0.03' \
  0 N_RECORDS
```

Run Stage2 from the cache:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py \
  --init-flow-bank-root output/stephanov_flow_banks/RUN_NAME_dense_cache \
  --records 0,1,2,3 \
  --write-final-snapshot
```

With `--init-flow-bank-root`, `--records` are flow-bank record ids, not the
original production record ids.  The extraction `x_bank_index.csv` maps them
back to source records/cycles.

Verification completed locally:

```text
make -C build FC=gfortran LDFLAGS= ../bin/build_flow_bank_dense ../bin/run_tltm_stage2
python3 -m py_compile codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py codex/workspaces/fortran_modernization/tasks/scripts/extract_stage2_highflow_x_bank.py
TLTM_PARAMETERS_FILE=data/parameters_stephanov_n2_smoke.dat TLTM_ODE_BACKEND=dop853 TLTM_DOP853_HINIT_ENABLED=1 TLTM_DOP853_STIFFNESS_CHECK_ENABLED=1 TLTM_FLOW_BANK_VALIDATE_ENDPOINTS=1 bin/build_flow_bank_dense output/tests/flow_bank_dense_stage2_smoke/input/x_bank.dat output/tests/flow_bank_dense_stage2_smoke/cache '0,1e-7' 0 2
TLTM_STAGE2_INIT_MODE=flow_bank TLTM_STAGE2_INITIAL_FLOW_BANK_DIR=output/tests/flow_bank_dense_stage2_smoke/cache TLTM_STAGE2_INITIAL_FLOW_BANK_RECORD=0 bin/run_tltm_stage2
python3 codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py --base-parameters data/parameters_stephanov_n2_smoke.dat --ladder '0,1e-7' --records 0 --init-flow-bank-root output/tests/flow_bank_dense_stage2_smoke/cache --write-final-snapshot --write-cold-x-history --skip-build --force
python3 codex/workspaces/fortran_modernization/tasks/scripts/extract_stage2_highflow_x_bank.py --run-root output/tests/flow_bank_dense_stage2_smoke/wrapper/flow_bank_wrapper --records 0 --source auto --output-root output/tests/flow_bank_dense_stage2_smoke/extract --run-name snapshot_bank --force
make -C build FC=gfortran LDFLAGS= test_odex_backend_package_contract
make -C build FC=gfortran LDFLAGS= test_odex_flow_jacobian_contract test_odex_foundation_contract test_odex_solver
make -C build FC=gfortran LDFLAGS= test_newton_eval_flow_status_context_contract
python3 codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py --repo-root . --output-root output/tests/m4_guardrails/precision_readiness
git diff --check -- src/physics/odex_backend.f90 tests/test_odex_backend_package_contract.f90 build/makefile codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py codex/workspaces/fortran_modernization/runbooks/STEPHANOV_FLOW_BANK_DENSE_CACHE_DEFERRED_PLAN_20260523.md
```

Full M4 guardrails were also attempted.  The dense-output and precision
boundaries passed, but the full run is still blocked by pre-existing local
environment/smoke issues outside the dense-output backend:

- retained QN route expects official DFO-LS package success in the local Python
  bridge, but the local bridge returned package failure;
- the tiny Stage3 smoke initializes direct `t=0.05` and can fail before writing
  `per_seed_summary_table.csv`.

Dense-output acceptance requirements:

- endpoint values from dense output at `t_end` match direct endpoint DOP853
  within the configured ODE tolerance profile;
- intermediate target-time values match independent endpoint integrations to
  those same times;
- failure statuses match the endpoint controller when the trajectory becomes
  unusable;
- dense output is used for initialization/cache generation only until a
  production-kernel equivalence gate is explicitly written and passed.

## Stage2 Integration Design

Add a new initialization mode after the runbook is reactivated:

```text
TLTM_STAGE2_INIT_MODE=flow_bank
TLTM_STAGE2_INITIAL_FLOW_BANK_DIR=/path/to/flow_bank
TLTM_STAGE2_INITIAL_FLOW_BANK_RECORD=<record-index>
```

Stage2 behavior:

1. For each fixed slot flow time, read the corresponding cached state.
2. Verify model id, parameter hash, physical dimension, flow backend, tolerance
   profile, and target time against the current run.
3. If the exact target time is unavailable, fail closed in the first
   implementation.
4. Keep production reverse gate on.
5. Keep preflow reverse gate off for any fallback adaptive preflow path.
6. Record the initialization source in the v1 manifest.

Do not change local HMC, swap Metropolis, reverse-gate replay, label tracing, or
observable sampling semantics.

## Verification Plan

### A. Cache Correctness

For a small fixed set of `t=0` records and ladder times:

1. Generate a target-time flow cache.
2. Independently recompute endpoint DOP853 for every `(record, target_time)`.
3. Compare cached `z`, phase, log-Jacobian, and effective energy.
4. Confirm failure statuses match.

Acceptance: all successful cached endpoints match direct endpoint integration
within the selected ODE tolerance profile; all failures are explicit and counted.

### B. Stage2 Initialization Equivalence

Run two short Stage2 jobs with the same ladder and bank records:

```text
case A: current adaptive preflow from t=0 bank
case B: flow_bank initialization
```

Compare:

- manifest controls;
- initial per-slot energies and phases;
- early pair acceptances;
- early proposal/failure counts;
- label trace sanity;
- walltime spent before cycle 1.

Acceptance: the flow-bank run reaches cycle 1 much faster and has no unexplained
diagnostic shift beyond ordinary stochastic differences.

### C. Restart Bank Safety

For a TLTM-produced large-flow restart bank:

1. Start short independent runs from disjoint restart subsets.
2. Compare pair acceptance, round trips, failures, and primary observables.
3. Verify results are stable against starting from the original `t=0` path after
   sufficient warmup.

Acceptance: restart improves startup cost without creating a visible support
hole or observable shift.

## Production Re-entry Criteria

Return to this plan only after:

- the `t_high=0.03` ladder is selected;
- at least one first-production run has completed and been read back;
- the run's observable stream policy is decided;
- the production output path and manifest provide a stable target for cache
  validation.

Current status:

- model-general dense flow-bank generation exists through `bin/build_flow_bank_dense`;
- Stage2 can initialize from `TLTM_STAGE2_INIT_MODE=flow_bank`;
- Stage2 can write `x_history.dat` and `final_snapshot.bin` for high-flow bank extraction;
- snapshot continuation supports an explicit restart-boundary policy;
- swap reflow has an optional experimental backend
  `TLTM_STAGE2_SWAP_REFLOW_BACKEND=dop853_dense`.
- swap reflow also has an optional experimental backend
  `TLTM_STAGE2_SWAP_REFLOW_BACKEND=continue_cache`.

The canonical production default remains `TLTM_STAGE2_SWAP_REFLOW_BACKEND=direct`.
The dense and continuation/cache swap paths must stay opt-in until they pass
larger decision-equivalence and walltime benchmarks on the selected Stephanov
ladder.

Initial replacement test result:

- `bin/compare_swap_reflow_backends` compares direct endpoint, dense single-target,
  and dense multi-target reflows on the same physical-x bank records and target
  flow times.
- On Stephanov `n=6` t0-bank records with the `t_high=0.03` ladder, dense
  single-target matched direct success/failure status, effective energies, and
  swap accept probabilities for all comparable endpoints, but was slower than
  direct endpoint reflow.
- On a low-flow all-success subset, dense single-target again matched direct to
  roundoff but remained slower.

Conclusion: dense output can be used as a correctness-equivalent opt-in swap
diagnostic backend, but it should not replace direct endpoint reflow for
production adjacent swaps.  Its performance value is in multi-target bank/cache
construction, where one integration of a physical `x` can populate many ladder
targets.

Continuation/cache implementation result:

- `solve_flow` exposes `flow_continue(t_source, t_target, z_source, J_source, ...)`.
  It integrates the same holomorphic flow/Jacobian variational equations from
  the known source endpoint and requires `t_target >= t_source`.
- Stage2 `continue_cache` uses `flow_continue` for low-to-high adjacent reflow.
  High-to-low uses the same-state endpoint cache first and direct reflow only on
  cache miss.
- Accepted local HMC updates can now seed same-state lower-neighbor reflow cache
  immediately; this turns the next high-to-low adjacent swap for that new state
  into a cache hit when the seed succeeds.
- The reflow cache capacity is now 16 endpoints per slot, enough for the current
  pruned 13-point ladder with margin.
- `compare_swap_reflow_backends` now reports adjacent continuation agreement
  against direct endpoint integration.

Local verification on Stephanov `n=6`, t0-bank records `0` and `40`, ladder
`0,0.001,0.003,0.007,0.01,0.013,0.016,0.018,0.02,0.0225,0.025,0.0275,0.03`:

```text
continue_adjacent attempts=5 successes=3
continue_adjacent_status_mismatches=0
continue_adjacent_max_abs z jac energy=
  2.239944E-016  5.258886E-015  2.131628E-014
wall_sec continue_adjacent_all=1.537461
```

Additional gates run locally:

```text
make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2 ../bin/compare_swap_reflow_backends test_tltm_swap_kernel_contract test_tltm_swap_kernel_contract_dense
TLTM_STAGE2_SWAP_REFLOW_BACKEND=continue_cache bin/test_tltm_swap_kernel_contract
TLTM_STAGE2_SWAP_REFLOW_BACKEND=continue_cache ... bin/run_tltm_stage2
git diff --check
```

The swap-kernel contract now explicitly checks both directions:

- high-to-low cache lookup returns the stored endpoint exactly within the test
  tolerance;
- `continue_cache` preserves the swap acceptance probability and accepted state
  movement contract.

Local lower-neighbor seed smoke:

```text
TLTM_STAGE2_SWAP_REFLOW_BACKEND=continue_cache
TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE=lower_neighbor
```

On the two-replica Stephanov `n=2` smoke this produced:

```text
local_reflow_cache_seed attempts=2 targets=2 stores=2 failures=0
swap_reflow_cache hits=1 misses=1 stores=1 flow_calls=1 flow_failures=0
```

With `TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE=none` on the same smoke:

```text
local_reflow_cache_seed attempts=0 targets=0 stores=0 failures=0
swap_reflow_cache hits=0 misses=2 stores=2 flow_calls=2 flow_failures=0
```

## Notes For The Next Agent

- DOP853 dense output is available for flow-bank generation and optional swap
  reflow.  The swap path is not the production default.
- Current `t=0` Stephanov development bank is documented in
  `STEPHANOV_T0_CHECKPOINT_BANK_20260522.md`.
- Preflow reverse gate must remain off; production reverse gate must remain on.
- Failure counts are diagnostic data.  Do not optimize them away by silently
  filtering cache records.
- The bank/cache layer should sit in scripts/init/product-surface plumbing, not
  in model-specific canonical sampler logic.
