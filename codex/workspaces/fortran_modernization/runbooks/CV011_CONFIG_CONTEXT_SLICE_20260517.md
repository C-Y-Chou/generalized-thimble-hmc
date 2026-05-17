# CV-011 Config Context Slice

Updated: 2026-05-17 JST

## Scope

This slice moves the behavior-bearing Stage1/Stage2 local-update integrator controls onto the existing top-level TLTM run context without changing the public config format or physics parameters.

Implemented source changes:

- `tltm_run_context_t%config` now owns a `simulation_config_t` snapshot plus a `loaded` flag.
- Stage1 and Stage2 seed each per-replica/per-slot run context from the already validated `param_mod%config` after `read_parameters()`.
- Stage1 local Metropolis updates read `trajectory_length` and `integration_steps` from the run-context config snapshot.
- Stage2 adaptive preflow and local Metropolis updates read `trajectory_length` and `integration_steps` from the run-context config snapshot.
- If a legacy caller has not loaded a config context, the resolver falls back to the existing module-level `config` values.

This is intentionally a narrow productization slice. It does not replace `param_mod` as the parser/validator/global mirror, does not change the key-value parameter schema, does not change summary/manifest fields, and does not alter integrator values.

## Claim Boundary

Closed for this slice:

- Active Stage1/Stage2 local-update product paths no longer need to dereference `param_mod%config` at each HMC update/preflow callsite for the two integrator controls.
- The run-context config slot is now real state rather than a placeholder, giving later wrapper/product code a stable place to carry validated config snapshots.
- Current output semantics are preserved because snapshots are seeded from the same validated global config before any slot/replica initialization.

Still open after this slice:

- `param_mod%config` still owns parsing, validation, defaults, and most summary/manifest/provenance reads.
- Final product config schema, compatibility conventions, and public field cleanup remain open.
- Constraint-solver aggregate/failure-capture diagnostics state, model tape/cache state, and any threaded CVODE comparison callback state remain CV-011 work.

## Verification

Commands run locally:

```text
make -C build ../bin/run_tltm_stage1 ../bin/run_tltm_stage2
make -C build test_tltm_swap_kernel_contract
make -C build modernization_guardrails
```

Results:

- Stage1 and Stage2 binaries built successfully.
- `test_tltm_swap_kernel_contract` passed.
- M4 modernization guardrails passed, including script evidence audit, F20 precision readiness audit, retained ODEX/swap tests, Stage3 sidecar dry runs, F14 pre-redo gate, official-line kernel correctness gate, post-B RNG reference anchor, Stage2 RNG v2 deterministic anchor, and chunk-merge metadata checks.

## Next Action

Continue CV-011 productization with the remaining behavior/state boundaries:

- constraint aggregate/reverse-gate/failure-capture diagnostics ownership,
- model tape/cache state ownership,
- final config/product schema and wrapper-facing API cleanup,
- CVODE callback bridge state only if threaded CVODE comparison becomes product scope.
