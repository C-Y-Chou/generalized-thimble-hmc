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
- Modernization is not yet at the final "update production version and redo production" gate. F14 remains deferred until F3/CV-009, F4/CV-010, CV-001/CV-002, and final schema/wrapper/naming decisions are resolved or explicitly accepted.
- F3 retained-core deterministic evidence has passing guardrails for Newton replay, successful one-step RATTLE/RG pass replay, BTN residual reconstruction, and official-route no-fallback surface. F3 remains active for fixed-seed official-line route census, package-success route coverage, RG reject/live-state identity, and local-volume/branch-measure coverage.
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
- `runbooks/RETAINED_CORE_DETERMINISTIC_EVIDENCE_20260511.md`: first Newton and successful RATTLE/RG pass replay evidence.
- `runbooks/OFFICIAL_DFOLS_PRODUCTION_REDO_READBACK_20260512.md`: official DFO-LS 256seed/200k production-comparison redo readback.
- `state/RETAINED_CORE_EVIDENCE.tsv`: retained-core evidence registry.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Use `runbooks/MODERNIZATION_FORWARD_WORKSTEPS_20260511.md` as the active forward queue. F1 ODEX is accepted reduced scope and F2 official DFO-LS backend replacement is accepted for the current representative scope. The immediate next technical work is to continue F3 retained-core deterministic evidence with fixed-seed official-line route census, package-success route coverage, RG reject/live-state identity, and local-volume/branch-measure checks. Do not promote the current modernization branch into final production rerun status until the affected foundation and baseline gates are satisfied or explicitly accepted.
