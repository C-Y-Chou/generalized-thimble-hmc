# CV-011 Remaining State Decision Point

Updated: 2026-05-12 JST

Scope: stop point after route-B RNG streams, post-B reference anchor, and the
first explicit scratch-workspace migrations.

## Completed Before This Point

- Route-B RNG streams:
  - per-replica/per-slot local-update RNG state;
  - separate Stage2 swap RNG stream;
  - explicit `mt95_state_t`, including Gaussian spare state.
- Post-B deterministic reference anchor:
  - `POST_B_RNG_REFERENCE_ANCHOR_V1.json`;
  - M4 includes the anchor.
- Scratch workspace migrations:
  - `hmc_kernels:decompose2` -> `decompose2_workspace_t`;
  - `quasi_newton_linear_solver_mod` -> `qn_linear_workspace_t`;
  - `hmc_constraints:solve_constraint_newton` -> `newton_constraint_workspace_t`;
  - active RATTLE core path owns these workspaces through `rattle_step_workspace_t`.

## Remaining Hidden State Classes

| Class | Examples | Product issue |
| --- | --- | --- |
| Flow/ODEX workspaces and counters | `solve_flow.f90` ODEX buffers, `intode_odex_workspace`, rescue/status counters, trace context, last-failure snapshot | Needs a per-run/per-thread flow context or an explicit scope decision for diagnostics/counters. |
| QN residual, trace, capture, and official-backend state | `quasi_newton_solver.f90` residual buffers, trace arrays, watchdog/capture files, backend preset cache, official DFO-LS callback context | Official callback context and active QN trace/eval/watchdog context are implemented. Remaining decision: capture file/counter/policy ownership via a driver-owned diagnostics sink, per-replica files, or legacy serial boundary. |
| Constraint/reverse-gate counters and capture files | `constraint_solver_stats.f90` counters, suppression depth, fail-capture units/files | Needs a run diagnostics object or explicit thread-safe aggregation policy. |
| Stage2 diagnostic file handles | `tltm_stage2_driver.f90` RG reject audit and local-transition audit units/files | Needs per-run audit handles rather than module globals. |
| Model tape/cache state | `model_generated.f90`, `model_tape_ad.f90` tape/cache arrays and current point | Needs either per-thread/per-context tape ownership or a product decision to avoid sharing this cache across OpenMP workers. |
| Runtime config mirror and profiling | `param_mod.f90` global config mirror, `perf_profile.f90` profiler accumulators | Config should move toward explicit immutable run config; profiler can be per-run or explicitly non-product/global diagnostic. |

## Decision Result

The next implementation was no longer just replacing scratch arrays. It defined
the product contract for diagnostics and context ownership. The key decision was:

```text
Should CV-011 proceed by introducing one top-level TLTM run context that owns
flow/QN/diagnostic/model/config/profiling state, or should we first migrate
module-by-module contexts and stitch them into the wrapper later?
```

User selected A: introduce one top-level TLTM run context as the product
direction, then migrate sub-contexts incrementally.

## Implemented First A Slice

- `tltm_run_context_mod` now defines `tltm_run_context_t`.
- `tltm_hmc_context_t` owns HMC proposal, reverse-probe, and warmup
  `rattle_step_workspace_t` instances.
- Stage1 owns one run context per replica.
- Stage2 owns one run context per slot.
- `metropolis_step`, `integrate_hmc_proposal`, and `integrate_hmc_warmup` accept
  optional HMC contexts while preserving legacy automatic-workspace callers.

See `CV011_TOP_LEVEL_RUN_CONTEXT_SLICE_20260512.md`.

## Recommendation Rationale

Use one top-level TLTM run context as the product direction, but implement it
incrementally:

1. Define product context types for flow, QN, diagnostics, config, model/tape,
   and profiling.
2. Thread the relevant sub-contexts through Stage1/Stage2 local-update paths.
3. Keep compatibility wrappers for legacy tests and scripts until the unified
   wrapper/product interface is ready.
4. Treat counters and diagnostic file handles as per-run context fields, with
   any cross-thread aggregation done explicitly at cycle/run boundaries.

This is the cleanest route to real OpenMP/thread-safe productization, but it is
a wider API migration than the completed scratch-workspace slices.

## Stop Condition Closed

The decision stop is closed by user confirmation. Continue source migration
inside the modernization tree until a slice would change physics, output schema
semantics, public run controls, or the production/modernization tree boundary.
