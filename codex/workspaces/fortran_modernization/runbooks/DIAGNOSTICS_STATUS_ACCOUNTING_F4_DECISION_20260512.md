# Diagnostics Status Accounting F4 Decision

Updated: 2026-05-12 JST

## Current Implemented Surface

- HMC proposal status distinguishes success, output-size mismatch, final-flow
  failure, force/projection failure, constraint failure, and reverse-gate
  rejection.
- Metropolis transition status distinguishes accepted, ordinary rejected,
  proposal failed, reverse-gate rejected, Hamiltonian invalid, `Delta H`
  invalid, and output-size mismatch.
- Stage1/Stage2 compatibility counters preserve old accept/reject and
  `projection_failure_count` behavior while appending typed local-transition
  counters.
- Stage2 v1alpha sidecars record local-transition, swap, label, and observable
  diagnostics without removing v0 fields.

## Missing Typed Context

F4 is not fully implemented until one typed diagnostics context separates these
event classes:

- forward physical proposal construction;
- reverse replay / reverse-gate checking;
- Newton/QN residual evaluation;
- debug or guardrail probes;
- rejected stay-put events;
- accepted live-state updates.

Each event should carry a context ID, status code, source route, acceptance
role, counter denominator, and schema version. Counters should be derived from
typed events rather than inferred from mixed booleans.

## Compatibility Policy Before F4 Completion

- Do not remove or rename v0 fields.
- Treat `projection_failure_count` as a legacy coarse compatibility counter,
  not a precise projection-failure statistic.
- Prefer appended typed counters and sidecar diagnostics for new interpretation.
- Any final production claim that uses diagnostics must state the schema and
  compatibility boundary.

## Decision

F4 has two valid paths:

1. Implement the typed diagnostics context before final production regeneration.
2. Explicitly accept the current compatibility-first diagnostics surface as a
   reduced-scope limitation for the next production redo.

Without one of these decisions, `CV-010` remains a production-regeneration
blocker.
