# M2 Retained Core Numerical Implementation Audit Summary

Updated: 2026-05-08
Scope: static source-level correctness audit of the retained canonical numerical cores before ODEX-only staged validation.

## Executive result

The retained-core audit is complete enough for discussion, but it does **not** clear the code for ODEX-only 10k -> 50k -> 100k validation yet.

The main finding is exactly the gap the user pointed out: disabling legacy/rescue paths is not equivalent to proving the remaining numerical implementation is correct. The retained route is mostly coherent at the routing/state-boundary level, but several low-level implementation details require derivation, correction, or explicit signoff before a physics baseline should be frozen.

Current gate decision:

- Do not submit ODEX-only validation jobs yet.
- Do not treat current output as canonical frozen behavior yet.
- Discuss the bug candidates and intentional deviations below first.
- After decisions, either patch the clear implementation bugs or mark deliberate deviations as accepted with deterministic tests.

## Source map audited

| Core | Primary routines checked |
|---|---|
| ODEX flow integration | `src/physics/solve_flow.f90`: `odex_step`, `calculate_wk`, `calculate_hk`, `build_nsteps`, `intode`, `flowz`, `flowzr` |
| Simplified Newton | `src/sampler/hmc_constraints.f90`: `solve_constraint_newton_seeded`, `solve_projected_step` |
| RATTLE structure | `src/sampler/hmc_integrator_core.f90`: `rattle_step_core`, `qn_reverse_gate_accepts`; `src/sampler/hmc.f90`: `rattle` |
| QN p28 projection loss | `src/sampler/quasi_newton_solver.f90`: `solve_constraint_quasi_newton`, `run_dfo_ls_attempt`, `evaluate_constraint_residual`; `src/sampler/quasi_newton_linear_solver.f90`: `initial_guess_from_jacobian` |
| HMC / Metropolis / RG boundary | `src/sampler/markovchain_metropolis.f90`, `src/sampler/tltm_stage2_driver.f90`, `src/sampler/hmc_reversibility_checks.f90` |

## Severity classification

| Severity | Meaning |
|---|---|
| P0 blocker | Must be discussed or fixed before ODEX-only staged validation. It may change trajectories or acceptance/rejection decisions. |
| P1 blocker | Must be tested or explicitly accepted before canonical baseline freeze. It may be a legitimate TLTM deviation but is currently under-documented. |
| P2 cleanup | Does not appear to change physics, but can confuse diagnostics, maintainability, or publishability. |
| Confirmed-safe | The audited boundary appears behavior-safe under the current contract. |

## P0/P1 findings

### F1. ODEX work estimate should be magnitude-based if negative integration intervals are ever allowed

State: `latent-controller-bug`, P1 for current nonnegative-flow production; P0 only if negative `x(1)` / negative integration intervals are admitted.

Observed code:

- `flowzr` is the inverse flow of `flow`: it sets `flow_vec_rhs_scale = -1.0_dp` and calls `intode(..., t1, ...)`.
- That inverse-flow implementation reverses the vector field, not necessarily the integration-step sign.
- Current Stage1/Stage2 production controls clamp flow ladders to nonnegative values, and `markovchain_mod` rejects negative `initial_flow_time`.
- Therefore, for the present canonical production path, `flowzr` should normally enter ODEX with nonnegative `h` even though it integrates the inverse vector field.
- Separately, `calculate_hk(h, err, k)` preserves the sign of `h`, which is correct for step direction if negative intervals are supported.
- `calculate_wk(h, err, k)` computes `wk = odex_ak_cache(kc)/hk`, so `wk` would become negative if a future or test path used negative `h`.

Why this matters:

- Work/cost estimates should be positive quantities. If `wk` is negative under a negative integration interval, order-selection inequalities can be inverted or made meaningless.
- This is not, by itself, evidence that the current `flowzr` production route is wrong, because inverse flow is implemented by reversing the RHS while keeping flow time nonnegative.
- It remains a publishability/general-ODEX robustness issue and should be covered by deterministic signed-interval tests.

Discussion decision needed:

- Likely robustness fix: compute work using `abs(hk)` while keeping `calculate_hk` signed.
- This should not change current nonnegative-flow production outputs, but it should still be tested.
- Required test before broad ODEX cleanup: forward/inverse-flow round-trip, plus explicit negative-interval ODEX microtest if negative intervals are intended to be supported.

### F2. ODEX step sequence and extrapolation contract are not yet reference-signed

State: `intentional-deviation-or-bug-candidate`, P1.

Observed code:

- `build_nsteps` generates `2, 4, 6, 12, 18, 36, ...`.
- `calculate_ak` mirrors that sequence in its cumulative work estimate.
- The code implements a modified midpoint/extrapolation tableau, but the exact sequence/order policy needs to be tied back to Hairer ODEX or to a deliberate TLTM choice.

Why this matters:

- This may be a valid GBS/ODEX-like sequence, but the publishable code should say which sequence is intended and why.
- If not reference-consistent, the sequence affects error/order behavior and therefore trajectories.

Discussion decision needed:

- Either cite the intended ODEX sequence and keep it, or make the sequence explicit as a TLTM implementation choice.
- Required test: analytic scalar/linear ODE convergence-order smoke test.

### F3. Simplified Newton residual/update sign convention needs derivation signoff

State: `needs-derivation`, P0/P1 depending on derivation.

Observed code:

- Zero seed starts with `B = del_z`.
- Seeded and iterated residual is `B = real(z - flowz(xt+u) - ld) + del_z`.
- `solve_projected_step` solves `jacr * dxi = B`, projects `dxi` into a real component, and sets `av = B - jacr*au`.
- The update is `u += dxi(real slots)` and `ld += av`.

Why this matters:

- The code is internally consistent with the existing `decompose2` projection pattern, but the audit did not yet prove that this is the exact simplified Newton equation from the reference/project formulation.
- A sign error here could be stable-looking but wrong because QN/RG/Metropolis can mask the issue as a route-frequency or acceptance shift.

Discussion decision needed:

- Write the intended residual equation in variables `(u, lambda, del_z, J)` and match every term to `B`, `dxi`, `av`, and `ld`.
- Required test: deterministic accepted Newton solutions must satisfy the written residual equation and have residual norm <= `cttol`.

### F4. RATTLE `state_has_progress` checks only `x(2)`

State: `bug-candidate-for-general-code`, P1 for current one-dimensional production, P0 for publishable multidimensional use.

Observed code:

- `state_has_progress(x_before, x_after)` returns true only if `abs(x_after(2)-x_before(2))` exceeds a floating-point threshold.
- `rattle` calls this after the final substep; `propagate_with_given_momentum` uses the same check for replay/probe behavior.

Why this matters:

- For current one-variable production this may be a pragmatic no-motion guard.
- For a mature codebase it is dimension-fragile: valid movement in other coordinates can be rejected, and small accepted moves in `x(2)` can be classified as failure.

Discussion decision needed:

- If TLTM production is permanently one-dimensional, document this as an invariant.
- Otherwise replace with norm-based progress or remove as a physics-level criterion and rely on residual/reversibility checks.

### F5. QN p28 residual appears internally consistent, but it is project-specific and must be signed against the original formulation

State: `intentional-deviation-needs-user-signoff`, P1.

Observed code:

- `initial_guess_from_jacobian` solves `J * dz = -del_z`, then maps `xi(1:n)=aimag(dz)`, `xi(n+1:)=real(dz)`.
- Active p28 residual uses `residual_jlc = J * (i*u + lambda_prime)`.
- It tests `flowzr(xt, z + del_z + residual_jlc)` and returns residual vector `[imag(inverse_flow_result), lambda_prime]`.
- Acceptance is exact: `res_norm <= tol`.

Why this matters:

- This is not a generic DFO-LS objective; it is a project-specific standard projection loss wrapped in DFO-LS machinery.
- The implementation is coherent with the `xi = (u, lambda_prime)` layout, but it must be matched to `new_algorithm__Copy_.pdf` and the current p28 target.

Discussion decision needed:

- Confirm that current production p28 means this standard residual, not BTN and not a mixed transition residual.
- Required test: unit-level residual construction for a tiny deterministic case plus fixed-seed p28 route census.

### F6. Reverse-gate replay suppresses constraint-solver stats, but not all ODE/global diagnostics

State: `diagnostic-risk`, P1/P2.

Observed code:

- `qn_reverse_gate_accepts` sets `qn_reverse_gate_active = .true.` and calls `push_constraint_solver_stats_suppression()` around a replayed `rattle_step_core`.
- ODEX/intode counters are global and are not suppressed by this mechanism.

Why this matters:

- This should not change physics if all replay state is local and proposal acceptance uses only the returned reverse check.
- It can contaminate diagnostic counters used for baseline comparisons, especially ODEX fallback/failure counts after the ODEX-only source gate.

Discussion decision needed:

- Decide whether reverse-gate replay ODE calls should be counted as real diagnostic work or separately tagged/suppressed.
- Required test: one fixed proposal with RG enabled should report separate forward vs replay ODE accounting, or the current combined accounting should be explicitly documented.

## Confirmed-safe or mostly-safe boundaries

### C1. Proposal failure does not appear to mutate accepted live Markov state

State: `confirmed-safe-at-boundary`.

Evidence:

- `rattle_step_core` initializes outputs from input and only sets `method_converged = .true.` after flow, momentum projection, and reverse gate pass.
- If reverse gate rejects, it returns before assigning `jacf` or reporting success.
- `metropolis_step` maps any failed/non-finite proposal to `accept = .false.` and `proposal_failed = .true.`.
- `run_local_updates` updates `slot%x`, `slot%z`, and `slot%jac` only if `accepted`.

Residual risk:

- Diagnostic counters may still include replay or failed-attempt work, but live state preservation looks correct.

### C2. Metropolis probability boundary is simple and coherent with a symmetric/reversible proposal contract

State: `accepted-if-RATTLE/RG-contract-holds`.

Evidence:

- `delta_h = h_final - h_initial`.
- If `delta_h <= 0`, accept probability is 1; otherwise `exp(-delta_h)`.
- Non-finite Hamiltonians and failed proposals reject.

Residual risk:

- This assumes RATTLE/RG provides the required reversible/symmetric proposal boundary. If the retained RATTLE/QN/RG path is not reversible, Metropolis alone cannot fix it.

### C3. DFO-LS mechanism is solver machinery, not the mathematical loss definition

State: `mostly-safe-if-loss-signed`.

Evidence:

- `run_dfo_ls_attempt` repeatedly calls the supplied residual callback `f`.
- The active production callback from `try_quasi_stage` is `evaluate_constraint_residual`.
- DFO-LS-style finite-difference Jacobian, LM damping, trust-radius limiting, and accept/reject are implementation mechanisms around that residual.

Residual risk:

- Legacy Broyden/line-search/continuation code still exists and should remain quarantined until deletion validation.

## Required deterministic checks before staged ODEX-only jobs

These are minimum checks, not the full test suite.

| Check | Purpose | Blocks |
|---|---|---|
| ODEX signed-interval microtest | Verify positive work estimate/order behavior if negative integration intervals are supported | F1 |
| ODEX analytic ODE smoke tests | Verify scalar exponential and 2D linear/rotation systems against tolerance | F1, F2 |
| Flow round-trip replay | `flowz` then `flowzr` returns representative TLTM state within tolerance | F1, F2, F5 |
| Jacobian finite-difference check | Propagated Jacobian agrees with finite-difference flow map | ODEX/RATTLE/HMC |
| Newton residual derivation replay | Accepted Newton solution satisfies the written residual equation | F3 |
| QN p28 residual construction test | Tiny deterministic case validates `xi=(u,lambda_prime)` mapping and residual vector | F5 |
| RATTLE one-step reversibility | One accepted step followed by reverse step returns state/momentum/Jacobian within RG tolerance | F3, F4, F5 |
| Failed proposal state identity | Failed/RG-rejected proposals leave live slot unchanged | C1 |
| Diagnostic counter split | Confirm whether reverse-gate replay ODE counters are expected in reported totals | F6 |

## Recommended discussion order

1. ODEX signed-work clarification: current inverse flow uses reverse RHS with nonnegative flow time; decide whether to patch `calculate_wk` for negative-interval robustness.
2. Simplified Newton residual equation: derive and sign off signs/variables.
3. QN p28 residual: confirm standard formulation and `lambda_prime` semantics.
4. RATTLE progress guard: decide one-dimensional invariant vs general norm check.
5. Reverse-gate diagnostic accounting: decide whether to split/suppress replay ODE counters.

## Audit conclusion

The canonical route is structurally much clearer than before:

`Newton -> QN p28 standard residual when Newton fails -> reverse gate -> Metropolis`, with ODEX-only flow as the target backend.

But the retained implementation is **not yet accepted for staged validation**. After the inverse-flow clarification, F1 is no longer evidence that current `flowzr` is wrong under nonnegative production flow time, but F2-F6 still require signoff/tests before touching long Monte Carlo jobs.
