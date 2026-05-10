# M3 Architecture Contract

Updated: 2026-05-10 JST
Scope: planning contract for the next modernization phase after the core numerical canonicalization and behavior-neutral infrastructure cleanup.

## Purpose

This document turns the current modernization decision point into an executable architecture contract.

The next phase must not begin with broad source refactors. It must first define the external product contract and the internal state/config ownership contract, because the remaining work touches public output fields, stage compatibility, hidden module state, RNG ownership, and future OpenMP/reentrant execution.

## Current Canonical Algorithm Boundary

The architecture contract starts from the current canonical numerical policy:

- Production p28 route: Newton first, then p28 QN BTN/backflow rescue residual, then reverse gate, then Metropolis.
- QN route: DFO-LS-style solve on `evaluate_constraint_residual`, with non-p28 DFO-GN/Broyden/global-continuation/post-refine paths removed from active source.
- Flow policy: ODEX primary integration plus solver-internal ODE assist only for NT/QN residual evaluation.
- Final physical proposal/live-state construction: strict `flow(...)` only, accepting strict ODEX success or zero-time no-op; solver assist must not finalize proposals.
- Reverse gate: permanent production algorithm requirement, not a diagnostic option.
- Output compatibility: current Stage-facing output schema remains `v0 compatibility` until a versioned replacement exists.
- Superseding decision, 2026-05-10 JST: existing dataset/output-timing compatibility is no longer a governing constraint for Stage2 tempering modernization. Datasets will be regenerated after the canonical protocol change; compatibility is preserved only where it does not conflict with the selected replica-exchange protocol and current schema/audit clarity.

## Non-Negotiable Rules

- No modernization step may silently change the physics, canonical p28 route, ODE assist boundary, reverse-gate definition, Metropolis rule, RNG order, or live-chain update semantics.
- No public output field may be removed or renamed until an explicit schema version exists and compatibility readers are updated.
- No stage-specific script may be deleted only because it is ugly; deletion waits for wrapper compatibility or an explicit user decision.
- No module-level `save` state migration may start as a broad rewrite. It must be split by ownership class and protected by affected baselines.
- Generated source must be changed through the generator, then regenerated.
- Any source patch that changes config loading, output schema, state ownership, RNG, counters, or proposal/control flow must state its comparison gate before implementation.

## External Product Contract

Long-term target: a unified TLTM wrapper/runner with config-driven modes and versioned output schema.

Working interface model:

- `production`: canonical p28 TLTM sampling path.
- `diagnostic`: explicit probes, failure capture, route/status accounting, and local audits.
- `regression`: fixed-seed, low-volume comparisons for route/counter/schema checks.
- `benchmark`: performance-oriented runs with explicit benchmark metadata.

Compatibility policy:

- Stage1/Stage2/Stage3/Stage3_4 executables and scripts remain compatibility entry points until the unified wrapper reproduces their required workflows.
- Existing Stage-facing output is `schema v0`.
- New wrapper output should introduce `schema v1` rather than mutating v0 in place.
- v0 readers/scripts may continue to exist as compatibility adapters after v1 appears.

Open naming decision:

- `run_tltm` is the current working name for the unified executable, but the final public name remains a user decision.

## Output Schema Contract

Schema v0:

- Current output names remain stable for compatibility.
- Legacy labels such as `final_resort_*`, `final_resort_budget_*`, `projection_failure_count`, `proposal_failed`, and global-filter compatibility columns may remain even when their internal meanings are more precise.
- New observability fields may be appended only if existing positional readers remain safe or are updated.

Schema v1:

- Must include an explicit schema version in machine-readable summaries.
- Must include provenance: git commit, canonical algorithm id, config digest or config snapshot, ODEX policy, QN route id, reverse-gate policy, RNG/seed policy, and output writer version.
- Should rename solver-assist fields away from legacy `final_resort` terminology.
- Should split proposal outcomes into explicit categories: proposal construction failure, reverse-gate rejection, invalid Hamiltonian, invalid `Delta H`, ordinary Metropolis rejection, and acceptance.
- Should preserve an adapter or migration map from v0 names to v1 names.

Schema migration rule:

- First implement v1 alongside v0.
- Then update analysis/merge/evaluation scripts to read by schema version.
- Only after that may v0 compatibility fields be deprecated or removed by explicit user decision.

## Typed Config Contract

Target source of truth:

- `simulation_config_t` becomes the only authoritative typed config object.
- Legacy globals in `param_mod` become compatibility mirrors during migration.
- New code should prefer explicit config arguments or context ownership over reading globals.

Runtime override policy:

- File config, environment overrides, and research toggles must be represented in run provenance.
- Existing env names remain stable until wrapper/schema versioning provides a replacement path.
- New env toggles should not be introduced casually; prefer typed config fields plus manifest reporting.

Migration rule:

- First classify config fields by owner: physics constants, sampler controls, solver policy, diagnostics, output, and workflow orchestration.
- Then migrate callers one module boundary at a time.
- During migration, serial output and route/counter behavior must remain unchanged unless a versioned contract says otherwise.

## Explicit Context And Workspace Contract

Long-term target: in-process parallel/OpenMP-capable execution through explicit per-run/per-replica state.

Context ownership classes:

- `tltm_run_context`: top-level config, provenance, output handles, and run mode.
- `rng_context`: deterministic random stream state and seed provenance.
- `flow_workspace`: ODEX work arrays, flow scratch buffers, failure/status diagnostics.
- `constraint_solver_workspace`: Newton/QN residual scratch, traces, solver-assist budgets, evaluation statuses.
- `hmc_workspace`: RATTLE/HMC proposal buffers, projection buffers, reverse-gate replay workspace.
- `diagnostics_context`: counters, capture files, route/status summaries, suppression state.
- `model_context`: generated model/tape cache strategy, if reentrant model evaluation becomes required.

Migration order:

- Start with diagnostics and config ownership because they are behavior-observable but easier to compare.
- Then move solver/flow workspaces with exact fixed-seed route/counter comparison.
- Move RNG context only after a deterministic RNG-order baseline exists.
- Move model/tape global state last unless a smaller non-reentrant wrapper preserves current serial behavior.

Compatibility rule:

- Existing public subroutines may keep compatibility wrappers.
- Internal implementations should progressively gain context/workspace arguments.
- Compatibility wrappers may allocate or access a singleton context only as a transition layer.

## Regression Gates

Planning/doc-only changes:

- No numerical tests required, but docs must not contradict current source state.

Output/schema changes:

- Build and smoke tests.
- Parser/merge/evaluation readback tests.
- v0 compatibility check for existing expected columns.
- v1 schema sample output and migration map check.

Typed config changes:

- Build and smoke tests.
- Missing/invalid env default-preservation tests.
- Explicit override tests.
- Fixed small-run summary comparison for config echo/provenance.

Context/workspace changes:

- Clean rebuild.
- `test_odex_solver`, `test1`, `test2` where affected.
- Tiny Stage1/Stage2 smoke.
- Fixed-seed route/counter comparison before and after.
- RNG-order comparison if RNG state or draw locations are touched.

Numerical kernel or proposal boundary changes:

- Must use the affected rows in `BASELINE_VERIFICATION_MATRIX.md`.
- Must preserve or explicitly justify changes to physical observables, route counters, failure categories, and accepted proposal semantics.

## Stop Gates

Stop for user confirmation before:

- Renaming or removing any public output column.
- Removing a compatibility env alias.
- Deleting stage workflow scripts or PBS wrappers.
- Choosing the final unified wrapper executable name.
- Moving RNG ownership or changing seed/stream semantics.
- Changing the canonical p28 route, reverse-gate definition, ODE assist boundary, or final-flow strictness.
- Replacing large module-level `save` state with a new context in a way that can alter counter timing, trace availability, or execution order.

## Recommended First Implementation Sequence

M3a: design-only contract.

- Add this architecture contract.
- Update planning index/status/progress logs.
- No Fortran source changes.

M3b: schema design draft.

- Draft `v0` column inventory and proposed `v1` schema/migration map.
- No output writer changes yet.

M3c: config ownership map.

- Inventory `simulation_config_t`, legacy `param_mod` globals, env overrides, and workflow-specific knobs.
- Mark each as physics, sampler, solver policy, diagnostics, output, or workflow.

M3d: module `save` state inventory.

- Build a source-backed inventory grouped by owner and migration risk.
- Select the first safe context migration candidate.

M3e: first code patch.

- Only after M3b-M3d identify a narrow, behavior-preserving slice with a concrete regression gate.

## Current Recommendation

Do not start by moving module `save` state or renaming legacy output columns.

The safest next source-facing path is:

- freeze v0 compatibility behavior,
- design v1 schema beside it,
- classify typed config ownership,
- inventory context/workspace state,
- then implement one narrow compatibility-preserving migration slice at a time.
