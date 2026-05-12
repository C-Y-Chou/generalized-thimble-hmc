# Modernization Forward Worksteps

Updated: 2026-05-12 JST

Scope: foundation-gap-gated forward queue for continuing TLTM Fortran modernization after official DFO-LS became the default backend and after the M6 R1-R4 reference baseline was accepted as historical/internal behavior evidence.

## Current Position

```text
Reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> full OpenMP/thread-safe productization remains
```

This queue supersedes any interpretation that M2/M6 means the numerical/software foundation is complete. M6 is a behavior-protection and degeneracy-observation anchor, not official DFO-LS certification; `FOUNDATION_COMPLETENESS_RESET_20260511.md` is the reset map for the unfinished foundation.

## Active Caveat Gates

- `CV-001`: closed for modernization-tree kernel correctness by the official-line kernel correctness gate under embedded official DFO-LS 1.6.5, stable_gate77, solver assist default-off, and the canonical p28 route.
- `CV-002`: current production-comparison outputs are provisional. Final production-output promotion is owned by the separate `tltm_production_comparison` tree and is not required before modernization source/product readiness can be called finished.
- `CV-003`: production-comparison jobs execute only from the synchronized production-comparison worktree; modernization must only provide frozen commits/contracts for redo to consume.
- `CV-004`: closed as permanent governance. Behavior-relevant source refactors require accepted reference comparison or an explicitly approved narrower baseline.
- `CV-005`: closed by script/evidence audit. Every tracked helper/PBS/config/script under audited roots has a registry row, and M4 validates full coverage plus historical quarantine.
- `CV-006`: closed by strict claim/provenance policy. DFO-LS claims must distinguish historical in-house/DFO-LS-style paths from embedded official package runs.
- `CV-007`: closed by endpoint-only TLTM product boundary. Dense output and a general-purpose Hairer ODEX library are non-goals; solver assist defaults off and is scheduled for later deletion. Do not claim assist-on production policy.
- `CV-008`: official DFO-LS backend replacement is accepted for the representative scope: package provenance, preset/source contract, sidecar provenance guardrails, small embedded gate, imported official assist calibration, and representative embedded 10seed x 10k readback all pass. Reopen only on package/preset/callback/runtime/QN-route changes or broader final-production claims.
- `CV-009`: closed for the pre-redo gate. Retained Newton/RATTLE/QN/HMC/RG cores now have deterministic guardrails for Newton replay, successful RATTLE/RG pass replay, BTN residual reconstruction, official package-success route census, stub no-fallback behavior, RG reject stay-put identity, failure-as-rejection accounting, and a branch/measure harness recorded by `f14_complete_pre_redo_gate.py`.
- `CV-010`: closed for the pre-redo gate. Local transition accounting now uses `tltm_local_transition_event_t`, `F4_LOCAL_TRANSITION_AUDIT_V1` freezes the typed audit context, and M4 validates audit row invariants plus reverse-gate counter identities.
- `CV-011`: route-B RNG streams are implemented; full OpenMP/thread-safe productization is still unfinished productization foundation.

## Forward Queue

| Step | Workstream | Status | Allowed now | Output | Gate to advance |
| --- | --- | --- | --- | --- | --- |
| F0 | foundation completeness reset | active | yes | `FOUNDATION_COMPLETENESS_RESET_20260511.md`, expanded `CAVEATS.tsv`/`OPEN_ITEMS.tsv` | no compact doc says foundation is complete |
| F1 | ODEX backend completeness | closed_product_boundary | yes | standalone endpoint backend, result/workspace/status, flow/Jacobian, default-off assist-policy, and representative assist-on/off diagnostics; product boundary says dense output/general ODEX library are non-goals | delete solver assist later; reopen only for dense output, product-complete Hairer claim, or changed final-flow policy |
| F2 | official DFO-LS backend completion | done | yes | representative embedded official DFO-LS 10seed x 10k gate passed; CV-001 official-line kernel correctness gate passed with package provenance and retained kernel contracts | reopen only on official DFO-LS package/preset/residual callback/acceptance gate/runtime bridge/QN-route changes or broader production-output claims |
| F3 | retained-core deterministic evidence pack | done | yes | deterministic guardrails now cover Newton, successful RATTLE/RG, BTN residual, official package-success route census, stub no-fallback behavior, RG reject identity, failure-as-rejection accounting, and F14 branch/measure harness | reopen only if retained-core route logic, tolerances, proposal policy, or official DFO-LS acceptance changes |
| F4 | diagnostics/status/accounting foundation | done | yes | typed local-transition event source, event-derived counters, local-transition audit schema, and M4 row-invariant validation | reopen only if status codes, local counters, sidecar schema, or audit row semantics change |
| F5 | M6 read-only comparison tooling | done | yes | `m6_reference_compare.py`, comparison summary/report | tool can regenerate report from accepted M6 readback or raw package CSV |
| F6 | M6 and official-small degeneracy observation | active | yes, read-only | use M6 R1-R4 only as historical/internal anchors; use imported official 10seed/10k production-comparison evidence for real official-line nofb-vs-withfb degeneracy observation | M6 is not official DFO-LS evidence; official 10seed/10k is calibration only; no source changes; label all production outputs provisional |
| F7 | public method naming and schema-role design | done | yes | `F7_METHOD_ALIASES_V1` freezes public `nofb`/`withfb` names with `no_fb`/`fb_norefine` compatibility aliases | reopen only for schema v2, public taxonomy change, or field removal |
| F8 | reference comparison harness for source patches | governed | yes | `F8_PATCH_REFERENCE_STATEMENT_V1` and `f14_complete_pre_redo_gate.py` provide patch-local reference statement and M6 anchor validation; CV-004 is now closed as permanent governance | run this harness for every future behavior-relevant source patch |
| F8b | script evidence audit | done | yes | `SCRIPT_EVIDENCE_AUDIT_20260512.tsv` and `validate_script_evidence_audit.py` classify all tracked script/task files and quarantine historical helpers | reopen CV-005 only on unclassified additions, historical-script overclaim, or current-tier legacy route drift |
| F9 | low-risk non-physics utility/API cleanup | gated | after-F8 | exact-output or tolerance-bound comparison against accepted rows | no RNG/proposal/schema/counter meaning drift |
| F10 | typed status/result propagation | gated | after-F14-redo-scope | explicit flow/solver/RATTLE/HMC/reverse-gate result objects | route/counter equality checks pass |
| F11 | diagnostics accounting implementation | gated | after-F14-redo-scope | broader structured forward/replay/probe/reject accounting beyond local-transition event source | schema versioning and compatibility readers exist |
| F12 | unified wrapper/product interface | gated | after-F14-redo-scope | wrapper runs same Stage2/Stage3 protocol with v1 sidecars | no public behavior replacement without compatibility layer |
| F13 | RNG/reentrancy/module workspace migration | active | yes | route-B per-replica/per-slot RNG streams implemented; add post-B anchor and continue full OpenMP/thread-safe productization | deterministic serial/reentrant comparisons exist |
| F14 | publication-grade production regeneration | external_redo_tree | no, outside modernization | F3/F4/F7/F8 pre-redo gates pass, CV-001 kernel correctness is closed, CV-006 claim policy is closed, and modernization can provide a frozen commit/contract | production redo scope/scale, target commit/worktree, and CV-002 promotion boundary stay in `tltm_production_comparison` |

## What Can Continue Before Pre-Redo

- Read-only reports and comparison tooling.
- Documentation and schema design.
- Local guardrail/tooling additions that do not mutate production outputs or active remote worktrees.
- Production redo planning with solver assist default-off.

Do not fast-forward or clean `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` while production-comparison jobs are active or pinned.

## Immediate Work

Read `FOUNDATION_COMPLETENESS_RESET_20260511.md` before any modernization task. The immediate implementation planning order is:

1. Commit the verified foundation/RNG checkpoint.
2. Add the post-B deterministic reference anchor for `per_replica_rng_v1`.
3. Continue CV-011 through full OpenMP/thread-safe productization: migrate or scope remaining module workspaces/state, counters, diagnostics, and policy state, then add deterministic serial/reentrant checks before closure.
4. Leave production redo scope/scale and CV-002 promotion boundary to the `tltm_production_comparison` tree.

M6 comparison tooling remains available as historical/internal behavior readback, especially for assist-off degeneracy observation, with:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/m6_reference_compare.py
```

Use the generated report as a behavior anchor, not as official DFO-LS evidence and not as evidence that the foundation is complete.
