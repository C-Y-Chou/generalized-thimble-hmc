# TLTM Fortran Modernization Project

This repository currently implements and modernizes a TLTM / GT-HMC-style
fixed-flow ladder workflow in modern Fortran, including:

- flow integration in complexified field space,
- constrained molecular dynamics (RATTLE-style updates),
- optional quasi-Newton / DFO-LS-style BTN diagnostic fallback paths,
- Markov-chain generation and observable evaluation.

It does not currently contain a complete WV-HMC transition kernel.  WV-HMC is a
planned sibling sampler path after canonical TLTM closure and repository
hygiene.

Project goal:

- perform GTM calculations for user-defined models,
- save ensembles for evaluating arbitrary user-defined observables.

## Project Status

The codebase is organized into explicit layers, has runnable numerical tests, and uses a centralized runtime configuration path. Documentation in `docs/` is maintained as the canonical reference for architecture, file layout, and runtime conventions.

Current modernization state:

- Canonical TLTM production mode is `nofb`; the frozen final criterion closure
  did not find a downstream correctness, ratio-stability, or wall-clock reason
  to promote `withfb`.
- Lower failure count alone is not a production criterion.
- DFO-LS fallback is default-off legacy diagnostic mode.
- Stage2/Stage3 remain compatibility workflow entry points while the canonical
  TLTM SOP and post-TLTM workflow define the next repository direction.
- WV-HMC must be added later as a sibling sampler, not as a hidden TLTM mode.
- Repository-level distribution license is GPL-3.0-or-later, selected to allow
  official DFO-LS production backend integration.

## Quick Start

From repository root (`0/`):

```bash
cd build
make fast
make modernization_guardrails
make test1
make test2
```

Generated executables are placed in `bin/`:

- `generate_markov_chain`
- `evaluate_expectations`
- `test_program` (Hamiltonian conservation)
- `test_program2` (action derivatives)

## Current TLTM Workflow

For local modernization preflight, run:

```bash
cd build
make modernization_guardrails
```

For the current Stephanov TLTM workflow, use Stage2/Stage3 entry points and
v1alpha sidecars as documented under
`codex/workspaces/fortran_modernization/runbooks/`.

Important runbooks:

- `MODERNIZATION_POST_TLTM_WORKFLOW_20260528.md`
- `TLTM_CANONICAL_SOP_20260528.md`
- `POST_TLTM_ARTIFACT_INVENTORY_20260528.md`
- `POST_TLTM_SOURCE_BOUNDARY_AUDIT_20260528.md`
- `POST_TLTM_GUARDRAIL_CHECKLIST_20260528.md`
- `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`
- `WV_LEGACY_RESIDUE_AUDIT_20260528.md`
- `runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`
- `PARALLEL_WORKSTREAM_BOUNDARY_AND_REFERENCE_DATASET_POLICY.md`
- `M6_REFERENCE_DATASET_DESIGN_SPEC.md`
- `M6_REFERENCE_DATASET_READBACK_PLAN.md`
- `M6_REFERENCE_DATASET_GENERATION_AND_COVERAGE_PLAN.md`
- `M6_TO_CODE_MODERNIZATION_ENTRY_GATE.md`
- `M6_REFERENCE_DATASET_PRODUCT_READINESS_PLAN.md`
- `M6_REFERENCE_DATASET_CHECKLIST.md`
- `M6_PROVENANCE_READBACK_CHECKLIST.md`
- `M5_PRE_M6_GATE_ASSESSMENT.md`
- `M5_STATE_CONFIG_OWNERSHIP_PLAN.md`
- `M3_TO_M6_BEFORE_REFERENCE_DATASET_PLAN.md`

## Legacy Single-Chain Workflow

The single-chain app still exists as a compatibility/development path:

```bash
cd build
make chain
make expect
```

- Parameters come from `data/parameters.dat`.
- This is not the Stage3_4 production-comparison path and is not sufficient as a modernization reference-package path.

## Build System

All build entry points are defined in `build/makefile`.

- `make` or `make all`: full optimized build
- `make fast`: debug-friendly build
- `make OMP=1`: OpenMP + parallel MKL build
- `make chain`, `make expect`, `make test1`, `make test2`: build and run selected targets
- `make modernization_guardrails`: run local M4 guardrails, including direct-env centralization, Stage2/eval build, ODEX/swap tests, protocol audit, and Stage3 sidecar smoke/merge checks
- `make test1_fb_on`, `make test1_fb_off`, `make test2_fb_on`, `make test2_fb_off`: run tests with fallback forced on/off
- `make clean`, `make veryclean`: cleanup

See [commands.md](./commands.md) for a compact command reference.

## Runtime Configuration

Primary runtime inputs are under `data/`:

- `parameters.dat`: runtime parameters and paths

### `parameters.dat` format

`param_mod` requires `key=value` format (`#` / `!` comments allowed).
Legacy positional `parameters.dat` files are no longer accepted.

Recommended behavior:

- Set `physical_state_size = 2 * stephanov_n * stephanov_n`; `x_size` is
  only the legacy packed size and must be `physical_state_size + 1`.
- Set `integrator_method = rattle` (default).
- `derivative_mode` must be `manual`; the active provider supplies
  hand-written `action`, `ds`, `hessian_vec`, and observables.
- Set `bootstrap_samples = 0` for automatic speed/accuracy tuning in expectation evaluation, or set a fixed positive value.
- Temporary override is also available via `EVAL_BOOTSTRAP_SAMPLES=<N>` at runtime.
- `nofb` is the canonical TLTM production mode. `withfb` / DFO-LS fallback is
  retained as a default-off legacy diagnostic path.
- Optional diagnostic fallback controls:
  - `QN_S1_PROBE_MAX_ITER` (default `28`; keep `<=32` outside ablations)
  - `QN_S1_NEAR_RESCUE_ENABLED` (default `0`)
  - `QN_S1_NONNEAR_RESCUE_ENABLED` (default `0`)

### Active Model Provider

The canonical model API is `src/physics/model.f90`. The active provider is:

- `src/physics/model_stephanov.f90`

Sampler, flow, and evaluator code call the generic model API only. Do not add
runtime model-selection branches to canonical sampler/config code; changing
models means replacing the active source provider while preserving the same
`calculate_action`, `ds`, `hessian_vec`, and observable APIs.

Generated/AD derivative tooling is retained only as validation tooling for
future provider work, not as the active Stephanov production path.

### Model Observable Surface

Observable formulas are model-owned, not sampler-owned. The active observable
names and formulas live in:

- `src/physics/model_stephanov.f90`
- `src/physics/model_observables.f90`

Stage2 writes optional generic observable streams with record layout
`phi + observable_values(:)`, and `evaluate_expectations` can read those
streams directly via `EVAL_OBSERVABLE_HISTORY_FILE`. See
[model_observables.md](./model_observables.md).

The reviewed Stephanov model plan and exact-reference table are under
`model_specs/high_dimensional/`. Future models should be drafted there before
replacing the active source provider.

## License And Third-Party Notices

TLTM is distributed under GPL-3.0-or-later; see the repository-root `LICENSE`
and `LICENSE_POLICY.md`.

Third-party packages/tools that affect production distribution are tracked in
repository-root `THIRD_PARTY_NOTICES.md`. In particular:

- Official DFO-LS is GPL-3.0-or-later and remains available for diagnostic
  fallback/readback paths unless the frozen final criterion framework promotes
  it.

## State Vector Convention

Canonical state vector `x(:)` semantics:

- `x(:)`: real physical seed/state coordinates only
- `flow_time`: fixed slot/replica label metadata, passed explicitly to flow APIs

Runtime default is randomized start generation. There is no `initial_x.dat` runtime input path.

New flow APIs pass the label explicitly:

- `flow_at`, `flowz_at`, `flowzr_at`
- `metropolis_step_at`

See [state_vector_convention.md](./state_vector_convention.md) for full details.

## Source Layout

Layered dependency direction (strict):

`apps -> sampler -> physics -> config -> core`

Main directories:

- `src/core`: primitive utilities, RNG, vector/matrix helpers
- `src/config`: parameter parsing and runtime config sync
- `src/physics`: action/derivatives, observables, and flow ODE integration
- `src/sampler`: HMC kernels, constraints, quasi-Newton, chain logic
- `src/apps`: executable entry points

Detailed architecture and responsibilities are documented in [module_architecture.md](./module_architecture.md) and [file_layout.md](./file_layout.md).

## Documentation Index

- [commands.md](./commands.md): build/run command reference
- [state_vector_convention.md](./state_vector_convention.md): state vector and input-file contract
- [module_architecture.md](./module_architecture.md): module layers and dependency rules
- [file_layout.md](./file_layout.md): repository structure and artifact policy
- [model_observables.md](./model_observables.md): model-owned action/observable surfaces and observable-stream I/O
- [coding_style.md](./coding_style.md): coding and output style conventions
- [fallback_policy_s1.md](./fallback_policy_s1.md): fixed stage-1 fallback policy and controls
- [`../scripts/README.md`](../scripts/README.md): script status (active vs historical)

## Notes

- Artifacts under `bin/`, `build/`, and `output/` are generated products.
- Rebuild before production runs; do not assume existing `bin/` executables are current.
- Run tests before production (`make test1`, `make test2`); policy is that tests should pass across environments.
- Source of truth for implementation is under `src/` and `tests/`.
