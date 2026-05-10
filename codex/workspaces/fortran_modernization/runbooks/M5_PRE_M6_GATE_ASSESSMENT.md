# M5 Pre-M6 Gate Assessment

Updated: 2026-05-10 JST

Scope: decide whether the current behavior-preserving M5 refactor work is sufficient to move into the M6 modernization reference-dataset product-readiness package, without starting production or reference-package generation.

## Gate Result

M5 can move to M6 planning and product-readiness work.

This is not a claim that all long-term architecture work is finished. It means the remaining M5 items that could affect RNG order, counter timing, public output meaning, or module workspace execution order are either already protected by guardrails or explicitly deferred until a stronger fixed-seed baseline exists.

## Completed M5 Work

Config/env ownership:

- Added centralized runtime env helpers in `src/config/runtime_env_mod.f90`.
- Migrated Stage1/Stage2, evaluation, HMC/QN policy loaders, Markov-chain controls, perf profiling, reversibility probe config, app seed selection, and test-local env reads behind `read_string_env`.
- Preserved env names, defaults, invalid-value behavior, too-long env rejection, legacy alias precedence, seed fallback, and RNG seeding order.
- Added an M4 source guardrail that fails on any direct `get_environment_variable` call outside `runtime_env_mod`.

State/status/result propagation already present in the current source state:

- Failed/unavailable Hamiltonians use explicit unavailable/non-finite status instead of the old `H==0` sentinel.
- HMC proposal and local transition status surfaces distinguish proposal construction failure, reverse-gate rejection, invalid Hamiltonian, invalid `Delta H`, ordinary Metropolis rejection, and output-size mismatch.
- Newton/QN residual flow-status counters and reverse-gate replay-status counters are separated as diagnostic surfaces.
- Legacy Radau/JFNK rescue, non-p28 QN paths, global continuation/restart, post-refine route, positional config parsing, and unused initial-state file compatibility have been removed.

M3/M4 support now in place for M5 refactors:

- Stage2 v1alpha sidecars and Stage3 propagation preserve protocol/provenance metadata without changing v0 output defaults.
- M4 guardrails cover Python compile, diff hygiene, direct-env centralization, Stage2/eval build, ODEX/swap tests, Stage3 dry-run, Stage2 protocol audit, sidecar-on/off smokes, and chunk-merge metadata preservation.
- The state/config ownership inventory is source-backed and regenerated after each slice.

## Explicit Deferrals

RNG ownership is deferred.

- Reason: moving RNG state or seed streams can change draw order and therefore trajectories.
- Required before source migration: fixed RNG-order baseline and explicit user decision on stream semantics.
- Current M6 requirement: document seed provenance and seed policy; do not rewrite RNG state now.

Large module-level `save` workspace migration is deferred.

- Reason: ODEX/QN/HMC/model workspaces and counters can affect trace availability, counter timing, and execution order.
- Required before source migration: fixed-seed route/counter comparison and affected rows from `BASELINE_VERIFICATION_MATRIX.md`.
- Current M6 requirement: document remaining workspace risks and keep local guardrails runnable.

Model/tape cache ownership is deferred.

- Reason: generated model/tape caches should move last unless a non-reentrant compatibility wrapper preserves current serial behavior.
- Current M6 requirement: identify it as a post-dataset-baseline architecture item.

Public schema deletion/renaming is deferred.

- Reason: v0 fields are still compatibility contracts for Stage3/Stage3_4 interpretation.
- Current M6 requirement: introduce or document v1 sidecar/schema contract while preserving v0 readers.

Full replacement of `param_mod` global mirrors is deferred.

- Reason: `simulation_config_t` is the intended source of truth, but many modules still read compatibility globals. Replacing them broadly is a module-boundary and wrapper design migration, not a safe incidental cleanup.
- Current M6 requirement: define the wrapper/config context path and provenance contract; keep existing source behavior unchanged.

## Remaining M6 Inputs

M6 should now assemble:

- A coherent TLTM runner/wrapper implementation path, with current Stage entry points explicitly retained as compatibility tools.
- A versioned output/provenance contract covering git commit, algorithm id, flow policy, QN route, reverse-gate policy, tempering protocol, sweep order, measurement boundary, config, env overrides, seed policy, and writer version.
- A modernization reference-package checklist that starts only after M6 signoff.
- Documentation that clearly states which M5 high-risk architecture items are intentionally deferred until fresh baselines exist.

## Not Allowed Yet

- Do not submit Stage3_4 production jobs or build/register modernization reference packages.
- Do not delete Stage scripts or PBS wrappers.
- Do not rename or remove public output fields.
- Do not move RNG streams, large solver workspaces, or model/tape caches.
- Do not change canonical p28, reverse-gate, ODE assist, final strict-flow, or Metropolis semantics.
