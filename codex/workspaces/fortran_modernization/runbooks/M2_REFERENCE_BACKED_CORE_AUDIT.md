# M2 Reference-Backed Retained Core Audit

Updated: 2026-05-08
Scope: second-pass, reference-first audit of the retained numerical cores. This supersedes source-first conclusions where the two disagree.

## Why this exists

The previous retained-core audit was useful as a source-level risk scan, but it was not strict enough: it identified implementation questions before fully anchoring each numerical core to the defining reference equations. This document resets the standard.

Audit rule used here:

1. State the reference contract first.
2. Map only the active retained Fortran route to that contract.
3. Mark every mismatch as either `matched`, `intentional-deviation`, `reference-deviation`, or `open-needs-test`.
4. Do not accept long Monte Carlo validation as meaningful until reference-level blockers are resolved or explicitly accepted.

## Overall signoff table

| Core | Reference-backed state | Decision before long validation |
|---|---|---|
| ODEX flow integration | `decision-use-hairer-iwork3` | Canonical modernization target is Hairer ODEX `IWORK(3)=3`: `2,4,6,8,12,16,24,32,...`; current code sequence is legacy and must be changed/tested before ODEX-only validation. |
| Simplified Newton | `matched-needs-deterministic-tests` | Residual sign, update decomposition, base-Jacobian use, and `Delta z` normalization match GT-HMC/TLTM for unit mass. Add deterministic replay tests. |
| RATTLE integrator | `mostly-matched-with-implementation-guards` | Main update order matches TLTM complex RATTLE. `state_has_progress` and failure-as-rejection vs paper momentum-flip/replacement need explicit policy/test coverage. |
| QN p28 / BTN rescue | `decision-use-paper-btn-variables` | p28 is BTN/backflow rescue. Future source should use paper variables directly: `xi1=b`, `xi2=a`, with correction `-J*(a+i*b)` and matching initial guess sign. |
| HMC / Metropolis / RG boundary | `matched-if-proposal-boundary-is-reversible` | Metropolis rule matches reference if RATTLE/RG proposal is reversible and state preserving. Reverse-gate and failure boundary need deterministic detailed-balance/replay checks. |

## Core 1: ODEX flow integration

Reference contract:

- Hairer ODEX is an explicit midpoint/GBS extrapolation method with variable order and variable step size.
- Hairer ODEX Appendix lists allowed even step-number sequences: `2,4,6,8,...`; `2,4,8,12,16,...`; `2,4,6,8,12,16,24,32,...`; `2,6,10,14,...`; `4,8,12,16,...`.
- Section II.9 explains the explicit midpoint smoothing step and even-power extrapolation.
- Hairer order selection uses positive work-per-unit-step measures `W(k)` and step-size candidates `Hnew`.

Active code mapping:

- `odex_step` implements explicit midpoint rows and the smoothing endpoint formula `0.5*(yprev + ycurr + dt*f(ycurr))`.
- `odex_step` builds a polynomial extrapolation tableau from the midpoint rows.
- `intode` wraps adaptive stepping with error control and ODEX-only failure semantics after the recent source-policy change.
- `flowz` integrates forward flow from real initial data; `flowzr` implements inverse flow by reversing the RHS scale with nonnegative production flow time.

Reference-backed findings:

- Matched: the basic explicit midpoint plus smoothing plus extrapolation structure is reference-consistent.
- Reference deviation: `build_nsteps` generates `2,4,6,12,18,36,...`, which is not one of the Hairer ODEX Appendix `IWORK(3)` sequences and not the standard II.9 examples.
- Decision: canonical modernization target is Hairer ODEX `IWORK(3)=3`, i.e. `2,4,6,8,12,16,24,32,...`.
- Required implementation change later: update both `build_nsteps` and `calculate_ak` so the sequence and work estimate remain consistent.
- Latent issue: `calculate_wk` divides by signed `hk`; current production nonnegative flow time avoids this for `flowzr`, but a general ODEX routine should use a positive work measure if negative integration intervals are supported.
- Open: the code omits several Hairer ODEX controls such as explicit stability checks and dense output, which may be acceptable for TLTM but should be documented as a reduced ODEX-like integrator rather than full ODEX.

Required before ODEX-only validation:

- Implement Hairer ODEX `IWORK(3)=3` sequence in `build_nsteps` and the matching work estimate in `calculate_ak`.
- Add analytic ODE smoke tests for convergence and forward/inverse flow round-trip.
- Add a negative-interval microtest only if negative intervals are intended to be supported.

## Core 2: Simplified Newton constraint solve

Reference contract:

- GT-HMC Eq. (3.37): `zt(x+u) = zt(x) + Delta z - lambda`.
- GT-HMC Eq. (3.40): `B = z + Delta z - lambda - znew`, where `znew = zt(x+u)`.
- GT-HMC Eq. (3.41): simplified Newton replaces `Enew` by the base `E` and solves `E Delta u + Delta lambda = B`.
- GT-HMC Eqs. (3.42)-(3.44): decompose `B = E B0,v + Bn`, then set `Delta u = B0,v`, `Delta lambda = Bn`.
- TLTM complex representation for unit mass gives `ztilde = z + Delta s*pi - (Delta s**2/2)*conjg(dS)`.

Active code mapping:

- `rattle_step_core` computes `E0=conjg(ds(state_z))`, `dV=E0_real/2`, and `del_z = step_size*momentum - step_size**2*dV`.
- Therefore `del_z` matches `Delta z` for the unit-mass normalization used in the TLTM complex formula.
- `solve_constraint_newton_seeded` computes `B = real(z - flowz(xt+u) - ld) + del_z`, which is the real-vector representation of `z + Delta z - lambda - znew`.
- `solve_projected_step` solves `J^{-1}B`, zeroes imaginary coordinates to get the base/tangent part, then computes `av = B - J*au` as the normal component.
- The update `u += Delta u`, `ld += Delta lambda` matches GT-HMC simplified Newton.

Reference-backed findings:

- Matched: residual sign and lambda sign are correct against GT-HMC.
- Matched: use of fixed base Jacobian is correct for simplified Newton; the code passes the pre-step `jaci` and factorizes it once.
- Matched: `del_z` normalization matches the TLTM unit-mass formula, assuming `momentum` represents the tangent velocity after projection and `ds` returns `dS`.
- Open-needs-test: accepted Newton solutions should be replayed and checked against Eq. (3.37)/(3.40), including residual <= `cttol` and `lambda = O(step_size**2)` scaling.

Required before long validation:

- Deterministic Newton replay test on accepted samples.
- Check and log `norm(lambda)/step_size**2` scaling on a fixed seed.

## Core 3: RATTLE integrator structure

Reference contract:

- TLTM Eq. (3.16)-(3.20) and GT-HMC Algorithm 2 define RATTLE: half-step force, position projection, momentum reconstruction, second force, and tangent projection.
- TLTM complex representation gives: `ztilde = z + Delta s*pi - Delta s**2/2*conjg(dS(z))`; project to `z'`; compute `pi_1/2=(z'-z)/Delta s`; compute `pi_tilde'=pi_1/2 - Delta s/2*conjg(dS(z'))`; project to tangent space.
- The reference emphasizes reversibility and volume preservation. When a valid projection cannot be found, TLTM discusses replacement by momentum flip `Psi` as a reversible fallback.

Active code mapping:

- `rattle_step_core` computes `del_z` exactly as the first complex-position trial term.
- It calls simplified Newton first, then QN/BTN rescue if enabled.
- It calls `flow(final_x, final_z, ws%temp_jac, ...)` after projection, reconstructs momentum as `(final_z - old_z)/step_size`, subtracts the second half force, and calls `decompose2` to keep the tangent component.
- `rattle` repeats substeps and uses the Metropolis boundary after the proposal.

Reference-backed findings:

- Matched: main position/momentum update order matches TLTM complex RATTLE.
- Matched: momentum projection via `decompose2` corresponds to the reference tangent projection `J Re(J^{-1} v)`.
- Intentional implementation boundary: code treats failed proposal as `proposal_ok=.false.` and lets Metropolis/driver reject without updating live state; the paper's failure discussion uses a reversible momentum flip/replacement map. User decision: failure-as-rejection is a valid MCMC boundary when failure is part of the proposal kernel, the live chain state remains unchanged on failure, diagnostics do not mutate the state, and successful proposals still pass the reversibility/constraint checks used by the Metropolis step.
- Reference deviation / guard: `state_has_progress` only checks `x(2)`. This is not in the reference algorithm and is dimension-fragile. The deeper issue is state representation: current `x(:)` stores flow time in `x(1)` and physical coordinates in `x(2:)`, so many APIs rely on implicit positional layout rather than a typed state boundary.

Required before long validation:

- Deterministic one-step forward/reverse replay for Newton-only and QN-rescued proposals.
- Do not treat `state_has_progress` as an isolated local fix. Short term: mark the `x(2)`-only progress guard as legacy/diagnostic and rely on solver convergence, constraint residuals, reverse gate, and Metropolis rejection for proposal validity. Long term: redesign state APIs so flow time and physical seed/state are separate typed fields, then remove implicit `x(1)`/`x(2:)` indexing from numerical kernels.
- Document failure-as-rejection as the project policy: failed projection/integration/reverse-gate proposals are rejected/stay-put events in the marginal chain. The failed proposal output buffers need not equal the old state, but callers must never commit them unless `accepted=.true.`.

## Core 4: QN p28 / BTN rescue

Reference contract:

- `new_algorithm__Copy_.pdf` separates the projection problem into geometry, parametrization, and solver layers.
- Standard formulation Eq. (9)/(24): solve `fstd(u,lambda; ztilde,x)=0` in the standard `(u,lambda)` variables.
- BTN formulation Eq. (15)-(19): backflow `fBTN(z)=Phi_-tau(z)` maps manifold points back to real `x`, so manifold membership is `Imag fBTN(z)=0`.
- BTN projection Eq. (22)/(25): solve `C(a,b;ztilde,x)=Imag fBTN(ztilde - E a - F b)=0` together with `a=0`.
- Appendix B defines the implemented policy: primary simplified Newton in the standard parametrization first; after failure, a bounded quasi rescue with `Nprobe=28`, optional follow-up budget, tolerance `tol=1e-13`, and trust-region/LM-style least-squares acceptance.

Active code mapping:

- Primary standard solve is `solve_constraint_newton`, already mapped above.
- QN rescue residual `evaluate_constraint_residual` builds `ztrial = z + del_z + J*(i*xi1 + xi2)` and returns `[Imag(flowzr(ztrial)), xi2]`.
- Current code sign convention: with `F=iJ`, BTN Eq. (22) uses `ztilde - J*a - iJ*b`, while current code uses `ztilde + J*(i*xi1 + xi2)`. Therefore current code has `xi1=-b` and `xi2=-a`.
- Decision: future modernization may either keep this internal negative-coordinate convention and document it, or switch to paper variables directly. If it switches to paper variables, use `xi1=b`, `xi2=a`, and compute the correction as `-J*(xi2 + i*xi1)` so the residual is `Imag fBTN(ztilde - J*a - iJ*b)` with `xi2=a`.
- `run_dfo_ls_attempt` is a finite-difference nonlinear least-squares trust-region/LM solver around the residual callback, not the exact external DFO-LS package, but it matches the intended solver-layer role of minimizing the project-defined residual.
- `initial_guess_from_jacobian` solves `J dz = -del_z` and maps `xi1=Imag(dz)`, `xi2=Real(dz)`, which is a plausible linearized seed for the BTN residual under the code's sign convention.

Reference-backed findings:

- Important correction: the active p28 residual is not the standard `(u,lambda)` residual. It is a BTN/backflow rescue residual used after the primary standard solve fails.
- Matched-as-BTN: `Imag(flowzr(...))` and the explicit second block enforcing `xi2=0` match the BTN idea of making manifold membership explicit in backflow variables.
- Implementation decision: code variable names should be changed/aligned so `xi1=b` and `xi2=a`. The residual block `fq(n+1:)=xi2` then directly enforces paper condition `a=0`.
- Open policy check: current route budgets and extra near/far rescue logic must be compared line-by-line to Appendix B before saying the implemented policy exactly matches the manuscript.
- Open solver check: the trust-region/LM machinery is acceptable as implementation choice only if fixed-seed route/reconstruction tests show it preserves the proposal boundary and residual contract.

Required before long validation:

- Rename/document p28 residual as BTN rescue, not standard residual.
- Decide implementation convention explicitly:
  - If retaining the current negative-coordinate convention, do not change the initial guess sign; current `J dz=-del_z` is consistent and gives `ztrial=z` at the linear seed, so the initial loss is approximately `||xi2||` in the current `xi2=-a` convention.
  - If switching to paper variables, implement `residual_jlc = -matmul(jac, xi2 + i*xi1)`, with `xi1=b`, `xi2=a`, and change `initial_guess_from_jacobian` to solve `J dz = +del_z`. Changing only one of residual sign or seed sign would create a mixed convention.
- Confirm downstream code treats `Jl` as the actual correction added to `z+del_z`; then recovery/replay paths do not need a separate sign change. Re-audit post-refine seed mapping separately if post-refine is retained.
- Unit test `evaluate_constraint_residual` against the BTN contract, not against old/new convention equivalence: after solver convergence, construct `ztrial = z + del_z + Jl`, verify `Imag(flowzr(ztrial))` is small, and verify the second residual block (`a`, or current-convention `xi2`) is small.
- Fixed-seed route-census comparison for `Nprobe=28` and any allowed follow-up budgets.

## Core 5: HMC / Metropolis / reverse gate

Reference contract:

- TLTM/HMC requires proposal maps that are reversible and volume-preserving, followed by Metropolis acceptance `min(1, exp(-Delta H))`.
- TLTM failure/replacement discussion relies on a reversible fallback relation, such as momentum flip, when projection cannot proceed.
- The user/project policy requires reverse gate as a permanent boundary for the p28 route.

Active code mapping:

- `metropolis_step` rejects failed/nonfinite proposals and otherwise uses `exp(-Delta H)`.
- `run_local_updates` updates live `slot%x`, `slot%z`, and `slot%jac` only when accepted.
- `rattle_step_core` only sets `method_converged=.true.` after flow, momentum projection, and reverse-gate pass.
- `qn_reverse_gate_accepts` replays the reverse step and checks state, Jacobian, and momentum against tolerance.

Reference-backed findings:

- Matched: Metropolis probability boundary is reference-consistent if the proposal map is reversible/volume-preserving.
- Matched: live-state preservation on failed/RG-rejected proposals is correct at the Markov state boundary.
- Project-specific addition / user decision: reverse gate is part of the proposal definition, not a debug-only filter. A reverse-gate failure means the proposal kernel did not produce a valid proposal and therefore follows the same failure-as-rejection/stay-put boundary.
- Diagnostic/accounting risk: reverse-gate replay suppresses constraint-solver stats but not all global ODE/intode counters, so diagnostic baselines may mix forward proposal work and replay work. User added that the broader count/capture/switch design is patchwork and must be included in later systematic modernization, not handled as an RG-only counter tweak.

Required before long validation:

- Deterministic RG pass/reject replay proving reverse consistency for accepted proposals and live-state identity for RG-rejected proposals.
- Redesign diagnostic accounting/capture/switch policy: separate forward proposal work, reverse-gate replay, probes, rescue attempts, failed proposal work, and debug-only counters in a typed diagnostics context rather than scattered global counters/suppression flags.
- Document proposal failure, including reverse-gate failure, as rejection in the marginal chain and how that replaces the paper's momentum-flip fallback at the implementation boundary.

## Revised discussion order

1. ODEX sequence implementation: switch to Hairer ODEX `IWORK(3)=3` and test before any ODEX-only validation.
2. QN p28 implementation: switch BTN rescue to paper variables (`xi1=b`, `xi2=a`) and flip the initial-guess RHS consistently.
3. RATTLE failure/progress policy: treat `state_has_progress` as a symptom of the current `x(1)=flow_time`, `x(2:)=seed` layout; defer real cleanup to state API redesign and document failure-as-rejection as the project MCMC boundary.
4. Deterministic replay tests: Newton residual, BTN residual, RATTLE reverse gate, flow round-trip, ODE analytic checks.
5. Only after these are resolved should ODEX-only 10k -> 50k -> 100k physical validation begin.

## Bottom line

This second pass changes the risk profile:

- Simplified Newton is stronger than the first audit claimed: its signs match GT-HMC.
- RATTLE's main update order is also largely reference-matched.
- ODEX sequence decision is now fixed: use Hairer ODEX `IWORK(3)=3`; current sequence is legacy until updated/tested.
- QN p28 must be described as BTN rescue, not standard `(u,lambda)` QN; future source should use paper variables `xi1=b`, `xi2=a`.
- HMC/Metropolis is acceptable only if reverse gate and failure semantics are treated as part of the proposal contract and tested deterministically.

## ODEX sequence decision - 2026-05-08 JST

User selected Hairer ODEX `IWORK(3)=3` as the canonical modernization target: `2,4,6,8,12,16,24,32,...`. The existing `2,4,6,12,18,36,...` sequence is therefore legacy. The future source change must update both `build_nsteps` and `calculate_ak`, then run analytic ODE and TLTM flow round-trip tests before long validation.

## BTN sign convention and paper-variable decision - 2026-05-08 JST

User confirmed p28 is BTN/backflow rescue and requested future code variables follow the paper convention. The current code and future target are distinguished as follows:

Current code convention:

- Reference BTN Eq. (22): `ztrial = ztilde - E*a - F*b`, with `F=iE` and `E=J`.
- Current code residual: `ztrial = z + del_z + J*(i*xi1 + xi2)`.
- Therefore current code variables satisfy `xi1=-b`, `xi2=-a`.

Future paper-variable target:

- Use `xi1=b` and `xi2=a`.
- Implement the trial correction as `residual_jlc = -J*(xi2 + i*xi1)`.
- Keep `fq(n+1:)=xi2`, which then directly enforces the paper condition `a=0`.
- Change `initial_guess_from_jacobian` consistently: solve `J dz = +del_z` instead of `J dz = -del_z`, then set `xi1=Im(dz)`, `xi2=Re(dz)`.
- The pair above is coupled. If residual remains in the current convention, the initial guess must also remain `J dz=-del_z`; changing only the initial guess would seed `ztrial` near `z+2*del_z`, not near `z`.
- Once the residual sign is changed to paper variables, the initial guess is the only seed-generation change required for the canonical p28 path; `Jl` should continue to mean the actual correction vector added to `z+del_z`, so recovery/replay can keep using `del_z + Jl`.
- Post-refine is off the canonical route and a deletion candidate. If retained, `build_post_refine_seed_from_qn` must be re-audited because it interprets the first block of `qn_solution_xi` by sign.
