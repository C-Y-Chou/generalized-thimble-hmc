# Fortran Modernization State Brief

Updated: 2026-05-16 JST

## Read Before Next Solver-Policy Step

- 2026-05-15 decision: solver assist is back on the deletion track.  Treat F15 navigation-assist/fallback-on work as historical diagnostic evidence, not the canonical modernization policy.
- F15b solver-assist deletion is implemented in active source. `solve_flow` no longer has an active solver-assist branch or assist env parser; compatibility policy queries/counters remain only as off/zero readers, and legacy enable envs no longer activate any route.
- Required read before interpreting the post-deletion source behavior or before rerunning the npt5 assist-off baseline:
  `runbooks/F15_SOLVER_ASSIST_DELETION_20260515.md`.
- Required read before any further source work that touches `flowz` / `flowzr`, QN residual evaluation, final `flow(...)`, reverse gate, or Metropolis:
  `runbooks/ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md`.
- Correct modernization starting point for this slice is official DFO-LS `npt5_r0055`, true Stage2 RNG v2, method-level assist off.  The 10seed/10k readback is: `nofb` failures `8340`, mean Re `-0.002818340294982019`; `withfb` failures `167`, mean Re `0.02974362444598664`.
- The assist-off PBS wrapper now requires an explicit `TLTM_EXPECTED_GIT_COMMIT` for the source tree being submitted, records the evidence commit separately, and labels the output campaign with the current run SHA.  Do not conflate the 2026-05-15 evidence commit with later governance-only HEADs.
- Current-HEAD start-gate rerun passed at `71af06f55c240a0c20fc7a38c1353219be805930`: `no_fb` job `15455.anode01` reproduced failures `8340`, mean Re `-0.002818340294982019`; `fb_norefine` job `15456.anode01` reproduced failures `167`, mean Re `0.02974362444598664`; both manifests recorded `BASELINE_RUNTIME_SOURCE_RELATION=runtime_source_matches_baseline_evidence`.
- `withfb` failure reduction remains numerically interesting but is not proof that the feedback kernel preserves the target measure.  Audit feedback-kernel correctness separately from solver-assist deletion.
- `runbooks/NAVIGATION_ASSIST_STRICT_CERTIFICATION_POLICY_20260513.md` remains historical context for the previous F15 candidate only.
- 2026-05-14 update: the assist/root-cause diagnostic tree is no longer active production work.  Keep the diagnostic evidence, but converge active work back to `fortran_modernization` and `tltm_production_comparison`: finish the modernization fix first, then sync production-comparison and regenerate production.
- Required read before claiming paper-level correctness of hand-written numerical algorithms, or before changing controller constants/branch logic under "cleanup":
  `runbooks/INTEGRATED_ALGORITHM_MODERNIZATION_PLAN_20260515.md`,
  `runbooks/OFFICIAL_DFOLS_THIN_BRIDGE_BRANCH_MAP_20260515.md`,
  `runbooks/F19_OFFICIAL_DFOLS_CERTIFICATION_RENAME_20260515.md`,
  `runbooks/F19_OFFICIAL_DFOLS_POLICY_ISOLATION_20260515.md`,
  `runbooks/F19_INTERNAL_DFO_BACKEND_DELETION_20260515.md`,
  `runbooks/MATURE_ODE_BACKEND_DECISION_20260515.md`,
  `runbooks/HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md`,
  `runbooks/HANDWRITTEN_ALGORITHM_CURRENT_HEAD_AUDIT_20260515.md`,
  `runbooks/HANDWRITTEN_ALGORITHM_DETAIL_AUDIT_GAP_REPORT_20260514.md`,
  `runbooks/ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`, and
  `runbooks/HANDWRITTEN_ALGORITHM_CURRENT_ANALYSIS_REPORT_20260514.md`.  This is `CV-012`: the 2026-05-15 all-handwritten paper-correctness/numerical-soundness audit is complete and found no immediate current-route source bug, but it explicitly blocks the claim that all hand-authored algorithms are paper-correct.
- Required read before continuing CV-011 RNG work: `runbooks/CV011_STAGE2_KERNEL_RNG_V2_IMPLEMENTATION_20260514.md`.  `TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2` is implemented as the Stage2 default; `legacy_global_v0` is compatibility only, and `per_replica_rng_v1` is retained for the post-B anchor/audit path.

## Current Position

- Current position is `Reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> post-B RNG anchor added -> top-level TLTM run context selected -> flow/ODEX/HMC/QN flow context implemented -> official DFO-LS callback context implemented -> QN trace/eval context implemented -> QN diagnostics context implemented -> QN policy context implemented -> HMC policy/reverse-gate context implemented -> F15 navigation-assist evidence demoted -> profile context implemented -> HMC reversibility diagnostics context implemented -> Newton eval-flow status context implemented -> Stage2 RNG v2 implemented -> assist-off start gate protected -> all-handwritten paper-correctness/numerical-soundness audit complete with explicit non-paper-exact surfaces -> mature ODE backend route selected for ODEX-controller risk -> F19 official DFO-LS thin bridge cleanup implemented through internal-backend deletion -> F15b solver-assist deletion implemented -> F18 SUNDIALS CVODE disabled-by-default backend implemented, local M4-gated, 10seed/10k comparison read back, fixed-point m>0 rejected, and max-step fail-fast s320 rejected at 10seed/10k -> remaining constraint/flow/model/config state boundaries`.
- M6 is not "modernization complete" and is not proof that the numerical/software foundation is complete; it is the accepted behavior baseline before larger source refactors resume.
- The compact source of truth for this positioning is `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`; the reset source of truth for foundation gaps is `runbooks/FOUNDATION_COMPLETENESS_RESET_20260511.md`.
- M3/M4/M5 modernization infrastructure work is treated as completed, partial, or explicitly deferred by workstream in that matrix.
- M6 R1-R4 reference packages are accepted after readback: expected per-method rows are present and protocol audit status is `pass` for R1-R4.
- The remote target is now semantically `fortran_modernization`, with branch `codex/fortran-modernization` and worktree `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- The old `qn_error_handling_validation` remote path/branch is historical and should not be the active target for new modernization work.
- Latest refresh shows no active PBS jobs. The remote modernization worktree
  was fast-forwarded to
  `1d750409cf3e4b7f15ccb203958a685aa922bf2c`; enabled CVODE binaries rebuilt
  and the enabled CVODE contract passed, including the deliberate max-step
  failure case, before the 10seed/10k `s320` fail-fast check.
- Embedded official DFO-LS is now the only active QN backend. `QN_SOLVER_BACKEND=internal` is no longer supported; active source warns and uses `official_dfols`.
- Official DFO-LS backend replacement F2 is accepted for the current representative scope: representative embedded 10seed x 10k gate passed with 1000 captured attempts, 923 embedded-converged attempts, 0 float64 failures, 0 missing replay rows, and 0 embedded-converged regressions.
- Official DFO-LS production-comparison evidence exists as a completed provisional artifact: `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`, 256 seeds x 200000 cycles for both `nofb` and `withfb`, generated under production-comparison commit `c0e4021`. This artifact predates the latest modernization HEAD and must not be interpreted as a rerun after updating production to the current modernization state.
- F1/CV-007 endpoint-only ODEX product boundary remains closed for dense-output/general-library scope.  The 2026-05-15 solver-policy decision supersedes the previous fallback-on strict-certification candidate, and F15b has deleted the active solver-assist policy/machinery. `ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md` remains the npt5 assist-off baseline handoff for any production-comparison sync or rerun.
- CV-001 is closed for modernization-tree official-line kernel correctness. `official_line_kernel_correctness_gate.py` passed under embedded official `DFO-LS==1.6.5`, `stable_gate77`, solver assist default-off, and the canonical Newton -> p28 QN BTN residual -> reverse gate -> Metropolis route. Manifest: `output/tests/official_line_kernel_correctness_gate/CV001_official_line_kernel_correctness_manifest.json`.
- CV-006 is closed by strict DFO-LS claim/provenance policy. `DFOLS_CLAIM_PROVENANCE_POLICY_V1` separates embedded official package evidence from historical/internal DFO-LS-style evidence, and M4 validates it through the CV-001 gate.
- CV-004 is closed as permanent governance: every behavior-relevant source patch requires F8, M4, and an affected-baseline comparison or explicitly approved narrower baseline.
- CV-005 is closed by the script/evidence audit registry and gate. Every tracked file under `scripts/`, `codex/tasks/`, and `codex/workspaces/fortran_modernization/tasks/` has a row in `SCRIPT_EVIDENCE_AUDIT_20260512.tsv`; M4 validates coverage and quarantines historical/legacy-route scripts.
- CV-011 route B is implemented for RNG streams: Stage1 replicas and Stage2 slots own local-update RNG state, Stage2 swaps use a separate deterministic swap stream, and summaries/manifests label `rng_stream_contract=per_replica_rng_v1`. This intentionally changes finite same-seed trajectories relative to the old shared serial RNG stream.
- The 2026-05-13 assist-regression tiny reproducer identified the Stage2 RNG stream contract as the first behavioral transition.  CV-011 RNG modernization now implements `stage2_kernel_rng_v2` with domain-separated transition-kernel RNG keys; do not promote `per_replica_rng_v1` to production equivalence by default.
- Modernization finish decisions are recorded in `MODERNIZATION_FINISH_DECISIONS_20260512.md`: full OpenMP/thread-safe productization remains in scope and production redo is fully separated into `tltm_production_comparison`.
- Post-B deterministic reference anchor is added for `per_replica_rng_v1`: `post_b_rng_reference_anchor.py` runs tiny Stage1/Stage2 twice, normalizes elapsed/runtime fields, and compares against `POST_B_RNG_REFERENCE_ANCHOR_V1.json`.
- First non-RNG CV-011 workspace slice is implemented: `hmc_kernels:decompose2` no longer uses shared `save` scratch arrays, and the RATTLE core path carries an explicit `decompose2_workspace_t` through `rattle_step_workspace_t`.
- Second non-RNG CV-011 workspace slice is implemented: `quasi_newton_linear_solver_mod` no longer uses module-level `save` scratch arrays for linear direction solves and QN initial guesses.
- Third non-RNG CV-011 workspace slice is implemented: `hmc_constraints:solve_constraint_newton` now uses explicit `newton_constraint_workspace_t`, held by the active RATTLE workspace.
- CV-011 top-level context route A is selected. First slice is implemented: `tltm_run_context_t` owns HMC proposal/reverse-probe/warmup workspaces, and Stage1/Stage2 carry one context per replica/slot through local updates.
- Stage2 audit file handles/row counters have been migrated out of module `save` state into a Stage2-owned audit context.
- CV-011 flow/ODEX context route A is selected and implemented. `odex_backend` now has a context-aware callback path; `solve_flow` owns endpoint buffers/RHS scratch/ODEX workspace through `flow_workspace_t`; Stage1/Stage2 initialization, Stage2 swap reflow, and Stage1/Stage2 local-update HMC/QN proposal paths pass per-replica/per-slot run-context flow workspaces.
- CV-011 official DFO-LS callback context route A is selected and implemented. The C bridge `ctx` pointer now carries per-attempt official callback context, so the active route no longer depends on module-level `qn_official_*` callback arrays/active flag.
- CV-011 QN trace/eval context route A first slice is implemented. Active Stage1/Stage2 local updates pass `run_context%qn%workspace`; QN residual scratch, eval proposed/flowed caches, last-trace buffers, trace route/iteration state, and per-attempt residual eval count now live in `qn_context_t`, with module fallback preserved for legacy direct callers.
- CV-011 QN diagnostics context route A is implemented. Stage1/Stage2 now own one run-level `qn_diagnostics_context_t`; QN attempt-capture file handles/flags/counters, eval-flow status counters, and QN global-filter counters live in that diagnostics sink, with module fallback preserved for legacy direct callers.
- CV-011 QN policy context route A is implemented. Stage1/Stage2 now own one run-level `qn_policy_context_t`; QN backend policy cache, official DFO-LS preset values, notice state, and official bridge failure warning state live in that policy context, with module fallback preserved for legacy direct callers.
- CV-011 HMC policy/reverse-gate context route A is implemented. Stage1/Stage2 now own one run-level `hmc_policy_context_t` and one run-level `hmc_replay_diagnostics_context_t`; each per-replica/per-slot HMC context owns `hmc_replay_runtime_context_t`; official DFO-LS bridge/reverse-gate policy, `qn_reverse_gate_active`, and replay status counters no longer use active shared module state on the Stage1/Stage2 local-update path.
- F15 navigation-assist strict-certification policy is implemented and locally gated, but it is no longer the canonical modernization direction.  Current decision keeps it as diagnostic/historical evidence; F15b deleted the active solver-assist route and M4 passed the post-deletion guardrails.
- CV-011 profile context is implemented. `perf_profile` now has `perf_profile_context_t`, optional context-aware profiler APIs, a legacy module fallback for old callers, and `tltm_run_context_t%profile%profiler` for future wrapper/product threading.
- CV-011 HMC reversibility diagnostics context is implemented. Stage1/Stage2 local updates now pass `tltm_run_context_t%diagnostics%hmc_reversibility`; reversibility-probe and state-progress diagnostic policy/counter state no longer use active shared module state on that path.
- CV-011 Newton eval-flow status context is implemented. Stage1/Stage2 local updates now pass a Stage/run-owned `newton_eval_flow_status_context_t`; Newton eval-flow summary counters no longer use active shared module state on that path.
- Remaining CV-011 state is not just scratch storage: constraint-solver aggregate/reverse-gate path/failure-capture counters, flow/ODEX counters/traces/last-failure snapshot, model tape cache, and config mirror still need migration or explicit product boundaries.
- Legacy dead-trigger and strange-name cleanup is modernization work when behavior is preserved: audit `eo`, `istest`, `testmom`, `rattle2`, and `decompose2` under F9/W11 with F8 guardrails. Deferred F16 is only for candidate bugs whose fix may intentionally change output, counters, route selection, or public schema meaning.
- Modernization is not at automatic production-regeneration approval, but the user-selected conservative F3/F4/F7/F8 pre-redo gates are now implemented without reduced-scope acceptance.
- CV-012 is active but all-handwritten audited: `HANDWRITTEN_ALGORITHM_CURRENT_HEAD_AUDIT_20260515.md` inspected the post-correction source at committed source head `3d63d4c`, and `HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md` performed the stronger all-handwritten paper-correctness/numerical-soundness audit. No immediate current-route source bug was found. Universal paper-correctness remains blocked. ODEX-controller risk is now routed through `MATURE_ODE_BACKEND_DECISION_20260515.md`: evaluate a mature package backend, with SUNDIALS CVODE primary and ODEPACK fallback, while keeping the handwritten endpoint-only ODEX as the baseline until F8/M4 and affected-baseline gates pass. `F18_MATURE_ODE_PACKAGE_DISCOVERY_20260515.md` records the F18 spike and implementation/readbacks: no preinstalled SUNDIALS/ODEPACK was found, remote SUNDIALS v7.7.0 serial CVODE was built under `.deps`, the disabled-by-default CVODE backend was implemented, local/default M4 passed, remote CVODE 10seed/10k comparison completed cleanly, the parallel 10seed/1k fixed-point sweep rejected `TLTM_CVODE_FIXEDPOINT_M=2/4/8`, and the `TLTM_CVODE_MAX_STEPS=320` fail-fast 10seed/10k check was rejected because it caused large proposal/failure-surface and observable drift.
- F20 precision/GPU readiness is active as a modernization closeout requirement. Strict double precision remains the canonical correctness baseline; future single/mixed precision or weaker tolerances must be a separately certified GPU/performance mode and must not be mixed into F18 SUNDIALS/CVODE correctness comparison.
- Integrated plan: `INTEGRATED_ALGORITHM_MODERNIZATION_PLAN_20260515.md` is the active execution sequence. `OFFICIAL_DFOLS_THIN_BRIDGE_BRANCH_MAP_20260515.md` is the active F19 source map. `F19_OFFICIAL_DFOLS_CERTIFICATION_RENAME_20260515.md`, `F19_OFFICIAL_DFOLS_POLICY_ISOLATION_20260515.md`, and `F19_INTERNAL_DFO_BACKEND_DELETION_20260515.md` record the implemented F19 thin bridge cleanup. `F15_SOLVER_ASSIST_DELETION_20260515.md` records the implemented solver-assist deletion. Keep RATTLE failure-as-rejection as the accepted MCMC policy; next continue mature ODE backend evaluation and the remaining explicit-state/productization queue.
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
- `runbooks/CV011_STAGE2_KERNEL_RNG_V2_DESIGN_20260514.md`: required target design for replacing or auditing `per_replica_rng_v1` after the assist-regression investigation.
- `runbooks/MODERNIZATION_FINISH_DECISIONS_20260512.md`: final modernization/redo boundary and full OpenMP/thread-safe productization decisions.
- `runbooks/POST_B_RNG_REFERENCE_ANCHOR_20260512.md`: post-B route-B RNG reference anchor, frozen hashes, and verification.
- `runbooks/CV011_DECOMPOSE2_WORKSPACE_SLICE_20260512.md`: first non-RNG hidden-workspace migration after route-B RNG streams.
- `runbooks/CV011_QN_LINEAR_WORKSPACE_SLICE_20260512.md`: QN linear solver scratch workspace migration.
- `runbooks/CV011_NEWTON_WORKSPACE_SLICE_20260512.md`: Newton constraint solver scratch workspace migration.
- `runbooks/CV011_REMAINING_STATE_DECISION_POINT_20260512.md`: remaining hidden-state categories and the top-level-context decision point.
- `runbooks/CV011_TOP_LEVEL_RUN_CONTEXT_SLICE_20260512.md`: user-selected top-level run context route and first HMC context threading slice.
- `runbooks/CV011_STAGE2_AUDIT_CONTEXT_SLICE_20260512.md`: Stage2 diagnostic audit file/counter state moved from module globals into run-owned context.
- `runbooks/CV011_FLOW_CONTEXT_DECISION_POINT_20260512.md`: selected route-A decision point for removing hidden ODEX RHS callback state.
- `runbooks/CV011_FLOW_CONTEXT_SLICE_20260513.md`: selected route-A implementation record for context-aware ODEX callbacks and `flow_workspace_t`.
- `runbooks/CV011_HMC_QN_FLOW_CONTEXT_SLICE_20260513.md`: HMC/Newton/QN local-update flow workspace threading slice.
- `runbooks/CV011_QN_OFFICIAL_CALLBACK_CONTEXT_DECISION_POINT_20260513.md`: selected route-A decision point for removing official DFO-LS callback module state.
- `runbooks/CV011_QN_OFFICIAL_CALLBACK_CONTEXT_SLICE_20260513.md`: official DFO-LS callback context implementation record.
- `runbooks/CV011_QN_TRACE_CAPTURE_CONTEXT_DECISION_POINT_20260513.md`: selected route-A decision point for QN trace/capture/eval context ownership.
- `runbooks/CV011_QN_TRACE_EVAL_CONTEXT_SLICE_20260513.md`: QN trace/eval context implementation record; watchdog pieces were later removed from active source by F19.
- `runbooks/CV011_QN_CAPTURE_DIAGNOSTICS_CONTEXT_DECISION_POINT_20260513.md`: selected route-A decision point for QN capture/counter diagnostics ownership.
- `runbooks/CV011_QN_DIAGNOSTICS_CONTEXT_SLICE_20260513.md`: QN diagnostics/capture sink implementation record.
- `runbooks/CV011_QN_BACKEND_POLICY_CONTEXT_DECISION_POINT_20260513.md`: selected route-A decision point for QN backend policy ownership; watchdog policy was later removed from active source by F19.
- `runbooks/CV011_QN_POLICY_CONTEXT_SLICE_20260513.md`: QN backend policy context implementation record; watchdog/force-best policy was later removed from active source by F19.
- `runbooks/CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_DECISION_POINT_20260513.md`: selected route-A decision point for HMC bridge/reverse-gate policy, runtime, and replay counters.
- `runbooks/CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_SLICE_20260513.md`: HMC bridge/reverse-gate policy/runtime/diagnostics context implementation record.
- `runbooks/CV011_PROFILE_CONTEXT_SLICE_20260513.md`: profiler context ownership and guardrail record.
- `runbooks/CV011_HMC_REVERSIBILITY_CONTEXT_SLICE_20260513.md`: HMC reversibility/progress diagnostic context ownership and guardrail record.
- `runbooks/CV011_NEWTON_FLOW_STATUS_CONTEXT_SLICE_20260513.md`: Newton eval-flow status context ownership and guardrail record.
- `runbooks/MODERNIZATION_LEGACY_TRIGGER_NAMING_CLEANUP_20260513.md`: active modernization lane for behavior-preserving dead-trigger and strange-name cleanup.
- `runbooks/POST_MODERNIZATION_CORRECTNESS_SWEEP_PLAN_20260513.md`: deferred post-modernization correctness lane for bug discovery that may intentionally change behavior after evidence and approval.
- `runbooks/ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md`: current solver-assist deletion handoff and reproducible official DFO-LS `npt5_r0055` assist-off baseline.
- `runbooks/F15_SOLVER_ASSIST_DELETION_20260515.md`: completed F15b active-source deletion of solver assist, compatibility/off-zero policy, F8 statement, focused tests, and M4 verification.
- `runbooks/NAVIGATION_ASSIST_STRICT_CERTIFICATION_POLICY_20260513.md`: historical F15 fallback-on solver-assist candidate; no longer canonical after the 2026-05-15 assist-deletion decision.
- `runbooks/F15_NAVIGATION_ASSIST_IMPLEMENTATION_20260513.md`: implemented typed solver-assist policy and M4-gated production-tree sync handoff.
- `runbooks/INTEGRATED_ALGORITHM_MODERNIZATION_PLAN_20260515.md`: current execution plan integrating RATTLE failure-as-rejection, official DFO-LS thin bridge cleanup, solver-assist deletion, and mature ODE backend evaluation.
- `runbooks/OFFICIAL_DFOLS_THIN_BRIDGE_BRANCH_MAP_20260515.md`: F19 source map updated after implementation; active source now has the official package bridge, TLTM strict certification gates, diagnostics-only surfaces, and no internal backend.
- `runbooks/F19_OFFICIAL_DFOLS_CERTIFICATION_RENAME_20260515.md`: completed F19.1 source slice renaming the strict candidate certification helper and recording local verification.
- `runbooks/F19_OFFICIAL_DFOLS_POLICY_ISOLATION_20260515.md`: completed F19.2 source slice isolating official DFO-LS from legacy rescue/force-best/watchdog/relaxed-tolerance policy and recording M4 verification.
- `runbooks/F19_INTERNAL_DFO_BACKEND_DELETION_20260515.md`: completed F19 deletion slice removing `QN_SOLVER_BACKEND=internal`, internal DFO-like helpers, near/far retry controls, force-best, and quasi watchdog/budget controls from active source.
- `runbooks/MATURE_ODE_BACKEND_DECISION_20260515.md`: selected direction for ODEX-controller risk; evaluate mature external ODE package backend instead of proving the handwritten endpoint-only controller as full Hairer ODEX.
- `runbooks/F18_MATURE_ODE_PACKAGE_DISCOVERY_20260515.md`: F18 package availability, remote SUNDIALS v7.7.0 serial CVODE dependency, disabled-by-default CVODE backend, local M4 gate, and 10seed/10k comparison readback record.
- `runbooks/F20_PRECISION_GPU_READINESS_20260515.md`: closeout requirement for precision/tolerance profiles and future single/mixed GPU readiness while preserving the strict double correctness baseline.
- `runbooks/HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md`: active all-handwritten paper-correctness and numerical-soundness audit; blocks universal paper-correctness while recording no immediate current-route source bug and the concrete closure queue.
- `runbooks/HANDWRITTEN_ALGORITHM_CURRENT_HEAD_AUDIT_20260515.md`: current-head CV-012/F17 audit after Stage2 RNG v2 and assist-off correction; supplemented by the all-handwritten paper-correctness audit.
- `runbooks/HANDWRITTEN_ALGORITHM_DETAIL_AUDIT_GAP_REPORT_20260514.md`: CV-012 report separating reference mapping, behavior baselines, and paper-level implementation-detail signoff for hand-written numerical algorithms.
- `runbooks/ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`: first-pass ODEX controller detail audit, including h0, h-min, adaptive h/order update, work estimate, rejection branches, stability, signed intervals, and endpoint-only claim boundary.
- `runbooks/HANDWRITTEN_ALGORITHM_CURRENT_ANALYSIS_REPORT_20260514.md`: current full handwritten-algorithm analysis report covering ODEX, flow/Jacobian RHS, Newton, RATTLE/HMC, BTN/QN, official DFO-LS bridge, navigation assist, Metropolis, Stage2 tempering/RNG, and diagnostics/counters.
- `runbooks/FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`: historical F1/CV-007 endpoint package and solver-assist default-off implementation notes.
- `runbooks/OFFICIAL_DFOLS_PRODUCTION_REDO_READBACK_20260512.md`: official DFO-LS 256seed/200k production-comparison redo readback.
- `state/RETAINED_CORE_EVIDENCE.tsv`: retained-core evidence registry.
- `state/M6_REFERENCE_PACKAGES.tsv`: package registry template.
- `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`: scheduler memory.

## Next Action

Start the next modernization patch from `/Users/ccy/Documents/TLTM_qn_error_handling` on `codex/fortran-modernization`, not from the legacy diagnostic checkout. F15b source deletion and M4 are complete; before production-comparison sync/regeneration from this patch, rerun the direct `npt5_r0055` 10seed/10k PBS wrapper from `ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md` at the clean selected commit, or explicitly record a narrower affected-baseline decision.

The next operational step is after the negative F18 fail-fast readback: the
10seed/10k campaign
`cvode_failfast_s320_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260516T000908_1d750409cf3e`
completed both jobs with `Exit_status=0`, but `TLTM_CVODE_MAX_STEPS=320`
produced unacceptable observable drift and proposal-failure inflation. Do not
scale the fixed-point `m>0` branch or the max-step fail-fast branch further.
Keep strict CVODE as a disabled-by-default comparison backend only unless an
explicitly different package route or non-kernel-changing performance path is
selected.
Keep F20 precision/GPU readiness as a modernization closeout requirement after
the double-precision package-backend route is understood. Feedback-kernel
measure correctness remains a separate audit. Production redo remains owned by
the separate `tltm_production_comparison` tree.
