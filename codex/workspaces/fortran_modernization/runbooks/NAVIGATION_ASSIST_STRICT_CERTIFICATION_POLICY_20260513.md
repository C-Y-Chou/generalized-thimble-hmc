# Navigation Assist With Strict Certification Policy

Status: implemented and modernization-local gated

Date: 2026-05-13 JST

Scope: instructions for moving the solver-assist decision from the
`tltm_production_comparison` evidence track back into the modernization tree.

Implementation update, 2026-05-13 JST: this policy is now encoded in the
modernization source tree.  `qn_navigation` is the canonical default, legacy
`INTODE_SOLVER_ASSIST_ENABLED=0/1` maps to `off` /
`all_navigation_diagnostic`, and Stage3 method env manifests now distinguish
`nofb` assist-off control from fallback-on navigation assist.  The
modernization-local M4 guardrail suite passed; production-tree sync is allowed
after refreshing remote/job state.

## Decision

The next canonical modernization candidate should be the fallback-enabled route,
not the assist-off route:

```text
strict NT -> QN fallback with navigation assist -> unassisted certification -> RG -> Metropolis
```

`no_fb` remains a comparison/control route.  It does not need to become the
final production target if the fallback-enabled route is the scientifically
accepted robust algorithm.

## Why This Replaces Parameter-Only Assist-Off Tuning

Production-comparison readback ruled out a purely parameter-tuned assist-off
official DFO-LS route as the likely solution:

- Phase D showed real improvement from `rho050_m500`: `fb_norefine` failures
  moved from `67061` to `33872`, and mean Re/Im improved.
- The same-scale assist-on reference had `19579` failures.
- Phase E full replay over `1994` captured `fb_norefine` QN attempts found the
  best focused candidate `rho050_m1000` at only `1726/1994` successes, just
  `+20` over `rho050_m500`.

Conclusion: keep the official DFO-LS residual gate and tuned backend, but do
not keep chasing parameter-only assist-off parity.  Formalize assist instead.

## Algorithm Contract

The contract has two residual roles.

### Navigation Residual

`R_nav` is allowed to use solver assist only inside QN fallback residual
evaluation.  Its job is to give DFO-LS a finite local signal when ordinary
`flowz` / `flowzr` evaluation hits an h-min or divergent path.

Allowed contexts:

- QN fallback residual evaluation;
- QN retry residual evaluation;
- reverse replay of the same QN fallback proposal generator, if the forward
  proposal generator uses the same navigation policy.

Forbidden contexts:

- strict NT;
- final proposal/live-state `flow(...)`;
- unassisted certification residual;
- RG accept/reject decision after certification;
- Metropolis acceptance.

### Certification Residual

`R_cert` is the exact unassisted TLTM residual.  A QN candidate produced with
navigation assist is not a solver success until `R_cert <= cttol` or the active
quasi tolerance.  Package success, navigation success, or a finite assisted
flow value is never sufficient.

Certification must use the same physical equation as the current residual gate,
with assist disabled and with non-finite values classified as failure.

## Newton Policy

Do not enable assist in the canonical NT path for this handoff.

Reason: NT is the author-faithful primary route.  Enabling assist inside NT
would change the primary solver semantics and would make the modernization
claim harder to defend.  Keep NT strict and use assist only in the fallback
layer, where the algorithm is already a robustness extension.

Diagnostic-only variants may test NT+QN assist, but they must not be promoted
without a separate user decision and a new correctness gate.

## Final Proposal Boundary

Final live-chain proposal construction remains strict:

- strict ODEX success and zero-time no-op may proceed;
- solver-assist success, stiff-rescue success, h-min failure, max-step failure,
  invalid-state failure, and unknown statuses are not strict final-flow success;
- proposal construction failures map to ordinary rejection, not state mutation;
- reverse-gate failures map to ordinary rejection with live-state identity.

The existing non-strict final-flow classification in `hmc_integrator_core`
should be preserved and tested.

## Public Method Meaning

The intended public method split is:

- `nofb`: author-faithful control/comparison route, strict NT only;
- `withfb`: canonical robust route, strict NT followed by QN fallback with
  navigation assist and strict certification.

Compatibility aliases such as `no_fb` and `fb_norefine` may remain in output
schema until a public schema version changes them.

## Required Code Changes

1. Replace the boolean mental model of assist with an explicit policy:
   `off`, `qn_navigation`, and `all_navigation_diagnostic`.
2. Thread a residual-evaluation role through flow calls:
   `nt_strict`, `qn_navigation`, `certification`, `final_flow`,
   `reverse_replay`.
3. Change the assist policy gate so canonical mode allows h-min assist for QN
   navigation contexts but not for NT or final-flow contexts.
4. Keep TLTM-side residual certification outside official DFO-LS package
   success flags.
5. Record the policy in Stage1/Stage2 manifests, for example:
   `flow_policy_id=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`.
6. Preserve old env names only as compatibility shims if needed; do not make
   a bare `INTODE_SOLVER_ASSIST_ENABLED=1` the final product contract.

## Required Guardrails

Add or update tests for these invariants:

- `test_odex_assist_policy`: canonical policy must reject assist for NT,
  final-flow, unknown context, unknown stage, invalid reason, and max-step
  reason; it may allow h-min assist for QN/QN-retry navigation contexts.
- QN navigation success followed by unassisted certification failure must be a
  proposal failure/rejection.
- QN navigation success followed by unassisted certification success may proceed
  to RG.
- Final `flow(...)` solver-assist success remains non-strict and fails final
  proposal construction.
- Reverse replay uses the same navigation policy as forward proposal
  construction, but both forward and reverse endpoints are certified
  unassisted.
- Counters distinguish navigation-assist calls from certification success.
- Manifest readback proves policy, backend, preset, and residual gate are all
  recorded.

## Acceptance Gates

Minimum modernization-local gate:

- build and run the updated assist policy tests;
- run retained-core tests touching Newton, QN, RATTLE, RG, and Metropolis;
- run `git diff --check`;
- run the M4 modernization guardrail wrapper if the source patch is
  behavior-relevant.

Production-comparison bridge gate:

- compare assist-off, legacy assist-on, and formalized navigation-assist
  fallback-on under the same commit/protocol;
- require `fb_norefine` / `withfb` failures to reach the assist-on scale, not
  the assist-off tuned scale;
- require mean Re/Im not to regress relative to the best current fallback-on
  reference;
- keep RG rejects and P68/P95 as diagnostics unless a later correctness gate
  promotes them to blockers.

## Non-Goals

- Do not add external escape, backtracking, best-rescue, or multistart wrappers
  around official DFO-LS as the solution.
- Do not weaken the TLTM residual gate.
- Do not let assisted finite values directly enter final acceptance.
- Do not make NT assist canonical in this handoff.
- Do not relabel provisional production-comparison outputs as final
  publication production without the normal production boundary.

## Handoff Summary

Modernization should treat solver assist as a typed, auditable navigation
mechanism inside the fallback solver, not as a hidden acceptance oracle.  The
canonical candidate is fallback-on only:

```text
NT strict; QN navigation assist allowed; certification, final flow, RG, and
Metropolis strict and unassisted.
```

This preserves author-faithful NT as the comparison baseline while allowing the
modernized robust route to use the numerical machinery that production evidence
shows is needed.

## Implementation Record

Implemented source contract:

- `solve_flow.f90` now exposes typed assist policies: `off`,
  `qn_navigation`, and `all_navigation_diagnostic`.
- Residual roles are threaded through the flow call boundary:
  `nt_strict`, `qn_navigation`, `certification`, `final_flow`, and
  `reverse_replay`.
- Canonical policy allows h-min assist only for QN navigation / QN retry /
  reverse replay residual evaluations under `flowz` / `flowzr` contexts.
- NT, unassisted certification, final proposal flow, RG, Metropolis,
  external/unknown contexts, invalid reasons, and max-step reasons remain
  strict.
- `rescue_attempt_from_best` now re-evaluates the candidate through a
  certification residual with the real Jacobian before accepting any
  navigation-derived best state.
- Stage2 v1 manifests record
  `flow_policy_id=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1` and
  the `INTODE_SOLVER_ASSIST_POLICY` env key.
- Stage3 method env overrides set `no_fb` to policy `off` and `fb` /
  `fb_norefine` to policy `qn_navigation`.

Verification passed locally:

- `git diff --check`
- `python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/run_m4_guardrails.py`
- `make -C build FC=gfortran LDFLAGS= test_odex_assist_policy`
- With `.venv-dfols` exported for the official package bridge:
  `make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract test_retained_core_rattle_rg_contract post_b_rng_reference_anchor`
- `make -C build FC=gfortran LDFLAGS= test_odex_foundation_contract`
- `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

Production-tree handoff rule:

- Sync the production tree only after the above local M4 gate is green and
  remote state confirms no active pinned production jobs.  This implementation
  has met the local gate; the remaining step is the production-tree
  fast-forward/readback.
