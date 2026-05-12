# CV-011 Flow Context Decision Point

Updated: 2026-05-12 JST

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

## Current Stop Condition

Stop for user decision before changing the ODEX callback interface. This is a
public internal architecture change even if the intended physics/output
behavior remains unchanged.
