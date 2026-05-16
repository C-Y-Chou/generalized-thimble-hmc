# All-Handwritten Line Audit Requirement

Date: 2026-05-16 JST

Status: active modernization requirement.

## Decision

The ODEX line audit is not a one-off exception.  Before claiming publication
grade paper-correctness or numerical-soundness for the modernization tree, every
handwritten numerical/code path must receive the same level of inspection:

- line-level source readback;
- comparison against the relevant paper/reference implementation where one
  exists;
- numerical-algorithm judgment where no exact paper line exists;
- classification into matched core, paper mismatch, project policy, or
  bug-candidate;
- durable handling plan for each bug-candidate or non-paper-exact surface;
- focused tests or affected-baseline gates before behavior/API changes.

## Minimum Scope

At minimum, this applies to:

- handwritten ODEX / flow integration;
- Simplified Newton / RATTLE / HMC constraint path;
- QN wrapper and residual/certification logic around official DFO-LS;
- Metropolis live-state and rejection output buffers;
- Stage2 swap/tempering/RNG protocol code;
- model/action/Jacobian generated-versus-handwritten boundaries;
- diagnostics/counter/status semantics when they affect public claims.

## Current State

ODEX has now received this level of line audit through
`F18B4F_PRE_IMPLEMENTATION_HANDWRITTEN_ODEX_LINE_AUDIT_20260516.md`.

The remaining handwritten areas still need equivalent line-audit packets before
universal paper-correctness can be claimed.
