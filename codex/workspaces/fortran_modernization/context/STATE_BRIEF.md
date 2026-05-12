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
- F1/CV-007 is accepted reduced scope for pre-redo: standalone endpoint ODEX package exists, dense output is explicitly out of scope, `INTODE_SOLVER_ASSIST_ENABLED` now defaults off, and assist-on is diagnostic opt-in only pending later deletion.
- Modernization is not at automatic production-regeneration approval, but the user-selected conservative F3/F4/F7/F8 pre-redo gates are now implemented without reduced-scope acceptance.
- F3/CV-009 is closed for the pre-redo gate: retained-core tests cover Newton replay, successful one-step RATTLE/RG pass replay, BTN residual reconstruction, official package-success route census, stub no-fallback route behavior, RG reject/live-state identity, and failure-as-rejection accounting; `f14_complete_pre_redo_gate.py` records the branch/measure harness.
- F4/CV-010 is closed for the pre-redo gate: `tltm_local_transition_event_t` is the typed local-transition event source, counters are derived from that event, `F4_LOCAL_TRANSITION_AUDIT_V1` freezes the audit context, and M4 validates audit row invariants.
- F7/F8 are closed for the pre-redo gate: `F7_METHOD_ALIASES_V1` freezes `nofb`/`withfb` with raw aliases, and `F8_PATCH_REFERENCE_STATEMENT_V1` plus `f14_complete_pre_redo_gate.py` provides the patch-local reference harness.
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
- `runbooks/F14_PRODUCTION_REGENERATION_DECISION_PACKET_20260512.md`: current F14 decision/gate packet.
- `runbooks/DIAGNOSTICS_STATUS_ACCOUNTING_F4_DECISION_20260512.md`: F4 diagnostics/accounting completion packet.
- `runbooks/SCHEMA_REFERENCE_F7_F8_DECISION_20260512.md`: F7/F8 schema/naming and reference-comparison completion packet.
- `runbooks/FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`: F1/CV-007 standalone endpoint package and solver-assist default-off pre-redo policy.
- `runbooks/OFFICIAL_DFOLS_PRODUCTION_REDO_READBACK_20260512.md`: official DFO-LS 256seed/200k production-comparison redo readback.
- `state/RETAINED_CORE_EVIDENCE.tsv`: retained-core evidence registry.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Record the exact F14 production redo scope/scale and promotion boundary: matched `nofb` + `withfb` versus a narrower run, seed/cycle count, target commit/worktree, and final wording around remaining CV-001/CV-002/CV-006 production/provenance limits. Solver assist is default-off for the eventual redo.
