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
| FG-001 | ODEX backend | Accepted reduced-scope endpoint backend. Hairer `IWORK(3)=3` step sequence and basic extrapolation structure are implemented; analytic ODE tests exist; `test_odex_foundation_contract` covers sequence, strict status, zero-time, forward/backward composition, unknown-context h-min failure, and assist-policy visibility. `test_odex_result_contract` covers internal options/workspace/result/status mapping, including endpoint-only and stability-control-none defaults. `test_odex_flow_jacobian_contract` covers zero-flow identity, `flow`/`flowz` endpoint consistency, `flowzr` inverse replay, Jacobian finite-difference consistency, and no fallback use. Historical ODEX-only vs solver-assist readback exists. A current-code deterministic assist policy gate now covers default-enabled and env-disabled modes. A representative official-DFO-LS `fb_norefine` 10seed x 10k assist-on/off readback shows assist-off increases unresolved failures `1179 -> 1542` while zeroing solver-assist counters. | No pre-production full-Hairer ODEX package claim. Dense output and conservative stability control are explicitly out of scope unless reopened. | Do not claim complete standalone/full Hairer ODEX package. |
| FG-002 | Official DFO-LS backend | Official package is embedded and tuned for the current representative backend-replacement scope; TLTM residual gate remains required. Official-alone `stable_gate77` preset policy has a source-level guardrail, Stage2 sidecar manifests guardrail official DFO-LS provenance env keys, and package-version provenance readback passed for `DFO-LS==1.6.5` / `GPL-3.0-or-later`. The small embedded 1seed x 500 gate passed with 100 captured attempts, 100 replay rows, 93 embedded-converged attempts, 0 float64 failures, 0 missing rows, and 0 regressions. The representative embedded 10seed x 10k gate passed with 10 seed cases, 1000 captured attempts, 923 embedded-converged attempts, 923 official residual successes, 0 float64 failures, 0 missing rows, and 0 embedded-converged regressions; Stage aggregate unresolved failures were 1179. Official 10seed/10k production-comparison evidence was also imported as calibration and shows `withfb` reduces unresolved failures from `7502` to `1179` versus `nofb`. | No remaining F2 work for representative backend replacement under `DFO-LS==1.6.5`, `stable_gate77`, and the current TLTM residual-gate contract. Reopen if package, preset, callback, acceptance gate, runtime bridge, or QN route changes. | Does not by itself make final publication production complete; final production remains gated by CV-001/CV-002/CV-009/CV-010 and schema/wrapper decisions. |
| FG-003 | Simplified Newton | Reference signs and update decomposition match GT-HMC/TLTM in the audit. `test_retained_core_newton_contract` now deterministically replays accepted solutions for step sizes `0.002/0.003/0.004`, with max residual `4.6635E-14` under `5.0E-11` and `lambda_scale=9.9817E-01`. | Keep the contract in M4 and rerun it for any residual, projection, tolerance, or force-normalization source change. | Newton has first deterministic evidence, but F3 remains open until the other retained cores are covered. |
| FG-004 | RATTLE/failure boundary | Main complex RATTLE update order is reference-matched; failure-as-rejection policy is chosen. `test_retained_core_rattle_rg_contract` now covers one successful one-step RATTLE replay with endpoint/Jacobian identity, tangent final momentum, and reverse-gate replay `success=1/failure_total=0`. | Add rejected/failure live-state identity, failure-as-rejection accounting proof, and typed state boundary coverage; keep the pass replay in M4. | Do not treat proposal boundary as fully evidenced. |
| FG-005 | QN p28 / BTN rescue | Paper-variable cleanup exists; local BTN contract replay succeeded for a small captured set. | Appendix-B route-budget line-by-line comparison, fixed-seed route census for `Nprobe=28` and follow-up budgets, official-DFO-LS-line equivalence/coverage. | Do not treat QN/BTN route as fully evidenced under official backend. |
| FG-006 | HMC/Metropolis/reverse gate | Metropolis boundary is correct if proposal map is reversible/volume-preserving; reverse gate is permanent. The first RG pass replay slice is covered by `test_retained_core_rattle_rg_contract` with reverse-gate replay `success=1/failure_total=0`. | Add deterministic RG reject replay, live-state stay-put checks, local-volume/branch-measure coverage on official DFO-LS line, and failure-as-rejection accounting proof. | Final publication production remains provisional. |
| FG-007 | Diagnostics/status/accounting | Status/counter slices exist and compatibility labels are preserved. | Typed diagnostics context separating forward proposal, reverse replay, solver residual evaluation, debug probes, rejected stay-put events, and accepted events. | Output/counter interpretation and final schema remain provisional. |
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
- The ODEX non-invasive evidence, result/workspace/status contract, and flow/Jacobian deterministic contract slices are recorded in `ODEX_BACKEND_COMPLETION_PLAN_20260511.md` and `ODEX_FOUNDATION_TEST_READBACK_20260511.md`; `CV-007` is accepted reduced scope, not a full Hairer ODEX package claim.
- Current official DFO-LS production-comparison jobs may continue as provisional data, but they cannot be promoted to final publication production while CV-001/CV-002/CV-009/CV-010 and schema/wrapper gaps remain unresolved or explicitly accepted.
