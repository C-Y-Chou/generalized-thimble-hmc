# Cross-Cutting Infrastructure Audit

Updated: 2026-05-10
Scope: repo-wide infrastructure outside the five core numerical algorithm audits. Live inventory.

## Purpose

The five core numerical audits are safety gates, but TLTM modernization is repo-wide. This audit tracks infrastructure that can affect reproducibility, output stability, maintainability, wrapper design, and OpenMP/reentrancy.

## Initial Inventory

### Utils / state mapping

Primary file:

- `/home/cychou/TLTM/src/core/utils.f90`

Responsibilities observed:

- real/complex matrix and vector mapping.
- `x` state layout helpers: flow time and seed extraction/setters.
- history I/O helpers.
- determinant/log determinant helper.
- basic math helpers such as factorial and outer product.

Risks:

- State layout convention is global and implicit.
- Mapping helpers are behavior-sensitive for flow/RATTLE/QN residuals.
- History I/O helpers are still mixed with math/state helpers.
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
- `/home/cychou/TLTM/src/config/runtime_env_mod.f90`

Responsibilities observed:

- config types/defaults.
- validation.
- legacy global synchronization.
- key-value parameter reader.
- shared Stage1/Stage2 runtime env parser helpers for int/real/logical/list values.
- environment/config interaction through downstream scripts.
- Historical positional `parameters.dat` support has been deleted; config files must use `key=value`.

Risks:

- Legacy globals couple old and new APIs.
- Environment override policy is still distributed across modules; only basic Stage parser mechanics are centralized so far.
- Missing/invalid env default-preservation semantics are behavior-bearing and must remain covered by smoke tests.
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

## Current Safe Actions

Safe now:

- Keep this inventory updated.
- Build a module responsibility map.
- Identify all module-level `save` state.
- Continue behavior-neutral parser/helper consolidation when caller defaults, env names, and output schemas are preserved.
- Draft RNG/config/output schema requirements.
- Draft wrapper compatibility requirements.

Decision-gated:

- Moving RNG state.
- Changing config semantics beyond the completed key-value-only cleanup.
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

## Diagnostics / Accounting Context

Status: modernization target.

The current counter/capture/switch design is scattered across global ODE counters, quasi-Newton traces, reverse-gate replay/probe accounting, rescue/failure counters, Stage2 accepted-route census, and output/reporting code. This makes benchmark interpretation fragile because forward proposal work can be mixed with replay/probe/debug/failure work.

Modernization target:

- Introduce a typed diagnostics/accounting context instead of scattered global counters and suppression flags.
- Classify work by role: forward proposal, reverse-gate replay, debug/probe, rescue attempt, failed proposal, accepted proposal, rejected/stay-put event, and output-summary aggregation.
- Keep output schema versioned so historical Stage3_4 comparisons remain interpretable while publishable counters become explicit.
