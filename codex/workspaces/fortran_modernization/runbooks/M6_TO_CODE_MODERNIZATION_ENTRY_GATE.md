# M6 To Code Modernization Entry Gate

Updated: 2026-05-10 JST

Scope: define what must be true before the modernization workstream resumes source-code refactors after M6 planning.

This document intentionally stops at the boundary before touching source code.

## Why This Gate Exists

The remaining modernization work can affect behavior indirectly through:

- RNG stream ownership;
- module `save` workspace ownership;
- state/status propagation;
- config/global mirror replacement;
- output schema/readers;
- wrapper orchestration;
- diagnostics and counter timing;
- solver routing and failure reporting.

Those are not safe to clean up using only tiny local smoke tests. They need a reference package or an explicitly approved substitute baseline.

## Required Before Source-Code Refactor

- M4 guardrails pass on the current branch.
- Worktree is clean or planned doc-only changes are committed/staged for review.
- Stage3_4/modernization workstream boundary is recorded.
- A modernization reference package is accepted, or the user explicitly approves a narrower baseline for the next source slice.
- Affected baseline rows are identified in `BASELINE_VERIFICATION_MATRIX.md`.
- The proposed source slice declares whether it is:
  - exact-output preserving;
  - trajectory-changing but statistically/physically preserving;
  - schema/provenance-only;
  - diagnostic-only;
  - behavior-changing and therefore blocked without explicit decision.

## Source Work That Should Wait For Accepted Reference Package

- RNG ownership or seed-stream migration.
- Large module `save` workspace migration.
- `param_mod` global mirror replacement.
- Reentrant/OpenMP context ownership.
- HMC/Markov state object redesign.
- Output schema removal/renaming.
- Wrapper replacing Stage2/Stage3 public entry behavior.
- Counter timing changes.
- Solver route restructuring that can alter proposal construction or failure classification.

## Source Work That May Proceed With Smaller Baselines

Only after explicit scope review:

- documentation-only edits;
- comments that do not affect preprocessing/build output;
- tests/readers/auditors that do not mutate production outputs;
- local guardrail improvements;
- parser/reporting additions that preserve existing fields;
- build-system dependency hygiene that does not alter compiler flags or runtime behavior.

## First Recommended Code Slices After Gate

After a reference package is accepted, the recommended order is:

1. Add read-only reference-package validation tooling, if not already present.
2. Add regression comparison harnesses against accepted package summaries.
3. Start low-risk code hygiene in non-physics utility modules.
4. Move to state/status/context ownership slices only after comparison harnesses are routine.
5. Defer RNG stream and module workspace ownership until the comparison harness can detect route/counter shifts.

## Mandatory Patch Header For Future Source Changes

Each future source-code patch should record:

- intended behavior class;
- affected modules;
- affected reference-package checks;
- expected output preservation level;
- commands run;
- whether RNG order, proposal route, failure classification, or schema meaning can change.

## Current Position

As of 2026-05-10 JST:

- This workstream is still before the source-code gate.
- No new source-code modernization should start in this thread until the M6 reference-dataset design/readback docs are accepted or the user explicitly chooses a narrower next baseline.
