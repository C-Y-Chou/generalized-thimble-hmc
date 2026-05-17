# HWM-RATTLE/HMC Line Audit Packet

Date: 2026-05-17 JST

Status: line-level audit/readback packet.  The proposed API hardening and
proof-test items from this packet were later implemented in
`HWM_RATTLE_HMC_PROOF_TEST_API_HARDENING_20260517.md`.

## Scope

This packet follows the ODEX-equivalent handwritten audit requirement for the
RATTLE/HMC proposal path.  It covers more than the already-confirmed
rejection-as-stay-put policy:

- proposal wrapper and multi-step HMC integration in `src/sampler/hmc.f90`;
- one-step RATTLE core in `src/sampler/hmc_integrator_core.f90`;
- simplified Newton constraint solve in `src/sampler/hmc_constraints.f90`;
- RATTLE force, Hamiltonian, and projection helpers in
  `src/sampler/hmc_kernels.f90`;
- Metropolis and local-transition boundary in
  `src/sampler/markovchain_metropolis.f90`,
  `src/sampler/markovchain_transition_status.f90`, and
  `src/sampler/tltm_types.f90`;
- current deterministic coverage in
  `tests/test_retained_core_rattle_rg_contract.f90`,
  `tests/test_retained_core_rg_reject_identity.f90`, and
  `tests/test_retained_core_newton_contract.f90`.

## Readback Summary

The live Metropolis-facing proposal route has the important stay-put protection:
`integrate_hmc_proposal`/`rattle` initializes output buffers to the input state,
maps RATTLE step failures to proposal statuses, and on failure resets
`final_x/final_z/jacf` to the input state before returning a failed proposal.
`metropolis_step` then treats proposal failure, invalid Hamiltonian, invalid
Delta-H, reverse-gate rejection, and ordinary finite Metropolis rejection as
non-accepted transitions that leave the public output buffers at the current
state.

The successful one-step RATTLE path is already guarded by deterministic tests:
endpoint replay, final momentum tangency, and reverse-gate replay success are
covered.  The simplified Newton target residual is also replay-tested for
accepted solves.

This is not enough to claim universal paper-correctness.  Several source
surfaces are project policy, API-boundary caveats, or still need derivation
signoff.

## Line-Level Map

| Area | Source lines read | Classification |
| --- | --- | --- |
| HMC proposal statuses and wrapper | `src/sampler/hmc.f90:33-117` | matched engineering boundary; status surface exists |
| HMC proposal setup, momentum source, initial projection, multi-step loop, failure abort | `src/sampler/hmc.f90:119-278`, `515-521` | live stay-put wrapper is sound; legacy `istest/testmom` caveat |
| HMC diagnostic reverse probe | `src/sampler/hmc.f90:282-431` | diagnostic only; does not gate acceptance |
| HMC step-status to proposal-status mapping | `src/sampler/hmc.f90:433-454` | engineering policy; detail collapses by design |
| Warmup `rattle2` | `src/sampler/hmc.f90:525-714` | legacy/warmup path; failure output contract is weaker than proposal wrapper |
| RATTLE core step | `src/sampler/hmc_integrator_core.f90:200-626` | mostly matched core plus QN/final-flow/RG project policy |
| Reverse-gate replay | `src/sampler/hmc_integrator_core.f90:646-711` | project policy; reversibility certification gate |
| RATTLE force/projection/Hamiltonian helpers | `src/sampler/hmc_kernels.f90:14-111` | formula core needs derivation signoff; one API guard caveat |
| Simplified Newton constraint solve | `src/sampler/hmc_constraints.f90:122-441` | residual target is retained-core matched; controller constants are project policy |
| Metropolis boundary | `src/sampler/markovchain_metropolis.f90:66-187` | HWM-MET-001 patched; live stay-put output contract now explicit |
| Local-transition counters | `src/sampler/tltm_types.f90:133-197` | typed event exists; some legacy counter names remain compatibility aggregates |

## Findings For Confirmation

| ID | Finding | Why it matters | Proposed handling |
| --- | --- | --- | --- |
| HWM-RATTLE-API-001 | `rattle_step_core` itself does not guarantee stay-put output buffers on every failure path.  It initializes `final_x/final_z` to the input state, but after final-flow or reverse-gate failure it may return with candidate outputs while `method_converged=.false.`.  Current HMC proposal callers immediately abort/reset, so this is not a live Metropolis-state bug. | Direct callers or future refactors could incorrectly treat failed core outputs as meaningful.  Existing direct core test covers only a successful step. | I recommend an API-hardening patch: make `rattle_step_core` reset `final_x/final_z/jacf` to `state_x/state_z/jaci` on all failure exits after shape checks, and add a focused direct-core failure-output test.  This is low behavioral risk for the live chain but should still get F8/M4 because it changes direct API outputs on failed core calls. |
| HWM-RATTLE-WARMUP-001 | `rattle2`/`integrate_hmc_warmup` has weaker failure semantics than `rattle`: its local `abort_with_failure` resets `final_hamiltonian` and `jacf`, but does not reset `final_x/final_z` to the warmup input state. | Warmup callers assign `x_state = x_trial` after `integrate_hmc_warmup`; if the warmup integrator fails after partial progress, the caller can see a partially advanced output before later flow/Hamiltonian checks. | I recommend source hardening unless the user wants warmup partial-progress semantics.  Patch `rattle2` failure abort to reset `final_x/final_z/jacf`, add a warmup failure-output test, and classify any changed warmup behavior with an affected-baseline decision. |
| HWM-RATTLE-LEGACY-001 | In `rattle`, `istest/testmom` overrides an explicit `momentum_in` after the optional momentum has already been accepted. | Production keeps `istest=.false.`, but this is surprising API behavior and can confuse deterministic tests or future product callers. | Treat as F9 behavior-preserving cleanup after the RATTLE packet: replace global test momentum override with an explicit test-only input path, or make explicit `momentum_in` take precedence.  Do not patch inside the proof packet unless approved. |
| HWM-RATTLE-STATUS-001 | HMC has detailed proposal statuses, but `metropolis_step` collapses most HMC proposal failures to `metropolis_status_proposal_failed`; only output-size mismatch and reverse-gate rejection remain distinct at the Metropolis transition status. | This is legal for MCMC rejection, but it limits public failure classification and can make diagnostics look more paper-complete than the public schema actually is. | Keep current schema for now.  Add a status-coverage table/test documenting every HMC proposal status -> Metropolis status/counter mapping.  Finer public statuses belong to F10/F11 typed-result/schema work. |
| HWM-RATTLE-COUNTER-001 | `projection_failure_count` remains a legacy aggregate name for proposal failures, while typed counters distinguish reverse-gate rejection, proposal failure, invalid Hamiltonian, invalid Delta-H, and output-size mismatch. | The counter is compatibility-preserving but semantically misleading if cited as literal projection-only evidence. | Keep the legacy field until schema v2.  Add documentation/tests that treat it as a compatibility aggregate, not proof of the physical projection-failure mechanism. |
| HWM-RATTLE-FORMULA-001 | `calculate_dV` uses `dV = E0_real/2` and ignores `E0_perp`; `decompose2`/`solve_projected_step` implement the real-Jacobian projection/decomposition used for momentum tangency and Newton updates.  Existing tests verify replay/tangency, but the formula provenance is not yet an independent derivation packet. | This is probably the intended TLTM/GT-HMC core, and previous retained-core audit says the Newton residual target maps to the simplified RATTLE equations.  Still, without an equation packet we should not call the helper layer universally paper-correct. | Add a short derivation/provenance packet tying `conjg(ds)`, the `1/2` factor, real/complex packing, `decompose2`, and Newton `lambda` signs to the constrained-HMC equations.  No source change unless the derivation exposes a sign/factor bug. |
| HWM-NEWTON-CTRL-001 | The simplified Newton residual target is replay-tested, but the controller constants and exits (`near_tol`, stagnation/divergence/tiny-step thresholds, dynamic iteration cap) are TLTM policy, not paper-given constants. | Controller changes alter constraint-failure frequency, QN fallback frequency, reverse-gate events, and observables. | Do not change opportunistically.  Create a separate Simplified Newton detail packet after RATTLE/HMC, with line-level treatment of residual target vs controller policy and focused failure-predicate tests. |
| HWM-RATTLE-QN-BOUNDARY-001 | `rattle_step_core` contains official DFO-LS bridge invocation and QN diagnostics/classification inside the RATTLE step.  After F19 it is one package attempt plus TLTM certification gates, but the wrapper/certification choices are not closed by the RATTLE audit. | Without separating this boundary, a RATTLE proof packet could accidentally imply the QN wrapper is paper-correct. | Keep QN as a separate HWM-QN packet: residual gate, official callback edge cases, final-flow certification, reverse-gate interaction, and diagnostics after internal-helper deletion. |
| HWM-RATTLE-HAM-001 | `calculate_hamiltonian` only warns if `size(p) /= 2*size(z)` and still computes `0.5*norm2(p)**2 + Re S(z)`.  Current callers mostly check shapes before this path. | This is a direct-helper API guard caveat, not a current live-chain issue. | Low-priority API hardening: either add a checked Hamiltonian helper/status or add direct tests documenting caller-owned shape responsibility.  Defer unless product API hardening is in scope now. |

## Confirmed Policy Boundary

HWM-RATTLE-001 remains the selected TLTM policy: failed proposal construction,
reverse-gate rejection, invalid proposal Hamiltonian, invalid Delta-H, and
ordinary Metropolis rejection are legal rejection/stay-put transitions.  We are
not implementing the paper's momentum-reflection continuation route unless that
decision is explicitly reopened.

The required proof/test packet should therefore prove the project policy, not
paper-reflection semantics:

- failed proposal does not mutate accepted Markov state;
- public HMC/Metropolis outputs are stay-put after valid output-shape checks;
- reverse-gate rejection is counted as a local rejection, not a Metropolis
  energy rejection;
- detailed HMC statuses and public Metropolis statuses are mapped deliberately;
- diagnostic reverse probes/replay counters are not physical proposal counters.

## Implemented Source Patch

The user confirmed the handling direction.  The narrow source-facing packet is
now implemented in
`HWM_RATTLE_HMC_PROOF_TEST_API_HARDENING_20260517.md`:

1. `rattle_step_core` resets `final_x/final_z/jacf` to
   `state_x/state_z/jaci` on failed exits after valid shape checks.
2. `rattle2` / `integrate_hmc_warmup` resets failed warmup outputs to the
   warmup input state and marks the final Hamiltonian unavailable.
3. `test_retained_core_rg_reject_identity` covers direct-core failed-output
   stay-put, warmup failed-output stay-put, finite Metropolis rejection output
   reset, reverse-gate rejection stay-put, and every current HMC proposal
   status to Metropolis transition-status mapping.
4. Retained-core RATTLE/RG, Newton, QN route, and full M4 guardrails pass.

Therefore `HWM-RATTLE-API-001`, `HWM-RATTLE-WARMUP-001`, and the focused
coverage part of `HWM-RATTLE-STATUS-001` are closed for the current scope.
`HWM-RATTLE-LEGACY-001`, Newton controller constants, QN wrapper boundaries,
and model/action provenance remain separate HWA rows.

## Recommended Next Patch If Reopened

If this area is reopened, the next narrow implementation slice should be:

1. Write a new F8 packet for the changed behavior/status surface.
2. Add focused direct tests before any Stage2/Stage3 screen.
3. Use remote PBS for any simulation or affected-baseline screen.

The current packet is no longer awaiting confirmation for the API hardening
items.

## 2026-05-17 Derivation Addendum

`HWM_RATTLE_HMC_DERIVATION_PACKET_20260517.md` now completes the full
pre-source-change derivation/provenance packet requested before source
hardening.  It is not limited to the user-mentioned momentum/symplectic
surface; it covers the RATTLE/HMC internal proposal path as a whole: action and
gradient convention, real/complex packing, tangent projection, Hamiltonian,
initial momentum source/projection, one-step RATTLE, simplified Newton residual
and projection split, QN/official DFO-LS boundary, strict final flow, final
momentum projection, multi-step wrapper, reverse gate, Metropolis boundary,
status/counter accounting, warmup, diagnostic, and legacy/test-trigger routes.

It closes the successful-core sign/factor question:

- `dV = E0_real/2` is the intended half-gradient convention;
- `del_z = h*p - h**2*dV` therefore matches
  `Delta z = h*pi - h**2/2*conjg(dS)`;
- the simplified Newton residual is
  `B = z + Delta z - lambda - flowz(x+u)`;
- `decompose2` implements the tangent split `J Re(J^{-1} b)`;
- the final momentum update is
  `pi_half = (z' - z)/h`,
  `pi_tilde' = pi_half - h/2*conjg(dS(z'))`,
  then tangent projection.

This addendum did not authorize source edits by itself; the follow-up
authorization and implementation are now recorded in
`HWM_RATTLE_HMC_PROOF_TEST_API_HARDENING_20260517.md`.  The remaining
source-facing items are the legacy `istest/testmom` cleanup boundary and the
separate Newton-controller/QN-wrapper/model-action packets.
