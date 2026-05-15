# Modernization Legacy Trigger and Naming Cleanup

Updated: 2026-05-13 JST

## Purpose

Legacy dead triggers, misleading branch flags, and nonsemantic routine names are
modernization work when they can be cleaned without changing physics, RNG order,
accepted states, counters, or public schema meaning.

This plan keeps that cleanup inside the active modernization lane instead of
deferring it to the post-modernization correctness sweep.

## Scope

Handle in modernization:

- prove whether `eo`, `istest`, `testmom`, and related historical switches are
  live product controls, dead code, or compatibility-only knobs;
- remove, quarantine, or document confirmed dead/misleading triggers when the
  output surface is unchanged;
- rename or wrap unclear internal names such as `rattle2` and `decompose2` after
  confirming their exact algorithmic role and call semantics;
- split names only when the split is mechanical and preserves route behavior;
- add comments or reference names where renaming would risk churn before the
  surrounding API is stable.

## Gates

- Treat the work as F9/W11 behavior-preserving cleanup.
- Use the F8 patch-local reference statement for behavior-relevant source
  patches.
- Run exact-output or accepted tolerance-bound comparisons for affected rows.
- Preserve compatibility aliases for public schema, public method labels, or
  external script interfaces unless the user explicitly approves removal.

## Escalation To F16

Escalate to the post-modernization correctness sweep only when the audit finds a
candidate bug whose fix may intentionally change output, counters, route
selection, or public schema meaning.

Examples:

- a trigger is live and selecting an unintended physics/solver path;
- a strange name hides two algorithmically different behaviors that should not
  remain equivalent;
- a diagnostic or counter is wrong in a way that changes publication
  interpretation.

Those cases require an evidence packet, explicit approval, focused tests, and a
separate behavior-changing commit.
