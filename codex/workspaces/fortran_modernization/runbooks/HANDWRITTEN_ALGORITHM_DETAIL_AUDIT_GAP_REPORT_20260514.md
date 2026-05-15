# Handwritten Algorithm Detail Audit Gap Report

Date: 2026-05-14 JST
Scope: `fortran_modernization`
Status: active foundation caveat; report-only, no physics/source change

## Executive Summary

The modernization evidence is currently strong enough to protect many existing
behaviors, but it is not strong enough to claim that every hand-authored
numerical algorithm has been proven correct against its defining paper or
reference at the implementation-detail level.

The ODEX step-size controller exposed the gap:

- the project has reference-backed evidence for the ODEX family, the Hairer
  `IWORK(3)` sequence, explicit midpoint/extrapolation structure, signed-step
  handling, endpoint-only product scope, and deterministic endpoint checks;
- the project does not yet have a line-by-line paper audit for all controller
  details such as first-step selection, `HNEW` / `HOPT` update logic, order
  promotion/demotion thresholds, rejected-step behavior, and every tolerance or
  h-min floor.

This is not only an ODEX problem.  It is a general claim-boundary problem for
all hand-written TLTM numerical kernels: ODEX, flow/Jacobian RHS, simplified
Newton, RATTLE, BTN/QN residuals, official DFO-LS callback and residual-gate
semantics, reverse gate, Metropolis/live-state mutation, Stage2 tempering/swap
logic, RNG stream contracts, and diagnostics/counter surfaces.

The immediate correction is to separate three evidence levels:

1. reference-level algorithm mapping;
2. behavior-preserving regression/guardrail evidence;
3. paper-level implementation-detail signoff.

Only the third level can support a publication-grade claim that a hand-written
algorithm is correct as an implementation of the reference method.

## Claim Boundary

Current modernization claims that remain valid:

- major legacy numerical routes have been removed or quarantined;
- the canonical route and public method names are documented;
- multiple retained core components have deterministic guardrails;
- behavior-relevant patches must use F8/M4 and an affected-baseline comparison;
- ODEX has an endpoint-only product boundary, not a dense-output/general-library
  Hairer ODEX claim;
- official DFO-LS package use is provenance-gated and TLTM residual-gated;
- Stage2 RNG v2 is now the default contract, with compatibility modes retained.

Current modernization claims that must not be made:

- "all handwritten numerical algorithms are paper-correct";
- "passing M4/M6 means the mathematical implementation is complete";
- "endpoint/self-consistency ODE tests prove every ODEX controller branch";
- "behavior preservation proves that the preserved behavior is scientifically
  correct";
- "production-comparison readback can replace reference-level source audit."

Correct wording:

```text
The modernization tree has reference-backed core mapping plus behavior and
deterministic guardrails, but several hand-written numerical controller and
policy details still need paper-level implementation-detail audit before any
publication-ready algorithm-correctness claim.
```

## Evidence-Level Vocabulary

Use these labels in future reports, state files, and PR descriptions:

| Label | Meaning | What it can support |
| --- | --- | --- |
| `reference-mapped` | The paper/reference formula and the active source route have been compared at the algorithm-block level. | A scoped statement that the implementation is intended to follow the reference structure. |
| `detail-mapped` | Controller constants, branch predicates, update equations, state mutation rules, and failure paths have been mapped line-by-line to the reference or to an explicit project deviation. | A strong implementation claim for that detail surface. |
| `deterministically-evidenced` | Fixed tests exercise the detail surface and failure boundary. | Guardrail against future drift; not by itself a paper proof. |
| `behavior-anchored` | Current outputs or summaries are frozen as a reference baseline. | Refactor preservation; not correctness of the baseline. |
| `intentional-deviation` | The code differs from the reference, but the project accepts the difference as the TLTM product contract. | Publication only if documented with rationale and tests. |
| `open-needs-proof` | The behavior may be right but has not been traced to a reference or accepted deviation. | Blocks publication-grade correctness claim for that surface. |
| `bug-candidate` | The behavior plausibly conflicts with the reference or product contract. | Requires evidence packet and explicit decision before source change. |

## ODEX Case Study

### What Is Already Supported

Reference and implementation notes already establish:

- Hairer ODEX / GBS-style extrapolation is the intended mechanism.
- The canonical sequence is Hairer `IWORK(3)=3`:
  `2,4,6,8,12,16,24,32,48,64,96`.
- The explicit midpoint row and endpoint smoothing are present.
- Extrapolation denominators use the expected even-power structure.
- `calculate_wk` now uses a positive work estimate while `calculate_hk`
  remains signed for integration direction.
- Dense output is out of scope for TLTM endpoint-flow production.
- The standalone `odex_backend` package boundary has options, workspace,
  result/status objects, and endpoint tests.

### What Is Not Yet Detail-Signed

The current source has concrete step-size logic:

- default initial step fraction:
  `odex_options%initial_step_fraction = 0.01_dp`;
- first step:
  `h = t*opts%initial_step_fraction`;
- h-min policy:
  `max(h_min_fp, min(h_min_tol, h_min_span))`;
- candidate step update:
  `h*0.94*(0.65/max(err, 1.0e-14))**invexp(k)`;
- order decisions based on `wk1`, `wk2`, and `0.9` thresholds;
- early rejection paths that halve `h` on invalid RHS or conservative
  stability rejection;
- `err > (k*k + 1)**2` as a demotion/rejection threshold.

These may be reasonable ODEX-derived implementation choices, but the current
runbooks do not yet provide a complete paper-to-source audit for each item.

### Required ODEX Detail Audit

Create a dedicated ODEX controller audit with this table shape:

| Surface | Source location | Reference formula or source | Status | Required evidence |
| --- | --- | --- | --- | --- |
| first step `h0` | `odex_integrate_endpoint*` | Hairer ODEX appendix first-step logic or accepted TLTM endpoint choice | `open-needs-proof` | line-by-line mapping or explicit deviation |
| h-min floor | `h_min_fp`, `h_min_tol`, `h_min_span` | Hairer h-min / roundoff logic or accepted TLTM failure policy | `open-needs-proof` | reference mapping plus h-min microtests |
| `HNEW` update | `calculate_hk` | Hairer ODEX step-size proposal | `partial` | formula comparison, exponent check, safety factors |
| work estimate | `calculate_wk`, `calculate_ak` | Hairer work-per-unit-step / `W(k)` logic | `partial` | positive work proof for signed intervals |
| order change | `wk1`, `wk2`, `0.9` thresholds | Hairer order-controller thresholds | `partial` | accept/demote/promote branch tests |
| rejection behavior | `err >= 1`, invalid RHS, stability rejection | Hairer reject/retry flow or TLTM endpoint deviation | `open-needs-proof` | branch tests and status mapping |
| endpoint-only decision | `endpoint_only=.true.` | TLTM requirement, not full Hairer dense output | `intentional-deviation` | already documented; keep tests |

## Project-Wide Audit Inventory

The following surfaces need explicit detail-level audit status.  Some already
have strong evidence; the point is to prevent broad overclaim.

| Area | Representative source | Current evidence | Detail-level gap | Current status |
| --- | --- | --- | --- | --- |
| ODEX controller | `src/physics/odex_backend.f90` | sequence, extrapolation, endpoint tests, package contract | first-step, h-min, adaptive `h`, order branch, reject branch not fully paper-mapped | `open-needs-proof` |
| Flow/inverse-flow/Jacobian RHS | `src/physics/solve_flow.f90`, `src/physics/model*.f90` | endpoint/Jacobian finite-difference tests and context refactor gates | full formula map for conjugation, RHS scale, Jacobian/tape/cache state, failure statuses | `partial` |
| Simplified Newton projection | `src/sampler/hmc_constraints.f90` | reference signs mapped; deterministic replay tests | reopen only on residual/projection/tolerance/force-normalization changes | `closed-for-current-gate` |
| RATTLE proposal | `src/sampler/hmc_integrator_core.f90`, `src/sampler/hmc.f90` | main order mapped; one-step and RG replay tests | full detail map for every failure/status branch and progress guard history | `partial` |
| BTN/QN residual | `src/sampler/quasi_newton_solver.f90` | paper-variable residual reconstruction and route census | solver-controller details, budget policy, watchdog, retry and certification branches | `partial` |
| Official DFO-LS callback/gate | `src/external/official_dfols_c_bridge.c`, QN modules | package provenance, preset contract, residual gate, official-line kernel gate | reopen on package/preset/callback/runtime/route changes; callback edge cases still need product docs | `accepted-representative-scope` |
| Navigation assist policy | `solve_flow`, `hmc_integrator_core`, `quasi_newton_solver` | F15 typed policy and M4 gates | production-comparison redo after synchronized post-fix tree remains external | `implemented-policy` |
| Reverse gate | HMC/QN replay modules | stay-put identity and accounting guardrails | full proposal-kernel proof remains tied to accepted project policy | `partial` |
| Metropolis/live-state mutation | `markovchain_metropolis.f90`, Stage drivers | failed/RG-rejected proposals preserve live state | detail map for every proposal status and public counter interpretation | `partial` |
| Stage2 tempering/swap | `src/sampler/tltm_stage2_driver.f90` | Stage2 RNG v2, swap stream, manifests, protocol audit | full replica-exchange paper contract and first-N-cycle/window convention needs explicit detail status | `partial` |
| RNG stream contract | RNG modules, Stage drivers | Stage2 RNG v2 default and anchors | publication wording for finite same-seed trajectory changes and compatibility modes | `implemented-with-contract` |
| Diagnostics/counters | diagnostics contexts and Stage drivers | F4 typed local-transition event | remaining flow/ODEX counters/traces/last-failure, constraint aggregate/failure-capture counters | `active-CV011` |
| Config/product schema | `param_mod`, runtime env, wrappers | provenance fields and sidecars | full product schema and compatibility layer | `partial` |

## Required Audit Method

Every hand-authored numerical algorithm surface must get a detail-audit packet
before it can be called publication-ready.

Required packet:

1. Reference contract
   - paper section/equation/subroutine;
   - variable dictionary;
   - assumptions and accepted scope.

2. Source mapping
   - exact source routines;
   - branch predicates;
   - constants and tolerances;
   - state mutation points;
   - failure/status/counter outputs.

3. Classification
   - `matched`;
   - `intentional-deviation`;
   - `open-needs-proof`;
   - `bug-candidate`;
   - `legacy-compatibility-only`.

4. Deterministic tests
   - formula-level microtests where possible;
   - branch tests for accept/reject/update paths;
   - failure-path stay-put tests;
   - tolerance-bound comparisons for affected end-to-end rows.

5. Behavior-preservation gate
   - F8 patch statement;
   - M4 guardrails;
   - affected baseline or explicitly approved narrower comparison.

6. Claim statement
   - exactly what can be said in a paper/report;
   - exactly what cannot be claimed;
   - when the audit must be reopened.

## Production And Publication Consequence

Until this caveat is resolved, the modernization tree may still continue with
behavior-preserving productization, but it must not claim general
paper-correctness for all hand-written algorithms.

Allowed:

- source cleanup that preserves behavior and passes F8/M4;
- explicit context/workspace migration with affected-baseline comparison;
- deterministic guardrail expansion;
- report/schema/provenance improvements;
- production-comparison redo from a frozen synchronized commit, labeled by its
  exact algorithm contracts.

Blocked without explicit decision:

- claiming all hand-written algorithms are paper-correct;
- using M6 or production readback as a substitute for controller detail audit;
- changing controller constants or branch logic under the label "cleanup";
- publishing an ODEX/HMC/QN implementation claim stronger than the audited
  surfaces support.

## Immediate Work Items

1. Register this report as `CV-012` / `F17` in the modernization state files.
2. Create a focused ODEX controller audit packet first, because it exposed the
   global gap and has clear source surfaces.
3. Update compact handoff wording so "reference-audited core" does not imply
   "all implementation details are paper-signed".
4. For any upcoming source patch that touches algorithm logic, require the F8
   statement to name whether the touched surface is `detail-mapped` or still
   `open-needs-proof`.
5. After ODEX, audit the next highest-risk controller surfaces:
   BTN/QN solver-controller policy, RATTLE failure/status paths, Stage2
   tempering/swap protocol, and remaining diagnostics/counter semantics.

## Bottom Line

The modernization effort has useful and real guardrails, but the user's
objection is correct: behavior preservation and broad reference mapping are not
the same as proving every hand-written algorithm detail against the papers.

This report reopens that distinction as an active foundation caveat.  From this
point forward, handwritten numerical algorithms need explicit detail-audit
packets before publication-grade correctness claims.
