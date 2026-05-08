# M2 Core Numerical Implementation Correctness Audit Plan

Updated: 2026-05-08
Scope: retained-core correctness audit before ODEX-only validation jobs or broader modernization.

## Purpose

This plan closes an explicit gap in the modernization process: it is not enough to disable legacy/rescue paths so that the remaining code resembles the reference algorithm at the routing level. We must also verify that the retained numerical implementation itself is correct, or at least that any deviations from the reference are known, intentional, and test-protected.

This audit is a gate before staged physics validation. The 10k -> 50k -> 100k ODEX-only validation should not be treated as meaningful until the retained five core numerical blocks have been reviewed for implementation correctness.

## Scope: the five retained numerical cores

The five audit targets are:

1. ODEX flow integration.
2. Simplified Newton constraint solve.
3. RATTLE proposal/integrator structure.
4. Quasi-Newton projection loss and p28 fallback solver.
5. HMC / Metropolis / reverse-gate proposal boundary.

These are correctness audits of the code that remains active in the canonical path, not deletion audits of inactive code.

## Audit standard

For each core block, produce:

- Reference contract: which paper/book section defines the algorithmic contract.
- Code map: which routines implement each mathematical step.
- Implementation deviations: what differs from the reference, and whether it is intentional TLTM-specific design or a bug candidate.
- Invariants/properties: identities or monotonicity/consistency checks that should hold independent of long Monte Carlo statistics.
- Failure semantics: what happens on non-convergence, non-finite values, tolerance exhaustion, and rejected proposals.
- Minimal tests/baselines: deterministic or small fixed-seed checks required before 10k validation.
- Signoff state: `unchecked`, `bug-candidate`, `intentional-deviation`, or `accepted-for-staged-validation`.

## Core 1: ODEX flow integration

References:

- Hairer, Norsett, Wanner, Solving Ordinary Differential Equations I.
- `references/Hairer_SODE_I_II9_Extrapolation_Methods_pdfpages_237_270.pdf`.
- `references/Hairer_SODE_I_Appendix_Subroutine_ODEX_pdfpages_494_496.pdf`.

Primary code:

- `src/physics/solve_flow.f90`: `odex_step`, `intode`, `flow`, `flowz`, `flowzr`, RHS mapping routines.
- `src/physics/model*.f90`: action gradient and Hessian-vector dependencies.

Correctness questions:

- Does the modified midpoint sequence and extrapolation tableau indexing match the intended ODEX/GBS method?
- Are order selection, rejected-step behavior, and step-size updates coherent and reference-consistent?
- Are error estimates using the correct columns/orders and scaling with `at` / `rt` correctly?
- Does the code avoid using invalid RHS values to contaminate extrapolation tables?
- Are `flowz` and `flowzr` sign conventions correct for forward/reverse flow?
- Does `flow` propagate the Jacobian consistently with the Hessian-vector equation?
- Are failure semantics ODEX-only after the policy change: no Radau rescue and no final-resort acceptance?

Minimal checks before staged validation:

- Analytic ODE checks for scalar exponential and 2D rotation/linear systems.
- Flow/reverse-flow round-trip checks on representative TLTM states.
- Jacobian finite-difference vs propagated-Jacobian checks.
- Known difficult-state failure classification: max-step, invalid RHS, h-min.

## Core 2: Simplified Newton constraint solve

References:

- `references/2311.10663v4.pdf` for simplified Newton / constrained HMC projection context.
- Project-specific mapping from `new_algorithm__Copy_.pdf` where the projection variables interact with TLTM geometry.

Primary code:

- `src/sampler/hmc_constraints.f90`.
- `src/sampler/hmc_integrator_core.f90`.
- `src/sampler/hmc_kernels.f90`.

Correctness questions:

- Does the residual being solved correspond to the intended constraint equation, not just a numerically convenient surrogate?
- Are `B`, `u`, `ld`, `lambda`, `del_z`, `Jl`, and related variables consistently named and signed?
- Does the simplified Newton linearization match the paper/project formulation?
- Are stopping criteria based on the correct residual norm and tolerance?
- Are failed solves classified without accidentally mutating accepted proposal state?

Minimal checks before staged validation:

- Deterministic projection residual decrease on representative states.
- Check accepted Newton solutions satisfy the constraint within tolerance.
- Fixed-seed Newton success/failure route counts.
- Failure samples replay without changing live Markov state.

## Core 3: RATTLE proposal/integrator structure

References:

- `references/2311.10663v4.pdf` for RATTLE-style constrained proposal structure.

Primary code:

- `src/sampler/hmc_integrator_core.f90`.
- `src/sampler/hmc.f90`.
- `src/sampler/hmc_state_buffers.f90`.
- `src/sampler/hmc_reversibility_checks.f90`.

Correctness questions:

- Does the step ordering match the RATTLE proposal contract: momentum half-step, position/flow update, projection, momentum projection, and reversibility requirements?
- Are lambda and lambda-prime roles separated correctly?
- Does the code preserve symplectic/reversible structure to the degree required by the chosen algorithm?
- Do failure exits leave live state unchanged and diagnostics isolated?
- Are reverse-gate inputs taken from the correct candidate state, not a partially mutated workspace?

Minimal checks before staged validation:

- Reversibility checks for successful Newton-only and QN-used proposals.
- Hamiltonian conservation trend for short deterministic runs.
- Constraint residual before/after proposal and momentum projection.
- Failed-proposal state-identity checks.

## Core 4: Quasi-Newton projection loss and p28 fallback solver

References:

- `references/new_algorithm__Copy_.pdf` for the original projection-loss design and standard/BTN formulation.
- `references/1804.00154v2.pdf` for DFO-LS software mechanism background.
- `references/s12532-019-00161-7_DFO_GN.pdf` for DFO-GN background.

Primary code:

- `src/sampler/quasi_newton_solver.f90`.
- `src/sampler/quasi_newton_linear_solver.f90`.
- `src/sampler/quasi_newton_jacobian_update.f90`.
- `src/sampler/quasi_newton_line_search.f90`.
- `src/sampler/hmc_integrator_core.f90`.
- `src/sampler/constraint_solver_stats.f90`.

Correctness questions:

- Does the active p28 route solve the intended standard `(u, lambda)` residual/loss?
- When standard fails, is BTN fallback entered only under the intended condition and with the intended variables?
- Is the DFO-LS/DFO-GN machinery implementing the project-specific loss rather than replacing it with a generic objective?
- Are route counters, watchdogs, and fallback scopes observational, or do they affect proposal physics?
- Are Broyden/line-search elements only implementation choices under the solver layer, not hidden changes to the mathematical loss?
- Are p28 stopping/failure criteria compatible with RG and Metropolis boundary semantics?

Minimal checks before staged validation:

- Unit-level residual evaluation checks for standard and BTN variables.
- Fixed-seed p28 route census and residual trace summaries.
- Successful QN proposal reversibility/RG checks.
- Failure replay snapshots that distinguish residual bug, flow failure, and route policy failure.

## Core 5: HMC / Metropolis / reverse-gate proposal boundary

References:

- `references/1912.13303_TLTM_HMC.pdf` for TLTM/HMC sampling semantics.
- `references/2311.10663v4.pdf` for constrained-HMC proposal semantics.
- `references/new_algorithm__Copy_.pdf` for project-specific fallback/reverse consistency requirements.

Primary code:

- `src/sampler/hmc.f90`.
- `src/sampler/markovchain_metropolis.f90`.
- `src/sampler/hmc_integrator_core.f90`.
- `src/sampler/hmc_reversibility_checks.f90`.
- `src/sampler/tltm_stage2_driver.f90`.

Correctness questions:

- Does proposal failure always map to the intended Metropolis rejection behavior?
- Are Hamiltonian values, non-finite proposals, and sentinel failures handled correctly?
- Is reverse gate a permanent algorithmic boundary, and does reject preserve live-slot identity?
- Are replay diagnostics isolated from physical proposal counters?
- Do TLTM stage outputs report physical and diagnostic counters without mixing semantics?

Minimal checks before staged validation:

- Fixed-seed proposal success/failure and Metropolis accept/reject counts.
- Reverse-gate pass/reject/live-slot preservation checks.
- Non-finite/sentinel proposal rejection checks.
- Summary/output schema sanity check for the canonical p28 route.

## Required sequencing before 10k -> 50k -> 100k validation

1. Complete static reference-to-code audit for all five retained cores.
2. Mark each core with a signoff state.
3. Add or identify minimal deterministic checks for the highest-risk invariants.
4. If any core is `bug-candidate`, stop and discuss before running staged physics validation.
5. Only after all five are at least `accepted-for-staged-validation`, run ODEX-only 10k validation.

## Current signoff table

| Core | Current state | Notes |
|---|---|---|
| ODEX flow integration | `latent-controller-bug-needs-test` | ODEX-only routing is implemented. `flowzr` is inverse flow via reversed RHS under nonnegative production flow time; `calculate_wk` still appears signed if negative integration intervals are ever supported. |
| Simplified Newton | `reference-matched-needs-tests` | GT-HMC Eqs. (3.37)-(3.44) match code residual/update signs when `del_z=Delta z` and `ld=lambda`; remaining checks are normalization, base-Jacobian use, and deterministic replay. |
| RATTLE proposal structure | `needs-derivation-plus-bug-candidate` | Step boundary is coherent, but `state_has_progress` only checks `x(2)` and must be accepted as a one-dimensional invariant or redesigned. |
| QN p28 projection loss | `intentional-deviation-needs-user-signoff` | Active residual is project-specific standard p28 loss using `xi=(u,lambda_prime)` and DFO-LS machinery; it needs signoff against `new_algorithm__Copy_.pdf`. |
| HMC/Metropolis/RG boundary | `accepted-with-diagnostic-risk` | Live-state preservation and Metropolis rejection boundary look correct; reverse-gate replay diagnostic accounting is not fully isolated from ODE/global counters. |

## Immediate next deliverable

Before submitting any validation job, create a concise audit note for each core with:

- reference equations/algorithm steps;
- exact routine mapping;
- bug candidates;
- intentional deviations;
- minimal pre-validation checks.

The first practical audit target should be `src/physics/solve_flow.f90` because the ODEX-only source gate has already been implemented and any retained ODEX bug would directly affect the planned 10k validation.

## Static audit completion note - 2026-05-08 JST

The first retained-core static audit has been completed and summarized in `M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`. It found no evidence that failed/RG-rejected proposals mutate live Markov state, but it did identify several blockers before ODEX-only staged validation: inverse-flow/ODEX signed-interval semantics, simplified Newton residual replay/normalization checks, QN p28 residual signoff, `x(2)`-only RATTLE progress guard, and reverse-gate replay diagnostic accounting.
