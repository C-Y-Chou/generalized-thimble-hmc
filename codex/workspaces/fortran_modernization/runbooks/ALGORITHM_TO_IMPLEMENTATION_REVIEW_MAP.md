# Algorithm-to-Implementation Review Map

Updated: 2026-05-08 JST

## Purpose
This map pins each core TLTM Fortran algorithm area to its reference source before modernization review. The goal is behavior-preserving engineering: clarify and improve the code without silently changing physics, proposal semantics, or approved output behavior.

## Reference hierarchy
### TLTM framework
- Reference: `references/1912.13303_TLTM_HMC.pdf`
- Covers: tempered Lefschetz thimble HMC framework, replica/tempering structure, thimble HMC embedding, Metropolis-level sampling semantics.
- Main implementation areas:
  - `src/sampler/tltm_stage2_driver.f90`
  - `src/sampler/markovchain_metropolis.f90`
  - `src/sampler/hmc.f90`
  - `src/apps/run_tltm_stage2.f90`

### Simplified Newton, RATTLE, GT-HMC / WV-HMC
- Reference: `references/2311.10663v4.pdf`
- Covers: constrained molecular dynamics, RATTLE projection, simplified Newton / fixed-point projection, lambda and lambda-prime determination.
- Main implementation areas:
  - `src/sampler/hmc_integrator_core.f90`
  - `src/sampler/hmc_constraints.f90`
  - `src/sampler/hmc.f90`
  - `src/physics/solve_flow.f90`

### ODE flow integration
- Reference: `references/Hairer_Norsett_Wanner_SODE_I_Nonstiff_Problems_full.pdf`.
- Focused excerpts: `references/Hairer_SODE_I_II9_Extrapolation_Methods_pdfpages_237_270.pdf`, `references/Hairer_SODE_I_Appendix_Subroutine_ODEX_pdfpages_494_496.pdf`.
- Location guide: `references/ODEX_LOCATION_GUIDE.md`.
- Covers: ODEX / extrapolation ODE integration, adaptive step and error-control expectations.
- Main implementation areas:
  - `src/physics/solve_flow.f90`
  - `src/physics/model*.f90`

### DFO-GN core
- Reference: `references/s12532-019-00161-7_DFO_GN.pdf`
- Covers: derivative-free Gauss-Newton for nonlinear least-squares, linear residual models, trust-region framework, convergence framing.
- Current active implementation areas:
  - `src/sampler/quasi_newton_solver.f90`
  - `src/sampler/quasi_newton_linear_solver.f90`
- Historical modules deleted from active source on 2026-05-09:
  - `src/sampler/quasi_newton_jacobian_update.f90`
  - `src/sampler/quasi_newton_line_search.f90`

### DFO-LS robustness and software extensions
- Reference: `references/1804.00154v2.pdf`
- Covers: DFO-LS package design, robustness to noisy/expensive objectives, restarts, regression/sample averaging concepts.
- Main implementation areas:
  - `src/sampler/quasi_newton_solver.f90`
  - bounded local priority pass and residual-assist policy in the QN path

### Original projection-loss and parametrization-layer design
- Reference: `references/new_algorithm__Copy_.pdf`
- Covers: projection ambiguity, geometry / parametrization / solver layers, standard `(u, lambda)` formulation, BTM/BTN fallback formulation, project-specific quasi-Newton projection-loss design.
- Main implementation areas:
  - `src/sampler/quasi_newton_solver.f90`
  - `src/sampler/hmc_integrator_core.f90`
  - `src/sampler/hmc_constraints.f90`

## Current production target interpretation
- `nofb`: standard `(u, lambda)` formulation.
- `fg`: standard formulation first; when standard fails, use BTM/BTN fallback formulation.
- Current quasi-Newton projection loss is canonical current design, not a disposable exploration artifact.
- Modernization may clarify, isolate, document, and test this design, but must not replace it with a generic DFO-GN/DFO-LS objective.

## Broyden and line-search classification
- No separate user-provided Broyden or line-search reference is required at this stage.
- Treat Broyden update and line-search/backtracking as implementation mechanisms under the DFO-GN/DFO-LS-inspired solver layer.
- Review should still distinguish general DFO-GN/DFO-LS method support from project-specific constants, route policies, watchdogs, continuation, and fallback decisions.

## Review questions by module
### `src/physics/solve_flow.f90`
- Does the implementation preserve the ODEX contract for flow / inverse-flow use?
- Are fallback, trace, and rescue diagnostics separated from the ODE integration mechanism?
- Are `at` / `rt` tolerances and failure modes explicit enough for regression testing?

### `src/sampler/hmc_constraints.f90`
- Does the simplified Newton residual match the RATTLE projection equations in the reference?
- Are `B`, `u`, `ld`, `lambda`, and seed semantics clear and stable?
- Which parts are numerical mechanism versus rescue policy?

### `src/sampler/quasi_newton_solver.f90`
- Which residual/loss is solved: standard `(u, lambda)`, BTM/BTN, or route-dependent combination?
- Which pieces are DFO-GN/DFO-LS mechanisms and which are project-specific projection-loss design?
- Are continuation, restarts, watchdogs, and route classifiers observable and test-protected?

### `src/sampler/hmc_integrator_core.f90`
- Does RATTLE orchestration preserve proposal semantics and reverse-gate requirements?
- Are Newton, QN, BTM/BTN fallback, diagnostics, and statistics separable without behavior drift?

### `src/sampler/hmc.f90` and `src/sampler/markovchain_metropolis.f90`
- Does proposal success/failure reporting preserve Metropolis semantics?
- Are Hamiltonian and rejection paths behaviorally stable under solver refactors?

## Baseline requirements before implementation changes
- Fixed-seed output summaries for representative configs.
- Solver route census and failure counts.
- Reverse-gate candidate/pass/reject counters.
- Reversibility and Hamiltonian diagnostics.
- Derivative / Hessian-vector consistency checks.
- For any Level B numerical refactor, tolerance-bounded comparison of representative trajectory diagnostics.

## Immediate planning deliverable
Write a behavior-preserving algorithm audit that follows this order:
1. TLTM/HMC framework review.
2. ODE/flow solver review.
3. simplified Newton/RATTLE review.
4. quasi-Newton projection-loss review.
5. Metropolis/proposal boundary review.
