# Handwritten Algorithm Current Analysis Report

Date: 2026-05-14 JST
Scope: current handwritten numerical algorithms in `fortran_modernization`
Status: audit body report complete for current understanding; no source change

## Executive Conclusion

The audit body is now done to current-analysis depth.  The result is mixed in
the right way: many handwritten TLTM algorithm blocks are understandable and
reference-consistent at their main mathematical boundary, but not every
controller constant, branch predicate, failure path, and diagnostic side effect
is detail-signed against the defining papers.

Current defensible position:

- ODEX: midpoint/extrapolation core and Hairer `IWORK(3)=3` sequence are
  understood; controller details remain the largest open proof surface.
- Flow/Jacobian RHS: direction, inverse-flow sign, conjugated RHS, and Jacobian
  evolution are source-understood; full formula/detail closure should stay
  tied to ODEX and model/cache audits.
- Simplified Newton: currently the strongest handwritten algorithm surface;
  signs, residual, projected update, and base-Jacobian simplified Newton role
  are mapped.
- RATTLE/HMC: main update order is mapped; proposal failure as stay-put
  rejection is an intentional implementation policy that needs continued
  deterministic replay coverage.
- BTN/QN: residual variables and initial guess now follow the paper-variable
  BTN convention; the official DFO-LS bridge is accepted for representative
  scope with TLTM residual certification, but controller budgets/watchdogs are
  project policy.
- Metropolis/live state: implementation preserves live state on failed or
  rejected proposals and uses the expected `exp(-Delta H)` boundary.
- Stage2 tempering/swap: current code matches the selected fixed-slot/mobile
  label replica-exchange contract; one alternating parity per cycle and
  post-swap measurement are explicit production conventions.
- RNG and diagnostics: Stage2 RNG v2 is now a declared contract, not a
  same-finite-trajectory promise.  Diagnostics/counters still contain active
  CV-011 surfaces.

No confirmed source bug requiring an immediate Fortran patch was established by
this report.  The main correction is claim discipline: behavior preservation,
deterministic guardrails, and production readbacks are not substitutes for
paper-level implementation-detail signoff.

## Evidence Basis

References inspected for this report:

- Hairer ODEX appendix and Section II.9 extrapolation references under
  `references/`.
- TLTM HMC paper `references/1912.13303_TLTM_HMC.pdf`.
- Constrained HMC / RATTLE reference `references/2311.10663v4.pdf`.
- Project BTN/QN algorithm note `references/new_algorithm__Copy_.pdf`.
- DFO-LS / DFO-GN references and prior official-package provenance runbooks.

Source inspected for this report:

- `src/physics/odex_backend.f90`
- `src/physics/solve_flow.f90`
- `src/sampler/hmc_constraints.f90`
- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/quasi_newton_linear_solver.f90`
- `src/sampler/quasi_newton_solver.f90`
- `src/sampler/markovchain_metropolis.f90`
- `src/sampler/tltm_stage2_driver.f90`

Existing modernization evidence used:

- `M2_REFERENCE_BACKED_CORE_AUDIT.md`
- `M3_TEMPERING_PROTOCOL_AND_OUTPUT_SCHEMA_DESIGN.md`
- retained-core deterministic evidence and pre-redo gates
- CV-011 context/RNG/diagnostics slice reports
- F15 navigation-assist strict-certification policy
- `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`

## Classification Summary

| Area | Current status | Why |
| --- | --- | --- |
| ODEX controller | `partial/open-needs-proof` | The method family and sequence are mapped, but h0, h-min, step-size bounds, order thresholds, and rejection branches are not fully Hairer-signed. |
| Flow/inverse/Jacobian RHS | `reference-mapped/partial` | `flowz` starts from real seed coordinates, `flowzr` reverses RHS scale, and `flow` evolves z plus Jacobian; full closure depends on model derivative and ODEX controller details. |
| Simplified Newton | `closed-for-current-gate` | Residual sign, `Delta z`, fixed-base Jacobian, and projected step match the retained-core audit. |
| RATTLE proposal | `mostly-matched/project-policy-partial` | Main update order is mapped; failure-as-rejection and reverse-gate policy are implementation boundaries requiring replay tests. |
| BTN/QN residual | `matched-core/partial-controller` | Paper-variable residual and initial guess are aligned; route budgets, watchdogs, and rescue classification are project controller policy. |
| Official DFO-LS bridge | `accepted-representative-scope` | Official package bridge and TLTM residual certification exist; production-output completeness remains external. |
| Navigation assist | `implemented-policy` | QN navigation assist is scoped to h-min residual-evaluation navigation and strict certification; it is not a paper algorithm by itself. |
| Reverse gate | `project-proposal-boundary/partial-proof` | Reverse replay checks x, z, Jacobian, and momentum; proposal-kernel proof remains tied to policy and deterministic gates. |
| Metropolis/live-state mutation | `matched` | Failed, invalid, and rejected proposals leave live state unchanged; finite proposals use `min(1, exp(-Delta H))`. |
| Stage2 tempering/swap | `protocol-mapped/partial-tests` | Swap acceptance, invalid-reflow rejection, fixed slots, mobile labels, and post-swap measurement are explicit; more replay/window tests can strengthen it. |
| RNG stream contract | `implemented-with-contract` | Stage2 kernel RNG v2 domain-separates init/local/swap streams; finite same-seed trajectory preservation is not claimed. |
| Diagnostics/counters | `active-CV011` | Local transition event accounting is strong, but remaining flow/ODEX/constraint/model/config state boundaries are still active. |

## 1. ODEX Controller

Current understanding:

- `odex_backend` is an endpoint extrapolation backend, not a full public
  Hairer ODEX library.
- The explicit-midpoint rows and extrapolation tableau are in the ODEX/GBS
  family.
- The step-number sequence is Hairer `IWORK(3)=3`.
- `calculate_wk` uses positive work for signed intervals; `calculate_hk`
  preserves the sign of integration direction.
- `flowzr` implements inverse flow by reversing RHS scale rather than by
  passing a negative physical flow time.

Open surfaces:

- first-step policy is `h=0.01*t`, not Hairer's user/derivative-informed `H`;
- no explicit Hairer step-size growth/shrink bounds are visible;
- order demotion/promotion thresholds use source-local `0.9` logic rather than
  a visibly separated `0.8` / `0.9` default pair;
- h-min is a TLTM-specific floor and failure policy;
- conservative stability control is reduced-scope and default-off;
- rejection/demotion branches need branch tests.

Decision:

- Treat ODEX as `partial/open-needs-proof`.
- Do not change source in this report.
- The next ODEX work should be tests/decision first, then source only if a
  deliberate controller correction is approved.

Detailed packet:

- `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`

## 2. Flow, Inverse Flow, And Jacobian RHS

Current understanding:

- `flowz` builds a real vector from physical seed coordinates with imaginary
  parts zero and integrates forward to `t=x(1)`.
- `flowzr` converts the current complex state to a real vector and integrates
  with RHS scale `-1` for the same nonnegative flow time.
- `rhs_flow_vec_context` calls `ds(z)` and maps the conjugated/scaled complex
  derivative into the real ODE RHS.
- `flow` evolves both the complex coordinate and Jacobian map; the Jacobian RHS
  applies `hessian_vec` to each Jacobian column and maps the result through the
  same conjugated/scaled real representation.
- The flow workspace owns ODEX endpoint buffers/RHS scratch after CV-011 route
  A, reducing hidden callback state on active Stage1/Stage2 paths.

Open surfaces:

- exact derivative formula closure belongs with the model module and Tapenade
  or hand derivative audit;
- ODEX controller open surfaces affect flow endpoint reliability;
- model tape/cache and remaining flow/ODEX counters are still CV-011 active
  state boundaries.

Decision:

- Treat flow/Jacobian RHS as `reference-mapped/partial`, not as a current bug.

## 3. Simplified Newton Constraint Solver

Current understanding:

- RATTLE constructs `del_z = step_size*momentum - step_size**2*dV`, matching the
  TLTM unit-mass complex trial displacement convention used in prior audits.
- `solve_constraint_newton_seeded` forms the residual as
  `z + del_z - lambda - flowz(xt+u)` in real-vector form.
- `solve_projected_step` solves the fixed-base Jacobian system, keeps the
  real/base component as the seed-coordinate correction, and uses the remainder
  as the normal/Lagrange component.
- Stagnation/divergence/tiny-step guards are implementation guards, not changes
  to the defining simplified Newton equation.

Decision:

- Treat Simplified Newton as `closed-for-current-gate`.
- Reopen if residual sign, `del_z` normalization, fixed-base Jacobian use,
  projection decomposition, tolerance acceptance, or force normalization
  changes.

## 4. RATTLE / HMC Proposal

Current understanding:

- The RATTLE step computes the first force term, projects the trial position
  with Newton then QN rescue if enabled, performs strict final `flow(...)`,
  reconstructs midpoint momentum from `(z_final-z_initial)/step_size`, subtracts
  the second force term, and projects momentum back to the tangent component.
- Final proposal construction requires strict final flow; QN navigation assist
  is not allowed to construct accepted final physical states.
- The reverse gate replays the reverse step with negated final momentum and
  checks x, z, Jacobian, and momentum against tolerance.
- If projection/final flow/reverse gate fails, Metropolis receives a failed
  proposal boundary and the live chain state is not committed.

Open surfaces:

- failure-as-rejection differs from the paper momentum-flip fallback language,
  but is an explicit project Markov-boundary policy;
- every status branch and diagnostic side effect still needs the same typed
  discipline as F4 local-transition events;
- reverse-gate replay accounting still interacts with remaining diagnostic
  state surfaces.

Decision:

- Treat RATTLE as `mostly-matched` for the main update, with
  `project-policy-partial` status for failure and reverse-gate boundaries.

## 5. BTN/QN Residual And Official DFO-LS Route

Current understanding:

- QN p28 is BTN/backflow rescue after primary simplified Newton, not the
  standard `(u,lambda)` residual.
- The residual now uses paper variables:
  `xi(1:n)=b`, `xi(n+1:)=a`, and actual correction
  `-J*(a+i*b)`.
- The residual returns `Imag(flowzr(ztrial))` and the `a` block, matching the
  BTN condition that the backflow lands on the real manifold with `a=0`.
- `initial_guess_from_jacobian` solves `J dz = +del_z` and maps
  `xi1=Imag(dz)`, `xi2=Real(dz)`, consistent with the paper-variable residual.
- The official DFO-LS bridge calls the embedded official package, then rechecks
  the resulting/best state through TLTM's own residual certification before
  accepting.
- The default active backend is official DFO-LS with `stable_gate77` policy;
  the internal legacy/in-house path remains selectable only by explicit
  backend override.

Open surfaces:

- official DFO-LS package use is accepted for representative/kernel scope, not
  proof of final production-output completion;
- p28 budgets, near/far route classification, watchdogs, and force-best
  controls are project controller policy and should not be described as exact
  paper machinery unless separately audited;
- internal solver path remains legacy-comparison surface, not the canonical
  modernization claim.

Decision:

- Treat BTN/QN residual math as `matched-core`.
- Treat QN route controller policy as `partial/open-needs-proof`.

## 6. Navigation Assist Policy

Current understanding:

- ODEX/intode solver assist is allowed only for h-min failures under selected
  flow contexts and roles.
- Canonical policy is strict NT, QN navigation assist, unassisted
  certification, strict final flow, reverse gate, then Metropolis.
- Assist is navigation for residual evaluation, not permission to skip final
  proposal construction checks.

Decision:

- Treat navigation assist as an `implemented project policy`.
- It is not a paper algorithm claim; it is a product route definition that must
  remain labeled in manifests and reports.

## 7. Metropolis And Live-State Mutation

Current understanding:

- `metropolis_step` initializes proposed outputs to the current state.
- If proposal construction fails, Hamiltonian values are invalid, `Delta H` is
  invalid, or reverse gate rejects, it restores output buffers to the current
  state and reports a failed/rejected transition.
- For finite proposals, it computes `Delta H = H_final - H_initial` and accepts
  with probability `1` for nonpositive `Delta H` or `exp(-Delta H)` otherwise.
- Stage2 commits `slot%x`, `slot%z`, and `slot%jac` only when `accepted`.

Decision:

- Treat Metropolis/live-state mutation as `matched` for the current proposal
  boundary.
- Reopen if any caller commits failed proposal buffers or changes status
  semantics.

## 8. Stage2 Tempering, Swap, Measurement, And RNG

Current understanding:

- The Stage2 loop is now local updates, swap sweep, label refresh/round-trip
  update, then measurement/history/label trace.
- Slots are fixed flow-time zones; labels represent mobile walkers.
- `attempt_adjacent_swap` reflows each base configuration at the other slot's
  flow time, computes `E = Re S - Re logdetJ`, and accepts with
  `min(1, exp(-[(E_a(y)+E_b(x))-(E_a(x)+E_b(y))]))`.
- Invalid current energy or invalid proposed reflow rejects the swap.
- Accepted swaps update the fixed slots with reflowed states and exchange
  labels.
- The selected sweep schedule attempts one alternating adjacent-pair parity per
  cycle.
- Stage2 kernel RNG v2 domain-separates init, local-momentum, local-accept, and
  swap-accept random streams.  This is a reproducibility contract, not a claim
  that finite trajectories match the old shared serial stream.

Open surfaces:

- full first-N-cycle replay tests would strengthen the swap/RNG draw boundary;
- one parity per cycle is a production convention and should remain explicit in
  protocol files;
- compatibility modes must not be promoted to canonical equivalence by accident.

Decision:

- Treat Stage2 as `protocol-mapped/partial-tests`.
- It is strong enough to describe the selected protocol, but not enough to
  erase CV-012 for every future Stage2 policy change.

## 9. Diagnostics, Counters, Config, And Hidden State

Current understanding:

- F4 local-transition event accounting is strong: local counters derive from a
  typed event and M4 validates invariants.
- CV-011 has migrated many active shared states into run/context objects:
  RNG, flow/ODEX workspace, HMC/QN flow workspace, official DFO-LS callback,
  QN trace/eval/diagnostics/policy, HMC policy/replay diagnostics, profiler,
  HMC reversibility diagnostics, and Newton eval-flow status context.
- Remaining active state surfaces include constraint-solver aggregate/reverse
  gate path/failure-capture counters, flow/ODEX counters/traces/last-failure
  snapshots, model tape/cache state, and config mirror.

Decision:

- Treat diagnostics/counters as `active-CV011`, not as algorithm proof.
- Do not use counters as correctness evidence until their denominator, scope,
  replay/probe inclusion policy, and schema meaning are typed.

## Current Safe Claims

Safe to claim now:

- The main retained core algorithms are no longer black boxes; their active
  source boundaries and reference roles have been audited to a useful degree.
- The ODEX backend is a Hairer-ODEX-family endpoint extrapolation integrator
  with the canonical `IWORK(3)=3` sequence.
- Simplified Newton, BTN residual variables, Metropolis live-state mutation,
  and Stage2 swap acceptance are source-understood and broadly
  reference-consistent under their stated product policies.
- QN navigation assist, reverse gate, failure-as-rejection, one-parity Stage2
  sweep, and Stage2 RNG v2 are explicit project contracts.

Not safe to claim now:

- all handwritten algorithms are paper-correct at controller/detail level;
- ODEX is a full Hairer ODEX controller implementation;
- production readbacks prove mathematical correctness of every retained
  handwritten algorithm;
- diagnostics counters are proof unless their scope and denominator are typed;
- compatibility RNG modes are production-equivalent to Stage2 kernel RNG v2.

## Priority Follow-Up Queue

1. ODEX controller closure:
   - decide or implement first-step policy;
   - add step-size bound/order-threshold branch tests;
   - classify h-min and stability behavior as Hairer-mapped or TLTM-specific.

2. QN route controller packet:
   - budgets, watchdogs, near/far classification, force-best route, and
     official-package bridge edge cases.

3. RATTLE failure/status packet:
   - every proposal failure status;
   - stay-put identity;
   - reverse-gate replay/status/counter boundaries.

4. Stage2 swap/RNG replay packet:
   - first-N-cycle deterministic replay;
   - RNG draw boundary;
   - one-parity schedule convention;
   - post-swap measurement boundary.

5. Diagnostics/CV-011 continuation:
   - typed flow/ODEX and constraint counters;
   - model tape/cache state;
   - config mirror/product boundary.

## Bottom Line

The user's concern is correct and now explicitly reflected in the project
state.  The audit body shows that the handwritten algorithms are not merely
unexamined, but also not all fully closed at the paper-detail level.  The next
modernization claims must use the classifications above instead of collapsing
reference mapping, behavior preservation, and publication-grade correctness
into one word.
