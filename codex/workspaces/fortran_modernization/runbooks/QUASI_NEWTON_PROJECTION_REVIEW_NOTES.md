# Quasi-Newton Projection Review Notes

Updated: 2026-05-08
Scope: planning-only, behavior-preserving review. No source edits, no jobs.

## Purpose

This note fixes the third low-level review boundary: the quasi-Newton / DFO-LS / DFO-GN projection route and the user-defined projection loss. This is the most behavior-sensitive part of modernization because it mixes mathematical formulation, production rescue policy, branch classification, diagnostics, and algorithm experiments.

## Reference Definition

Primary references:

- `s12532-019-00161-7_DFO_GN.pdf`: derivative-free Gauss-Newton framework for nonlinear least-squares residual models.
- `1804.00154v2.pdf`: DFO-LS software/robustness extensions for practical least-squares solving.
- `new_algorithm__Copy_.pdf`: user original formulation for the quasi-Newton projection loss and standard/BTN fallback design.
- `2311.10663v4.pdf`: simplified Newton and RATTLE reference layer that the quasi route must preserve or safely emulate when Newton fails.

User clarification recorded for this task:

- Canonical naming decision: use `BTN`; treat `BTM` as a historical typo/alias only.

- `nofb`: standard `(u, lambda)` formulation.
- `fg`: use standard formulation first, and use BTN only when standard fails.
- Broyden update and line search do not currently require an additional dedicated reference beyond the DFO-GN/DFO-LS family unless later review finds a gap.
- The quasi-Newton loss function is original project design and should not be treated as disposable implementation detail.


## Production Route Decision

Decision recorded: the only production-canonical quasi route is the current p28 path.

Canonical p28 route:

1. Newton is attempted first.
2. If Newton fails, run QN S1 probe with `QN_S1_PROBE_MAX_ITER=28`.
3. The QN probe uses `solve_constraint_quasi_newton(evaluate_constraint_residual, ...)`.
4. The active solver inside that route is DFO-LS on the standard residual.
5. Near rescue, non-near rescue, and global fallback are off for the current Stage3_4 p28 production settings.
6. Reverse gate is applied before Metropolis when RG is enabled.

Legacy/deletion-candidate routes:

- DFO-GN paper route.
- Broyden/line-search route.
- Global continuation/restart fallback routes outside the p28 production path.
- Any other non-p28 quasi route unless explicitly re-promoted later.

Post-refine status:

- Post-refine is still under observation.
- It is not yet guaranteed to remain in the final publishable production route.
- It may be removed after current Stage3_4/refine-vs-norefine evidence is reviewed.
- Until then, modernization must preserve both `fb_refine` and `fb_norefine` behavior when comparing current results.

## Current Implementation Map

Primary files:

- `/home/cychou/TLTM/src/sampler/quasi_newton_solver.f90`
- `/home/cychou/TLTM/src/sampler/quasi_newton_linear_solver.f90`
- `/home/cychou/TLTM/src/sampler/quasi_newton_jacobian_update.f90`
- `/home/cychou/TLTM/src/sampler/quasi_newton_line_search.f90`
- `/home/cychou/TLTM/src/sampler/hmc_integrator_core.f90`
- `/home/cychou/TLTM/src/sampler/constraint_solver_stats.f90`

Top-level solver route:

- `solve_constraint_quasi_newton` starts from `initial_guess_from_jacobian`, optionally applies a seed override, runs `run_dfo_ls_attempt`, then may run priority pass, continuation, fine continuation, sweeps, diversified restarts, and global filter bookkeeping depending on thresholds and env/config flags.
- The active production route appears to prefer `run_dfo_ls_attempt`; `run_dfo_gn_attempt`, `run_dfo_gn_paper_attempt`, and `run_quasi_newton_attempt` coexist as alternate or legacy/research routes.
- `hmc_integrator_core.try_quasi_stage` calls `solve_constraint_quasi_newton(evaluate_constraint_residual, ...)` and then optionally `refine_quasi_with_dfols_loss` using `evaluate_constraint_residual_newton_loss`.

Residual definitions:

- `evaluate_constraint_residual`: standard inverse-flow residual. It forms a proposed complex point from `z + del_z + Jl`, then calls `flowzr(xt, residual_z_trial, ierr)`. The residual vector is `[aimag(flowzr_result); xi_lambda_part]` in current code form.
- `evaluate_constraint_residual_newton_loss`: post-refine loss with independent variables `xi=[u;ld]`. It computes `r = z + del_z + (-i*J*ld) - flowz(x0 + u)`, maps this complex residual to real form, and stores `Jl` as the proposal correction.
- `build_post_refine_seed_from_qn`: converts QN solution to post-refine seed with `u0 = Re(zinv_qn) - x0`, `ld0 = -u_qn`.

DFO/solver machinery:

- `run_dfo_ls_attempt`: trust-region least-squares path with finite-difference/model Jacobian construction, Levenberg-style regularization, trust radius update, escape/stagnation logic, and trace recording.
- `run_dfo_gn_paper_attempt`: closer-to-paper interpolation set / poisedness / geometry-improvement implementation.
- `run_quasi_newton_attempt`: Broyden + line-search style path with merit/backtracking/growth guards.
- `quasi_newton_jacobian_update.f90`: Broyden rank-1 update and safeguard helper.
- `quasi_newton_line_search.f90`: compact acceptance and merit-update predicates.

Policy and diagnostics mixed in:

- Global fallback gating, final-resort budgets, accepted-iteration budgets, watchdog scope, route codes, trace arrays, and flowz/flowzr call tracking are stored as module-level `save` state.
- `constraint_solver_stats.f90` owns counters and captured failure details used by Stage3_4 diagnostics.
- `hmc_integrator_core` classifies quasi failures as local/mid/global and near/far, then chooses skip/light/anchor routes and near rescue paths.

## Behavior Preservation Risks

Highest-risk surfaces:

- The residual definitions are algorithm definitions. They must not be renamed or rearranged in a way that changes signs, variable ordering, or flow direction.
- Current `xi` layout, `Jl` meaning, and `del_z` mapping are not self-evident and are easy to break during API cleanup.
- The standard residual and post-refine Newton-loss residual intentionally differ. Collapsing them into one generic residual would be dangerous.
- Route thresholds such as `promising_first_pass_res`, `probe_global_rescue_trigger_res`, `fine_cont_trigger_res`, sweep triggers, trust radii, lambda bounds, and accept tolerances are behavior.
- Watchdog/final-resort budget behavior can change proposal failure rates and accepted route composition.
- Module-level trace arrays and route codes create hidden dependencies between solver attempts and later diagnostics/counters.
- Multiple solver families coexist; modernization must first classify canonical, fallback, experimental, and deprecated paths.

## Refactorability Assessment

Safe now, as planning work:

- Define a residual contract document: variable order, equations, flow direction, output meaning, and failure behavior.
- Create a solver-route taxonomy: active production, fallback production, diagnostic/research, legacy candidate.
- Identify exact counters that must match for each route.

Potentially safe after baselines:

- Extract residual evaluation into a documented projection-loss module with unchanged signatures wrapped for compatibility.
- Split DFO-LS/DFO-GN/Broyden implementations into files by algorithm family while preserving exported entry points.
- Replace ambiguous names only with test-backed equivalence and equations in comments.
- Encapsulate trace state into a derived type after route/counter baselines exist.

Blocked until Stage3_4 completion or explicit approval:

- Changing default route selection or enabling global fallback by default.
- Removing `run_dfo_gn_paper_attempt` or Broyden paths before confirming they are unused in all production configs.
- Changing residual acceptance tolerance or `residual_within_accept_tolerance` semantics.
- Changing final-resort/watchdog budgets.
- Changing post-refine skip/success/failure policy.

## Required Baselines

- Residual microtests for both `evaluate_constraint_residual` and `evaluate_constraint_residual_newton_loss`, including sign/order checks for `xi`, `Jl`, `del_z`, and flow direction.
- Fixed captured-case QN trace replay: residual sequence, accepted flags, route codes, best residual, valid fraction, and final success/failure.
- Production route census: probe/full/post-refine/near/far/reverse-gate counters before and after any refactor.
- Solver family coverage: at least one DFO-LS normal case, one DFO-LS priority/continuation case, one post-refine skip, one post-refine solve, one post-refine fail capture, and one watchdog/final-resort budget case if available.
- Accepted proposal correctness: QN-used proposal must pass reversibility and local volume checks already noted in `codex/knowledge/FULL_PROGRAM_MAP_CHECK.md`.

## Open Questions For Confirmation

- Should BTN be unified to one naming convention in docs/code comments, and which spelling is canonical?
- Confirm after Stage3_4 whether post-refine remains in production or is removed.
- Should global fallback remain research-only and disabled by default?
- Should route thresholds become named config parameters later, or remain compiled constants for reproducibility?

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS standard residual -> reverse gate -> Metropolis.
- Post-refine is a deletion candidate and should not be part of the final canonical p28 route unless explicitly re-promoted later.
- M2c implementation may remove or disable post-refine after comparison harness coverage.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- Until that validation gate passes, DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants remain legacy/quarantine candidates rather than approved deletions.
