# Subroutine and API Redesign Guide

## Why this matters
At present, several critical procedures combine numerical mechanism, policy decisions, runtime tracing, and statistics updates. This makes the code difficult to verify, test, and evolve safely.

## Redesign goals
- each public subroutine should have one primary responsibility
- argument lists should encode a stable contract rather than historical convenience
- mathematical objects should have one agreed meaning across callers
- failure handling should be explicit and locally understandable

## Priority smells to eliminate
- giant procedures that perform kernel work, routing, and reporting together
- shared semantics represented only by loose arrays and comments
- optional arguments that encode major behavioral mode switches
- hidden dependence on module-global mutable state
- duplicated convergence, acceptance, or fallback logic across procedures

## Preferred redesign patterns
- split orchestration from kernel evaluation
- separate input state, workspace, result, and diagnostics concerns
- centralize residual and merit definitions
- expose structured solver outcome summaries rather than ad-hoc counters
- keep instrumentation wrappers outside the tightest numerical core when possible

## Immediate target areas
- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/hmc_constraints.f90`
- `src/sampler/quasi_newton_solver.f90`
- `src/physics/solve_flow.f90`
- `src/config/param_mod.f90`

## Thread-Safety / Reentrancy Decision - 2026-05-08
- Long-term modernization target: support in-process parallelism/OpenMP-capable TLTM execution.
- Hidden module-level `save` workspaces, counters, RNG state, traces, and solver policies should be progressively moved behind explicit context/workspace objects.
- Short-term production behavior remains serial/process-level until Stage3_4/TLTM judgment and fresh baselines are complete.
- No source-level context refactor should start until affected baseline rows are covered.
- Final wrapper design should make per-run/per-replica state explicit enough for deterministic parallel execution.
