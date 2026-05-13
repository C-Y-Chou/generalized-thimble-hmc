# CV-011 QN Trace/Capture Context Decision Point

Updated: 2026-05-13 JST

## Why This Is A Decision Point

After route-B RNG, top-level run context, flow/ODEX context, HMC/QN flow
threading, and official callback context, `quasi_newton_solver_mod` still has
module-owned state that is not just scratch:

- residual scratch and flowed/proposed eval caches;
- `quasi_last_trace_*` buffers read by retained-core diagnostics;
- watchdog active/last-hit state;
- QN attempt-capture files, write flags, row counters, and current eval count;
- QN eval-flow/global-filter counters;
- backend policy cache, preset values, and notice/warning flags.

Moving these changes the ownership of diagnostics and "last trace" APIs, not
only allocation buffers.

## Options

### A. Run-Owned QN Context

Introduce a QN sub-context under `tltm_run_context_t` and move active-route QN
eval scratch, last-trace buffers, watchdog active state, and attempt-capture
state into it in staged slices. Keep compatibility module wrappers for legacy
tests while Stage1/Stage2 use the explicit context.

Consequence:

- best match for full OpenMP/thread-safe productization;
- makes QN diagnostics ownership explicit;
- broader API migration across QN solver, HMC core, retained-core tests, and
  capture/trace readers;
- requires careful behavior-boundary docs and M4/post-B verification.

### B. Scratch-Only QN Workspace First

Move residual scratch arrays only, while leaving last-trace, watchdog, capture,
and counters module-global.

Consequence:

- smaller patch;
- does not close QN thread-safety;
- risks creating misleading progress around the hardest QN state.

### C. Defer QN Context, Move Counters Elsewhere

Leave QN trace/capture state global for now and move easier solver/flow
counters first.

Consequence:

- reduces near-term API churn;
- leaves the active official QN route as the largest OpenMP blocker;
- delays deterministic reentrant QN evidence.

## Recommendation

Choose A. QN is on the active official route, and the remaining QN state mixes
scratch with diagnostics. A run-owned QN context is the honest product shape.

## Current Stop Condition

Stop for user decision before moving QN trace/capture/eval state, because this
sets the diagnostics ownership model for the active QN route.
