# CV-011 QN Official Callback Context Decision Point

Updated: 2026-05-13 JST

## Resolution

User selected option A on 2026-05-13 JST.

Implemented in `CV011_QN_OFFICIAL_CALLBACK_CONTEXT_SLICE_20260513.md`:

- Added a per-attempt `qn_official_callback_context_t` carried through the C
  bridge `ctx` pointer.
- The Fortran official DFO-LS callback recovers `xt`, `z`, `del_z`, `jac`, and
  the active `flow_workspace_t` from `ctx`.
- Removed the active-route dependency on module-level `qn_official_*` callback
  context arrays and active flag.
- Official QN route, retained-core, post-B RNG anchor, and full M4 verification
  passed.

Remaining work is no longer this decision point: QN trace/capture/eval context
state is the next CV-011 decision point.

## Why This Is A Decision Point

The active official DFO-LS backend calls a C bridge. The bridge already accepts
a `ctx` pointer and passes it back to the objective callback, but the current
Fortran callback still reads module-level `qn_official_*` state for `xt`, `z`,
`del_z`, `jac`, and callback activation.

The previous HMC/QN flow-context slice lets that callback use the active
`flow_workspace_t` for flow evaluations, but it does not remove the official
backend callback context itself from module state.

## Options

### A. Use The C Callback `ctx` Pointer

Create a per-attempt callback context, pass it through the C bridge `ctx`
argument, and have the Fortran callback recover the context from `ctx` instead
of using module-level `qn_official_*` state.

Consequence:

- product-correct direction for OpenMP/thread-safe official DFO-LS backend;
- removes a central callback-state blocker from the active route;
- touches Fortran/C interop and official DFO-LS callback plumbing;
- requires official QN route, post-B, and M4 verification.

### B. Defer Official Callback State

Record `qn_official_*` callback state as an explicit temporary product boundary
and continue lower-risk counters/model/config/profile migrations first.

Consequence:

- faster next patch;
- leaves a central OpenMP/thread-safe productization blocker open;
- cannot honestly claim full thread-safe official-backend productization.

### C. Use Internal QN For Thread-Safety Work

Temporarily route thread-safety validation through the internal QN backend and
leave official DFO-LS callback state untouched.

Consequence:

- avoids C callback redesign now;
- conflicts with the selected official DFO-LS default backend direction;
- weaker product evidence for the actual active route.

## Recommendation

Choose A. It uses an existing C bridge feature (`ctx`) and addresses the active
official backend rather than proving thread-safety on a non-default route.

## Former Stop Condition

Stop for user decision before rewriting the official DFO-LS callback context.
This is a callback ABI/context design change even though the intended
physics/output behavior remains unchanged.

This stop condition is cleared by the 2026-05-13 route-A decision.
