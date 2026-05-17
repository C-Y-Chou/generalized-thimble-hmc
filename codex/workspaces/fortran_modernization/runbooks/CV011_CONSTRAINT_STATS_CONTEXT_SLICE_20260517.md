# CV-011 Constraint Stats Context Slice

Updated: 2026-05-17 JST

## Scope

This slice gives the constraint-solver aggregate diagnostics a real context object while preserving the current serial aggregate/capture output contract.

Implemented source changes:

- `constraint_solver_stats_context_t` now owns the aggregate Newton/QN/failure counters, reverse-gate path counters, failure-capture policy, failure-capture file handles, runtime sample indices, and failure-meta delta state.
- The existing `constraint_solver_stats_mod` record/get/reset API now operates through a lazily bound context alias.
- Legacy/direct callers still bind to the module fallback automatically.
- Stage1 and Stage2 bind a run-owned `constraint_solver_stats_context_t` before `reset_constraint_solver_stats()`, so their product paths no longer store this state only as scattered module-level scalar `SAVE` variables.
- `release_constraint_solver_stats_context()` closes any active failure-capture files and restores the module fallback binding.
- `test_retained_core_rattle_rg_contract` now checks that two explicit constraint-stats contexts retain independent counters when rebound.

This is intentionally not the final per-thread merge/capture schema. It is the conservative run-level context slice: current aggregate totals, failure-capture filenames, sample ordering, and summary fields stay unchanged.

## Claim Boundary

Closed for this slice:

- Stage1/Stage2 can own one run-level constraint-stats context for current serial product paths.
- Constraint aggregate state is no longer represented as dozens of independent module `SAVE` scalars.
- Context rebound isolation is proof-tested for aggregate counters.
- Existing public summaries and failure-capture file contracts are preserved.

Still open after this slice:

- The alias bridge is a transitional compatibility layer, not the final explicit per-call/per-thread API.
- True threaded product scope still needs a separate merge/capture-schema decision: per-thread/per-slot counters, deterministic merge order, and failure-capture file namespace/order.
- Model tape/cache state, final config/product schema and wrapper API cleanup, and CVODE callback bridge state remain separate CV-011/productization work.

## Verification

Commands run locally:

```text
make -C build ../bin/run_tltm_stage1 ../bin/run_tltm_stage2
make -C build test_retained_core_rattle_rg_contract
make -C build test_retained_core_newton_contract
make -C build test_tltm_swap_kernel_contract
make -C build modernization_guardrails
```

Results:

- Stage1/Stage2 binaries built successfully.
- Retained-core RATTLE/RG contract passed, including `constraint_stats_context_isolation`.
- Retained-core Newton contract passed.
- TLTM swap-kernel contract passed.
- M4 modernization guardrails passed.

## Next Action

Continue CV-011/productization with:

- model tape/cache state ownership,
- final config/product schema and wrapper API cleanup,
- later explicit per-thread constraint-stats merge/capture schema only when the threaded product path is implemented,
- CVODE callback bridge state only if threaded CVODE comparison becomes product scope.
