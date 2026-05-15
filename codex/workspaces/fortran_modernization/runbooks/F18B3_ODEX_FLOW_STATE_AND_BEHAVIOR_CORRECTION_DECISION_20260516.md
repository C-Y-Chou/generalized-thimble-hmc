# F18b.3 ODEX/Flow State And Behavior-Correction Decision

Date: 2026-05-16 JST
Scope: `src/physics/solve_flow.f90`, `src/physics/odex_backend.f90`, and the
Stage1/Stage2 run-context path that calls `flowz`, `flowzr`, `flow`, and
`intode*`.
Status: decision packet for the next source slice; no source behavior change
authorized by this document.

## Decision Summary

F18b.3 should productize ODEX/flow diagnostic state before any ODEX controller
behavior patch.

The next source-facing patch is not a numerical-controller correction.  It is a
state-ownership correction:

```text
Move INTODE/ODEX aggregate counters, CVODE comparison counters, runtime trace
state, and last-failure snapshots into explicit TLTM contexts while preserving
the current endpoint solver kernel, status codes, and public summary values.
```

The behavior-correction rule is:

```text
Do not silently "fix" counters, status meanings, ODEX controller choices, final
flow policy, or reverse-gate behavior while migrating state.  If implementation
shows that a public counter/status/schema meaning is wrong, stop and promote
that finding to a separate F4/F7/F8 behavior-correction packet.
```

## Current Source Map

Already context-owned:

| State surface | Current owner | Decision |
| --- | --- | --- |
| Endpoint RHS scratch and ODEX workspace | `flow_workspace_t` in `solve_flow.f90` | Keep. This is the already-selected CV-011 flow workspace route. |
| Stage1/Stage2 local-update flow workspace | `tltm_run_context_t%flow%workspace` | Keep. It is the correct per-replica/per-slot flow execution workspace. |
| HMC replay diagnostics | `tltm_run_context_t%diagnostics%hmc_reversibility` and related HMC contexts | Keep separate from flow diagnostics. |

Still module-owned in `solve_flow.f90`:

| State surface | Current source | Meaning | F18b.3 decision |
| --- | --- | --- | --- |
| INTODE call/fallback counters | `intode_calls_*`, `intode_fallback_*` | Run-level diagnostic/output counters | Move to an explicit run diagnostics context with legacy module fallback. |
| Context-split fallback counters | `intode_fallback_attempts_ctx`, `intode_fallback_failures_ctx` | Flowz/flowzr/flow classification counters | Move with the same diagnostics context; preserve current bins. |
| CVODE comparison counters | `intode_cvode_*` | Disabled-by-default comparison backend diagnostics | Move with the same diagnostics context; preserve exact readback values. |
| Runtime trace fields | `intode_trace_*`, `intode_current_context` | Per-active-call attribution for failures and context bins | Split from aggregate counters. Runtime attribution should be explicit per flow/proposal path, not shared hidden module state. |
| Last-failure snapshot | `intode_last_failure_*`, `intode_last_failure_y` | Diagnostic snapshot of the last failed integration | Move to the run diagnostics context; keep legacy fallback for direct tests/callers. |
| Solver-assist compatibility readers | off/zero compatibility APIs | Historical API compatibility after F15b deletion | Leave off/zero unless a schema-removal packet is approved. |
| Disabled Radau/JFNK rescue readers | zero diagnostic compatibility APIs | Historical API compatibility after rescue deletion | Leave off/zero unless a schema-removal packet is approved. |

Bridge-global in `odex_backend.f90`:

| State surface | Current owner | F18b.3 decision |
| --- | --- | --- |
| CVODE C callback active RHS/context pointers | `cvode_active_rhs*`, `cvode_callback_active` | Leave as a narrow callback bridge for now. Reopen only if thread-safe active CVODE comparison becomes product scope. |

## Ownership Options

### A. Split Runtime Trace From Run Diagnostics

Add explicit flow/INTODE state objects defined by `solve_flow`:

- an `intode_diagnostics_context_t` owned by
  `tltm_run_context_t%diagnostics`;
- an active runtime trace/context object carried by the flow/HMC path, either
  inside `flow_workspace_t` or as a sibling object passed beside it;
- legacy module fallback for direct callers and existing small tests.

Consequence:

- preserves run-level summary semantics for counters;
- avoids per-replica counter fragmentation;
- gives future OpenMP/thread-safe code a clear place to protect shared
  diagnostics;
- keeps per-call trace attribution away from shared hidden state;
- requires wider but behavior-free API threading through flow/HMC callers.

### B. Put Everything In `flow_workspace_t`

Move counters, traces, and last-failure snapshots into the existing
per-replica/per-slot flow workspace.

Consequence:

- smaller immediate implementation;
- changes aggregate-counter ownership and risks changing summary semantics;
- makes run-level reporting require an additional merge layer;
- not recommended for a product path.

### C. Legacy Serial Boundary

Keep counters/traces/last-failure snapshots module-global and document them as
serial diagnostic state.

Consequence:

- smallest near-term action;
- does not close the remaining CV-011 flow/diagnostic state boundary;
- acceptable only as a temporary compatibility fallback.

## Selected Implementation Shape

Use option A.

This matches the existing CV-011 pattern:

- per-replica/per-slot workspaces own active computation scratch;
- run/stage diagnostics contexts own summary counters and diagnostic sinks;
- module fallbacks remain only for legacy/direct callers;
- tests prove context isolation rather than relying on source inspection.

The first source patch should therefore implement `F18b.3a`:

1. Define a public `intode_diagnostics_context_t` in `solve_flow`.
2. Add a release/reset helper for the diagnostics context.
3. Add context-aware variants or optional context arguments for
   `reset_intode_fallback_stats`, `get_intode_fallback_stats`,
   `get_intode_fallback_context_stats`, `get_intode_cvode_stats`,
   `get_intode_cvode_context_stats`, and last-failure readers.
4. Add explicit diagnostic-context plumbing to `intode_with_context` and
   flow wrappers used by Stage1/Stage2 product paths.
5. Add a per-call/runtime trace owner so failure attribution no longer depends
   on shared module trace fields on the product path.
6. Keep direct legacy calls behavior-compatible through the existing module
   fallback.

## Behavior-Correction Classification

F18b.3a is intended to be behavior preserving.

| Finding during implementation | Classification | Required action |
| --- | --- | --- |
| Values match current counters/status/output after context migration | state productization | focused context-isolation tests, `git diff --check`, M4. |
| Only legacy direct-call fallback needs compatibility glue | compatibility maintenance | focused direct-call tests; no affected-baseline needed if public values match. |
| A context migration changes run-level counters or output summaries | public diagnostic behavior change | stop, write F4/F7/F8 packet, decide schema/status meaning, then run affected baseline. |
| A failure-attribution bug is found but physical proposal behavior is unchanged | diagnostic behavior correction | separate commit, focused counter tests, M4, and affected output readback if public tables change. |
| Any patch changes endpoint success/failure, accepted endpoint values, final flow, reverse gate, or Metropolis accept/reject | numerical/proposal behavior change | explicit user approval, one patch family per commit, F8 statement, focused deterministic tests, M4, and affected-baseline comparison. |
| Any patch changes ODEX `h0`, h-min, order thresholds, rejection logic, signed interval behavior, error floor, or stability default | ODEX controller behavior change | governed by `F18B_CONTROLLER_DECISION_PACKET_20260516.md`; not authorized here. |

## Stop Conditions

Stop before implementation continues if any of the following becomes true:

- preserving current public counter/status values requires knowingly keeping a
  wrong diagnostic definition;
- the clean implementation needs a public schema removal rather than a
  compatibility fallback;
- Stage1/Stage2 product paths cannot receive an explicit diagnostics context
  without touching proposal/final-flow/reverse-gate behavior;
- a test reveals a physical output change rather than a diagnostic ownership
  change.

## Verification Gate

Minimum gate for the F18b.3a source patch:

- focused context-isolation test for two independent INTODE diagnostics
  contexts;
- focused legacy fallback test for direct callers;
- existing ODEX/flow Jacobian contract;
- retained-core guardrails that touch flow/QN/HMC if call signatures change;
- `git diff --check`;
- M4 guardrails.

Affected-baseline comparison is required only if public output values,
counter/status meanings, proposal behavior, final flow, reverse gate, or
Metropolis behavior change.

## Immediate Next Step

Implement F18b.3a as a behavior-preserving state productization slice.

Do not start an ODEX controller alignment patch.  The controller behavior was
already accepted as TLTM endpoint policy for modernization closure in F18b.2,
and any future controller alignment remains a separate behavior-changing
decision.
