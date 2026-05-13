# CV-011 QN Capture/Diagnostics Context Decision Point

Updated: 2026-05-13 JST

## Why This Is A Decision Point

`CV011_QN_TRACE_EVAL_CONTEXT_SLICE_20260513.md` moved active-route QN residual
scratch, eval caches, last-trace buffers, watchdog state, and per-attempt eval
count into run-owned `qn_context_t`.

The remaining QN module state is different: it owns shared diagnostic sinks,
global counters, and policy caches.

Remaining QN module-owned state:

- QN attempt-capture policy flags, file units, file-ready/write-error flags,
  row counters, sample counters, stride/limit, and capture directory;
- QN eval-flow status counters;
- QN global-filter candidate/pass/reject counters;
- QN backend policy cache, preset values, notice/warning flags.

If these are blindly moved into per-replica/per-slot QN contexts, diagnostics can
silently change meaning or corrupt shared capture files under OpenMP. This is an
ownership/API decision, not a mechanical scratch migration.

## Options

### A. Stage/Run Diagnostic Sink Context

Introduce an explicit diagnostics or QN-capture sink context owned by the
Stage1/Stage2 run/driver layer. QN contexts emit per-attempt data into that
sink; file handles, sample counters, and aggregate counters are centralized and
can later be protected by a serial writer or OpenMP critical section.

Consequence:

- best product shape for full OpenMP/thread-safe diagnostics;
- preserves single capture stream semantics when desired;
- requires more API threading from QN solver to the driver-owned diagnostics
  context;
- keeps per-replica scratch separate from global diagnostics.

### B. Per-Replica/Per-Slot Capture Files

Move capture file units and counters into each `qn_context_t`, and suffix capture
files by replica/slot identity.

Consequence:

- simpler local ownership;
- naturally avoids write races;
- changes capture artifact shape from one stream to many streams;
- requires merge/readback tooling if global sampling semantics matter.

### C. Legacy Diagnostic Boundary

Keep attempt capture and aggregate QN counters module-global for serial/debug
runs only, document them as not OpenMP-productized yet, and continue with other
workspace/productization slices.

Consequence:

- smallest near-term patch;
- does not close QN diagnostic thread-safety;
- leaves a clear caveat rather than risking silent diagnostic semantic drift.

## Recommendation

Choose A. It keeps the product direction honest: per-replica QN scratch belongs
in `qn_context_t`, while shared diagnostic files/counters belong in an explicit
driver-owned diagnostics sink. That shape can support both serial compatibility
and future OpenMP-safe capture.

## Current Stop Condition

Stop for user decision before migrating QN capture/counter/policy state, because
the choice determines whether QN diagnostics remain one global stream, become
per-replica/slot streams, or stay serial-only legacy diagnostics for now.
