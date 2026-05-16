# F18b.3a ODEX/Flow State Productization

Date: 2026-05-16 JST

Status: implemented locally; behavior-preserving source slice.

Scope:

- `src/physics/solve_flow.f90`
- Stage1/Stage2 flow/HMC/QN product paths that call `flowz`, `flowzr`,
  `flow`, and `intode_with_context`
- Stage2 adaptive preflow initialization through
  `markovchain_mod:adaptive_preflow_to_target`
- focused ODEX foundation contract tests

## Implementation Summary

F18b.3a implements the option-A decision from
`F18B3_ODEX_FLOW_STATE_AND_BEHAVIOR_CORRECTION_DECISION_20260516.md`.

Implemented:

- `intode_diagnostics_context_t` now owns INTODE call/fallback counters, context
  bins, CVODE comparison counters, failure-capture policy, and last-failure
  snapshots.
- `intode_runtime_trace_context_t` now owns per-active-call attribution fields.
  `flow_workspace_t` owns one runtime trace context for product-path flow calls.
- `solve_flow` keeps legacy module fallback contexts for direct callers and
  existing small tests.
- `reset_intode_fallback_stats`, fallback/CVODE readers, and last-failure
  readers accept an optional diagnostics context while preserving old call
  signatures.
- `intode`, `intode_with_context`, `flowz`, `flowzr`, and `flow` accept optional
  diagnostics contexts.
- Stage1/Stage2 product paths thread explicit INTODE diagnostics through direct
  flow initialization, adaptive preflow initialization, local-update HMC,
  Newton residual flow, QN residual and official DFO-LS callback evaluation,
  final flow, reverse probe, reverse gate, and Stage2 swap reflow.
- `tltm_run_context_t%diagnostics%intode` owns per-replica/per-slot diagnostics;
  Stage2 aggregates these contexts before writing public fallback/CVODE summary
  lines.
- The M5 state inventory scanner now recognizes `save` declarations with
  additional attributes such as `save, target`, and the inventory was refreshed.

## Non-Goals

No ODEX controller behavior was changed:

- no `h0` change;
- no h-min / step-size policy change;
- no order-promotion/demotion change;
- no rejection or stability policy change;
- no signed-interval change;
- no final-flow, reverse-gate, or Metropolis behavior change.

No public counter/status/schema semantic correction was made. If future work
finds that a public diagnostic meaning is wrong, it remains a separate
F4/F7/F8 behavior-correction packet.

## Verification

Focused gate run:

```text
make -C build test_odex_foundation_contract
```

Observed checks included:

- legacy direct zero-time and forward/backward ODEX contracts;
- legacy unknown-context failure contract;
- explicit diagnostics context isolation: one diagnostics context records the
  failure while a second context and the module fallback remain zero;
- workspace runtime trace context: rattle step/substep, stage, Newton iter,
  quasi iter, and context code are recorded through the explicit workspace trace;
- solver-assist compatibility policy remains off/zero.

This is sufficient for the intended state-productization slice. Wider M4 and
flow/Jacobian/retained-core guardrails should still be run before this patch is
promoted as a synchronization point for production-comparison.

Promotion gate run:

```text
TLTM_OFFICIAL_DFOLS_PYTHONPATH=$PWD/.venv-dfols/lib/python3.11/site-packages make -C build modernization_guardrails
TLTM_OFFICIAL_DFOLS_PYTHONPATH=$PWD/.venv-dfols/lib/python3.11/site-packages make -C build test_odex_foundation_contract test_retained_core_qn_route_contract test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity
```

Observed:

- M4 modernization guardrails passed, including the post-B RNG reference anchor.
- The post-B RNG anchor initially caught an intentional-state refactor bug:
  Stage2 adaptive preflow was still recording 485 INTODE calls in the module
  fallback diagnostics context. The fix was to thread the existing Stage2
  `run_context` diagnostics through adaptive preflow, not to update the frozen
  reference.

## Current Claim Boundary

F18b.3a closes the current ODEX/flow diagnostics/runtime-trace ownership slice
for Stage1/Stage2 product paths. It does not close:

- `odex_backend` CVODE bridge-global callback state for threaded CVODE
  comparison use;
- constraint-solver aggregate/failure-capture diagnostics state;
- model tape/cache state;
- config mirror ownership;
- full OpenMP/thread-safe productization.

The modernization claim remains endpoint ODEX/GBS with Hairer `IWORK(3)=3`
inside a TLTM-owned endpoint solver policy, not full Hairer ODEX.
