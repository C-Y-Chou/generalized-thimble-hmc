# CV-011 Flow Context Decision Point

Updated: 2026-05-13 JST

## Resolution

User selected option A on 2026-05-13 JST.

Implemented in `CV011_FLOW_CONTEXT_SLICE_20260513.md`:

- `odex_backend` keeps the legacy `ode_rhs(y)` path and adds a context-aware
  `ode_rhs_context(y, context)` / `odex_integrate_endpoint_context(...)` path.
- `solve_flow` endpoint buffers, flow/Jacobian RHS scratch, and ODEX endpoint
  workspace now live in `flow_workspace_t`.
- `flow`, `flowz`, and `flowzr` accept an optional `flow_workspace_t`; legacy
  callers use automatic local workspaces, while run-context paths can pass an
  explicit per-replica/per-slot workspace.
- Stage1 initialization and Stage2 initialization/swap reflow paths use the
  top-level run-context flow workspace.
- `test_odex_flow_jacobian_contract` compares the compatibility path against
  the explicit context path and passed with zero endpoint/Jacobian difference.

Remaining work is no longer this decision point: continue CV-011 by threading
the explicit flow workspace through remaining local-update HMC/QN internals and
then scoping counters/traces/model/config/profile state.

## Why This Is A Decision Point

`solve_flow.f90` still has behavior-bearing module state:

- `intode_yc`, `intode_yf`;
- `flow_vec_y`, `flow_vec_yf`, `flow_vec_z`, `flow_vec_ds`;
- `flow_jac_y`, `flow_jac_yf`, `flow_jac_z`, `flow_jac_ds`;
- `flow_jac_j`, `flow_jac_jprod`;
- `flow_vec_rhs_scale`;
- `intode_odex_workspace`;
- fallback counters, trace context, and last-failure snapshot.

Some arrays can be moved mechanically, but the core thread-safety issue is the
ODEX RHS callback interface:

```fortran
function ode_rhs(y) result(dy)
```

The callback currently has no explicit user/context argument. `solve_flow`
therefore uses module-global work arrays so `rhs_flow_vec` and `rhs_flow_jac`
can see the current flow/Jacobian scratch state during ODEX integration.

## Options

### A. Redesign ODEX Callback Context

Extend the local ODEX backend with a context-aware callback path, then move
flow/Jacobian RHS scratch state into a `flow_context`/workspace owned by
`tltm_run_context_t`.

Consequence:

- product-correct direction for OpenMP/thread-safe TLTM;
- avoids hidden RHS state;
- wider API migration inside `odex_backend`, `solve_flow`, and callers that
  integrate flow;
- requires focused ODEX flow/Jacobian and post-B/M4 verification.

### B. Partial Workspace Move Only

Move only easy `intode` buffers and ODEX endpoint workspace into an explicit
workspace while leaving RHS bridge state module-global.

Consequence:

- smaller patch;
- does not close flow thread-safety;
- risks creating misleading "partial progress" around the hardest state.

### C. Internal Procedure Closure

Use internal RHS procedures that capture local/context workspaces without
changing the ODEX backend public interface.

Consequence:

- avoids ODEX API redesign;
- may rely on compiler trampoline/executable-stack behavior when passing
  internal procedures as callbacks;
- less attractive for cluster portability and productization.

## Recommendation

Choose A. It is the only option that actually removes the hidden RHS state
rather than moving easier buffers around it.

## Former Stop Condition

Stop for user decision before changing the ODEX callback interface. This is a
public internal architecture change even if the intended physics/output
behavior remains unchanged.

This stop condition is cleared by the 2026-05-13 route-A decision.
