# CV-011 Profile Context Slice

Updated: 2026-05-13 JST

## Scope

This slice handles the profiling-counter part of CV-011.  Profiling is a
diagnostic/product-observability surface, not a physics decision surface, but it
still used module-level `save` arrays that prevented clean per-run ownership.

## Implemented Slice

- Added `perf_profile_context_t` in `perf_profile`.
- Moved profiler accumulators, call counters, enabled flag, and initialization
  flag behind a context object.
- Kept legacy direct-call wrappers through `module_perf_context`, so existing
  `perf_tic`, `perf_toc`, `perf_reset`, and `perf_report` call sites continue
  to work unchanged.
- Added optional context arguments to the profiler API, enabling future
  per-run/per-thread profiling without changing the hot physics route today.
- Added `release_perf_profile_context`.
- Replaced the placeholder `tltm_profile_context_t%reserved` field with an
  owned `perf_profile_context_t` under `tltm_run_context_t`.
- Added `test_perf_profile_context_contract` and included it in the build and
  M4 guardrail suite.

## Behavior Boundary

This is a state ownership/productization slice only.

No intended change to:

- TLTM physics equations;
- flow, Newton, QN, RATTLE, reverse-gate, or Metropolis decisions;
- route-B RNG stream contract;
- public output schema;
- default profiling policy.

With `PERF_PROFILE` unset, profiling remains disabled by default.  Existing
call sites still use the legacy wrapper context until a later wrapper/product
slice chooses to thread `run_context%profile%profiler` into the hot path.

## Verification

Passed:

```sh
make -C build test_perf_profile_context_contract
```

Passed:

```sh
make -C build ../bin/run_tltm_stage2
```

Passed:

```sh
git diff --check
```

## Remaining Open Boundary

This removes profiling counters from the remaining CV-011 hidden-state list as a
source-level ownership problem.  CV-011 remains open for:

- solver and reverse-gate diagnostics counters outside the prior HMC/QN slices;
- flow/ODEX counters, runtime traces, and last-failure snapshots;
- model tape/cache ownership;
- `param_mod` config mirror replacement or scoped product boundary;
- reversibility/progress probe config and counters;
- deterministic serial/reentrant checks across the migrated contexts.

Production redo remains external to modernization and belongs to
`tltm_production_comparison`.
