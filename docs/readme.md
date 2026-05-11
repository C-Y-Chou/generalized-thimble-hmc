# WV-HMC Fortran Project

This repository implements a worldvolume-HMC workflow in modern Fortran, including:

- flow integration in complexified field space,
- constrained molecular dynamics (RATTLE-style updates),
- canonical p28 quasi-Newton/DFO-LS-style BTN backflow rescue,
- Markov-chain generation and observable evaluation.

Project goal:

- perform GTM calculations for user-defined models,
- save ensembles for evaluating arbitrary user-defined observables.

## Project Status

The codebase is organized into explicit layers, has runnable numerical tests, and uses a centralized runtime configuration path. Documentation in `docs/` is maintained as the canonical reference for architecture, file layout, and runtime conventions.

Current modernization state:

- Canonical TLTM route is Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Flow policy is ODEX primary integration plus solver-internal ODE assist for Newton/QN residual evaluation, with strict final `flow(...)` for live proposals.
- Stage2/Stage3 remain compatibility workflow entry points while M6 product-readiness work defines the future unified TLTM wrapper path.
- Stage3_4 owns the separate `nofb` vs `withfb` production-comparison workflow.
- Modernization reference-dataset construction/registration is paused until the M6 checklist is reviewed and explicitly started.
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

For the current compatibility TLTM workflow, use Stage2/Stage3 entry points and v1alpha sidecars as documented under `codex/workspaces/fortran_modernization/runbooks/`.

Important runbooks:

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
- `make regen_model_derivatives`: regenerate `src/physics/model_generated.f90` from `src/physics/model_action_body.inc` (`GEN_BACKEND=auto|symbolic|tape|st_auto|st_tapenade|st_enzyme`, default `auto`)
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

- Set `x_size` explicitly in `parameters.dat` (`>= 2`).
- Set `integrator_method = rattle` (default).
- `derivative_mode` is `generated` (the code path is generated-only for `ds`/`hessian`/`hessian_vec`).
- Set `bootstrap_samples = 0` for automatic speed/accuracy tuning in expectation evaluation, or set a fixed positive value.
- Temporary override is also available via `EVAL_BOOTSTRAP_SAMPLES=<N>` at runtime.
- Quasi fallback remains the active improvement path; no-fallback is a reference mode.
- Current working fallback baseline is bounded probe-only with near/non-near rescue disabled.
- Optional fallback controls:
  - `QN_S1_PROBE_MAX_ITER` (default `28`; keep `<=32` outside ablations)
  - `QN_S1_NEAR_RESCUE_ENABLED` (default `0`)
  - `QN_S1_NONNEAR_RESCUE_ENABLED` (default `0`)

### Single-Source Model Action

For the generated workflow, the model action is defined once in:

- `src/physics/model_action_body.inc`

Run `make regen_model_derivatives` after editing this file.
`calculate_action` and generated `ds`/`hessian`/`hessian_vec` all derive from this same action body, so you do not manually maintain derivative formulas.
The action body can include loops/couplings over the full `z(:)` vector (not restricted to diagonal Hessian structure).
Generated derivatives support backends via `GEN_BACKEND`:
- `auto`: try symbolic source-generation for separable forms, otherwise fallback to tape backend
- `symbolic`: force symbolic separable generation (fastest, analytic-like)
- `tape`: force tape backend (`src/physics/model_tape_ad.f90`) for general coupled bodies
- `st_auto`: try source-transformation adapters (`st_tapenade` then `st_enzyme`), fallback to `auto` if unavailable
- `st_tapenade`: force Tapenade adapter (`scripts/st_backends/tapenade_codegen.py`)
- `st_enzyme`: force Enzyme adapter (`scripts/st_backends/enzyme_codegen.py`, requires external driver)

See [source_transform_backend.md](./source_transform_backend.md) for setup,
environment variables, and Tapenade provenance/license handling.

## License And Third-Party Notices

TLTM is distributed under GPL-3.0-or-later; see the repository-root `LICENSE`
and `LICENSE_POLICY.md`.

Third-party packages/tools that affect production distribution or generated-code
provenance are tracked in repository-root `THIRD_PARTY_NOTICES.md`. In
particular:

- Official DFO-LS is GPL-3.0-or-later and is the planned production solver
  backend after behavior gates pass.
- Tapenade is currently treated as an external MIT-licensed code-generation
  tool; Tapenade-generated files require version/provenance recording before
  release.

## State Vector Convention

State vector `x(:)` semantics:

- `x(1)`: flow time
- `x(2:)`: real seed values

Runtime default is randomized start generation. There is no `initial_x.dat` runtime input path.

Helper APIs (recommended over direct indexing) are defined in `src/core/utils.f90`:

- `x_get_flow_time`, `x_set_flow_time`
- `x_get_seed_real`, `x_set_seed_real`

See [state_vector_convention.md](./state_vector_convention.md) for full details.

## Source Layout

Layered dependency direction (strict):

`apps -> sampler -> physics -> config -> core`

Main directories:

- `src/core`: primitive utilities, RNG, vector/matrix helpers
- `src/config`: parameter parsing and runtime config sync
- `src/physics`: action/derivatives and flow ODE integration
- `src/sampler`: HMC kernels, constraints, quasi-Newton, chain logic
- `src/apps`: executable entry points

Detailed architecture and responsibilities are documented in [module_architecture.md](./module_architecture.md) and [file_layout.md](./file_layout.md).

## Documentation Index

- [commands.md](./commands.md): build/run command reference
- [state_vector_convention.md](./state_vector_convention.md): state vector and input-file contract
- [module_architecture.md](./module_architecture.md): module layers and dependency rules
- [file_layout.md](./file_layout.md): repository structure and artifact policy
- [coding_style.md](./coding_style.md): coding and output style conventions
- [fallback_policy_s1.md](./fallback_policy_s1.md): fixed stage-1 fallback policy and controls
- [`../scripts/README.md`](../scripts/README.md): script status (active vs historical)

## Notes

- Artifacts under `bin/`, `build/`, and `output/` are generated products.
- Rebuild before production runs; do not assume existing `bin/` executables are current.
- Run tests before production (`make test1`, `make test2`); policy is that tests should pass across environments.
- Source of truth for implementation is under `src/` and `tests/`.
