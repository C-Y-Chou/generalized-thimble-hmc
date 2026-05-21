# Repository File Layout

This document defines the intended responsibilities of top-level directories and key files.

## 1. Source and Build Artifacts

- `src/core/`
  - foundational utilities, RNG, type helpers, state-vector helpers
- `src/config/`
  - runtime parameter parsing and configuration synchronization (`param_mod`)
- `src/physics/`
  - model equations, derivatives, observable definitions, and flow integration logic
- `src/sampler/`
  - HMC kernels, constraints, quasi-Newton solvers, Markov-chain workflow
- `src/apps/`
  - executable entry programs only (thin orchestration layer)
- `tests/`
  - standalone numerical validation programs
- `build/makefile`
  - authoritative build and run target definitions
- `build/.obj/`
  - compiler-generated object/module files

## 2. Runtime Input Data

- `data/parameters.dat`
  - runtime parameter file (`key=value` only)
- `model_specs/`
  - inert staging area for future model definitions and validation plans; not compiled

## 3. Generated Runtime Outputs

- `bin/`
  - compiled executables and some generated runtime plots/logs (convenience artifacts; rebuild before production)
- `output/`
  - chain histories and observable output files
- `run.log`
  - runtime log output

## 4. Documentation

- `docs/readme.md`
  - project overview, build/run workflow, documentation index
- `docs/commands.md`
  - command reference
- `docs/state_vector_convention.md`
  - `x` semantics and helper API contract
- `docs/model_observables.md`
  - model-owned action/observable surfaces and observable-stream I/O contract
- `docs/module_architecture.md`
  - layer contract and dependency rules
- `docs/fallback_policy_s1.md`
  - fixed stage-1 fallback policy and control parameters
- `docs/coding_style.md`
  - coding and logging conventions
- `docs/file_layout.md`
  - this document

## 5. Governance Rules

- Keep dependency direction consistent with architecture (`apps -> sampler -> physics -> config -> core`).
- Keep runtime parameter interpretation centralized in `src/config/param_mod.f90`.
- Keep state-vector helper APIs centralized in `src/core/utils.f90`.
- Keep runtime initialization in sampler/driver codepaths; do not reintroduce `data/initial_x.dat`.
- Keep build/run command surface centralized in `build/makefile`.
- Avoid duplicating logic across `apps/`; algorithmic logic belongs to lower layers.
