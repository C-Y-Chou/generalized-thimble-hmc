# Foundation Completeness Reset

Updated: 2026-05-11 JST

Scope: reset the modernization state after the discovery that several known caveats were treated as wording or planning notes instead of foundation work. This document is the current source of truth for whether the Fortran modernization foundation is complete enough to support production-grade source work.

## Correction

The previous shorthand

```text
Completed foundation -> accepted M6 reference baseline -> remaining modernization blocks
```

is not accurate enough.

Use this instead:

```text
Reference-audited core + accepted M6 behavior baseline -> foundation gaps still active -> source modernization remains gated
```

M6 is a behavior-protection baseline and can be used as an observational detector for degeneracy such as assist-off robustness collapse. It is not proof that ODEX, official DFO-LS, retained-core deterministic evidence, diagnostics/accounting, RNG/workspace ownership, or wrapper/schema foundations are complete, and it must not be used as official DFO-LS certification.

## What Went Wrong

Earlier modernization notes used the word "audit" for several different states:

- reference was collected and read;
- a source-level risk was identified;
- one implementation slice was fixed;
- a validation gate passed for a specific route;
- a remaining gap was documented but not promoted to a blocking open item.

Those are different states. The failure was allowing known open findings to remain in long runbooks while the compact handoff made the work look more complete than it was.

## Completion Vocabulary

- `reference-audited`: the reference contract and active source route were compared.
- `partially-implemented`: one or more concrete implementation gaps remain.
- `baseline-anchored`: a behavior reference exists for preserving current outputs, not necessarily for proving the method is complete.
- `deterministically-evidenced`: fixed deterministic tests cover the implementation contract and failure boundary.
- `publication-ready`: implementation, deterministic evidence, production/provisional boundary, schema, and provenance are all complete or explicitly accepted as reduced scope.

Do not use `done`, `complete`, or `foundation complete` unless the relevant row is publication-ready or explicitly accepted as reduced scope.

## Known Foundation Gaps

| ID | Area | Current evidence | Missing foundation work | Blocking consequence |
| --- | --- | --- | --- | --- |
| FG-001 | ODEX backend | Accepted reduced-scope endpoint backend for pre-redo. Hairer `IWORK(3)=3` step sequence and basic extrapolation structure are implemented; analytic ODE tests exist; `test_odex_backend_package_contract` covers the standalone endpoint package boundary; `test_odex_foundation_contract` covers sequence, strict status, zero-time, forward/backward composition, unknown-context h-min failure, and default-disabled assist-policy visibility; `test_odex_assist_policy` covers default-disabled, explicit env-enabled, and explicit env-disabled modes. `test_odex_result_contract` covers internal options/workspace/result/status mapping, including endpoint-only and stability-control-none defaults. `test_odex_flow_jacobian_contract` covers zero-flow identity, `flow`/`flowz` endpoint consistency, `flowzr` inverse replay, Jacobian finite-difference consistency, and no fallback use. The 10seed and 16seed x 10k assist-on/off readbacks are retained as diagnostics; user selected solver assist default-off and later deletion rather than a larger pre-redo observable gate. | Dense output is out of scope. Solver assist source deletion remains post-redo cleanup. Full publication-ready language still depends on F14 scope/scale and remaining non-F3/F4 caveat decisions. | Do not claim assist-on production policy or full product completion; pre-redo uses assist default-off. |
| FG-002 | Official DFO-LS backend | Official package is embedded and tuned for the current representative backend-replacement scope; TLTM residual gate remains required. Official-alone `stable_gate77` preset policy has a source-level guardrail, Stage2 sidecar manifests guardrail official DFO-LS provenance env keys, and package-version provenance readback passed for `DFO-LS==1.6.5` / `GPL-3.0-or-later`. The small embedded 1seed x 500 gate passed with 100 captured attempts, 100 replay rows, 93 embedded-converged attempts, 0 float64 failures, 0 missing rows, and 0 regressions. The representative embedded 10seed x 10k gate passed with 10 seed cases, 1000 captured attempts, 923 embedded-converged attempts, 923 official residual successes, 0 float64 failures, 0 missing rows, and 0 embedded-converged regressions; Stage aggregate unresolved failures were 1179. Official 10seed/10k production-comparison evidence was also imported as calibration and shows `withfb` reduces unresolved failures from `7502` to `1179` versus `nofb`. | No remaining F2 work for representative backend replacement under `DFO-LS==1.6.5`, `stable_gate77`, and the current TLTM residual-gate contract. Reopen if package, preset, callback, acceptance gate, runtime bridge, or QN route changes. | Does not by itself make final publication production complete; final production remains gated by CV-001/CV-002/CV-006 and F14 scope/scale/promotion decisions. |
| FG-003 | Simplified Newton | Reference signs and update decomposition match GT-HMC/TLTM in the audit. `test_retained_core_newton_contract` deterministically replays accepted solutions for step sizes `0.002/0.003/0.004`, with max residual `4.6635E-14` under `5.0E-11` and `lambda_scale=9.9817E-01`. The F14 complete gate keeps this in the branch/measure harness. | Keep the contract in M4 and rerun it for any residual, projection, tolerance, or force-normalization source change. | Closed for the pre-redo gate. |
| FG-004 | RATTLE/failure boundary | Main complex RATTLE update order is reference-matched; failure-as-rejection policy is chosen. `test_retained_core_rattle_rg_contract` covers one successful one-step RATTLE replay with endpoint/Jacobian identity, tangent final momentum, and reverse-gate replay `success=1/failure_total=0`; `test_retained_core_rg_reject_identity` covers reverse-gate reject stay-put outputs and accounting. The F14 complete gate records this as the retained-core branch/measure harness. | Keep the harness in M4 and rerun/reopen for proposal, reverse-gate, tolerance, or status-code changes. | Closed for the pre-redo gate. |
| FG-005 | QN p28 / BTN rescue | Paper-variable cleanup exists; `test_retained_core_qn_route_contract` directly reconstructs the BTN paper-variable residual with zero error, fixes the current official-line route surface, requires true official package success when the bridge is enabled, and passes a fixed-step route census at `0.002/0.003/0.004` with route code `10`. Stub bridge mode still verifies no internal fallback. | Keep the route contract in M4 and rerun/reopen for package, preset, callback, route, or residual-gate changes. | Closed for the pre-redo gate. |
| FG-006 | HMC/Metropolis/reverse gate | Metropolis boundary has deterministic RG reject identity coverage: HMC and Metropolis outputs stay at the input state, transition status is reverse-gate rejected, and local transition accounting records one legal rejection with compatibility `projection_failure_count=1` plus typed `reverse_gate_reject_count=1`. | Keep stay-put identity and event-accounting checks in M4 and rerun/reopen for proposal/rejection accounting changes. | Closed for the pre-redo gate. |
| FG-007 | Diagnostics/status/accounting | Status/counter slices and compatibility labels are preserved. Local transition accounting now constructs `tltm_local_transition_event_t` and derives counters from that typed event. `F4_LOCAL_TRANSITION_AUDIT_V1` freezes the audit context/columns, and M4 validates audit row invariants plus reverse-gate counter identities. | Keep F4 schema/audit validation in M4 and rerun/reopen for local counter, status-code, sidecar, or audit-row semantic changes. | Closed for the pre-redo gate. |
| FG-008 | RNG/workspace/reentrancy | Serial/process-level PBS use is acceptable; hidden state risks are inventoried. | Explicit per-run/per-replica RNG and workspaces, module `SAVE` migration plan, deterministic serial/parallel tests. | Do not claim productized reentrant/OpenMP readiness. |
| FG-009 | Wrapper/schema/config/product interface | Sidecars, manifests, and protocol audits exist. | Versioned public schema, canonical method names/algorithm IDs, unified runner, compatibility layer, final third-party provenance lock. | Final production outputs must remain provisional until schema/wrapper conventions are frozen or regeneration is scheduled. |

## Immediate Queue Reset

1. Freeze behavior-relevant source refactors except explicitly scoped guardrails/tests.
2. Promote foundation gaps into `CAVEATS.tsv` and `OPEN_ITEMS.tsv`.
3. Replace "foundation complete" wording in compact handoff docs.
4. Build ODEX completion design and first deterministic test plan.
5. Keep official DFO-LS backend/preset policy and readback evidence current; reopen only on package/preset/callback/runtime/QN-route changes.
6. Build retained-core deterministic evidence pack.
7. Only then resume behavior-preserving source modernization against M6 or narrower accepted baselines.

## Relationship To Existing Evidence

- M2 is a reference-backed audit, not final implementation signoff.
- M6 is an accepted historical/internal behavior baseline, not official DFO-LS evidence and not a proof that each method foundation is complete.
- The ODEX non-invasive evidence, result/workspace/status contract, standalone endpoint package slice, flow/Jacobian deterministic contract, and solver-assist default-off pre-redo policy are recorded in `FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`, `ODEX_FOUNDATION_TEST_READBACK_20260511.md`, and the 2026-05-12 session log. `CV-007` is accepted reduced scope for pre-redo, not full product completion.
- Current official DFO-LS production-comparison data may remain provisional comparison evidence, but it cannot be promoted to final publication production while CV-001/CV-002/CV-006 and F14 scope/scale/promotion decisions remain unresolved.
