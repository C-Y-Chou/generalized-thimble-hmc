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
- `CV-007`: ODEX backend is accepted reduced scope; do not claim full Hairer ODEX package unless reopened.
- `CV-008`: official DFO-LS backend replacement is accepted for the representative scope: package provenance, preset/source contract, sidecar provenance guardrails, small embedded gate, imported official assist calibration, and representative embedded 10seed x 10k readback all pass. Reopen only on package/preset/callback/runtime/QN-route changes or broader final-production claims.
- `CV-009`: retained Newton/RATTLE/QN/HMC/RG cores need deterministic evidence packs before being treated as complete; Newton, successful RATTLE/RG pass replay, BTN residual reconstruction, and official-route no-fallback surface now pass, while fixed-seed route census, package-success route coverage, RG reject/live-state identity, and volume/branch coverage remain open.
- `CV-010`: diagnostics/status/counter accounting needs a typed foundation before final schema or production regeneration.
- `CV-011`: RNG/workspace/reentrancy remains an unfinished productization foundation.

## Forward Queue

| Step | Workstream | Status | Allowed now | Output | Gate to advance |
| --- | --- | --- | --- | --- | --- |
| F0 | foundation completeness reset | active | yes | `FOUNDATION_COMPLETENESS_RESET_20260511.md`, expanded `CAVEATS.tsv`/`OPEN_ITEMS.tsv` | no compact doc says foundation is complete |
| F1 | ODEX backend completeness | done | yes | accepted reduced-scope endpoint extrapolation backend; result/workspace/status, flow/Jacobian, assist-policy, and representative assist-on/off guardrails pass | reopen only for full Hairer ODEX package, dense output, stability-control behavior, or changed final-flow/assist policy |
| F2 | official DFO-LS backend completion | done | yes | representative embedded official DFO-LS 10seed x 10k gate passed with 1000 captured attempts, 923 embedded-converged attempts, 0 float64 failures, 0 missing rows, and 0 embedded-converged regressions | reopen only on official DFO-LS package/preset/residual callback/acceptance gate/runtime bridge/QN-route changes or broader final-production claims |
| F3 | retained-core deterministic evidence pack | active | tests/tooling | Newton replay, successful RATTLE/RG pass replay, BTN residual reconstruction, and official-route no-fallback guardrails pass; next add fixed-seed route census, package-success route coverage, RG reject identity, and local-volume/branch-measure checks | affected core rows pass or are explicitly scoped |
| F4 | diagnostics/status/accounting foundation | active | design/tests | typed diagnostics context and schema compatibility plan | counters/status/capture meaning is versioned and testable |
| F5 | M6 read-only comparison tooling | done | yes | `m6_reference_compare.py`, comparison summary/report | tool can regenerate report from accepted M6 readback or raw package CSV |
| F6 | M6 and official-small degeneracy observation | active | yes, read-only | use M6 R1-R4 only as historical/internal anchors; use imported official 10seed/10k production-comparison evidence for real official-line nofb-vs-withfb degeneracy observation | M6 is not official DFO-LS evidence; official 10seed/10k is calibration only; no source changes; label all production outputs provisional |
| F7 | public method naming and schema-role design | gated | docs/schema design only | raw aliases remain readable; canonical roles/algorithm IDs specified | no field removal until versioned schema exists |
| F8 | reference comparison harness for source patches | gated | tests/tooling only | patch header template plus baseline comparison command set | required before behavior-relevant source refactors |
| F9 | low-risk non-physics utility/API cleanup | gated | only after F8 and affected foundation rows | exact-output or tolerance-bound comparison against accepted rows | no RNG/proposal/schema/counter meaning drift |
| F10 | typed status/result propagation | gated | after F3/F4/F8 | explicit flow/solver/RATTLE/HMC/reverse-gate result objects | route/counter equality checks pass |
| F11 | diagnostics accounting implementation | gated | after F4/schema decision | structured forward/replay/probe/reject accounting | schema versioning and compatibility readers exist |
| F12 | unified wrapper/product interface | gated | after schema decision | wrapper runs same Stage2/Stage3 protocol with v1 sidecars | no public behavior replacement without compatibility layer |
| F13 | RNG/reentrancy/module workspace migration | deferred | no | explicit per-run/per-replica state | deterministic parallel/reference comparisons exist |
| F14 | publication-grade production regeneration | deferred | no | final production datasets | CV-001/CV-002/CV-006/CV-009/CV-010 and schema/wrapper decisions resolved or explicitly accepted |

## What Can Continue While 32seed/50k Official Gate Runs

- Read-only reports and comparison tooling.
- Documentation and schema design.
- Local guardrail/tooling additions that do not mutate production outputs or active remote worktrees.
- Production-gate monitoring and readback.

Do not fast-forward or clean `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` while production-comparison jobs are active or pinned.

## Immediate Work

Read `FOUNDATION_COMPLETENESS_RESET_20260511.md` before any modernization task. The immediate implementation planning order is:

1. Retained-core deterministic evidence pack.
2. Diagnostics/status/accounting foundation.
3. Reference-comparison harness for future behavior-relevant source patches.
4. Publication-production regeneration decision after remaining caveats are closed or explicitly accepted.

M6 comparison tooling remains available as historical/internal behavior readback, especially for assist-off degeneracy observation, with:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/m6_reference_compare.py
```

Use the generated report as a behavior anchor, not as official DFO-LS evidence and not as evidence that the foundation is complete.
