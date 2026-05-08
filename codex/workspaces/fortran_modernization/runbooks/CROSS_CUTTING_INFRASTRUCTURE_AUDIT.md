# Cross-Cutting Infrastructure Audit

Updated: 2026-05-08
Scope: repo-wide infrastructure outside the five core numerical algorithm audits. Planning-only inventory.

## Purpose

The five core numerical audits are safety gates, but TLTM modernization is repo-wide. This audit tracks infrastructure that can affect reproducibility, output stability, maintainability, wrapper design, and OpenMP/reentrancy.

## Initial Inventory

### Utils / state mapping

Primary file:

- `/home/cychou/TLTM/src/core/utils.f90`

Responsibilities observed:

- real/complex matrix and vector mapping.
- `x` state layout helpers: flow time and seed extraction/setters.
- initial condition/state/history I/O helpers.
- determinant/log determinant helper.
- basic math helpers such as factorial and outer product.

Risks:

- State layout convention is global and implicit.
- Mapping helpers are behavior-sensitive for flow/RATTLE/QN residuals.
- I/O helpers mixed with math/state helpers.
- Any cleanup can affect residual sign/order or history compatibility.

### RNG / seed policy

Primary file:

- `/home/cychou/TLTM/src/core/mt95.f90`

Known users include HMC momentum, Metropolis accept/reject, Stage2 slot seeds, swap accept/reject, tests, and scripts.

Risks:

- Module-global RNG state is not OpenMP-safe.
- RNG draw order is part of behavior.
- Future wrapper needs per-run/per-replica deterministic streams.
- Seed provenance must be captured in manifests.

### Config / parameter system

Primary file:

- `/home/cychou/TLTM/src/config/param_mod.f90`

Responsibilities observed:

- config types/defaults.
- validation.
- legacy global synchronization.
- key-value and legacy parameter readers.
- environment/config interaction through downstream scripts.

Risks:

- Legacy globals couple old and new APIs.
- Environment overrides are distributed across modules, not centralized.
- Wrapper design needs one coherent config model and manifest provenance.

### Performance, counters, diagnostics

Primary files:

- `/home/cychou/TLTM/src/core/perf_profile.f90`
- `/home/cychou/TLTM/src/sampler/constraint_solver_stats.f90`
- `/home/cychou/TLTM/src/physics/solve_flow.f90`
- `/home/cychou/TLTM/src/sampler/tltm_stage2_driver.f90`

Risks:

- Counters are used as scientific/diagnostic evidence, not mere logs.
- Module-level counters are not reentrant.
- Reverse-gate replay counter suppression is behavior-critical.
- Summary output fields are Stage3_4 contracts.

### I/O, histories, and evaluation

Primary files:

- `/home/cychou/TLTM/src/sampler/markovchain_io.f90`
- `/home/cychou/TLTM/src/apps/evaluate_expectations.f90`
- Stage2 history writers in `/home/cychou/TLTM/src/sampler/tltm_stage2_driver.f90`

Risks:

- Binary history schema is implicit.
- Evaluation contains substantial analysis/statistics logic and output schema logic.
- Future wrapper needs versioned output schema.
- Current stage history timing is transitional and must be documented until wrapper replacement.

### Scripts / orchestration

Primary areas:

- `/home/cychou/TLTM/scripts/`
- `/home/cychou/TLTM/codex/tasks/`
- Stage3_4 PBS scripts under `codex/workspaces/stage3_4/tasks/pbs/`

Risks:

- Scripts encode production conventions, environment knobs, output paths, and report schemas.
- Many scripts are experiment-specific and should become compatibility/internal layers after wrapper exists.
- Merge/report scripts are part of current Stage3_4 output contract.

### Build/test/tooling

Primary areas:

- `tests/test_action_derivatives.f90`
- `tests/test_hamiltonian_conservation.f90`
- benchmark/check scripts under `scripts/`

Risks:

- Existing tests are useful but not sufficient as official modernization baselines.
- Build modes, compiler flags, and dependencies need product-grade documentation.
- Future CI/reproducibility workflow must separate fast tests from production campaigns.

## Pre-Stage3_4 Actions

Safe now:

- Keep this inventory updated.
- Build a module responsibility map.
- Identify all module-level `save` state.
- Draft RNG/config/output schema requirements.
- Draft wrapper compatibility requirements.

Blocked until after Stage3_4/TLTM judgment and characterization baseline:

- Moving RNG state.
- Changing config semantics.
- Changing output/history schema.
- Rewriting scripts into wrapper entry points.
- Refactoring `utils` mapping helpers.

## Future Deliverables

- `SAVE_STATE_INVENTORY.md`
- `RNG_AND_SEED_POLICY.md`
- `CONFIG_AND_MANIFEST_DESIGN.md`
- `OUTPUT_SCHEMA_DESIGN.md`
- `DIAGNOSTICS_AND_COUNTER_CONTRACT.md`
- `WRAPPER_INTERFACE_DESIGN.md`
