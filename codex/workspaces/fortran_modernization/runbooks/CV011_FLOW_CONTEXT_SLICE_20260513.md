# CV-011 Flow Context Slice

Updated: 2026-05-13 JST

## Decision

The user selected flow/ODEX option A: redesign the local ODEX callback context
path, then migrate flow/Jacobian RHS scratch into an explicit workspace owned
by the TLTM run context.

## Implementation

- Added `ode_rhs_context(y, context)` and
  `odex_integrate_endpoint_context(...)` to `src/physics/odex_backend.f90`.
- Preserved the legacy `ode_rhs(y)` / `odex_integrate_endpoint(...)` API for
  compatibility callers.
- Added `flow_workspace_t` to `src/physics/solve_flow.f90`.
- Moved `intode` endpoint buffers, flow/Jacobian RHS scratch arrays,
  `flow_vec_rhs_scale`, and the ODEX endpoint workspace into
  `flow_workspace_t`.
- Added optional workspace arguments to `flow`, `flowz`, and `flowzr`.
- Added context-aware RHS callbacks for vector flow and Jacobian flow.
- Added `release_flow_workspace(...)` and wired it into
  `release_tltm_run_context(...)`.
- Threaded per-replica/per-slot flow workspaces through Stage1 initialization
  and Stage2 initialization/swap reflow.
- Updated the Stage2 swap kernel contract so its direct swap call uses
  `tltm_run_context_t`, matching the production Stage2 call shape.

## Behavior Boundary

This is a state-ownership refactor only.

No intended change to:

- flow equations;
- ODEX step-size/order policy;
- solver-assist default-off policy;
- QN route or residual definition;
- reverse-gate policy;
- Metropolis acceptance;
- route-B RNG stream contract;
- output schema.

The explicit context path was checked against the compatibility path in
`test_odex_flow_jacobian_contract`; endpoint and Jacobian differences were both
zero in the focused check.

## Verification

Passed:

```bash
make -C build FC=gfortran LDFLAGS= test_odex_flow_jacobian_contract test_odex_solver test_odex_foundation_contract
make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2
make -C build FC=gfortran LDFLAGS= test_tltm_swap_kernel_contract
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Full M4 result: all guardrails passed; artifacts in `output/tests/m4_guardrails`.

## Still Open

- Local-update HMC/QN internals are covered by
  `CV011_HMC_QN_FLOW_CONTEXT_SLICE_20260513.md`.
- Official DFO-LS backend callback context still relies on module-level
  `qn_official_*` state; see
  `CV011_QN_OFFICIAL_CALLBACK_CONTEXT_DECISION_POINT_20260513.md`.
- `solve_flow` fallback counters, trace context, and last-failure snapshot are
  intentionally not moved in this slice; they need a later diagnostics/status
  context decision.
- Other CV-011 hidden-state categories remain: QN traces/capture/backend
  callback state, constraint/reverse-gate counters and capture files, model
  tape/cache state, config mirror, and profiling state.

## Production Boundary

Production redo is separate and belongs to `tltm_production_comparison`.
This slice did not synchronize, stage, or modify production-comparison work.
