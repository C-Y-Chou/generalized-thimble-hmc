# Risk Register: fortran_modernization

## High
- `quasi_newton_solver.f90` mixes numerical kernel, routing policy, trace capture, fallback strategy, and watchdog logic.
- `solve_flow.f90` is large enough that local changes may have wide, hard-to-see behavioral impact.
- `param_mod.f90` remains a hybrid structured-config plus legacy-global state hub.
- behavior-preservation risk is high unless baselines are captured before refactor.

## Medium
- `constraint_solver_stats.f90` may be over-coupled to solver internals and current routing taxonomy.
- large drivers may duplicate orchestration responsibilities that should live elsewhere.
- performance-sensitive workspace reuse may hide correctness assumptions.

## Low but important
- documentation can drift from implementation unless updated during each refactor phase.
- task-level governance may lag behind code-level progress if not maintained routinely.
