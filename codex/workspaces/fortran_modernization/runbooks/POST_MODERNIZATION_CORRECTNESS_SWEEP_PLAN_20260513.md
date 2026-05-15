# Post-Modernization Correctness Sweep Plan

Updated: 2026-05-13 JST

## Purpose

Modernization patches remain output-preserving by default. That rule protects
physics and makes refactors reviewable, but it can also preserve minor bugs as
golden behavior. This plan records the separate post-modernization correctness
sweep for cases where a fix may intentionally change behavior.

Behavior-preserving cleanup of dead triggers and strange internal names belongs
inside modernization; see
`MODERNIZATION_LEGACY_TRIGGER_NAMING_CLEANUP_20260513.md`.

## Timing

Do this after the modernization closure gate, not during active output-preserving
refactor slices.  Nonbehavioral dead-trigger and naming cleanup remains active
modernization work.

Prerequisites:

- CV-011 state/workspace/productization work is closed or explicitly scoped;
- production-tree synchronization and publication-ready source contracts have a
  clean checkpoint;
- current M4/F8 behavior-preservation gates still pass.

## Scope

The sweep should deliberately look for minor-but-important bugs that
modernization may have preserved, including:

- trigger or naming audits that reveal a live semantic bug rather than
  behavior-neutral cleanup;
- legacy compatibility switches whose current behavior is unused or ambiguous;
- status/counter/diagnostic inconsistencies that do not currently change
  accepted states but can mislead analysis;
- reference-formula or sign-convention mismatches against the retained TLTM,
  GT-HMC, ODEX, and DFO-LS sources;
- tests that only preserve baseline output without checking the intended
  invariant.

## Rules

- Do not use this sweep as permission to change physics inside ordinary
  modernization commits.
- Every candidate bug gets a short evidence packet before a fix:
  source location, expected invariant/reference, observed behavior, minimal
  reproducer or deterministic test, and expected output/counter delta.
- Behavior-changing fixes require an explicit approval point and a separate
  patch/commit from pure modernization cleanup.
- If a candidate turns out to be intended behavior, rename or document it so the
  next reader does not rediscover the same ambiguity.

## Deliverables

- A candidate issue registry under `state/` or `runbooks/`.
- Focused tests or reference checks for accepted candidates.
- A behavior-change decision packet for any fix that changes output, counters,
  or public schema.
- A handoff back to the modernization cleanup lane for confirmed nonbehavioral
  cleanup items.

## Initial Candidate Queue

- Accept escalations from the modernization trigger/naming cleanup audit when a
  candidate cannot be fixed without changing behavior.
- Review legacy compatibility switches only when their removal or correction
  would alter route selection, counters, accepted states, or public schema.

## Boundary

This is a future correctness lane. The current modernization lane should still
remove or rename dead/misleading internals when behavior is preserved.  It must
escalate any behavior-changing fix here for explicit evidence and approval.
