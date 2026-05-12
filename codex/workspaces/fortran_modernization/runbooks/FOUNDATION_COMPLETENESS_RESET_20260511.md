# Foundation Completeness Reset

Updated: 2026-05-12 JST

Scope: reset the modernization state after the discovery that several known caveats were treated as wording or planning notes instead of foundation work. This document is the current source of truth for whether the Fortran modernization foundation is complete enough to support production-grade source work.

## Correction

The previous shorthand

```text
Completed foundation -> accepted M6 reference baseline -> remaining modernization blocks
```

is not accurate enough.

Use this instead:

```text
Reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> non-RNG workspace/reentrancy remains
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
| FG-001 | ODEX backend | Closed by explicit endpoint-only product boundary. Hairer `IWORK(3)=3` step sequence and basic extrapolation structure are implemented; analytic ODE tests exist; `test_odex_backend_package_contract` covers the standalone endpoint package boundary; `test_odex_foundation_contract` covers sequence, strict status, zero-time, forward/backward composition, unknown-context h-min failure, and default-disabled assist-policy visibility; `test_odex_assist_policy` covers default-disabled, explicit env-enabled, and explicit env-disabled modes. `test_odex_result_contract` covers internal options/workspace/result/status mapping, including endpoint-only and stability-control-none defaults. `test_odex_flow_jacobian_contract` covers zero-flow identity, `flow`/`flowz` endpoint consistency, `flowzr` inverse replay, Jacobian finite-difference consistency, and no fallback use. | Dense output and a general-purpose Hairer ODEX library are non-goals for TLTM modernization. Solver assist source deletion remains later cleanup. | Do not claim assist-on production policy, dense output, or general ODEX library completeness. TLTM endpoint-flow backend scope is closed. |
| FG-002 | Official DFO-LS backend | Official package is embedded and tuned for the current representative backend-replacement scope; TLTM residual gate remains required. Official-alone `stable_gate77` preset policy has a source-level guardrail, Stage2 sidecar manifests guardrail official DFO-LS provenance env keys, and package-version provenance readback passed for `DFO-LS==1.6.5` / `GPL-3.0-or-later`. The representative embedded 10seed x 10k gate passed with 10 seed cases, 1000 captured attempts, 923 embedded-converged attempts, 923 official residual successes, 0 float64 failures, 0 missing rows, and 0 embedded-converged regressions. CV-001 formal official-line kernel correctness gate also passed and wrote `output/tests/official_line_kernel_correctness_gate/CV001_official_line_kernel_correctness_manifest.json`. | No remaining modernization-tree kernel-correctness work for `DFO-LS==1.6.5`, `stable_gate77`, solver assist default-off, and the current TLTM residual-gate contract. Reopen if package, preset, callback, acceptance gate, runtime bridge, QN route, or kernel semantics change. | Does not by itself make final publication production output complete; CV-002 remains the production-output boundary in the production-comparison tree. |
| FG-003 | Simplified Newton | Reference signs and update decomposition match GT-HMC/TLTM in the audit. `test_retained_core_newton_contract` deterministically replays accepted solutions for step sizes `0.002/0.003/0.004`, with max residual `4.6635E-14` under `5.0E-11` and `lambda_scale=9.9817E-01`. The F14 complete gate keeps this in the branch/measure harness. | Keep the contract in M4 and rerun it for any residual, projection, tolerance, or force-normalization source change. | Closed for the pre-redo gate. |
| FG-004 | RATTLE/failure boundary | Main complex RATTLE update order is reference-matched; failure-as-rejection policy is chosen. `test_retained_core_rattle_rg_contract` covers one successful one-step RATTLE replay with endpoint/Jacobian identity, tangent final momentum, and reverse-gate replay `success=1/failure_total=0`; `test_retained_core_rg_reject_identity` covers reverse-gate reject stay-put outputs and accounting. The F14 complete gate records this as the retained-core branch/measure harness. | Keep the harness in M4 and rerun/reopen for proposal, reverse-gate, tolerance, or status-code changes. | Closed for the pre-redo gate. |
| FG-005 | QN p28 / BTN rescue | Paper-variable cleanup exists; `test_retained_core_qn_route_contract` directly reconstructs the BTN paper-variable residual with zero error, fixes the current official-line route surface, requires true official package success when the bridge is enabled, and passes a fixed-step route census at `0.002/0.003/0.004` with route code `10`. Stub bridge mode still verifies no internal fallback. | Keep the route contract in M4 and rerun/reopen for package, preset, callback, route, or residual-gate changes. | Closed for the pre-redo gate. |
| FG-006 | HMC/Metropolis/reverse gate | Metropolis boundary has deterministic RG reject identity coverage: HMC and Metropolis outputs stay at the input state, transition status is reverse-gate rejected, and local transition accounting records one legal rejection with compatibility `projection_failure_count=1` plus typed `reverse_gate_reject_count=1`. | Keep stay-put identity and event-accounting checks in M4 and rerun/reopen for proposal/rejection accounting changes. | Closed for the pre-redo gate. |
| FG-007 | Diagnostics/status/accounting | Status/counter slices and compatibility labels are preserved. Local transition accounting now constructs `tltm_local_transition_event_t` and derives counters from that typed event. `F4_LOCAL_TRANSITION_AUDIT_V1` freezes the audit context/columns, and M4 validates audit row invariants plus reverse-gate counter identities. | Keep F4 schema/audit validation in M4 and rerun/reopen for local counter, status-code, sidecar, or audit-row semantic changes. | Closed for the pre-redo gate. |
| FG-008 | RNG/workspace/reentrancy | Route-B RNG stream ownership is implemented: mt95 explicit state includes Gaussian spare state, Stage1 replicas and Stage2 slots own local-update streams, and Stage2 swaps use a separate deterministic stream. | Remaining non-RNG module `SAVE` workspaces/counters/diagnostics/policy state, plus deterministic serial/reentrant tests. | Do not claim productized reentrant/OpenMP readiness; pre-B and post-B finite same-seed trajectories are different RNG contracts. |
| FG-009 | Wrapper/schema/config/product interface | Sidecars, manifests, and protocol audits exist. | Versioned public schema, canonical method names/algorithm IDs, unified runner, compatibility layer, final third-party provenance lock. | Final production outputs must remain provisional until schema/wrapper conventions are frozen or regeneration is scheduled. |
| FG-010 | Script/evidence boundary | CV-005 is closed by `SCRIPT_EVIDENCE_AUDIT_20260512.tsv` and `validate_script_evidence_audit.py`; M4 validates every tracked file under `scripts/`, `codex/tasks/`, and `codex/workspaces/fortran_modernization/tasks/`, including quarantine of historical and legacy-route helpers. | Keep the registry current when adding or reclassifying helpers, PBS scripts, configs, or analysis tools. | No current script-evidence caveat remains; historical rows cannot support current official or publication claims without rerun/reclassification. |

## Immediate Queue Reset

1. Freeze behavior-relevant source refactors except explicitly scoped guardrails/tests.
2. Promote foundation gaps into `CAVEATS.tsv` and `OPEN_ITEMS.tsv`.
3. Replace "foundation complete" wording in compact handoff docs.
4. Keep ODEX, official DFO-LS, retained-core, diagnostics, schema, and script-evidence gates wired into M4.
5. Continue CV-011 after route-B RNG stream migration; close only after remaining workspace/reentrancy migration and deterministic serial/reentrant tests.
6. Keep production redo scope/scale and CV-002 promotion decisions in the separate `tltm_production_comparison` tree.
7. Resume behavior-preserving source modernization only with F8/M4 and affected-baseline comparison.

## Relationship To Existing Evidence

- M2 is a reference-backed audit, not final implementation signoff.
- M6 is an accepted historical/internal behavior baseline, not official DFO-LS evidence and not a proof that each method foundation is complete.
- The ODEX non-invasive evidence, result/workspace/status contract, standalone endpoint package slice, flow/Jacobian deterministic contract, and solver-assist default-off policy are recorded in `FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`, `ODEX_FOUNDATION_TEST_READBACK_20260511.md`, and `FOUNDATION_CLOSURE_DECISIONS_20260512.md`. `CV-007` is now closed by explicit TLTM endpoint-only product boundary.
- Current official DFO-LS production-comparison data may remain provisional comparison evidence, but it cannot be promoted to final publication production while CV-002 and production-comparison scope/scale/promotion decisions remain unresolved.
