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
| HWM-RATTLE-001 | `keep_as_project_policy` for rejection-as-stay-put | Do not implement paper momentum reflection.  Add a formal proof/test packet documenting Markov legality, every proposal-failure/reverse-gate status, stay-put identity, and accounting behavior. |
| HWM-MET-001 | `change_api_contract` to reset output buffers on all rejection | Implement a focused Metropolis API patch so `accepted=.false.` implies `x_new/z_new/j_new` equal the current state.  Expected live-chain behavior should remain unchanged for current callers, but this still needs focused tests and M4. |

Rows not listed here remain pending or evidence-first according to the table
below.

## Decision Table

| ID | Surface | Audit status | Current behavior | Mismatch / caveat | Already changed after audit? | Risk if changed | Proposed handling for confirmation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HWM-ODEX-001 | ODEX controller: `h0`, h-min, growth/shrink, order, rejection, signed interval, stability | paper-family core; controller open-needs-proof | Endpoint GBS/ODEX-family integrator with `IWORK(3)=3`; `h0=0.01*t`; TLTM h-min; no explicit Hairer `WORK(4)/WORK(5)` bounds; order/reject/stability are TLTM policy | Not full Hairer ODEX controller.  Biggest paper-correctness blocker. | Only state/diagnostics ownership changed in F18b.3a; numerical controller behavior unchanged. | High: endpoint success/failure, proposal failures, reverse gate, observables, counters can drift. | Confirmed: change toward Hairer/paper behavior.  Reopen as F18b.4.  Split into patch families: bounds/order first, then `h0`, h-min, rejection/status, stability.  Each needs branch tests, M4, and 1k paired screen before 10k. |
| HWM-FLOW-001 | Antiholomorphic flow RHS and Jacobian RHS | paper-matched core; product-state caveat | `dot z = conjg(dS/dz)`, inverse flow via RHS scale `-1`, Jacobian via conjugated Hessian-vector products | Formula level is mapped; do not let this absorb ODEX controller, model-cache, or failure-status claims. | F18b.3a migrated flow diagnostics/trace ownership. | Low for formula if unchanged; medium if model/tape/cache or status handling changes. | Keep formula unchanged.  Add a short equation/provenance note and reopen only on RHS/Jacobian/status/model-cache edits. |
| HWM-RATTLE-001 | RATTLE/HMC failure policy | mostly paper-matched core; project-policy failure surface | Core step order maps to RATTLE/HMC; projection/reverse-gate/final-flow failures become proposal rejection/stay-put through callers | Paper discusses momentum-flip/continuation for projection failure; TLTM uses rejection-as-no-endpoint. | Retained-core tests and RG reject stay-put identity exist; no switch to paper reflection. | Very high if changed: proposal kernel, reversibility, acceptance, and event accounting can change. | Confirmed: keep rejection-as-stay-put as TLTM project policy.  Add proof/test packet for Markov legality, status coverage, stay-put identity, and accounting. |
| HWM-NEWTON-001 | Simplified Newton projection controller | paper-matched target; project-policy controller | Fixed-Jacobian/simple Newton residual target through `flowz`; iteration caps, divergence/stagnation/tiny-step exits are TLTM policy | Paper target equation maps, but controller/failure constants are not paper-exact. | Workspace/context ownership improved; controller behavior unchanged. | Medium to high: can alter fallback frequency and proposal failures. | Add detail packet for caps/failure predicates.  Prefer evidence-first; change only if a specific predicate is shown harmful or nonphysical. |
| HWM-QN-001 | BTN/QN / official DFO-LS bridge controller | residual target matched; controller partial | Active route uses official DFO-LS package plus TLTM residual gate/certification; internal DFO-like helpers removed | Official package core is not handwritten, but TLTM wrapper choices remain handwritten: initial seeds, callback edge cases, residual gate, final-flow/reverse-gate interaction. | Yes: F19 removed internal backend, near/far retry, force-best, watchdog/budget, relaxed quasi tolerance. | Medium: residual gate or wrapper changes affect QN success/failure and proposal surface. | Keep official DFO-LS package.  Add wrapper detail packet for residual gate, callback edge cases, and final-flow/RG certification. |
| HWM-MET-001 | Metropolis output buffer semantics | acceptance paper-matched; API caveat | Finite Metropolis reject can leave proposal values in `x_new/z_new/j_new`; callers commit only when `accepted` | Live Markov state is safe, but output buffers do not universally mean stay-put state. | RG/proposal-failure stay-put identity tests exist; ordinary finite reject output reset not changed. | Low to medium: changing buffers should not alter live chain if callers are correct, but may affect direct API/tests. | Confirmed: reset output buffers on all rejection.  This should be a small focused API patch with tests proving live-chain behavior and stay-put outputs. |
| HWM-STAGE2-001 | Stage2 replica exchange, schedule, swap replay, RNG replay evidence | acceptance paper-matched; replay evidence partial | Swap accepts using `Re S - Re log det J` after reflow; Stage2 RNG v2 gives domain-separated init/local/swap streams | Formula is mapped, but full order/schedule invariance and swap-isolation evidence are incomplete. | Yes: Stage2 RNG v2 implemented; anchors and M4 gates exist. | Medium: schedule/RNG changes intentionally alter finite trajectories. | Evidence-first: first-N-cycle signatures, local-update order invariance, swap isolation tests, rejected-swap sidecar evidence.  No source behavior change unless tests reveal a defect. |
| HWM-MODEL-001 | Action and model derivative provenance | source-consistent; not independently paper-signed | `model_action_body.inc` is the formula source; generated derivatives and finite-difference guardrails are internally consistent | Audit checked consistency against implemented action, not a fresh derivation from the physics paper/sign conventions. | No model formula change. | Very high if formula/sign changes. | Add a model/action derivation packet tying implemented action, signs, determinant/log convention, and branch conventions to the physics definition before claiming paper-level model correctness. |
| HWM-DIAG-001 | Diagnostics/counters/status schema | useful evidence; not paper signoff | Typed local-transition event exists; broader flow/constraint/replay/capture counters are engineering diagnostics | Diagnostics can support debugging and evidence, but cannot be used as paper-correctness proof. | Yes: F18b.3a moved ODEX/flow diagnostics to explicit contexts. | Low to high depending on public output/schema changes. | Continue schema/versioned diagnostics audits.  Treat any public counter/status semantic fix as F4/F7/F8 behavior/schema packet. |
| HWM-LEGACY-001 | Legacy `istest/testmom`, `eo`, `rattle2`, strange/internal names | legacy trigger/naming caveat | `istest/testmom` can override explicit momentum if enabled; production keeps it false | Not active production bug, but dangerous for future API/product hardening. | Not yet cleaned in this sequence. | Low if guarded/deleted under production-off contract; medium if old tests depend on it. | F9 cleanup packet: either remove/guard legacy trigger or make explicit test-only API.  Require exact-output or affected-baseline decision. |
| HWM-CFG-001 | Precision/tolerance/config profile | project policy; F20 active | Strict double precision is current baseline; future GPU may need single/mixed precision and weaker tolerances | Tolerances are not paper-correctness by themselves; they define certified numerical profiles. | F20 recorded, not implemented. | High if default tolerance/precision changes. | Keep strict double as canonical.  Design explicit precision/tolerance profiles and certify single/mixed modes separately. |

## Proposed Ordering If User Chooses To Change

This ordering is only a proposal for review, not an authorization:

1. HWM-ODEX-001 F18b.4 controller paper-alignment spec and branch tests.
2. HWM-MET-001 output-buffer contract, because it is small and clarifies API
   safety.
3. HWM-RATTLE-001 formal rejection-as-stay-put proof/test packet.
4. HWM-QN-001 wrapper/certification detail packet after the official DFO-LS
   cleanup already done.
5. HWM-STAGE2-001 replay/order-invariance evidence.
6. HWM-MODEL-001 derivation note.
7. HWM-LEGACY-001 and HWM-DIAG-001 cleanup/schema packets.
8. HWM-CFG-001 precision/tolerance profiles.

## Remaining Confirmation Needed

Confirmed rows are listed above.  Remaining high-impact rows still need a
decision:

- HWM-QN-001: keep official DFO-LS package wrapper with added certification
  docs/tests, or reopen wrapper behavior.
- HWM-STAGE2-001: evidence-only first, or source behavior change.
- HWM-MODEL-001: derivation note only, or full model/formula re-audit.
