# Handwritten Algorithm Mismatch Resolution Table

Date: 2026-05-16 JST
Status: partially confirmed by user; row-level source behavior changes still
require their own F8/M4/affected-baseline packets.

## Why This Exists

The all-handwritten audit found several non-paper-exact or not-yet-paper-signed
surfaces.  After that audit, some engineering/productization changes were made,
but the ODEX controller behavior was frozen as TLTM endpoint policy without a
separate explicit user confirmation of each mismatch surface.

This table reopens that decision boundary.  It does not revert any completed
source cleanup or state productization.  It also does not authorize new
behavior-changing patches by itself.  Each row below needs an explicit decision:

- `change_to_paper_or_stronger_reference`
- `keep_as_project_policy`
- `add_evidence_first`
- `defer`

Until a row is confirmed, do not describe it as final paper-correctness
closure.  For confirmed rows, this table records the direction only; it is not
itself a source patch authorization.

## Current Facts

- The all-handwritten audit found no immediate current-route source bug that
  required an urgent physics-changing patch.
- That does not mean the current behavior is paper-correct.
- F18b.3a changed ODEX/flow diagnostics and runtime-trace ownership, not ODEX
  controller numerical behavior.
- F19 removed internal DFO-like helpers, force-best/watchdog/near-far retry
  policy, and left active QN solving on the official DFO-LS package plus TLTM
  residual certification.
- F15b deleted active solver assist.

## Confirmed Decisions

Confirmed by user on 2026-05-16 JST:

| ID | Decision | Operational consequence |
| --- | --- | --- |
| HWM-ODEX-001 | `change_to_paper_or_stronger_reference` | Start `F18b.4 ODEX controller paper-alignment`.  Do not batch all controller surfaces into one patch.  First write the Hairer/paper controller spec and branch tests, then patch small families with M4 and paired screens. |
| HWM-RATTLE-001 | `keep_as_project_policy` for rejection-as-stay-put | Do not implement paper momentum reflection.  Formal line-audit, derivation, source hardening, and proof-test packets now document Markov legality, direct/warmup failed-output stay-put behavior, proposal-failure/reverse-gate statuses, and focused accounting/status mapping. |
| HWM-MET-001 | `change_api_contract` to reset output buffers on all rejection | Implemented and M4-passed on 2026-05-17 in `src/sampler/markovchain_metropolis.f90`: ordinary finite Metropolis rejection now resets `x_new/z_new/j_new` to the current state after a valid output-shape check.  `test_retained_core_rg_reject_identity` now covers both RG rejection and finite ordinary Metropolis rejection stay-put outputs. |

Rows not listed here are now closed for the current source-contract scope by
the HWA line-audit packets below, but may still have product/F9/F20 reopen
boundaries.

## Decision Table

| ID | Surface | Audit status | Current behavior | Mismatch / caveat | Already changed after audit? | Risk if changed | Proposed handling for confirmation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HWM-ODEX-001 | ODEX controller: `h0`, h-min, growth/shrink, order, rejection, signed interval, stability | paper-family core; controller open-needs-proof | Endpoint GBS/ODEX-family integrator with `IWORK(3)=3`; `h0=0.01*t`; TLTM h-min; no explicit Hairer `WORK(4)/WORK(5)` bounds; order/reject/stability are TLTM policy | Not full Hairer ODEX controller.  Biggest paper-correctness blocker. | Only state/diagnostics ownership changed in F18b.3a; numerical controller behavior unchanged. | High: endpoint success/failure, proposal failures, reverse gate, observables, counters can drift. | Confirmed: change toward Hairer/paper behavior.  Reopen as F18b.4.  Split into patch families: bounds/order first, then `h0`, h-min, rejection/status, stability.  Each needs branch tests, M4, and 1k paired screen before 10k. |
| HWM-FLOW-001 | Antiholomorphic flow RHS and Jacobian RHS | paper-matched core; product-state caveat; current-scope line audit/proof tests implemented | `dot z = conjg(dS/dz)`, inverse flow via RHS scale `-1`, Jacobian via conjugated Hessian-vector products | Formula level is mapped; do not let this absorb ODEX controller, model-cache, or failure-status claims. | Yes: F18b.3a migrated flow diagnostics/trace ownership; `HWM_FLOW_MODEL_ACTION_LINE_AUDIT_20260517.md` adds equation readback, direct API hardening, and focused tests. | Low for formula if unchanged; medium if model/tape/cache or status handling changes. | Closed for current flow/model RHS scope. Reopen only on RHS/Jacobian/status/model-cache/precision edits. |
| HWM-RATTLE-001 | RATTLE/HMC failure policy | mostly paper-matched core; project-policy failure surface; line-audit, derivation/readback, source hardening, and proof tests are implemented for the current scope | Core step order maps to RATTLE/HMC; live proposal wrapper resets failed proposals to stay-put; direct `rattle_step_core` and warmup `rattle2` now reset failed outputs to stay-put after valid shape checks; HMC proposal status to Metropolis transition-status mapping is explicitly tested | Paper discusses momentum-flip/continuation for projection failure; TLTM uses rejection-as-no-endpoint.  `HWM_RATTLE_HMC_LINE_AUDIT_20260517.md` records the line-level audit, `HWM_RATTLE_HMC_DERIVATION_PACKET_20260517.md` records action/gradient, packing, projection, Hamiltonian, initial momentum, one-step RATTLE, Newton residual/projection split, QN boundary, final flow/momentum, wrapper, reverse gate, Metropolis/status/counter, warmup, diagnostic, legacy-trigger, and finite-precision claim boundaries, and `HWM_RATTLE_HMC_PROOF_TEST_API_HARDENING_20260517.md` records the implemented API hardening and tests. | Yes: retained-core tests now cover RG reject stay-put, finite Metropolis reject stay-put, direct core failure-output stay-put, warmup failure-output stay-put, and status mapping; no switch to paper reflection. | Very high if changed: proposal kernel, reversibility, acceptance, and event accounting can change. | Closed for current RATTLE/HMC rejection-as-stay-put scope.  Reopen only if behavior/status/schema/policy changes; continue HWA-NT, HWA-QN, model/action, diagnostics, and legacy trigger rows separately. |
| HWM-NEWTON-001 | Simplified Newton projection controller | paper-matched target; project-policy controller; current-scope line audit/proof tests implemented | Fixed-Jacobian/simple Newton residual target through `flowz`; iteration caps, divergence/stagnation/tiny-step exits are TLTM policy; direct invalid-input API guards now fail stay-put | Paper target equation maps, but controller/failure constants are not paper-exact. | Yes: `HWM_NEWTON_CONSTRAINT_LINE_AUDIT_20260517.md` adds direct `jac`/tol API hardening and focused tests for replay, projection split, failure-output reset, invalid tolerance, invalid Jacobian shape, and iteration-exhaustion stay-put. | Medium to high if controller predicates are changed: can alter fallback frequency and proposal failures. | Closed for current simplified-Newton scope. Keep controller constants as documented TLTM policy unless future evidence shows a harmful/nonphysical predicate or the user explicitly chooses a behavior-changing paper-alignment route. |
| HWM-QN-001 | BTN/QN / official DFO-LS bridge controller | current-scope line audit/proof tests implemented | Active route uses official DFO-LS package plus TLTM residual gate/certification; internal DFO-like helpers removed; direct invalid-input API guards fail before package/callback work | Official package core is not handwritten, but TLTM wrapper choices remain handwritten: initial seeds, callback edge cases, residual gate, final-flow/reverse-gate interaction. | Yes: F19 removed internal backend, near/far retry, force-best, watchdog/budget, relaxed quasi tolerance. `HWM_QN_OFFICIAL_DFOLS_LINE_AUDIT_20260517.md` adds wrapper line audit, direct API hardening, BTN residual/seed proof, package route census, and context-isolation tests. | Medium if changed: residual gate or wrapper changes affect QN success/failure and proposal surface. | Closed for current official DFO-LS wrapper scope. Reopen only if package/preset/callback policy, BTN residual, seed mapping, TLTM residual gate, final-flow/RG certification, trace classification semantics, or public route schema changes. |
| HWM-MET-001 | Metropolis output buffer semantics | output-contract patch implemented and M4-passed | After a valid output-shape check, finite ordinary Metropolis reject, proposal failure, Hamiltonian/Delta-H invalid rejection, and reverse-gate rejection reset `x_new/z_new/j_new` to the current state.  Output-size mismatch returns before reset because the buffers are the wrong shape. | Closed for the selected API caveat; direct callers can treat `accepted=.false.` as stay-put outputs except for explicit output-size mismatch. | Yes: focused patch plus retained-core finite-reject/RG-reject stay-put coverage. | Low: current live-chain callers already commit only on accepted proposals; direct API/tests now see corrected stay-put outputs. | Keep the focused retained-core test in M4.  Do not use this as proof of broader HMC/RATTLE paper-correctness. |
| HWM-STAGE2-001 | Stage2 replica exchange, schedule, swap replay, RNG replay evidence | current-scope line audit/source hardening/proof tests implemented | Swap accepts using `Re S - Re log det J` after reflow; Stage2 RNG v2 gives domain-separated init/local/swap streams; invalid energies fail closed | Formula/order/RNG boundary is mapped for the current unit scope; production-redo and output-schema claims remain separate. | Yes: Stage2 RNG v2 implemented; `HWM_STAGE2_RNG_PROTOCOL_LINE_AUDIT_20260517.md` adds protocol readback, invalid effective-energy hardening, swap proof tests, Philox and MT95 replay tests. | Medium: schedule/RNG changes intentionally alter finite trajectories. | Closed for current Stage2/RNG scope. Reopen on cycle order, measurement boundary, label/slot semantics, RNG stream contract, swap draw boundary, output schema, or production-redo contract changes. |
| HWM-MODEL-001 | Action and model derivative provenance | current-scope line audit/proof tests implemented | `model_action_body.inc` is the formula source; generated derivatives are checked against closed-form action/ds/Hessian/Hv and finite differences | Current model formula and determinant/phase convention are documented; branch crossings and future model changes remain reopen surfaces. | Yes: `HWM_FLOW_MODEL_ACTION_LINE_AUDIT_20260517.md` adds action derivation readback and proof tests. | Very high if formula/sign changes. | Closed for current model/action scope. Reopen for formula/sign/branch convention/model-cache/precision changes. |
| HWM-DIAG-001 | Diagnostics/counters/status schema | current-scope closure packet implemented | Typed local-transition event exists; accepted events canonicalize contradictory direct `proposal_failed` input; broader flow/constraint/replay/capture counters are engineering diagnostics | Diagnostics can support debugging and evidence, but cannot be used as paper-correctness proof. | Yes: F18b.3a moved ODEX/flow diagnostics to explicit contexts; `HWM_REMAINING_HANDWRITTEN_SURFACES_CLOSURE_20260517.md` adds event canonicalization. | Low to high depending on public output/schema changes. | Closed for current diagnostics source-contract scope. Treat any public counter/status semantic fix as F4/F7/F8 behavior/schema packet. |
| HWM-LEGACY-001 | Legacy `istest/testmom`, `eo`, `rattle2`, strange/internal names | paper-correctness scope closed; F9 product cleanup remains | `istest/testmom` are test-only deterministic momentum hooks; production keeps `istest=false`; `rattle2/decompose2` are compatibility names around audited routines | Not active production bug, but dangerous for future API/product hardening. | Yes: remaining-surfaces closure classifies the hooks/names and hardens `decompose2`; no deletion/rename yet. | Low if guarded/deleted under production-off contract; medium if old tests depend on it. | Closed for paper-correctness scope. F9 cleanup packet can remove/rename or make hooks explicit test APIs with exact-output or affected-baseline protection. |
| HWM-CFG-001 | Precision/tolerance/config profile | strict-double source-contract closure implemented; F20 active | Strict double precision is current baseline; invalid/nonfinite env/config/tolerance inputs fail closed or preserve defaults; future GPU may need single/mixed precision and weaker tolerances | Tolerances are not paper-correctness by themselves; they define certified numerical profiles. | Yes: runtime/config/Stage1/Stage2 finite-control hardening is implemented; F20 remains a future product mode. | High if default tolerance/precision changes. | Closed for current strict-double config scope. Design explicit precision/tolerance profiles and certify single/mixed modes separately under F20. |

## Proposed Ordering If User Chooses To Change

This ordering is only a proposal for review, not an authorization:

1. HWM-ODEX-001 F18b.4 controller paper-alignment spec and branch tests.
2. HWM-MET-001 output-buffer contract is implemented and M4-passed.
3. HWM-RATTLE-001 formal rejection-as-stay-put proof/test packet is implemented and M4-passed.
4. HWM-QN-001 wrapper/certification detail packet after the official DFO-LS
   cleanup already done.
5. HWM-STAGE2-001 replay/order-invariance evidence.
6. HWM-MODEL-001 derivation note.
7. HWM-LEGACY-001 and HWM-DIAG-001 cleanup/schema packets.
8. HWM-CFG-001 precision/tolerance profiles.

Items 4-8 now have current-scope HWA closure packets. Future work in those
areas is productization, schema cleanup, precision certification, or behavior
change, not an unresolved all-handwritten audit blocker.

## Remaining Confirmation Needed

No mismatch-table row remains as an all-handwritten audit blocker for the
current source-contract scope. Reopen rows only when their listed behavior,
schema, product, precision, or publication-surface boundaries change.
