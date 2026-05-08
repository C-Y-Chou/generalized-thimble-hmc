# Simplified Newton / RATTLE Review Notes

Updated: 2026-05-08
Scope: planning-only, behavior-preserving review. No source edits, no jobs.

## Purpose

This note fixes the second low-level review boundary: the constrained HMC proposal step. The goal is to map the current implementation to the simplified Newton / RATTLE / HMC reference family before any Fortran modernization changes subroutine boundaries or control flow.

## Reference Definition

Primary reference bundle:

- `2311.10663v4.pdf`: simplified Newton, RATTLE-style constrained integration, reverse/volume checks in the relevant constrained-HMC setting.
- `1912.13303_TLTM_HMC.pdf`: TLTM HMC context and how constrained flow coordinates enter the tempered Lefschetz thimble algorithm.
- `new_algorithm__Copy_.pdf`: user-defined projection formulation and quasi-Newton fallback semantics, especially the distinction between standard `(u, lambda)` behavior and BTM/BTN fallback behavior.

Reference-level invariant for modernization:

- The proposal map must preserve the current physical algorithm and Metropolis target. Refactors may clarify implementation, but cannot silently change projection equation, momentum projection, flow convention, reversibility gate, acceptance probability, or rescue-route semantics.

## Current Implementation Map

Primary files:

- `/home/cychou/TLTM/src/sampler/hmc.f90`
- `/home/cychou/TLTM/src/sampler/hmc_integrator_core.f90`
- `/home/cychou/TLTM/src/sampler/hmc_constraints.f90`
- `/home/cychou/TLTM/src/sampler/hmc_kernels.f90`
- `/home/cychou/TLTM/src/sampler/hmc_state_buffers.f90`
- `/home/cychou/TLTM/src/sampler/constraint_solver_stats.f90`

Current proposal route:

1. `hmc.rattle` samples momentum, projects it with `decompose2`, and computes initial Hamiltonian.
2. For each HMC substep, `rattle_step_core` computes force-like `dV` from `ds`, builds `del_z = h*p - h^2*dV`, and tries the constraint projection.
3. First projection attempt is simplified/Newton route through `solve_constraint_newton`.
4. If Newton fails and quasi fallback is enabled, `rattle_step_core` enters the quasi-Newton/DFOLS route.
5. If quasi succeeds, optional post-Newton refine may run using the separate Newton-loss residual.
6. The proposal then calls `flow` to update endpoint `z` and Jacobian `jac`.
7. Momentum is reconstructed from `(final_z - temp_z)/step_size`, adjusted by force, and projected again with `decompose2`.
8. Optional reverse gate replays one reverse step and compares `x/z/jac/p` against the input state.
9. `hmc.rattle` optionally runs a reversibility probe after the whole proposal when configured.
10. `markovchain_metropolis.metropolis_step` accepts/rejects by `exp(-(H_final-H_initial))`, with explicit proposal failure handling.

Newton constraint details:

- `solve_constraint_newton` maps complex Jacobian to a real matrix and LU factorizes it once.
- `solve_constraint_newton_seeded` solves for displacement variables and Lagrange-like correction variables using residual `B`.
- It includes zero-start and seeded behavior, rescue-mode tolerance changes, backtracking, stagnation/divergence guards, and post-QN refine logging.
- The implementation has production heuristics beyond a clean textbook Newton step. These are behavior and must be baselined.

RATTLE/HMC kernel details:

- `calculate_dV` currently sets `dV = E0_real/2` after `E0 = conjg(ds(z))` and tangent/normal processing.
- `decompose2` maps the complex Jacobian to real form, solves for tangent coordinates, constructs one projected component, and returns the residual component.
- `hmc_state_buffers` already contains a workspace type for the RATTLE step, which is a good modernization seed, but it does not cover all module-level state in solver/fallback paths.

## Behavior Preservation Risks

High-risk behavior surfaces:

- Newton residual definition and update variables. This is algorithmic, not cosmetic.
- Seeded Newton behavior after quasi fallback or post-refine.
- Rescue-mode thresholds: near tolerance, stagnation floor, divergence floor, iteration caps, backtracking limits.
- `del_z = h*p - h^2*dV` construction and the exact `dV` convention.
- Momentum projection/reconstruction through `decompose2` and real/complex mapping helpers.
- Reverse gate semantics and tolerance, including comparison of `jac` in addition to `x/z/p`.
- `state_has_progress` behavior in `hmc.f90`; existing knowledge notes that it is currently dimension-fragile.
- Counter and capture side effects in `constraint_solver_stats.f90`, especially suppression during reverse-gate replay.

## Refactorability Assessment

Safe now, as planning work:

- Document proposal route and distinguish mathematical RATTLE steps from production fallback policy.
- Define tests for Newton-only, quasi-used, reverse-gate-pass, reverse-gate-reject, and proposal-failure paths.
- Identify internal APIs that should eventually become smaller: force evaluation, projection solve, momentum projection, failure capture, reverse gate.

Potentially safe after baselines:

- Extract clearer RATTLE step data structures around existing `rattle_step_workspace_t` without changing route order.
- Split pure kernels from policy/counter recording, if counters are tested before and after.
- Improve naming around `Jl`, `del_z`, `u`, `ld/lambda`, and residual `B` while preserving equations.

Blocked until Stage3_4 completion or explicit approval:

- Changing reverse-gate policy, tolerance, or replay accounting.
- Changing Newton backtracking/stagnation/rescue thresholds.
- Changing momentum projection conventions.
- Changing Metropolis ratio to compensate for route mixtures without a separate physics decision.
- Changing fallback route order or enabling/disabling rescue paths by default.

## Required Baselines

- Newton-only proposal baseline with fixed seed and no quasi fallback.
- Quasi-used successful proposal baseline with solver route counters.
- Reverse-gate rejection identity baseline: live slot must remain unchanged and counters must match summary.
- Whole-proposal reversibility baseline: forward then reverse must recover `x/z/jac/p` within current tolerances.
- Hamiltonian conservation trend using existing `tests/test_hamiltonian_conservation.f90` as a starting point.
- Failure-path baseline for Newton fail, quasi fail, post-refine fail, and reverse-gate fail.

## Open Questions For Confirmation

- Should `state_has_progress` remain a current-production convention for one-dimensional physical states, or be treated as a modernization bug to fix after baselines?
- Is reverse gate a permanent algorithmic requirement for all quasi/fallback proposals, or a production guard until proof is complete?
- Should Newton rescue-mode thresholds be documented as empirical production policy or derived from the simplified Newton/RATTLE reference?

## Reverse Gate Decision - 2026-05-08
- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It is not merely a temporary debug guard or optional diagnostic mode.
- Modernization must preserve reverse-gate semantics, tolerance behavior, Jacobian comparison, replay accounting suppression, and live-slot identity on reject.
- Any future wrapper should expose this as part of the canonical p28 algorithm contract, not as an experimental add-on.
