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
| FG-001 | ODEX backend | Hairer `IWORK(3)=3` step sequence and basic extrapolation structure are implemented; analytic ODE tests exist; `test_odex_foundation_contract` now covers sequence, strict status, zero-time, forward/backward composition, unknown-context h-min failure, and assist-policy visibility. Historical ODEX-only vs solver-assist readback exists, but no fresh current-code ODEX assist-on/off policy test has been run. | Stability-control decision or implementation, endpoint-only/dense-output policy, mechanism/policy split, explicit workspace/result/status API, flow-wrapper/Jacobian deterministic tests, and a real current ODEX assist-on/off or equivalent policy revalidation. | Do not claim complete ODEX solver or start ODEX-affecting source refactors beyond the accepted source-slice plan. |
| FG-002 | Official DFO-LS backend | Official package is embedded and tuned enough for provisional gates; TLTM residual gate remains required. Official 10seed/10k production-comparison evidence was imported as calibration and shows `withfb` reduces unresolved failures from `7502` to `1179` versus `nofb`. | Official-alone preset tuning policy, in-package stall/robustness decisions without external rescue wrappers, package provenance, captured-attempt comparison, representative-scale readback, and official readback on TLTM residual acceptance. | Do not treat final official solver replacement as complete. |
| FG-003 | Simplified Newton | Reference signs and update decomposition match GT-HMC/TLTM in the audit. | Deterministic replay of accepted solutions against Eq. 3.37/3.40, residual <= `cttol`, and `lambda = O(step_size**2)` scaling. | Do not treat Newton foundation as fully evidenced. |
| FG-004 | RATTLE/failure boundary | Main complex RATTLE update order is reference-matched; failure-as-rejection policy is chosen. | Forward/reverse deterministic replay, live-state identity on failure/reject, and replacement of fragile `x(2)` progress guard by typed state boundary. | Do not treat proposal boundary as fully evidenced. |
| FG-005 | QN p28 / BTN rescue | Paper-variable cleanup exists; local BTN contract replay succeeded for a small captured set. | Appendix-B route-budget line-by-line comparison, fixed-seed route census for `Nprobe=28` and follow-up budgets, official-DFO-LS-line equivalence/coverage. | Do not treat QN/BTN route as fully evidenced under official backend. |
| FG-006 | HMC/Metropolis/reverse gate | Metropolis boundary is correct if proposal map is reversible/volume-preserving; reverse gate is permanent. | Deterministic RG pass/reject replay, local-volume/branch-measure coverage on official DFO-LS line, and failure-as-rejection accounting proof. | Final publication production remains provisional. |
| FG-007 | Diagnostics/status/accounting | Status/counter slices exist and compatibility labels are preserved. | Typed diagnostics context separating forward proposal, reverse replay, solver residual evaluation, debug probes, rejected stay-put events, and accepted events. | Output/counter interpretation and final schema remain provisional. |
| FG-008 | RNG/workspace/reentrancy | Serial/process-level PBS use is acceptable; hidden state risks are inventoried. | Explicit per-run/per-replica RNG and workspaces, module `SAVE` migration plan, deterministic serial/parallel tests. | Do not claim productized reentrant/OpenMP readiness. |
| FG-009 | Wrapper/schema/config/product interface | Sidecars, manifests, and protocol audits exist. | Versioned public schema, canonical method names/algorithm IDs, unified runner, compatibility layer, final third-party provenance lock. | Final production outputs must remain provisional until schema/wrapper conventions are frozen or regeneration is scheduled. |

## Immediate Queue Reset

1. Freeze behavior-relevant source refactors except explicitly scoped guardrails/tests.
2. Promote foundation gaps into `CAVEATS.tsv` and `OPEN_ITEMS.tsv`.
3. Replace "foundation complete" wording in compact handoff docs.
4. Build ODEX completion design and first deterministic test plan.
5. Build official DFO-LS backend/preset policy and readback checklist.
6. Build retained-core deterministic evidence pack.
7. Only then resume behavior-preserving source modernization against M6 or narrower accepted baselines.

## Relationship To Existing Evidence

- M2 is a reference-backed audit, not final implementation signoff.
- M6 is an accepted historical/internal behavior baseline, not official DFO-LS evidence and not a proof that each method foundation is complete.
- The first ODEX non-invasive evidence slice is recorded in `ODEX_BACKEND_COMPLETION_PLAN_20260511.md` and `ODEX_FOUNDATION_TEST_READBACK_20260511.md`; `CV-007` remains open until source-level backend completion or explicit reduced-scope acceptance.
- Current 32seed/50k official DFO-LS production-comparison jobs may continue as provisional data, but they cannot be promoted to final publication production while FG-001, FG-002, FG-006, FG-007, and schema/wrapper gaps remain unresolved or explicitly accepted.
