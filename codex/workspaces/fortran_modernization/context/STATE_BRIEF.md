# Fortran Modernization State Brief

Updated: 2026-05-12 JST

## Current Position

- Current position is `Reference-audited core + accepted M6 behavior baseline -> foundation gaps still active -> source modernization remains gated`.
- M6 is not "modernization complete" and is not proof that the numerical/software foundation is complete; it is the accepted behavior baseline before larger source refactors resume.
- The compact source of truth for this positioning is `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`; the reset source of truth for foundation gaps is `runbooks/FOUNDATION_COMPLETENESS_RESET_20260511.md`.
- M3/M4/M5 modernization infrastructure work is treated as completed, partial, or explicitly deferred by workstream in that matrix.
- M6 R1-R4 reference packages are accepted after readback: expected per-method rows are present and protocol audit status is `pass` for R1-R4.
- The remote target is now semantically `fortran_modernization`, with branch `codex/fortran-modernization` and worktree `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- The old `qn_error_handling_validation` remote path/branch is historical and should not be the active target for new modernization work.
- Latest refresh shows no active pinned M6 jobs.
- Embedded official DFO-LS is now the default QN backend. `QN_SOLVER_BACKEND=internal` is only for controlled legacy comparison.
- Official DFO-LS backend replacement F2 is accepted for the current representative scope: representative embedded 10seed x 10k gate passed with 1000 captured attempts, 923 embedded-converged attempts, 0 float64 failures, 0 missing replay rows, and 0 embedded-converged regressions.
- Official DFO-LS production-comparison evidence exists as a completed provisional artifact: `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`, 256 seeds x 200000 cycles for both `nofb` and `withfb`, generated under production-comparison commit `c0e4021`. This artifact predates the latest modernization HEAD and must not be interpreted as a rerun after updating production to the current modernization state.
- F1/CV-007 is active again: the user reopened ODEX from reduced-scope endpoint backend to complete standalone/full Hairer ODEX endpoint package plus assist-off observable degeneracy testing. Dense output is explicitly out of scope.
- Modernization is not at automatic production-regeneration approval. F14 production regeneration is blocked until F1/CV-007 is completed or explicitly re-scoped, then the remaining F3/CV-009 and F4/CV-010 decisions still need resolution.
- F3 retained-core deterministic evidence has passing guardrails for Newton replay, successful one-step RATTLE/RG pass replay, BTN residual reconstruction, official package-success route census, stub no-fallback route behavior, RG reject/live-state identity, and failure-as-rejection accounting. The remaining F3 question is whether deterministic branch coverage is accepted or a formal local-volume/branch-measure proof/harness is required before production.
- F4 diagnostics/status/accounting is decision-pending: compatibility counters and sidecars exist, but the typed proposal/replay/residual/probe/reject/accept event context is not implemented.
- The default local source of truth is `/Users/ccy/Documents/TLTM_qn_error_handling`, not `/Users/ccy/Documents/New project/TLTM_repo`.

## Hard Rules

- Do not fast-forward the active remote worktree while pinned PBS jobs are running.
- Even when no pinned jobs are recorded, refresh remote state before fast-forward, rename, or cleanup.
- For PBS queue selection or repair, use the cluster02 scheduler agent.
- Do not delete reference outputs/logs until registry/readback is complete.

## Key Files

- `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`: compact status matrix and current position.
- `runbooks/STATUS.md`: long history.
- `runbooks/CLUSTER02_SCHEDULING_AGENT.md`: scheduler agent.
- `runbooks/M6_REFERENCE_DATASET_READBACK_PLAN.md`: readback gate.
- `runbooks/M6_REFERENCE_DATASET_READBACK_20260510.md`: accepted M6 R1-R4 readback.
- `runbooks/RETAINED_CORE_DETERMINISTIC_EVIDENCE_20260511.md`: retained-core guardrail evidence, including the 2026-05-12 official package route census and RG reject identity/accounting addendum.
- `runbooks/F14_PRODUCTION_REGENERATION_DECISION_PACKET_20260512.md`: current F14 decision packet.
- `runbooks/DIAGNOSTICS_STATUS_ACCOUNTING_F4_DECISION_20260512.md`: F4 diagnostics/accounting decision packet.
- `runbooks/SCHEMA_REFERENCE_F7_F8_DECISION_20260512.md`: F7/F8 schema/naming and reference-comparison decision packet.
- `runbooks/FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`: reopened F1/CV-007 full Hairer ODEX endpoint package and assist-off observable plan.
- `runbooks/OFFICIAL_DFOLS_PRODUCTION_REDO_READBACK_20260512.md`: official DFO-LS 256seed/200k production-comparison redo readback.
- `state/RETAINED_CORE_EVIDENCE.tsv`: retained-core evidence registry.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Continue `runbooks/FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`: audit and implement the standalone/full Hairer ODEX endpoint package boundary, then test whether disabling solver assist causes observable degeneracy. Do not promote the current modernization branch into final production rerun status while CV-007 is active.
