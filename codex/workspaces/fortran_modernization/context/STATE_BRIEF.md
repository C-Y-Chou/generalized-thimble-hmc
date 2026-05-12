# Fortran Modernization State Brief

Updated: 2026-05-12 JST

## Current Position

- Current position is `Reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> post-B RNG anchor added -> full OpenMP/thread-safe productization remains`.
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
- F1/CV-007 is closed by explicit product boundary: TLTM modernization targets an endpoint-only ODEX backend for TLTM flow endpoint evaluation; dense output and a general-purpose Hairer ODEX library claim are non-goals. `INTODE_SOLVER_ASSIST_ENABLED` defaults off and assist-on is diagnostic opt-in only pending later deletion.
- CV-001 is closed for modernization-tree official-line kernel correctness. `official_line_kernel_correctness_gate.py` passed under embedded official `DFO-LS==1.6.5`, `stable_gate77`, solver assist default-off, and the canonical Newton -> p28 QN BTN residual -> reverse gate -> Metropolis route. Manifest: `output/tests/official_line_kernel_correctness_gate/CV001_official_line_kernel_correctness_manifest.json`.
- CV-006 is closed by strict DFO-LS claim/provenance policy. `DFOLS_CLAIM_PROVENANCE_POLICY_V1` separates embedded official package evidence from historical/internal DFO-LS-style evidence, and M4 validates it through the CV-001 gate.
- CV-004 is closed as permanent governance: every behavior-relevant source patch requires F8, M4, and an affected-baseline comparison or explicitly approved narrower baseline.
- CV-005 is closed by the script/evidence audit registry and gate. Every tracked file under `scripts/`, `codex/tasks/`, and `codex/workspaces/fortran_modernization/tasks/` has a row in `SCRIPT_EVIDENCE_AUDIT_20260512.tsv`; M4 validates coverage and quarantines historical/legacy-route scripts.
- CV-011 route B is implemented for RNG streams: Stage1 replicas and Stage2 slots own local-update RNG state, Stage2 swaps use a separate deterministic swap stream, and summaries/manifests label `rng_stream_contract=per_replica_rng_v1`. This intentionally changes finite same-seed trajectories relative to the old shared serial RNG stream.
- Modernization finish decisions are recorded in `MODERNIZATION_FINISH_DECISIONS_20260512.md`: full OpenMP/thread-safe productization remains in scope and production redo is fully separated into `tltm_production_comparison`.
- Post-B deterministic reference anchor is added for `per_replica_rng_v1`: `post_b_rng_reference_anchor.py` runs tiny Stage1/Stage2 twice, normalizes elapsed/runtime fields, and compares against `POST_B_RNG_REFERENCE_ANCHOR_V1.json`.
- First non-RNG CV-011 workspace slice is implemented: `hmc_kernels:decompose2` no longer uses shared `save` scratch arrays, and the RATTLE core path carries an explicit `decompose2_workspace_t` through `rattle_step_workspace_t`.
- Second non-RNG CV-011 workspace slice is implemented: `quasi_newton_linear_solver_mod` no longer uses module-level `save` scratch arrays for linear direction solves and QN initial guesses.
- Third non-RNG CV-011 workspace slice is implemented: `hmc_constraints:solve_constraint_newton` now uses explicit `newton_constraint_workspace_t`, held by the active RATTLE workspace.
- CV-011 is now at a product-context decision point. Remaining state is not just scratch storage: flow/ODEX context, QN traces/capture/backend callback state, diagnostics counters/file handles, model tape cache, config mirror, and profiling need a top-level context strategy before further API migration.
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
- `runbooks/FOUNDATION_CLOSURE_DECISIONS_20260512.md`: user decisions for closing/reclassifying CV-001/CV-004/CV-005/CV-006/CV-007/CV-011.
- `runbooks/OFFICIAL_LINE_KERNEL_CORRECTNESS_GATE_20260512.md`: CV-001 official-line kernel correctness gate.
- `runbooks/DFOLS_CLAIM_PROVENANCE_POLICY_20260512.md`: CV-006 official-vs-historical DFO-LS claim policy.
- `runbooks/SCRIPT_EVIDENCE_AUDIT_20260512.md`: CV-005 script/evidence audit and quarantine policy.
- `runbooks/CV011_RNG_WORKSPACE_DECISION_PACKET_20260512.md`: CV-011 RNG/workspace/reentrancy decision packet; user selected route B.
- `runbooks/CV011_PER_REPLICA_RNG_IMPLEMENTATION_20260512.md`: route-B RNG implementation record and verification.
- `runbooks/MODERNIZATION_FINISH_DECISIONS_20260512.md`: final modernization/redo boundary and full OpenMP/thread-safe productization decisions.
- `runbooks/POST_B_RNG_REFERENCE_ANCHOR_20260512.md`: post-B route-B RNG reference anchor, frozen hashes, and verification.
- `runbooks/CV011_DECOMPOSE2_WORKSPACE_SLICE_20260512.md`: first non-RNG hidden-workspace migration after route-B RNG streams.
- `runbooks/CV011_QN_LINEAR_WORKSPACE_SLICE_20260512.md`: QN linear solver scratch workspace migration.
- `runbooks/CV011_NEWTON_WORKSPACE_SLICE_20260512.md`: Newton constraint solver scratch workspace migration.
- `runbooks/CV011_REMAINING_STATE_DECISION_POINT_20260512.md`: remaining hidden-state categories and the top-level-context decision point.
- `runbooks/FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`: historical F1/CV-007 endpoint package and solver-assist default-off implementation notes.
- `runbooks/OFFICIAL_DFOLS_PRODUCTION_REDO_READBACK_20260512.md`: official DFO-LS 256seed/200k production-comparison redo readback.
- `state/RETAINED_CORE_EVIDENCE.tsv`: retained-core evidence registry.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Ask for the CV-011 product-context decision: top-level TLTM run context first, or module-by-module contexts first. Production redo remains owned by the separate `tltm_production_comparison` tree and is not part of the modernization-finished condition.
