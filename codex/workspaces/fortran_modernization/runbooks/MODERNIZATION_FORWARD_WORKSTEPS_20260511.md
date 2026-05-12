# Modernization Forward Worksteps

Updated: 2026-05-11 JST

Scope: foundation-gap-gated forward queue for continuing TLTM Fortran modernization after official DFO-LS became the default backend and after the M6 R1-R4 reference baseline was accepted as historical/internal behavior evidence.

## Current Position

```text
Reference-audited core + accepted M6 behavior baseline -> foundation gaps still active -> source modernization remains gated
```

This queue supersedes any interpretation that M2/M6 means the numerical/software foundation is complete. M6 is a behavior-protection and degeneracy-observation anchor, not official DFO-LS certification; `FOUNDATION_COMPLETENESS_RESET_20260511.md` is the reset map for the unfinished foundation.

## Active Caveat Gates

- `CV-001`: final publication production still needs an official-DFO-LS-line kernel correctness gate or explicit accepted limitation.
- `CV-002`: current production-comparison outputs are provisional until final wrapper/schema/naming/counter conventions are frozen or final regeneration is scheduled.
- `CV-003`: production-comparison jobs execute only from the synchronized production-comparison worktree.
- `CV-004`: behavior-relevant source refactors need accepted reference comparison or an explicitly approved narrower baseline.
- `CV-005`: auxiliary or historical scripts require deep-read before reuse as evidence or automation.
- `CV-006`: DFO-LS claims must distinguish historical in-house/DFO-LS-style paths from embedded official package runs.
- `CV-007`: ODEX backend is accepted reduced scope for pre-redo; solver assist defaults off and is scheduled for later deletion. Do not claim full product completion or assist-on production policy.
- `CV-008`: official DFO-LS backend replacement is accepted for the representative scope: package provenance, preset/source contract, sidecar provenance guardrails, small embedded gate, imported official assist calibration, and representative embedded 10seed x 10k readback all pass. Reopen only on package/preset/callback/runtime/QN-route changes or broader final-production claims.
- `CV-009`: closed for the pre-redo gate. Retained Newton/RATTLE/QN/HMC/RG cores now have deterministic guardrails for Newton replay, successful RATTLE/RG pass replay, BTN residual reconstruction, official package-success route census, stub no-fallback behavior, RG reject stay-put identity, failure-as-rejection accounting, and a branch/measure harness recorded by `f14_complete_pre_redo_gate.py`.
- `CV-010`: closed for the pre-redo gate. Local transition accounting now uses `tltm_local_transition_event_t`, `F4_LOCAL_TRANSITION_AUDIT_V1` freezes the typed audit context, and M4 validates audit row invariants plus reverse-gate counter identities.
- `CV-011`: RNG/workspace/reentrancy remains an unfinished productization foundation.

## Forward Queue

| Step | Workstream | Status | Allowed now | Output | Gate to advance |
| --- | --- | --- | --- | --- | --- |
| F0 | foundation completeness reset | active | yes | `FOUNDATION_COMPLETENESS_RESET_20260511.md`, expanded `CAVEATS.tsv`/`OPEN_ITEMS.tsv` | no compact doc says foundation is complete |
| F1 | ODEX backend completeness | accepted_reduced_scope | yes | standalone endpoint backend, result/workspace/status, flow/Jacobian, default-off assist-policy, and representative assist-on/off diagnostics | delete solver assist after pre-redo; reopen only for dense output, product-complete Hairer claim, or changed final-flow policy |
| F2 | official DFO-LS backend completion | done | yes | representative embedded official DFO-LS 10seed x 10k gate passed with 1000 captured attempts, 923 embedded-converged attempts, 0 float64 failures, 0 missing rows, and 0 embedded-converged regressions | reopen only on official DFO-LS package/preset/residual callback/acceptance gate/runtime bridge/QN-route changes or broader final-production claims |
| F3 | retained-core deterministic evidence pack | done | yes | deterministic guardrails now cover Newton, successful RATTLE/RG, BTN residual, official package-success route census, stub no-fallback behavior, RG reject identity, failure-as-rejection accounting, and F14 branch/measure harness | reopen only if retained-core route logic, tolerances, proposal policy, or official DFO-LS acceptance changes |
| F4 | diagnostics/status/accounting foundation | done | yes | typed local-transition event source, event-derived counters, local-transition audit schema, and M4 row-invariant validation | reopen only if status codes, local counters, sidecar schema, or audit row semantics change |
| F5 | M6 read-only comparison tooling | done | yes | `m6_reference_compare.py`, comparison summary/report | tool can regenerate report from accepted M6 readback or raw package CSV |
| F6 | M6 and official-small degeneracy observation | active | yes, read-only | use M6 R1-R4 only as historical/internal anchors; use imported official 10seed/10k production-comparison evidence for real official-line nofb-vs-withfb degeneracy observation | M6 is not official DFO-LS evidence; official 10seed/10k is calibration only; no source changes; label all production outputs provisional |
| F7 | public method naming and schema-role design | done | yes | `F7_METHOD_ALIASES_V1` freezes public `nofb`/`withfb` names with `no_fb`/`fb_norefine` compatibility aliases | reopen only for schema v2, public taxonomy change, or field removal |
| F8 | reference comparison harness for source patches | done | yes | `F8_PATCH_REFERENCE_STATEMENT_V1` and `f14_complete_pre_redo_gate.py` provide patch-local reference statement and M6 anchor validation | run this harness for every future behavior-relevant source patch |
| F9 | low-risk non-physics utility/API cleanup | gated | after-F8 | exact-output or tolerance-bound comparison against accepted rows | no RNG/proposal/schema/counter meaning drift |
| F10 | typed status/result propagation | gated | after-F14-redo-scope | explicit flow/solver/RATTLE/HMC/reverse-gate result objects | route/counter equality checks pass |
| F11 | diagnostics accounting implementation | gated | after-F14-redo-scope | broader structured forward/replay/probe/reject accounting beyond local-transition event source | schema versioning and compatibility readers exist |
| F12 | unified wrapper/product interface | gated | after-F14-redo-scope | wrapper runs same Stage2/Stage3 protocol with v1 sidecars | no public behavior replacement without compatibility layer |
| F13 | RNG/reentrancy/module workspace migration | deferred | no | explicit per-run/per-replica state | deterministic parallel/reference comparisons exist |
| F14 | publication-grade production regeneration | blocked | redo scope/scale decision | F3/F4/F7/F8 pre-redo gates now pass without reduced-scope acceptance | record exact redo scope/scale, target commit/worktree, and promotion boundary before final regeneration |

## What Can Continue Before Pre-Redo

- Read-only reports and comparison tooling.
- Documentation and schema design.
- Local guardrail/tooling additions that do not mutate production outputs or active remote worktrees.
- Production redo planning with solver assist default-off.

Do not fast-forward or clean `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` while production-comparison jobs are active or pinned.

## Immediate Work

Read `FOUNDATION_COMPLETENESS_RESET_20260511.md` before any modernization task. The immediate implementation planning order is:

1. F14 scope/scale decision: matched `nofb` + `withfb` versus narrower run, seed/cycle count, and target commit/worktree.
2. Record the production-promotion boundary for CV-001/CV-002/CV-006: what the next redo can and cannot claim.
3. Then update the chosen production worktree and regenerate under solver assist default-off.

M6 comparison tooling remains available as historical/internal behavior readback, especially for assist-off degeneracy observation, with:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/m6_reference_compare.py
```

Use the generated report as a behavior anchor, not as official DFO-LS evidence and not as evidence that the foundation is complete.
