# Behavior Preservation Protocol

## Purpose
This protocol governs every modernization change. Engineering cleanup is allowed; unapproved physics or behavior drift is not.

## Preservation levels
### Level A: exact-preservation refactor
- Intended for file moves, subroutine splits, API cleanup, naming cleanup, workspace reuse cleanup, and documentation-aligned restructuring.
- Requirement: same inputs, same seeds, same outputs.

### Level B: numerically equivalent refactor
- Intended for internal numerical cleanup where floating-point path details may change without changing scientific meaning.
- Requirement: fixed-seed comparisons, invariant checks, solver statistics checks, and tolerance-bounded output equivalence.

### Level C: scientific behavior change
- Not part of ordinary modernization.
- Requires explicit scientific approval, separate documentation, and separate validation criteria.

## Required evidence before accepting a change
1. Baseline run definition recorded.
2. Before/after outputs compared.
3. Relevant invariants checked.
4. Any observed deviation explained.
5. Approval recorded if deviation is intentional.

## Minimum comparison surface
- key summary metrics
- acceptance/rejection behavior
- solver route counts and failure counts
- representative trajectory diagnostics
- derivative and Hamiltonian validation tests where relevant

## Non-negotiable rule
If behavior changes unexpectedly, stop the refactor, isolate the first cause, and resolve or explicitly escalate it before proceeding.
