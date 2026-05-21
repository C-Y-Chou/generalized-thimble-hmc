# Flow-Time Label / Physical-State Split

Status: active modernization slice, 2026-05-21.

## Decision

Flow time is a fixed slot/replica label, not a mutable coordinate in the
physical state vector.

Canonical state contract:

- `slot%flow_time` / `replica%flow_time` owns the fixed flow label.
- `slot%x(:)` / `replica%x(:)` stores only real physical coordinates.
- `size(x) = config%state%physical_size = config%state%z_size`.
- legacy packed `x_legacy = [flow_time, physical_state...]` is compatibility
  only.

This promotes the previously documented typed-state redesign debt into an
active high-dimensional-readiness blocker.

## Implementation Boundary

Implemented boundary:

- `flow_at`, `flowz_at`, and `flowzr_at` accept explicit flow labels.
- `metropolis_step_at` accepts explicit flow labels and keeps sampler state
  physical-only while bridging current retained-core HMC internals through the
  legacy packed adapter.
- Stage1 and Stage2 product paths allocate slot/replica state as physical-only.
- Stage2 swap evaluates `slot_b%x` at `slot_a%flow_time` and `slot_a%x` at
  `slot_b%flow_time` without writing a flow label into either state vector.
- Config parsing accepts preferred `physical_state_size`; legacy `x_size` is
  still accepted as `physical_state_size + 1`.

Compatibility retained:

- legacy `flow`, `flowz`, `flowzr`, `x_get_flow_time`, `x_set_flow_time`, and
  seed accessors remain for old callers and retained-core tests.
- old HMC/RATTLE/QN internals still operate through the packed adapter until a
  deeper internal cleanup removes their positional `x(1)` assumptions.

## Invariants

- Local updates must not mutate `slot%flow_time` or `replica%flow_time`.
- Swap acceptance may move labels between physical states, but a slot's fixed
  `flow_time` remains the evaluation label for that slot.
- New high-dimensional code must not count the flow label in state dimension.
- New product schema should expose flow time as metadata, not as state element
  `x(1)`.

## Verification

Initial local verification:

- `git diff --check`
- `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage1 ../bin/run_tltm_stage2 test_tltm_swap_kernel_contract test_retained_core_newton_contract`
- `make -C build FC=gfortran LDFLAGS= test_retained_core_rattle_rg_contract`
- `TLTM_OFFICIAL_DFOLS_PYTHONPATH=$PWD/.venv-dfols/lib/python3.11/site-packages make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract test_retained_core_rg_reject_identity`
- tiny local Stage1 smoke: one replica, zero flow, one cycle, one local update.
- tiny local Stage2 smoke: two slots, zero-flow ladder, one cycle, one local
  update, sidecar output; manifest records `physical_state_size`.
- tiny local Stage2 2D smoke from a temporary `parameters.dat` with
  `physical_state_size=2`, `x_size=3`, `z_size=2`; sidecar manifest and
  resolved config record the new dimensions.
- `TLTM_OFFICIAL_DFOLS_PYTHONPATH=$PWD/.venv-dfols/lib/python3.11/site-packages make -C build FC=gfortran LDFLAGS= modernization_guardrails`
  passed locally.

Cluster/PBS verification is deferred while the cluster is under maintenance.
