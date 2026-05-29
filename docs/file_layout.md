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
  - default Stephanov `n=2` runtime parameter file (`key=value` only)
- `data/parameters_stephanov_n2_smoke.dat`
  - tiny local Stephanov smoke config for build/flow/observable-stream checks
- `data/parameters_stephanov_n6_mu06_t0.dat`
  - selected Stephanov working-point preset (`n=6, m=0.004, mu=0.6, tau=0, t=0`)
- `data/parameters_stephanov_n6_mu06_t1e6_eps008_nstep2.dat`
  - selected local-development nofb protocol preset (`epsilon=0.08, nstep=2, L=0.16, t=1e-6`)
- `model_specs/`
  - inert staging area for future model definitions and validation plans; not compiled

## 3. Generated Runtime Outputs

- `bin/`
  - compiled executables and some generated runtime plots/logs (convenience artifacts; rebuild before production)
- `output/`
  - chain histories and observable output files
- `output/stephanov_checkpoint_banks/`
  - local/generated Stephanov `t=0` checkpoint-bank artifacts; ignored by git
    and rebuilt through the runbook command when needed
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
- `codex/workspaces/fortran_modernization/tasks/scripts/build_stephanov_t0_checkpoint_bank.py`
  - cluster-side helper that runs Stage2 `t=0` chains and consolidates
    physical `x` checkpoints into a restart bank
- `codex/workspaces/fortran_modernization/tasks/scripts/filter_x_bank_by_flow_diagnostics_20260530.py`
  - filters a checkpoint bank to records prevalidated by dense-flow diagnostics
    for WV-HMC bank initialization
- `codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py`
  - local development helper that scans Stephanov `n=6` bank-started nofb HMC
    protocol candidates with fixed adaptive-preflow initialization
- `codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py`
  - local development helper that runs Stephanov `n=6` bank-started flow-time
    sign-problem ladders and summarizes phase/observable diagnostics

## 5. Governance Rules

- Keep dependency direction consistent with architecture (`apps -> sampler -> physics -> config -> core`).
- Keep runtime parameter interpretation centralized in `src/config/param_mod.f90`.
- Keep state-vector helper APIs centralized in `src/core/utils.f90`.
- Keep runtime initialization in sampler/driver codepaths; do not reintroduce `data/initial_x.dat`.
- Keep build/run command surface centralized in `build/makefile`.
- Avoid duplicating logic across `apps/`; algorithmic logic belongs to lower layers.
