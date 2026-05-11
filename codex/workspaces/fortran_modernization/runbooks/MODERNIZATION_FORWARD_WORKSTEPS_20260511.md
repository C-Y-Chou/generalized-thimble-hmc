# Modernization Forward Worksteps

Updated: 2026-05-11 JST

Scope: caveat-gated forward queue for continuing TLTM Fortran modernization after official DFO-LS became the default backend and after the M6 R1-R4 reference baseline was accepted.

## Current Position

```text
Completed foundation -> accepted M6 reference baseline -> caveat-gated forward modernization
```

This queue supersedes any interpretation that M6 means modernization is complete. M6 is the behavior-protection anchor for the next work.

## Active Caveat Gates

- `CV-001`: final publication production still needs an official-DFO-LS-line kernel correctness gate or explicit accepted limitation.
- `CV-002`: current production-comparison outputs are provisional until final wrapper/schema/naming/counter conventions are frozen or final regeneration is scheduled.
- `CV-003`: production-comparison jobs execute only from the synchronized production-comparison worktree.
- `CV-004`: behavior-relevant source refactors need accepted reference comparison or an explicitly approved narrower baseline.
- `CV-005`: auxiliary or historical scripts require deep-read before reuse as evidence or automation.
- `CV-006`: DFO-LS claims must distinguish historical in-house/DFO-LS-style paths from embedded official package runs.
- `CV-007`: ODEX claims must state the current ODEX-primary/reduced-scope flow instead of pure or complete ODEX.

## Forward Queue

| Step | Workstream | Status | Allowed now | Output | Gate to advance |
| --- | --- | --- | --- | --- | --- |
| F0 | control-plane caveat hygiene | done | yes | `codex/state/CAVEATS.tsv`, L0 caveat display | `validate_control_plane` pass |
| F1 | implementation-truth caveat audit | active | yes | DFO-LS and ODEX truth boundaries registered and visible | no modernization claim stronger than implementation/evidence |
| F2 | DFO-LS claim-boundary cleanup | active | yes | historical in-house/DFO-LS-style evidence separated from official backend evidence | official claims require embedded backend/package provenance |
| F3 | ODEX scope-boundary cleanup | active | yes | ODEX-primary/reduced-scope wording and missing-completeness decisions explicit | no pure-ODEX or complete-ODEX overclaim |
| F4 | M6 read-only comparison tooling | active | yes | `m6_reference_compare.py`, comparison summary/report | tool can regenerate report from accepted M6 readback or raw package CSV |
| F5 | M6/product calibration reconciliation | next | yes, read-only | compare M6 R1-R4 against official DFO-LS provisional gates | no source changes; label all production outputs provisional |
| F6 | public method naming and schema-role design | next | docs/schema design only | raw `fb_norefine` remains readable; canonical `withfb` and algorithm IDs specified | no field removal until versioned schema exists |
| F7 | reference comparison harness for source patches | next | tests/tooling only | patch header template plus baseline comparison command set | required before behavior-relevant source refactors |
| F8 | low-risk non-physics utility/API cleanup | gated | only after F7 | exact-output or tolerance-bound comparison against accepted rows | no RNG/proposal/schema/counter meaning drift |
| F9 | typed status/result propagation | gated | after F7/F8 | explicit flow/solver/RATTLE/HMC/reverse-gate result objects | route/counter equality checks pass |
| F10 | diagnostics accounting context | gated | after schema decision | structured forward/replay/probe/reject accounting | schema versioning and compatibility readers exist |
| F11 | unified wrapper/product interface | gated | after schema decision | wrapper runs same Stage2/Stage3 protocol with v1 sidecars | no public behavior replacement without compatibility layer |
| F12 | RNG/reentrancy/module workspace migration | deferred | no | explicit per-run/per-replica state | deterministic parallel/reference comparisons exist |
| F13 | publication-grade production regeneration | deferred | no | final production datasets | CV-001/CV-002/CV-006/CV-007 resolved or explicitly accepted |

## What Can Continue While 32seed/50k Official Gate Runs

- Read-only reports and comparison tooling.
- Documentation and schema design.
- Local guardrail/tooling additions that do not mutate production outputs or active remote worktrees.
- Production-gate monitoring and readback.

Do not fast-forward or clean `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` while jobs `14766..14774` are active.

## Immediate Work

Keep F1-F3 current by auditing the implementation-truth caveats in `IMPLEMENTATION_TRUTH_CAVEATS_20260511.md`.
After that, run F4 with:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/m6_reference_compare.py
```

Then use the generated report as the first comparison anchor before planning schema/naming and source-patch comparison harnesses.
