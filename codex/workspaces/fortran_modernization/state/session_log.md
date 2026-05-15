# Session Log: fortran_modernization

## 2026-05-11 JST - Official DFO-LS small assist-degeneracy evidence imported
- Imported the official DFO-LS 10seed/10k production-comparison nofb-vs-withfb evidence from `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` into `state/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb/`.
- Added `runbooks/OFFICIAL_DFOLS_SMALL_ASSIST_DEGENERACY_READBACK_20260511.md`, `state/OFFICIAL_DFOLS_SMALL_ASSIST_DEGENERACY_SUMMARY.tsv`, and `state/OFFICIAL_DFOLS_EVIDENCE.tsv`.
- Readback: official `nofb` unresolved failures `7502`, official `withfb` unresolved failures `1179`, RG rejects `1252 -> 996`; this is official-line production-method degeneracy evidence, not M6 evidence and not ODE solver-internal assist-off.

## 2026-05-11 JST - ODEX assist conclusion wording corrected
- Corrected the ODEX assist readback artifact and related state wording: the artifact is a historical readback from recorded 2026-05-09 ODEX-only/solver-assist runs, not a fresh current-code ODEX revalidation test.
- `ODX-F4` is now informational rather than pass/fail evidence for closing `CV-007`.
- A real current-code ODEX assist-on/off or equivalent policy test remains required before drawing a current policy conclusion.

## 2026-05-11 JST - Current-code ODEX assist policy gate added
- Added comparison-only env control `INTODE_SOLVER_ASSIST_ENABLED=0`; default remains enabled when unset.
- Added `tests/test_odex_assist_policy.f90` and `make test_odex_assist_policy`, which runs default-enabled and env-disabled modes.
- Gate verifies h-min assist is allowed only in Newton/QN/QN-retry `flowz`/`flowzr` residual contexts, and rejects wrong reason, unknown context, final-flow context, and non-residual stages.
- This is a deterministic current-code policy boundary test, not a production-scale ODEX assist-on/off validation.

## 2026-05-11 JST - Representative ODEX assist on/off readback completed
- Added and ran `odex_official_dfols_assist_onoff_10seed_10k_20260511.pbs` on canonical remote modernization tree commit `61505c307358323fe81568eeb49cdd177a134496`.
- Scope: embedded official DFO-LS backend, `fb_norefine`, `t=0.35,L=2,nstep=20`, 10 seeds x 10000 cycles; only `INTODE_SOLVER_ASSIST_ENABLED` changed between variants.
- PBS job `14797.anode01` completed with `Exit_status=0`; imported aggregate/per-seed evidence into `state/odex_official_dfols_assist_onoff_20260511/`.
- Readback: assist-on Newton/QN solver-assist counters `682682/1858`; assist-off counters `0/0`; unresolved failures `1179 -> 1542`; h-min failures `0/0 -> 14515/118`.
- Conclusion: current-code solver-internal assist is a real robustness mechanism at this representative scale. This closes the representative policy readback slice, but CV-007 remains open for source-level ODEX result/workspace/status mapping and flow/Jacobian deterministic tests.

## 2026-04-30 16:05 JST
- Goal: establish the modernization governance and planning set before code refactors.
- Scope: architecture, solver-chain redesign planning, behavior-preservation rules, testing roadmap, risk tracking.
- Key principle: physics and approved outputs must be preserved during engineering refactors unless a scientific change is explicitly approved.
- Next action: perform the formal architecture audit and baseline verification plan.

## 2026-05-08 JST - Scope alias clarified
- User clarified that the desired "code refine" task is `fortran_modernization`.
- Do not create a separate `code_refine` workspace unless the scope later splits into a concrete implementation sprint.
- Use this workspace for behavior-preserving code cleanup/refactor planning and execution guardrails.

## 2026-05-09 JST - QN-clean promoted and ODEX scale-up submitted
- Promoted QN-clean modernization state into canonical `codex/preprod-hardening` without force-pushing; production worktree `/lustre1/home/cychou/TLTM` now points to `5b93aaa`.
- Copied the QN-clean 10k ODEX baseline into the production output namespace so future validation no longer depends on the side worktree.
- Rebuilt `run_tltm_stage2` and `evaluate_expectations` after cleaning stale compiler module artifacts.
- Submitted refreshed ODEX validation: `14324` for 32seed x 50k, `14325`-`14332` for 128seed x 100k chunks, and `14333` as the afterok merge job.

## 2026-05-09 JST - QN-clean ODEX staged validation completed
- Read completed 50k and 100k QN-clean ODEX reports.
- 100k physical observables are compatible with zero: `mean Re<O>=0.0017729074`, `mean Im<O>=-0.0005999719`, `Zmean Re=0.385239`, `Zmean Im=-0.200998`.
- ODEX-only increased projection/unresolved failures relative to pre-ODEX characterization, but RG rejects and pair0 acceptance stayed stable and no ODE invalid failures appeared.
- Added `runbooks/ODEX_50K_100K_VALIDATION_RESULT_20260509_QNCLEAN.md` with the staged-validation judgment.

## 2026-05-09 JST - Solver-internal ODE assist validation completed
- Read completed solver-assist 10k/50k/100k reports from commit `704e2aafa650dc7ea5a404f60c9e37d7c841f49d`.
- 100k physical observables remain compatible with zero: `mean Re<O>=-0.0013054876`, `mean Im<O>=0.0005283082`, `Zmean Re=-0.315388`, `Zmean Im=0.214810`.
- Solver assist reduced 100k unresolved failures from ODEX-only `326569` to `224580`, essentially matching the earlier pre-ODEX `fb_norefine` level `224439`.
- Updated canonical flow-policy candidate to ODEX primary plus solver-internal residual assist plus strict final proposal flow.
- Added `runbooks/ODEX_SOLVER_ASSIST_VALIDATION_RESULT_20260509_QNCLEAN.md`.

## 2026-05-09 JST - State/information propagation audit completed
- Audited HMC transition/status flow before source changes.
- Added `runbooks/STATE_INFORMATION_PROPAGATION_AUDIT.md`.
- Finding: rejected/failed proposals do not overwrite live Stage2 slot state, but failed/unavailable Hamiltonians are still encoded as `0.0` in HMC proposal/warmup/test paths.
- Proposed first source patch for user confirmation: remove `H=0` as unavailable-Hamiltonian sentinel, use existing proposal status/non-finite handling, and update Hamiltonian conservation test accordingly.

## 2026-05-09 JST - State/information propagation refine queue added
- User clarified that the flagged `h==0` issue means Hamiltonian `H==0` when a proposal is rejected, not ODE step size.
- Added `runbooks/STATE_INFORMATION_PROPAGATION_REFACTOR.md`.
- Recorded policy: solver-internal ODE assist can help NT/QN residual evaluation, but it must not finalize a proposal; final `flow(...)` remains strict.
- Future refactor should introduce typed state/status propagation, explicit HMC rejection-state semantics, sentinel-free residual/Hamiltonian handling, and separated assist/replay/proposal counters after solver-assist validation is analyzed.

## 2026-05-09 JST - HMC unavailable-Hamiltonian sentinel patch implemented
- Implemented the first state/information propagation source slice locally: HMC failed/unavailable Hamiltonians now use IEEE quiet NaN instead of `0.0`.
- Updated Hamiltonian conservation test to consume `proposal_ok` and finite-Hamiltonian checks.
- Updated warmup handling to branch on finite Hamiltonians rather than the legacy `H==0` sentinel.
- Verification passed: `make -C build FC=gfortran LDFLAGS= ../bin/test_program` and `make -C build FC=gfortran LDFLAGS= test1`.
- A tiny local Stage2 smoke still fails slot-1 initialization, but the same smoke fails on clean `HEAD`; recorded as pre-existing local smoke behavior rather than a patch regression.

## 2026-05-09 JST - Proposal status surface patch implemented
- Audited the next state boundary: `proposal_failed` currently conflates proposal construction failure, reverse-gate rejection, unavailable Hamiltonian, invalid `Delta H`, and related unavailable-proposal cases.
- Implemented optional RATTLE-step, HMC-proposal, and Metropolis-transition status codes while preserving existing `accept`, `proposal_ok`, and `proposal_failed` behavior.
- Updated Hamiltonian conservation test to assert successful proposals return `hmc_proposal_status_success`.
- Verification passed after clean rebuild: `make -C build FC=gfortran LDFLAGS= ../bin/test_program`, `make -C build FC=gfortran LDFLAGS= test1`, and `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2`.
- Found build-system risk: incremental build after public module API changes can crash because stale objects are not rebuilt automatically; clean rebuild is required until Fortran module dependency tracking is fixed.

## 2026-05-09 JST - Fortran module dependency build patch implemented
- Tracked `build/makefile` as the build entrypoint while keeping generated build artifacts ignored.
- Added `scripts/fortran_module_deps.py` to generate Make dependencies from Fortran `module`/`use` relationships.
- `build/makefile` now includes generated `.obj/fortran_module_deps.mk`, so module consumers rebuild when provider objects change.
- Verified the stale-object fix by touching `src/sampler/hmc.f90`; incremental `make -C build FC=gfortran LDFLAGS= ../bin/test_program` rebuilt downstream consumers including `tests/test_hamiltonian_conservation.o`.
- Verification passed: clean `../bin/test_program` rebuild, `test1`, and `../bin/run_tltm_stage2` build.

## 2026-05-08 JST - Planning information collection complete
- Read relevant Fortran source sections for ODEX/flow, Newton/RATTLE, quasi-Newton projection, HMC/Metropolis, Stage2 driver, tests, and existing program-map docs.
- Added low-level review notes for ODEX, simplified Newton/RATTLE, quasi-Newton projection, and HMC/Metropolis/TLTM driver.
- Added `BASELINE_VERIFICATION_MATRIX.md` and `PLANNING_DISCUSSION_BRIEF.md`.
- No Fortran source edits, jobs, or production worktree mutations were performed.
- Next action: discuss and confirm decisions listed in `PLANNING_DISCUSSION_BRIEF.md` before any implementation.
## 2026-05-08 JST - Decision: BTN canonical naming
- User confirmed `BTN` is the correct canonical name; earlier `BTM` usage was a typo. Future planning docs and code comments should use `BTN`; `BTM` may be mentioned only as a historical typo/alias.

## 2026-05-08 JST - Decision: p28 quasi route canonical
- User confirmed that outside the current p28 route, all other quasi routes should be treated as legacy and may be scheduled for deletion.
- Canonical production quasi route is p28: Newton first, then QN S1 probe with `QN_S1_PROBE_MAX_ITER=28`, using DFO-LS on `evaluate_constraint_residual`, with current Stage3_4 near/non-near/global rescue off, then RG when enabled.
- Historical note: post-refine was still under observation at this point; it has since been removed from active source after validation and user approval.

## 2026-05-08 JST - Decision: unified TLTM wrapper direction
- User confirmed that after TLTM construction is complete, the project should not continue exposing fragmented Stage2/Stage3/Stage3_4 workflows.
- Modernization target is a unified TLTM wrapper/runner with config-driven modes and versioned output schema.
- Existing stage-specific outputs remain frozen short-term for Stage3_4 compatibility, then become compatibility/internal layers.

## 2026-05-08 JST - Decision: fresh modernization baselines after TLTM judgment
- User confirmed official modernization baselines should be regenerated after Stage3_4/TLTM judgment completes.
- Existing `output/tests` artifacts should be used only as historical/reference evidence, not as formal modernization baselines.

## 2026-05-08 JST - Decision: reverse gate is permanent algorithmic requirement
- User selected option 1: reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It is not merely a temporary guard or optional diagnostic mode.
- Modernization must preserve RG semantics, tolerance, Jacobian comparison, replay counter suppression, and live-slot identity on reject.

## 2026-05-08 JST - Tentative decision: ODEX-only flow backend
- User is considering removing Radau rescue and related rescue/final-resort paths, leaving only ODEX as the flow backend.
- Recorded as tentative long-term publishable direction: ODEX-only backend; Radau/JFNK/final-resort rescue stack is legacy robustness/deletion candidate.
- Constraint: no change before Stage3_4/TLTM judgment. After judgment, regenerate baselines and perform ODEX-only comparison before deletion.

## 2026-05-08 JST - Decision: OpenMP-capable reentrant target
- User selected strongest thread-safety target: long-term TLTM wrapper should support in-process parallel/OpenMP-capable execution.
- Modernization should progressively replace hidden module `save` state with explicit context/workspace objects for flow, solvers, RNG, counters, traces, and policy state.
- This is a long-term target after Stage3_4/TLTM judgment and fresh baselines, not an immediate source edit.

## 2026-05-08 JST - Scope correction: repo-wide modernization
- User clarified that the five core algorithm audits should not become the center of the roadmap because large parts of the code sit outside them, including utils and RNG.
- Roadmap corrected: core algorithm audits are safety gates; full modernization is repo-wide.
- Added cross-cutting infrastructure scope covering utils, RNG, config, I/O/output schema, build/test tooling, scripts/PBS, diagnostics/logging, memory/workspace ownership, and error handling.

## 2026-05-08 JST - Pre-Stage3_4 planning artifacts complete
- Added pre-Stage3_4 completion plan, cross-cutting infrastructure audit, code hygiene audit, legacy deletion candidates registry, and planning index.
- Corrected roadmap order: after Stage3_4/TLTM judgment, create a temporary characterization baseline, then canonicalize core numerical behavior, then freeze official canonical baseline, then proceed with repo-wide modernization.
- No Fortran source edits, production jobs, or production worktree mutations were performed.

## 2026-05-08 JST - M1 characterization baseline created
- Read completed Stage3_4 128seed/100k p28 RG report and aggregate/per-seed CSVs.
- Added `M1_TEMPORARY_CHARACTERIZATION_BASELINE.md`, `M2_CORE_CANONICALIZATION_QUEUE.md`, and `M1_CHARACTERIZATION_METRICS_20260508.tsv`.
- Characterization is explicitly temporary and not the official canonical baseline freeze.
- Main observed effect: `fb_norefine` sharply reduces unresolved failures versus `no_fb`, increases RG rejects modestly relative to candidates, and increases runtime.

## 2026-05-08 JST - M2a decision: fb_norefine canonical
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route is Newton -> QN S1 p28 DFO-LS standard residual -> RG -> Metropolis.
- Post-refine is a deletion candidate and should not remain in final canonical route unless explicitly re-promoted later.

## 2026-05-08 JST - M2a decision: ODEX-only canonical flow backend
- User confirmed ODEX-only as canonical long-term flow backend target.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and ODE final-resort acceptance are deletion candidates.
- Implementation still requires flow-level characterization and ODEX-only comparison coverage before removal/disablement.

## 2026-05-08 JST - M2a decision: non-p28 routes legacy first
- User clarified non-p28 quasi routes should first be marked legacy, not deleted immediately.
- Deletion waits until staged 10k -> 50k -> 100k checks show no major physical-observable issue for canonical p28 route.
- Applies to DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants.

## 2026-05-08 JST - M2 execution policy before ODEX-only
- User confirmed the next action order: finish everything except ODEX-only first, then change ODEX-only and validate through 10k -> 50k -> 100k.
- Clarified policy: non-ODEX cleanup before ODEX-only must not change current produced data or physical behavior; it is limited to canonical route documentation, legacy/quarantine labeling, dependency inventory, and test planning.
- Added `M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md` and `ODEX_ONLY_STAGED_VALIDATION_PLAN.md`.
- ODEX-only remains the first numerical canonicalization step expected to allow trajectory changes; validation will judge physical observables and diagnostics, not exact trajectory identity.

## 2026-05-08 JST - ODEX-only source policy implemented
- Implemented ODEX-only by disabling the Radau rescue entry and final-resort acceptance policy in `src/physics/solve_flow.f90`.
- Kept legacy Radau/JFNK code in place for quarantine/reference until staged 10k -> 50k -> 100k validation approves deletion.
- No production job was submitted.

## 2026-05-08 JST - Retained-core correctness audit gap identified
- User clarified that the audit must not only decide which legacy paths to disable; it must also check whether the retained five core numerical implementations are themselves correct.
- Added `M2_CORE_NUMERICAL_IMPLEMENTATION_AUDIT_PLAN.md` covering ODEX, simplified Newton, RATTLE, QN p28 projection loss, and HMC/Metropolis/RG boundary.
- ODEX-only validation jobs are blocked until this retained-core correctness audit accepts the active numerical cores for staged validation.

## 2026-05-08 JST - Retained-core audit completed for discussion
- User asked to audit the retained five numerical cores, not just disabled legacy paths.
- Completed source-level audit and documented blockers in `runbooks/M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`.
- No Fortran code changes or production jobs were performed in this audit step.
- 2026-05-08 JST: Clarified retained-core audit F1: `flowzr` is inverse flow via reversed RHS under nonnegative production flow time; signed `calculate_wk` is a latent negative-interval robustness issue, not proof of wrong current `flowzr`.
- 2026-05-08 JST: Checked GT-HMC simplified RATTLE equations; simplified Newton residual/update signs match Eqs. (3.37)-(3.44), pending deterministic replay and `del_z` normalization checks.
- 2026-05-08 JST: Completed reference-backed re-audit and added `M2_REFERENCE_BACKED_CORE_AUDIT.md`; source-first audit is superseded for signoff decisions.
- 2026-05-08 JST: User selected Hairer ODEX `IWORK(3)=3` (`2,4,6,8,12,16,24,32,...`) as canonical sequence; this was later patched and covered by ODEX self-consistency checks.
- 2026-05-08 JST: Confirmed p28 QN as BTN/backflow rescue; sign convention is `xi1=-b`, `xi2=-a` (`a=-xi2`, `b=-xi1`).
- 2026-05-08 JST: Decided future p28 BTN code should use paper variables `xi1=b`, `xi2=a`; residual correction and initial guess RHS must both flip sign together.

## 2026-05-09 JST - State propagation slice: local transition counters
- Implemented detailed Stage1/Stage2 local transition counters using the Metropolis transition status surface.
- Added lightweight `markovchain_transition_status` module so status constants are shared by Metropolis and TLTM types without a types-to-implementation dependency.
- Preserved legacy `projection_failure_count` as the compatibility total for `proposal_failed`; new counters split ordinary Metropolis reject, reverse-gate reject, proposal construction failure, invalid Hamiltonian, invalid `Delta H`, and output-size mismatch.
- Stage1/Stage2 summary schemas append new columns after legacy columns; Stage2 writes `# local_transition_totals ...`.
- Multiseed run and merge scripts now carry the new local transition counters through per-seed and aggregate CSV output.
- Verification: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, and tiny local Stage2 smoke/parser readback all passed.

## 2026-05-09 JST - State propagation slice: ODE/flow status surface
- Added optional integer status outputs to `intode`, `flowz`, `flowzr`, and `flow`, while preserving all existing logical error callers.
- Status values distinguish strict ODEX success, zero-time no-op, legacy stiff-rescue success, solver-internal assist success, max-step failure, invalid-state failure, and h-min failure.
- Promoted `tests/test_odex_solver.f90` into `make test_odex_solver` and extended it to assert status values.
- Verification: `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, and tiny local Stage2 smoke all passed.

## 2026-05-09 JST - State propagation slice: strict final proposal flow gate
- RATTLE final proposal `flow(...)` now consumes the optional ODE/flow status.
- Strict final proposal flow accepts only strict ODEX success and zero-time no-op; max-step, invalid-state, h-min, and unexpected non-strict success statuses become explicit final-flow step failures.
- HMC proposal-level compatibility is preserved by mapping the detailed final-flow step statuses back to the existing final-flow failure category.
- Verification: `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, and tiny local Stage2 smoke all passed.

## 2026-05-09 JST - State propagation slice: QN residual flow-status counters
- QN residual evaluators now request optional status from `flowzr(...)` / `flowz(...)` and record residual-evaluation flow outcomes separately from final proposal flow.
- Added counters for strict success, zero-time success, stiff rescue, solver assist, max-step failure, invalid-state failure, h-min failure, and unknown status.
- Stage1/Stage2 summaries write `# qn_eval_flow_status ...`; multiseed run and merge scripts propagate new per-seed and aggregate CSV columns.
- Behavior-preservation note: no solver decision changed. `ierr` remains the validity signal, and invalid residual evaluations still return neutral `fq=0`, `Jl=0`, `ierr=.true.`.
- Verification: `py_compile`, `git diff --check`, `test_odex_solver`, `test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke, and parser readback all passed.

## 2026-05-09 JST - State propagation slice: strict initialization flow gate
- Added `intode_status_is_strict_success(...)` in `solve_flow.f90` and reused it in HMC final proposal flow.
- Stage1 replica initialization and Stage2 slot initialization now request optional `flow(...)` status and accept only strict ODEX success or zero-time no-op.
- Behavior-preservation note: canonical strict/zero-time init paths are unchanged; non-strict solver-assist or legacy rescue success is fail-closed for live-chain initialization.
- Verification: `git diff --check`, `test_odex_solver`, Stage1/Stage2 executable build, `test1`, and tiny local Stage2 smoke passed.

## 2026-05-09 JST - State propagation slice: strict physical flow call sites
- Generic Markov-chain initial flow, warmup reflow, adaptive preflow trial flow, and Stage2 swap reflow now request optional `flow(...)` status and require strict success.
- Behavior-preservation note: strict ODEX/zero-time physical state construction is unchanged; solver assist remains only a residual-evaluation tool.
- Simplified Newton residual `flowz(...)` call sites were intentionally left for a separate residual-status slice.
- Verification: `git diff --check`, Stage1/Stage2 executable build, `test1`, and tiny local Stage2 smoke with swap enabled passed.

## 2026-05-09 JST - State propagation slice: Newton residual flow-status counters
- Simplified Newton residual `flowz(...)` calls now request optional ODE/flow status and record diagnostic counters.
- Stage1/Stage2 summaries write `# newton_eval_flow_status ...`; multiseed run and merge scripts propagate the new columns.
- Behavior-preservation note: Newton convergence/failure behavior is unchanged; `solve_failed` remains the behavior-bearing signal.
- Verification: `py_compile`, `git diff --check`, `test_odex_solver`, `test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke, and parser readback passed. The smoke observed `newton_eval_flow_zero_time_count=80`.

## 2026-05-09 JST - State propagation slice: reverse-gate replay status counters
- Reverse-gate replay now requests `step_status` from the nested `rattle_step_core(...)` replay and records diagnostic counters.
- Stage1/Stage2 summaries write `# reverse_gate_replay_status ...`; multiseed run and merge scripts propagate the new columns.
- Behavior-preservation note: replay construction, RG tolerance comparison, pass/reject outcome, and suppression semantics are unchanged.
- Verification: `py_compile`, `git diff --check`, `test_odex_solver`, `test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke/parser readback, and RG-enabled tiny smoke passed. The RG-enabled smoke observed `reverse_gate_replay_success=80`.

## 2026-05-09 JST - Source hygiene cleanup
- Removed tracked backup artifact `src/sampler/hmc_integrator_core.f90.bak_codex_20260429`.
- Behavior-preservation note: the backup file was not compiled and only polluted source audit/search results.
- Verification: source artifact scan no longer reports backup files under `src`.

## 2026-05-09 JST - Test strict-flow contract cleanup
- Updated `tests/test_hamiltonian_conservation.f90` so its initial `flow(...)` requests optional status and requires strict success.
- Behavior-preservation note: this only aligns the test guard with the production strict-flow contract.
- Verification: `git diff --check` and `test1` passed.

## 2026-05-09 JST - Legacy diagnostic and post-refine deletion
- Removed tracked root-level source artifacts `hmc_integrator_core.f90` and `constraint_solver_stats.f90`.
- Removed standalone diagnostic app sources and make targets for `sample_flow_manifold`, `replay_quasi_failures`, `probe_hmc_volume`, `scan_flow_vs_flowz`, and `scan_flowzr_stability`.
- Removed helper scripts tied to those deleted diagnostic binaries and removed the active replay command documentation.
- Deleted the active post-refine HMC/QN path, including `QN_POST_NEWTON_REFINE_*` controls, post-refine solver attempts/captures, and post-refine Stage2/multiseed summary columns.
- Kept `fb_norefine` in the Stage3 runner as a compatibility alias for the now-canonical fallback-enabled/no-post-refine route.
- Verification passed: `py_compile`, `git diff --check`, production executable build, `test_odex_solver`, `test1`, and tiny Stage2 smoke with explicit `TLTM_STAGE2_INIT_SIGMA=0.1`.
- Follow-up decision: an existing Stage2 config aliasing hazard makes the default `TLTM_STAGE2_INIT_SIGMA` appear as `0.0000` in the local smoke when unset. Fixing it likely changes default initialization behavior and should be separated from the deletion patch.

## 2026-05-09 JST - Stage env-parser default repair
- Repaired Stage1/Stage2 environment parsing by changing integer/real/logical parser helpers to `intent(inout)` value arguments.
- Defaults now stay in the caller; parser helpers only overwrite on valid environment values and otherwise leave the configured default untouched.
- Removed the nonconforming same-variable default/output pattern that made unset `TLTM_STAGE2_INIT_SIGMA` appear as `0.0000`.
- Verification: `git diff --check`, stale parser-call scan, Stage1/Stage2 executable build, `test_odex_solver`, Stage1 smoke without explicit init sigma, Stage2 smoke without explicit init sigma, and Stage2 explicit-override smoke all passed.

## 2026-05-09 JST - QN legacy route source cleanup
- Removed active-source implementations for DFO-GN, DFO-GN paper, Broyden/line-search, strict continuation, global continuation/restart/sweep, and post-refine Newton-loss residual paths.
- Removed `src/sampler/quasi_newton_line_search.f90` and `src/sampler/quasi_newton_jacobian_update.f90` from the build.
- Removed active `QN_QUASI_GLOBAL_FALLBACK_ENABLED` control; retained summary schema compatibility for global-filter columns.
- Preserved canonical p28 DFO-LS standard residual route and bounded local priority pass.
- Verification passed: `py_compile`, deleted-symbol census, `git diff --check`, forced Stage1/Stage2 executable rebuild, `test_odex_solver`, `test1`, tiny Stage1 smoke, and tiny Stage2 smoke with the removed global-fallback env set.

## 2026-05-09 JST - Radau/JFNK flow-rescue source cleanup
- Deleted inactive Radau/JFNK rescue implementation from `src/physics/solve_flow.f90`.
- Kept `intode_stiff_rescue(...)` as an explicit disabled compatibility stub.
- Kept solver-internal residual assist and schema-compatible rescue stats; Radau fields now return zero.
- Verification passed: Stage1/Stage2 executable build, `test_odex_solver`, and `test1`.

## 2026-05-09 JST - Root stale-source and strict-mode API cleanup
- Deleted tracked root-level stale Fortran artifacts `quasi_newton_solver.f90`, `tltm_stage2_driver.f90`, and `replay_quasi_failures.f90`.
- Deleted stale backup config `data/parameters.stage3_2.bak` and refreshed persistent knowledge maps to current active architecture.
- Removed the no-op `set_intode_strict_mode(...)` API and call sites; final-flow strictness is now represented only by explicit status gates.
- Verification passed: active-source symbol census, `git diff --check`, production executable rebuild including `generate_markov_chain`, `test_odex_solver`, `test1`, tiny Stage1 smoke, and tiny Stage2 smoke.

## 2026-05-09 JST - Solver-assist internal naming cleanup
- Renamed the ODE h-min residual-assist implementation from internal `final_resort` names to `solver_assist` names while keeping output/schema compatibility aliases.
- Updated `generate_markov_chain` diagnostics to describe solver assist explicitly.
- Verification passed: `git diff --check`, production executable rebuild including `generate_markov_chain`, `test_odex_solver`, `test1`, tiny Stage1 smoke, tiny Stage2 smoke, and Stage2 summary readback.

## 2026-05-09 JST - RATTLE progress-guard downgrade
- Removed the active no-progress proposal-failure checks from `hmc.f90`; the reserved `hmc_proposal_status_no_progress` value is no longer emitted by active proposal paths.
- Added opt-in `HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT` reporting for zero/near-zero displacement across physical coordinates `x(2:)`.
- Proposal validity now relies on solver convergence, constraint residual handling, strict final flow, reverse gate, finite Hamiltonians, and Metropolis/status gates.
- Verification passed with `git diff --check`, production Stage1/Stage2 build, `test_odex_solver`, `test1`, tiny Stage1 smoke, tiny Stage2 smoke, and summary status readback.

## 2026-05-09 JST - QN solver-assist watchdog naming cleanup
- Renamed internal QN watchdog variables/functions from final-resort terminology to solver-assist terminology.
- Added preferred `QN_SOLVER_ASSIST_BUDGET` env parsing while retaining `QUASI_FINAL_RESORT_BUDGET` as a legacy fallback alias.
- Preserved compatibility output/schema names for `final_resort_budget_*`.
- Verification passed with `git diff --check`, Stage1/Stage2 executable build, `test_odex_solver`, and `test1`.

## 2026-05-09 JST - Config compatibility cleanup
- User confirmed deletion of legacy positional `parameters.dat` parsing and the unused `initial_x.dat` compatibility path.
- `param_mod` now reads only key-value `parameters.dat` and reports a fatal error for positional input.
- Removed unused initial-state file helpers from active source and updated docs to make sampler/driver randomized initialization the only runtime path.
- This is an intentional input-compatibility break; current production configs are key-value and should be unaffected.

## 2026-05-10 JST - Runtime env parser centralization
- Added `src/config/runtime_env_mod.f90` for shared Stage1/Stage2 int/real/logical/list env parser helpers.
- Removed duplicated parser helpers from `tltm_stage1_driver.f90` and `tltm_stage2_driver.f90`; Stage2 init-mode lowercase handling now imports the shared helper.
- Behavior-preservation note: env names, caller defaults, invalid-env default preservation, output schemas, RNG draw order, and physics code are unchanged.
- Verification passed with `git diff --check`, Stage1/Stage2 executable build, `test_odex_solver`, `test1`, tiny Stage1/Stage2 smokes, flow-time ladder list-parser smokes, and invalid logical default-preservation smoke.

## 2026-05-10 JST - Env-token lowercase helper cleanup
- Removed duplicated local ASCII-lower helpers from `markovchain_mod.f90` and `hmc_reversibility_checks.f90`.
- Both paths now import `runtime_env_mod:to_lower_ascii` for env-token normalization; boolean/default semantics are unchanged.
- Verification passed with `git diff --check`, build of `generate_markov_chain`, `run_tltm_stage2`, `test1`, and a tiny Stage2 reversibility-probe env smoke showing `fallback_only=F` for `HMC_REVERSIBILITY_PROBE_FALLBACK_ONLY=OFF`.

## 2026-05-10 JST - Runtime int env parser reuse
- Replaced local integer env reads for `HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT`, `HMC_REVERSIBILITY_PROBE_LIMIT`, `CONSTRAINT_FAIL_CAPTURE_LIMIT`, and `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE` with `runtime_env_mod:parse_int_env`.
- Behavior-preservation note: negative HMC limits are still clamped to zero; constraint capture limit still allows `0`/negative as unlimited; invalid env values still preserve defaults.
- Verification passed with `git diff --check`, Stage1/Stage2 executable build, `test1`, tiny Stage2 reversibility-probe smoke, and `CONSTRAINT_FAIL_CAPTURE_LIMIT=0 HMC_SKIP_PLOT=1 bin/test_program` showing `constraint fail capture limit=unlimited`.

## 2026-05-10 JST - Param module import-boundary cleanup
- Replaced all bare `use param_mod` statements in active source/tests with explicit `only:` import lists.
- Behavior-preservation note: this only narrows compile-time module visibility; no runtime logic, output schema, config semantics, or physics code paths changed.
- Verification passed with `git diff --check`, builds for `generate_markov_chain`, `evaluate_expectations`, Stage1/Stage2, `test_program`, `test_odex_solver`, `test2`, direct `HMC_SKIP_PLOT=1 bin/test_program`, and tiny Stage1/Stage2 smokes.

## 2026-05-10 JST - Utils module import-boundary cleanup
- Replaced all bare `use utils` statements in active source/tests with explicit `only:` import lists.
- Replaced the remaining non-generated broad module import in `markovchain_metropolis.f90`.
- Behavior-preservation note: this only narrows compile-time helper visibility; numerical helper implementations and call sites are otherwise unchanged.
- Verification passed with `git diff --check`, a clean rebuild for production/test binaries, `test_odex_solver`, `test1`, `test2`, and a follow-up Stage1/Stage2 plus ODEX/test2 build.

## 2026-05-10 JST - Generated model import/header cleanup
- Updated `scripts/generate_model_generated.py` so the tape backend emits an explicit `model_tape_ad` `only:` import list.
- Generated headers now record repo-relative source paths, avoiding local absolute-path churn across worktrees.
- Regenerated `src/physics/model_generated.f90`.
- Verification passed with `py_compile`, deterministic regeneration, `git diff --check`, `evaluate_expectations` build, `test2`, and `test_odex_solver`.

## 2026-05-10 JST - M3 architecture contract
- Added `runbooks/M3_ARCHITECTURE_CONTRACT.md` as the next-phase planning gate after behavior-neutral infrastructure cleanup.
- Contract freezes v0 output compatibility until schema versioning exists and defines v1 schema, typed config, explicit context/workspace, regression-gate, and stop-gate rules.
- No Fortran source, output writer, production workflow, or job submission changes were made in this planning-only slice.

## 2026-05-10 JST - M3 tempering protocol and schema design
- Added `runbooks/M3_TEMPERING_PROTOCOL_AND_OUTPUT_SCHEMA_DESIGN.md`.
- Design explicitly combines TLTM flowed-surface rules with standard replica-exchange requirements before defining v1 output schema.
- Recorded the then-current Stage2 timing convention: local updates and histories were sampled before swap, while label trace was written after swap. This was later superseded by the replica-exchange timing decision below.
- No Fortran source, output writer, production workflow, or job submission changes were made in this planning-only slice.

## 2026-05-10 JST - M3 v0 output inventory and protocol-audit plan
- Added `runbooks/M3_V0_OUTPUT_INVENTORY_AND_PROTOCOL_AUDIT_PLAN.md`.
- Inventoried Stage1, Stage2, Stage3 per-seed, and Stage3 aggregate v0 output surfaces, including compatibility aliases that should not be renamed in place.
- Defined the next safe executable step as a parser-only TLTM protocol audit before any v1 writer or wrapper-output change.
- No Fortran source, output writer, production workflow, or job submission changes were made in this planning-only slice.

## 2026-05-10 JST - M3 parser-only audit and swap-kernel contract test
- Added `scripts/audit_tltm_tempering_protocol.py`, a parser-only audit CLI for Stage2 summary, label trace, and optional Stage3 per-seed cross-checks.
- Added `tests/test_tltm_swap_kernel_contract.f90` and a build target to verify the TLTM adjacent-swap acceptance probability and invalid-current-energy rejection behavior.
- Verification passed: Python compile, parser audit on eight existing Stage2/label-trace fixtures, parser audit with a synthetic Stage3 per-seed cross-check fixture, and `make -C build FC=gfortran LDFLAGS= test_tltm_swap_kernel_contract`.
- Follow-up note: v1 manifest/protocol writer work proceeded as an opt-in sidecar after user clarified that only true no-clear-best-choice design nodes should pause the workflow.

## 2026-05-10 JST - Stage2 v1alpha sidecar package
- Added opt-in Stage2 v1alpha sidecars in `src/sampler/tltm_stage2_driver.f90`.
- `TLTM_STAGE2_V1_OUTPUT_DIR` writes `manifest.json`, `protocol.json`, `diagnostics/local_transition_summary.csv`, `diagnostics/swap_summary.csv`, `diagnostics/label_summary.csv`, and `observables/per_slot_phase_summary.csv`.
- Individual `TLTM_STAGE2_V1_MANIFEST_FILE` and `TLTM_STAGE2_V1_PROTOCOL_FILE` paths are also supported.
- Default Stage2 output behavior is unchanged when v1 sidecar env vars are absent.
- Extended `scripts/audit_tltm_tempering_protocol.py` to cross-check optional v1 sidecars and diagnostics row counts.
- Follow-up decision recorded below: the selected convention is standard replica-exchange-style `local update -> swap -> measure/history/label trace`.

## 2026-05-10 JST - Replica-exchange timing decision
- User decided not to preserve existing dataset timing compatibility.
- Selected protocol convention: local updates, then adjacent swap sweep, then measurement/history/label trace at the post-swap boundary.
- Existing datasets should be regenerated after this change.
- `swap -> local -> measure` remains a valid paper-aligned alternative, but it is not the selected convention for this codebase.

## 2026-05-10 JST - M3 to M6 before dataset regeneration
- User decided to continue modernization through M6 before regenerating official datasets.
- Added `runbooks/M3_TO_M6_BEFORE_DATASET_PLAN.md`.
- Updated status/planning/progress docs so dataset regeneration is gated by M3 protocol/schema completion, M4 guardrails, M5 repo-wide refactor decisions, and M6 product-readiness/provenance docs.
- Next executable modernization slice is M3 completion: Stage3 sidecar propagation and sidecar-aware protocol audit/readback, not production dataset generation.

## 2026-05-10 JST - Stop-for-decision rule and M3 propagation slice
- Recorded that routine behavior-preserving modernization should proceed without approval stops.
- Stop only for unresolved choices that affect physics semantics, data interpretation, RNG/seed streams, public schema meaning/removal/renaming, wrapper/product interface, production workflow deletion, or dataset regeneration/provenance cost.
- Completed Stage3 propagation for Stage2 v1alpha sidecars and sidecar-aware protocol audit/readback.
- `scripts/run_stage3_3_multiseed.py` now supports opt-in `--stage2-v1-sidecars on`, parser-only protocol audit control, per-seed sidecar/audit metadata columns, and Stage3 row cross-check audit summaries.
- `scripts/merge_stage3_multiseed_chunks.py` preserves sidecar/audit metadata columns and merges chunk-level protocol audit summaries when present.
- Verification: Python compile, dry-run with sidecars enabled, existing Stage2 audit smoke, tiny sidecar-on Stage3 smoke, tiny sidecar-off Stage3 smoke, and one-chunk merge smoke.

## 2026-05-10 JST - M4 guardrail entry point
- Added `scripts/run_m4_guardrails.py`.
- Added `make -C build modernization_guardrails`.
- The guardrail runner collects Python compile, `git diff --check`, optional Fortran build plus ODEX/swap tests, Stage3 sidecar dry-run, Stage2 protocol audit smoke, tiny sidecar-on/off Stage3 smokes, and chunk merge preservation checks.
- This is a local development guardrail only; it does not submit production jobs or define official datasets.
- Verification passed by running `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ""`.
- Verification also passed through `make -C build FC=gfortran M4_GUARDRAIL_LDFLAGS= modernization_guardrails`.

## 2026-05-10 JST - M5 state/config ownership inventory
- Added `scripts/inventory_fortran_state.py`.
- Generated `state/M5_STATE_CONFIG_OWNERSHIP_INVENTORY.tsv` and `runbooks/M5_STATE_CONFIG_OWNERSHIP_INVENTORY_SUMMARY.md`.
- Added `runbooks/M5_STATE_CONFIG_OWNERSHIP_PLAN.md`.
- Inventory result: 384 rows including 275 `save` declarations, 52 runtime env reads, 43 RNG calls, and 14 `param_mod` import sites.
- First true M5 decision point: choose the first source-refactor lane. Recommendation is config/env/provenance ownership first; defer RNG and model/tape cache migration.

## 2026-05-10 JST - Lane A string env consolidation
- User selected Lane A: config/env/provenance ownership first.
- Added `runtime_env_mod:read_string_env`.
- Replaced Stage1/Stage2 direct string env reads for flow ladders, summary/history paths, init mode, sidecar paths, git commit provenance, and v1 env manifest fields.
- Preserved env names/defaults, empty-env behavior, too-long env rejection behavior, v0 output schema, RNG order, and numerical code paths.
- M4 guardrails passed.
- Regenerated M5 ownership inventory: total rows dropped from 384 to 368 and env-read rows dropped from 52 to 36.

## 2026-05-10 JST - Lane A evaluation env consolidation
- Replaced `evaluate_expectations` direct env reads for multichain mode and diagnostic/evaluation thresholds with `runtime_env_mod:read_string_env`.
- Preserved existing env names, empty-env behavior, too-long env rejection behavior, invalid-value warnings, defaults, min-bound checks, sample-count clamps, and statistical formulas.
- Verification passed through `make -C build modernization_guardrails`.
- Regenerated M5 ownership inventory: total rows dropped from 368 to 356 and env-read rows dropped from 36 to 24.

## 2026-05-10 JST - Lane A core-policy env consolidation
- Replaced remaining production/source direct env reads in HMC/QN policy loaders, Markov-chain random-start controls, perf profiling, reversibility probe config, and `generate_markov_chain` seed selection with `runtime_env_mod:read_string_env`.
- Preserved policy defaults, primary-vs-legacy alias precedence, invalid-value handling, false-token semantics, seed fallback, and `sgrnd` timing.
- Verification passed through `make -C build modernization_guardrails`.
- Regenerated M5 ownership inventory: total rows dropped from 356 to 337 and env-read rows dropped from 24 to 5; production/source direct env reads now live only in `runtime_env_mod`.

## 2026-05-10 JST - Lane A final direct-env cleanup
- Replaced the test-local `HMC_SKIP_PLOT` direct env read with `runtime_env_mod:read_string_env`.
- Verification passed through `make -C build modernization_guardrails`.
- Regenerated M5 ownership inventory: total rows dropped from 337 to 336 and env-read rows dropped from 5 to 4.
- Direct `get_environment_variable` calls are now centralized in `runtime_env_mod`.

## 2026-05-10 JST - Lane A direct-env guardrail
- Added an M4 source guardrail that scans `src/` and `tests/` and fails if any file outside `src/config/runtime_env_mod.f90` directly calls `get_environment_variable`.
- Verification passed through `make -C build modernization_guardrails`; the run now reports `direct env reads centralized`.

## 2026-05-10 JST - M5 pre-M6 gate assessment
- Added `runbooks/M5_PRE_M6_GATE_ASSESSMENT.md`.
- Gate result: proceed to M6 product-readiness work, not dataset regeneration.
- Explicitly deferred RNG ownership, large module `save` workspace migration, model/tape cache ownership, public schema deletion/renaming, and full `param_mod` global replacement until stronger baselines or explicit wrapper/schema decisions exist.

## 2026-05-10 JST - M6 product-readiness package start
- Added `runbooks/M6_PRE_DATASET_PRODUCT_READINESS_PLAN.md`.
- Added `runbooks/M6_DATASET_REGENERATION_CHECKLIST.md`.
- Added `runbooks/M6_PROVENANCE_READBACK_CHECKLIST.md`.
- M6 now has a wrapper/provenance/output/readiness contract and an explicit preflight ladder for future 10k -> 50k -> 100k dataset regeneration.
- No production jobs were submitted; dataset regeneration remains paused until explicit user instruction.
- Updated repo entry docs (`docs/readme.md`, `codex/README.md`) and the outer `/Users/ccy/Documents/New project/README.md` to point new sessions at the M6 gate and paused-regeneration status.
- Updated `FORTRAN_MODERNIZATION_MASTER_PLAN.md` and `M3_TO_M6_BEFORE_DATASET_PLAN.md` so the current position is M6 review before dataset regeneration.

## 2026-05-11 JST - External official DFO-LS comparison bridge
- User decided to externalize the DFO-LS solver layer rather than treating the in-house `run_dfo_ls_attempt` as the final package-level implementation.
- Added `src/apps/evaluate_btn_residual_case.f90`, an offline bridge that reads `constraint_solver_fail_{z0,delz,x0}.dat`, recomputes the base flow/Jacobian from captured `x0`, constructs the current BTN seed, and evaluates the retained BTN residual.
- Added `scripts/run_external_dfols_btn_compare.py`, which calls official `DFO-LS==1.6.5` through an `objfun(xi) -> residual_vector` callback and writes per-case CSV comparison rows.
- Added `requirements/external-dfols.txt` and `runbooks/EXTERNAL_DFOLS_BACKEND_COMPARISON.md`.
- Hard boundary recorded: the base flow Jacobian is not the BTN loss/residual Jacobian. External DFO-LS receives no TLTM Jacobian; it builds derivative-free models internally.
- Double precision check passed in an isolated venv: DFO-LS objective inputs, `soln.x`, `soln.resid`, and `soln.jacobian` are all `np.float64`.
- Makefile link flags now omit Linux `noexecstack` on macOS/Darwin while preserving it elsewhere, allowing the bridge to build locally without `LDFLAGS=` overrides.
- Verification: `python3 -m py_compile scripts/run_external_dfols_btn_compare.py`; `make -C build evaluate_btn_residual_case`; synthetic stream-capture smoke for bridge seed/residual; one-case official DFO-LS smoke wrote CSV with `float64_contract=1`.
- Corrected reference-package readback check: materialized M6 summary/reference packages are in remote worktree `/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/reference/fortran_modernization/m6` at source commit `a1028ad`.
- That M6 root contains R1-R4 `no_fb` and `fb_norefine` summary/per-seed tables, but no `constraint_solver_fail_*` capture files. Aggregate behavior comparison can use the existing package tables; official DFO-LS residual replay still requires a separate M6-aligned capture bundle.
- User corrected the comparison design: failure-only replay has limited value and should not be treated as meaningful solver-replacement evidence.
- Historical failure-capture smoke only: first 3 failures from `/Users/ccy/Documents/local_repo/build/rehydrate_eval/s20l2_t035_2M_p02_withfb/chain_003/output` preserve double precision, but this is only residual-oracle/hard-tail evidence. With `maxfun=28`, external final residuals stayed around `2.4e-2` to `3.9e-2`, while historical in-house trace best residuals were around `4e-9` to `1e-7`.
- Correct replacement-comparison design now requires representative QN-attempt capture before the solver outcome is known, including successful and failed attempts across initial residual scales, then attempt-level comparison before any chain-level M6 behavior comparison.

## 2026-05-11 JST - Representative QN-attempt DFO-LS probe
- Added opt-in `QN_ATTEMPT_CAPTURE_DIR` instrumentation to `quasi_newton_solver.f90`. When unset, production solver behavior remains unchanged; when set, it writes `qn_attempt_{z0,delz,x0,xi0}.dat` plus `qn_attempt_meta.csv` for representative solver-entry attempts before the outcome is known.
- Updated `evaluate_btn_residual_case` and `run_external_dfols_btn_compare.py` to support capture prefixes; representative bundles use `--capture-prefix qn_attempt --seed-source capture`.
- Added external DFO-LS controls for `npt`, `model.abs_tol`, `model.rel_tol`, and an independent TLTM-side `residual_success` gate.
- Local probe generated 20 representative attempts from a 1-seed, 500-cycle `fb_norefine` Stage3-style smoke at `t=0.35`, `L=2`, `nstep=20`; in-house metadata had 17/20 converged and 3/20 non-converged attempts.
- External `DFO-LS==1.6.5` preserved `float64_contract=1` on all tested settings.
- Important finding: package default `model.abs_tol=1e-12` is an objective tolerance and stops too early for TLTM residual targets. With `maxfun=28`, no tested attempt reached residual `<=1e-10`.
- Better but still non-drop-in setting: `maxfun=112`, `model.abs_tol=1e-26`, `rhobeg=0.25` gave 17/20 attempts with final residual `<=1e-6` and 13/20 `<=1e-12`; several package `flag=0` cases still failed the TLTM residual gate.
- Decision implication: official DFO-LS remains an offline backend candidate only. Production replacement requires a residual-gated wrapper, broader representative comparison, and explicit integration design.

## 2026-05-11 JST - Tuned official DFO-LS candidate
- User correctly rejected adding external escape/backtracking/best-rescue wrapper logic around official DFO-LS. Tuning scope was restricted to official package options plus a thin TLTM residual callback/dtype/failure/gate boundary.
- Added `run_external_dfols_btn_compare.py` options `--objfun-has-noise` and repeatable `--dfols-param KEY=VALUE` so official package internals can be tuned reproducibly.
- Found a viable candidate setting for the retained BTN residual: `maxfun=250`, `objfun_has_noise=True`, `model.abs_tol=1e-30`, `model.rel_tol=0`, `rhobeg=0.05`, `rhoend=1e-16`, and TLTM residual gate `<=1e-13`.
- On the first 20-attempt probe, the same candidate family passed 20/20 at `maxfun=150`; `maxfun=250` made package flags clean as well, with max residual about `1e-15`.
- Generated a larger 69-attempt representative probe from a 1-seed, 500-cycle `fb_norefine` Stage3-style smoke. Current in-house metadata: 61/69 attempts converged, 8/69 nonconverged.
- Candidate official DFO-LS result on 69 attempts: 69/69 double precision, 66/69 residual `<=1e-13`, and 61/61 success on the in-house-converged subset with max residual `1.59e-15`.
- The three official failures are attempts 33, 64, and 68; all three were already in-house nonconverged. Official-only tuning with larger budget can solve 33 and 64, but tested settings up to `maxfun=1000` did not solve 68.
- Conclusion: official DFO-LS is usable as an attempt-level backend candidate if configured, but package defaults are not acceptable. Production integration should preserve TLTM residual-gated acceptance and existing outer QN/HMC failure control flow.

## 2026-05-11 JST - Official DFO-LS replacement decision gate
- Added in-house QN attempt diagnostics to opt-in `QN_ATTEMPT_CAPTURE_DIR` metadata: `residual_eval_count` and `cpu_seconds`.
- Rebuilt the bridge and regenerated `output/tests/external_dfols_replacement_gate`, producing 69 representative QN attempts with in-house cost metadata.
- Cost proxy on in-house-converged attempts: in-house residual calls median/mean/p90/max = `46/50.6/72/92`; official candidate `nf` median/mean/p90/max = `40/65.4/127/250`.
- Interpretation: official DFO-LS is not worse in the typical successful case by residual-call proxy, but has a heavier successful-attempt tail.
- Product/runtime check at that moment: installed `DFO-LS==1.6.5` is Python source plus NumPy/Pandas/SciPy dependencies and reports license `GPL-3.0-or-later`; TLTM carried an MIT license file under `docs/LICENSE`.
- Decision gate recorded in `EXTERNAL_DFOLS_BACKEND_COMPARISON.md`: algorithmic backend candidate passes, direct Python subprocess production replacement is rejected, and full production replacement was held pending runtime architecture plus GPL-compatible distribution decision.

## 2026-05-11 JST - License policy and Tapenade AD toolchain
- User decided preserving MIT is not required for TLTM; TLTM is user-written and unpublished.
- Added repository-root `LICENSE` with GPL v3 text, plus `LICENSE_POLICY.md` with the project-level GPL-3.0-or-later grant; removed the old MIT-only `docs/LICENSE` file to avoid ambiguous repository license state.
- Added repository-root `THIRD_PARTY_NOTICES.md`.
- Recorded official DFO-LS `DFO-LS==1.6.5` as GPL-3.0-or-later and the planned production solver backend after behavior gates pass.
- Checked Tapenade AD as part of the toolchain: local usage is external CLI/source-transformation codegen through `GEN_BACKEND=st_tapenade`; official Tapenade distribution license checked on 2026-05-11 is MIT License, Copyright INRIA.
- Tapenade does not drive the GPL decision, but releases must record Tapenade version/generation command and inspect generated Fortran for retained notices, helper routines, or runtime dependencies.

## 2026-05-11 JST - Official DFO-LS backend gate PBS scaffold
- Added `codex/workspaces/fortran_modernization/tasks/config/official_dfols_backend_gate_1seed_500cycle_t035.json`.
- Added `codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_backend_gate_20260511.pbs`.
- Gate shape: build Stage2/eval/BTN residual bridge, run a 1-seed 500-cycle `fb_norefine` t=0.35 Stage3-style smoke with `QN_ATTEMPT_CAPTURE_DIR`, then replay captured attempts through official `DFO-LS==1.6.5` tuned preset.
- Gate failure criteria: no captured QN attempts, missing official replay rows, float64 contract failure, or any in-house-converged captured attempt failing the official TLTM residual gate.
- This is an offline backend replacement validation gate. It does not change the production HMC/QN path.
- Added `.venv-dfols/` to `.gitignore` so the official DFO-LS Python environment can exist in local/remote worktrees without tripping clean-tree guards.
- First submitted job `14726.anode01` failed before official replay because the PBS scaffold passed `QN_ATTEMPT_CAPTURE_DIR` as a relative path while Stage2 executed from `build/`; fixed the PBS scaffold to use absolute output/log/capture paths.

## 2026-05-11 JST - Official DFO-LS backend gate readback and preset revision
- Fixed-path gate job `14727.anode01` completed capture and replay for `official_dfols_backend_gate_20260511_3082dcc`.
- Gate capture contained 77 representative QN attempts; official replay produced 77 rows and preserved the float64 contract on all rows.
- Old preset `rhobeg=0.05`, `npt=default`, `maxfun=250` failed the replacement safety criterion: 75/77 residual successes, but one in-house-converged attempt (`sample_idx=6`) regressed to official residual `5.36e-4`.
- Official-only tuning showed larger `rhobeg` values fix sample 6 but regress other in-house-converged attempts. The stable revised preset is `npt=4`, `rhobeg=0.018`, `objfun_has_noise=True`, `rhoend=1e-16`, `model.abs_tol=1e-30`, `model.rel_tol=0`, `maxfun=250`.
- Revised preset result on the same 77-attempt gate capture: 71/77 residual successes, 63/63 in-house-converged attempts preserved, 0/77 float64 failures; residual-fail samples were 23, 28, 35, 46, 47, and 54, all in-house-nonconverged.
- Updated the PBS gate scaffold to use the revised `npt=4`, `rhobeg=0.018` official DFO-LS preset for future reruns.
- Updated-scaffold gate rerun `14728.anode01` (`official_dfols_backend_gate_20260511_1543cb4`) completed with PBS `Exit_status=0`; summary matched the revised preset readback: 77 attempts replayed, 63/63 in-house-converged attempts preserved, and 0 float64 failures.

## 2026-05-11 JST - Embedded official DFO-LS backend replacement
- Added `src/external/official_dfols_c_bridge.c`, an in-process Python C-API bridge to official `dfols.solve`. The C bridge exposes only official package controls and delegates the residual callback to TLTM Fortran.
- Replaced the default QN backend path in `solve_constraint_quasi_newton` with official DFO-LS. `QN_SOLVER_BACKEND=internal` remains available only for controlled legacy comparison.
- Added official-alone preset controls and `stable_gate77` as the production default: `npt=4`, `rhobeg=0.018`, `rhoend=1e-16`, `maxfun=250`, `objfun_has_noise=true`, `model.abs_tol=1e-30`, `model.rel_tol=0`.
- Added `build/makefile` support for `ENABLE_OFFICIAL_DFOLS=1`, Python embed compile/link flags, and the C bridge object. Official backend build is now the default.
- Updated Stage3 multiseed build/manifest handling so production preflight builds pass `ENABLE_OFFICIAL_DFOLS=1` and per-seed manifests record `TLTM_OFFICIAL_DFOLS_PYTHONPATH`.
- Added `runbooks/OFFICIAL_DFOLS_PRESET_TUNING_POLICY.md`.
- Local verification: built `../bin/run_tltm_stage2` and `../bin/evaluate_btn_residual_case`; installed `DFO-LS==1.6.5` into `.venv-dfols`; ran a 1-seed, 500-cycle `fb_norefine` Stage3-style smoke with `QN_SOLVER_BACKEND=official_dfols`.
- Live-smoke readback: `quasi_stage_stats probe_attempt=50 probe_success=45`, `constraint_stats quasi=45 failed=5`, `qn_eval_flow_status success=7063`, and captured 10 official-backend QN attempts with best residuals around `1e-15`. No official bridge/import/runtime error was present.

## 2026-05-11 JST - ODEX result/workspace/status source contract
- Added internal `odex_options`, `odex_workspace`, and `odex_result` types to `src/physics/solve_flow.f90`.
- Added ODEX mechanism-status helpers and routed `intode` strict success, zero-time no-op, and mechanism-failure exits through the new result-to-status mapping without changing existing public status values.
- Added `tests/test_odex_result_contract.f90` and the `make test_odex_result_contract` target.
- Updated M4 guardrails so the new ODEX result contract runs with the existing ODEX/assist/swap suite.
- Focused verification passed: `make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_result_contract test_odex_foundation_contract test_odex_solver test_odex_assist_policy`.
- Full local guardrail passed: `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''`.
- `CV-007` remains open. The next real decision point is whether to implement behavior-changing conservative stability control or accept the reduced-scope endpoint backend policy with `stability_control = none` plus explicit wording and flow/Jacobian deterministic tests.

## 2026-05-11 JST - ODEX reduced-scope endpoint backend accepted
- User accepted skipping pre-production conservative stability control.
- Recorded `CV-007` as accepted reduced scope: endpoint extrapolation backend, Hairer `IWORK(3)=3` sequence, no dense output, `stability_control = none`, solver-internal assist only as TLTM residual-evaluation policy, and strict final proposal/live-state flow.
- Added `tests/test_odex_flow_jacobian_contract.f90` and `make test_odex_flow_jacobian_contract`.
- The deterministic flow/Jacobian test covers zero-flow identity, `flow`/`flowz` endpoint consistency, `flowzr` inverse replay, Jacobian finite-difference consistency, and no fallback use.
- Focused verification passed: `make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_result_contract test_odex_flow_jacobian_contract test_odex_foundation_contract test_odex_solver test_odex_assist_policy`.
- Full local guardrail passed: `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''`.

## 2026-05-11 JST - Official DFO-LS preset/provenance guardrails
- Added `get_qn_official_dfols_policy(...)` so the official backend and preset surface can be tested without running the Python package.
- Added `tests/test_official_dfols_preset_contract.f90` and `make test_official_dfols_preset_contract`.
- The test verifies default backend `official_dfols`, production preset `stable_gate77`, stable aliases, legacy comparison alias, and unknown-preset fallback to stable.
- Extended Stage2 v1 sidecar manifest `env_overrides` with official DFO-LS runtime provenance keys: `QN_SOLVER_BACKEND`, `QN_OFFICIAL_DFOLS_PRESET`, all official preset controls, and `TLTM_OFFICIAL_DFOLS_PYTHONPATH`.
- Extended M4 guardrails to parse the Stage2 sidecar manifest and fail if those official DFO-LS provenance env keys disappear.
- Focused verification passed: `make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_official_dfols_preset_contract`.
- Full local guardrail passed: `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''`.

## 2026-05-11 JST - Official DFO-LS package provenance readback
- Added `codex/workspaces/fortran_modernization/tasks/scripts/official_dfols_provenance_readback.py`.
- The script inspects the Python executable used for the embedded official bridge, imports `dfols`, checks installed distribution metadata, and writes both a TSV state row and a runbook readback note.
- Local readback passed for `DFO-LS==1.6.5`, `GPL-3.0-or-later`, Python `3.11.14`, and module path under `.venv-dfols/lib/python3.11/site-packages/dfols`.
- Added the script to M4 Python compile guardrails.
- CV-008 remains open because package identity is not the same as embedded-backend captured-attempt comparison, TLTM residual acceptance evidence, or representative-scale readback.

## 2026-05-11 JST - Official DFO-LS embedded backend gate
- Updated `codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_backend_gate_20260511.pbs` so the gate builds with `ENABLE_OFFICIAL_DFOLS=1`, records `TLTM_OFFICIAL_DFOLS_PYTHONPATH`, and sets the `stable_gate77` official backend env controls before Stage2 capture.
- Submitted PBS job `14803.anode01` with label `official_dfols_embedded_gate_20260511_5ebb85c` on the canonical remote modernization worktree.
- PBS exit status was `0`.
- Gate readback: 100 captured attempts, 100 official replay rows, 93 embedded-converged attempts, 93 residual successes, 0 float64 failures, 0 missing rows, and 0 replay regressions among embedded-converged attempts.
- At that point, remaining F2 work was representative-scale embedded official backend readback and explicit production-regeneration promotion criteria; this was superseded by the representative gate section below.

## 2026-05-11 JST - Official DFO-LS representative embedded backend gate
- Parameterized `codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_backend_gate_20260511.pbs` for representative runs and added per-seed capture wiring through `QN_ATTEMPT_CAPTURE_BASE_DIR` in `scripts/run_stage3_3_multiseed.py` so multi-seed captures cannot overwrite each other.
- Submitted representative Stage2 PBS job `14804.anode01` with label `official_dfols_repr_gate_20260511_9d6f9fc`, config `docs/stage_3_4_t035_paired_10k_10seed.json`, method `fb_norefine`, 10 seeds x 10000 cycles, and 100 captured QN attempts per seed.
- Stage2 aggregate readback passed for 10 seeds: total unresolved failures `1179`, mean unresolved failures `117.9`, mean quasi probe successes `905.6`, total QN eval-flow successes `1476550`, total QN solver-assist count `1858`, total reverse-gate rejects `996`, and per-seed protocol audits passed.
- Fixed future replay discovery from depth 2 to depth 3 after the representative Stage2 run exposed the new `attempts/<method>/seed_<id>/qn_attempt_meta.csv` layout.
- Submitted replay recovery PBS job `14805.anode01` against existing captures. Replay summary: 10 seed cases, 1000 captured attempts, 1000 official replay rows, 923 embedded-converged attempts, 923 official residual successes, 0 float64 failures, 0 missing rows, and 0 embedded-converged regressions.
- Recorded `CV-008` as accepted representative scope and `F2`/`FM-004` as completed. Final production redo remains gated by `CV-001`, `CV-002`, `CV-009`, `CV-010`, and schema/wrapper decisions.

## 2026-05-11 JST - Retained-core deterministic evidence slice 1
- Added `tests/test_retained_core_newton_contract.f90` and `make test_retained_core_newton_contract`.
- Newton readback passed for step sizes `0.002`, `0.003`, and `0.004`: replay residuals `2.9197E-15`, `1.4743E-14`, and `4.6635E-14`; `lambda_scale=9.9817E-01` under the `20.0` limit.
- Added `tests/test_retained_core_rattle_rg_contract.f90` and `make test_retained_core_rattle_rg_contract`.
- RATTLE/RG readback passed: endpoint `z_err=0`, `jac_err=0`; final momentum normal component `0`; reverse-gate replay `success=1`, `failure_total=0`.
- Full local M4 guardrail passed: `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''`.
- Recorded `RETAINED_CORE_EVIDENCE.tsv` and `RETAINED_CORE_DETERMINISTIC_EVIDENCE_20260511.md`. `CV-009` remains active for QN p28 route census, official-DFO-LS-line coverage, RG reject/live-state identity, and local-volume/branch-measure coverage.

## 2026-05-11 JST - Retained-core QN route evidence slice
- Added `tests/test_retained_core_qn_route_contract.f90` and `make test_retained_core_qn_route_contract`.
- BTN paper-variable residual reconstruction passed with `jl_err=0` and `fq_err=0`.
- Current official-line route surface passed: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`, `npt=4`, `maxfun=250`, `noise=T`, route code `10`, and no internal fallback when the stub bridge fails.
- Focused retained-core tests passed together: `make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract`.
- Full local M4 guardrail passed with the QN route contract included.

## 2026-05-12 JST - Official DFO-LS production redo readback
- Refreshed remote state: no active PBS jobs remained, and `tltm_production_comparison` was clean at pinned commit `c0e40218e6abe2706f4b9b4c66067dbcea74eeff`.
- Read back merged production-comparison campaign `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`.
- Scale: 256 seeds x 200000 cycles per method, official DFO-LS backend, `stable_gate77`, RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Per-seed row counts passed: `nofb=256`, `withfb=256`.
- Aggregate readback: nofb unresolved failures `3846795`, reverse-gate rejects `607777`, Zmean Re/Im `1.0465518987029727/-0.6679884160043988`; withfb unresolved failures `618706`, reverse-gate rejects `510906`, Zmean Re/Im `1.9729537196453188/-0.6779881307435225`.
- Direct comparison: `withfb - nofb` unresolved failures `-3228089`, reverse-gate rejects `-96871`, mean runtime `+7696.45` seconds.
- Recorded `OFFICIAL_DFOLS_PRODUCTION_REDO_READBACK_20260512.md` and `OFFICIAL_DFOLS_PRODUCTION_REDO_SUMMARY.tsv`. This closes the ambiguity that production redo had not been run, but does not convert the result into final publication regeneration.

## 2026-05-12 JST - Production artifact versus modernization-release correction
- Corrected the production readback wording after user clarification.
- The `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` artifact was generated under production-comparison commit `c0e40218e6abe2706f4b9b4c66067dbcea74eeff`.
- It is not a rerun after the latest modernization HEAD, and it does not mean modernization is ready to update production and formally rerun final production.
- Current answer to that readiness question is no: F3/CV-009, F4/CV-010, CV-001/CV-002, and final schema/wrapper/naming decisions still block F14 unless explicitly accepted.

## 2026-05-12 JST - F3 retained-core completion to F14 decision point
- Extended `test_retained_core_qn_route_contract` so official bridge builds must prove true package success instead of passing after a missing `dfols` import. Official package success passed with `DFO-LS==1.6.5`, `ierr=F`, and an accepted TLTM residual-gated result.
- Added fixed-step official-line route census inside the QN retained-core test. Step sizes `0.002`, `0.003`, and `0.004` all stayed on route code `10` and all succeeded/accepted when the official package path was provided.
- Preserved stub-bridge no-fallback coverage: `ENABLE_OFFICIAL_DFOLS=0` passes with route code `10`, no internal fallback, and no package-success expectation.
- Added an official/stub bridge-mode stamp to `build/makefile` so switching `ENABLE_OFFICIAL_DFOLS` relinks binaries instead of silently reusing the previous bridge mode.
- Updated M4 guardrails to load `.venv-dfols` and `TLTM_OFFICIAL_DFOLS_PYTHONPATH`, so local M4 exercises the true official package-success branch.
- Added `test_retained_core_rg_reject_identity`, covering HMC and Metropolis stay-put outputs on reverse-gate rejection and local-transition accounting: `local_reject=1`, legacy `projection_failure_count=1`, and typed `reverse_gate_reject_count=1`.
- F3/CV-009 is now decision-pending rather than a hidden missing-work caveat. The remaining choice is whether deterministic branch coverage is sufficient for the next production redo or whether a formal local-volume/branch-measure proof/harness is required first.

## 2026-05-12 JST - F4/F14 production-regeneration decision packet
- Added `DIAGNOSTICS_STATUS_ACCOUNTING_F4_DECISION_20260512.md`: typed diagnostics/accounting remains unimplemented unless explicitly accepted as reduced scope.
- Added `F14_PRODUCTION_REGENERATION_DECISION_PACKET_20260512.md`: F14 now stops at a user decision between conservative completion first and reduced-scope production redo acceptance.
- Updated CAVEATS and OPEN_ITEMS so future handoffs cannot imply production redo is ready without this decision.

## 2026-05-12 JST - Reopen F1/CV-007 for full Hairer ODEX endpoint package
- User requested a complete standalone/full Hairer ODEX endpoint package and a direct test of whether disabling solver assist causes actual observable degeneracy.
- User clarified dense output is not required; dense output is out of scope for the reopened F1 target.
- Reopened `CV-007` and `F1`; previous reduced-scope endpoint backend acceptance is now only historical evidence, not completion of the requested target.
- Added `runbooks/FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md`.
- F14 production regeneration is blocked until full ODEX endpoint package evidence and assist-off observable evidence exist, unless the user explicitly re-scopes ODEX back to reduced scope.

## 2026-05-12 JST - Standalone ODEX endpoint package and assist-off gate submission

- Implemented standalone endpoint backend in `src/physics/odex_backend.f90` with explicit options/workspace/result/status contracts, Hairer `IWORK(3)=3` sequence, endpoint-only API, and conservative stability-control surface.
- `solve_flow.f90` now wraps the package backend and keeps TLTM final-flow, solver-assist, diagnostics, counters, trace state, and failure-capture policy outside the package.
- M4 local guardrails passed after source-boundary cleanup: `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''`.
- Committed and pushed modernization commit `709a7de721b2d03b10be0a87bd60c223124301fd`.
- Synced remote worktree `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization` to `709a7de721b2d03b10be0a87bd60c223124301fd`.
- Bad submit `14943.anode01` exited before evidence because `TLTM_EXPECTED_GIT_COMMIT` was not passed through PBS.
- Corrected submit `14944.anode01` is running on C12 with `qsub -v TLTM_EXPECTED_GIT_COMMIT=709a7de721b2d03b10be0a87bd60c223124301fd`.
- Gate label: `odex_official_dfols_assist_onoff_32seed_50k_20260512`; purpose: official DFO-LS assist-on/off observable degeneracy readback at 32 seeds x 50000 cycles.

## 2026-05-12 JST - Smaller parallel ODEX assist-off probe

- User requested a smaller first test with more resources instead of waiting on the 32seed x 50000 run.
- Cancelled `14944.anode01` after about 14 minutes walltime; it is excluded from evidence.
- Submitted first 16seed x 10000 parallel pair as `14945.anode01` and `14946.anode01`, then cancelled both immediately after boot logs exposed a generated PBS-script defect that left `TLTM_OFFICIAL_DFOLS_PYTHONPATH` empty.
- Submitted corrected v2 pair:
  - `14947.anode01`: assist_on, queue `C12`, `ncpus=12`, `jobs=12`.
  - `14948.anode01`: assist_off, queue `C8`, `ncpus=8`, `jobs=8`.
- Corrected v2 label: `odex_official_dfols_assist_onoff_16seed_10k_parallel_v2_20260512`.
- v2 boot readback passed: remote commit `709a7de721b2d03b10be0a87bd60c223124301fd`, `DFO-LS==1.6.5`, `numpy==2.4.4`, explicit `TLTM_OFFICIAL_DFOLS_PYTHONPATH`, and generated config with 16 seeds x 10000 cycles plus 1000 thermalization cycles.

## 2026-05-12 JST - 16seed ODEX assist-off readback

- `qstat -x` readback shows `14947.anode01` and `14948.anode01` finished with `Exit_status=0`; no active `cychou` PBS jobs remained in live `qstat`.
- Read back `odex_official_dfols_assist_onoff_16seed_10k_parallel_v2_20260512` from the remote `fortran_modernization` worktree at commit `709a7de721b2d03b10be0a87bd60c223124301fd`.
- Assist-on aggregate: mean Re/Im `0.0705266428994/0.0502919233894`, Zmean Re/Im `2.27748019368/2.08317626392`, unresolved failures `24273`, reverse-gate rejects `1558`.
- Assist-off aggregate: mean Re/Im `0.0997527533318/0.00220511583664`, Zmean Re/Im `2.12852982665/0.115668137187`, unresolved failures `26787`, reverse-gate rejects `1497`.
- Paired off-on deltas using `mean/SE`: `Ohat_Re` Z `0.856012123074`, `Ohat_Im` Z `-1.73299773805`, unresolved-failure Z `9.3044425516`, projection-failure Z `8.7725719855`, runtime Z `8.66834111461`.
- Conclusion: solver-health degradation remains decisive at 16seed x 10k, but observable degeneracy is still not proven. F14 remains blocked unless a larger observable gate is read back or the scope is explicitly reduced to solver-health evidence.

## 2026-05-12 JST - Solver assist default-off pre-redo decision

- User decided solver assist should default off for the pre-redo because assist is too close to a rescue/cheat path for the canonical physical route.
- Changed `INTODE_SOLVER_ASSIST_ENABLED` default to off in `src/physics/solve_flow.f90`; assist-on now requires explicit `INTODE_SOLVER_ASSIST_ENABLED=1`.
- Updated assist-policy tests so the default-disabled policy and explicit enabled/disabled env overrides are covered.
- `CV-007`/`F1` are now accepted reduced scope for pre-redo: standalone endpoint package remains, dense output is out of scope, assist-on/off observable evidence is diagnostic only, and solver assist deletion is scheduled after pre-redo.
- Remaining pre-redo decisions are F3 deterministic branch coverage, F4 compatibility diagnostics, F7 schema/naming policy, F8 reference-comparison boundary, and the exact production redo scope/scale.

## 2026-05-12 JST - No reduced-scope F3/F4/F7/F8 decision

- User rejected leaving F3/F4/F7/F8 as reduced-scope caveats.
- F14 now follows conservative completion: implement F3 formal local-volume/branch-measure proof or harness, F4 typed diagnostics context, F7 final schema/naming with compatibility aliases, and F8 patch-local reference comparison harness before production redo.
- Production simulation should not get ad hoc runtime intervention from these gates; they should be preflight, readback, schema, and diagnostics infrastructure unless explicitly recorded as behavior-changing physics policy.

## 2026-05-12 JST - Complete no-reduced F3/F4/F7/F8 pre-redo gate

- Implemented `codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py` and wired it into M4.
- Added frozen schema files:
  - `codex/workspaces/fortran_modernization/schema/F4_LOCAL_TRANSITION_AUDIT_V1.json`
  - `codex/workspaces/fortran_modernization/schema/F7_METHOD_ALIASES_V1.json`
  - `codex/workspaces/fortran_modernization/schema/F8_PATCH_REFERENCE_STATEMENT_V1.json`
- Added `tltm_local_transition_event_t` in `src/sampler/tltm_types.f90`; `record_tltm_local_transition(...)` now derives local counters from this typed event while preserving the old caller API.
- Updated `test_retained_core_rg_reject_identity` to assert the typed event schema/context/denominator on reverse-gate rejection.
- M4 now enables a tiny Stage3 local-transition audit sidecar and validates the F4 audit schema/invariants, F7 aliases, F8 reference anchors, and F14 manifest.
- Verification passed:
  - `make -C build FC=gfortran LDFLAGS= test_retained_core_rg_reject_identity`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- F14 manifest path: `output/tests/m4_guardrails/f14_complete_pre_redo_gate/F14_complete_pre_redo_gate_manifest.json`; status `pass`, `reduced_scope_accepted=false`.
- F3/CV-009, F4/CV-010, F7, and F8 are closed for the pre-redo gate. F14 now needs exact redo scope/scale, target commit/worktree, and production promotion-boundary decisions.

## 2026-05-12 JST - Foundation closure decisions and CV-001 gate

- User selected strict closure policy for remaining modernization foundation caveats:
  - CV-007 closes by endpoint-only ODEX product boundary; dense output and general-purpose Hairer ODEX library claims are non-goals.
  - CV-001 closes by formal official-line kernel correctness gate in the modernization tree.
  - CV-006 closes by strict DFO-LS claim/provenance policy.
  - CV-005 closes only after deep-auditing every relevant tracked script.
  - CV-004 closes as permanent F8/M4 behavior-preservation governance.
  - CV-011 closes only after full RNG/workspace/reentrancy migration and deterministic serial/parallel tests.
- Added `FOUNDATION_CLOSURE_DECISIONS_20260512.md`, `DFOLS_CLAIM_PROVENANCE_POLICY_20260512.md`, `DFOLS_CLAIM_PROVENANCE_POLICY_V1.json`, and `OFFICIAL_LINE_KERNEL_CORRECTNESS_GATE_20260512.md`.
- Implemented `official_line_kernel_correctness_gate.py` and wired it into M4 plus `make official_line_kernel_correctness_gate`.
- Verification passed:
  - `python3 -m py_compile codex/workspaces/fortran_modernization/tasks/scripts/official_line_kernel_correctness_gate.py scripts/run_m4_guardrails.py codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py`
  - `python3 codex/workspaces/fortran_modernization/tasks/scripts/official_line_kernel_correctness_gate.py --repo-root . --fc gfortran --ldflags '' --keep-going`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
  - `make -C build FC=gfortran LDFLAGS= official_line_kernel_correctness_gate`
- CV-001 manifest path: `output/tests/official_line_kernel_correctness_gate/CV001_official_line_kernel_correctness_manifest.json`; status `pass`, package `DFO-LS==1.6.5`, license `GPL-3.0-or-later`, preset `stable_gate77`, solver assist `default_off`.
- Updated caveat/open-item state: CV-001 `closed_kernel_gate`, CV-004 `closed_governed`, CV-006 `closed_claim_policy`, CV-007 `closed_product_boundary`; CV-005 and CV-011 remained open at this point.

## 2026-05-12 JST - CV-005 script evidence audit

- Deep-audited tracked files under `scripts/`, `codex/tasks/`, and `codex/workspaces/fortran_modernization/tasks/`.
- Added `codex/workspaces/fortran_modernization/state/SCRIPT_EVIDENCE_AUDIT_20260512.tsv` with per-file evidence role, execution surface, Python floor, claim boundary, and audit verdict.
- Added `codex/workspaces/fortran_modernization/runbooks/SCRIPT_EVIDENCE_AUDIT_20260512.md`.
- Implemented `codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py` and wired it into M4 plus `make script_evidence_audit_gate`.
- Audit policy:
  - current evidence scripts are explicitly labeled;
  - historical ODEX/M6/qn-error-handling PBS scripts are quarantined;
  - historical multichain/rescue-tuning helpers cannot support current official DFO-LS, current ODEX product, or publication-production claims;
  - new tracked script/task files under audited roots must receive a registry row before M4 evidence passes.
- Verification passed:
  - `python3 -m py_compile codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py codex/workspaces/fortran_modernization/tasks/scripts/official_line_kernel_correctness_gate.py scripts/run_m4_guardrails.py`
  - `python3 codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py --repo-root .`
  - `make -C build FC=gfortran LDFLAGS= script_evidence_audit_gate`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- CV-005 manifest path: `output/tests/script_evidence_audit/CV005_script_evidence_audit_manifest.json`; status `pass`, tracked_count `99`, audited_count `99`.
- CV-005 status is now `closed_script_audit`.

## 2026-05-12 JST - CV-011 RNG product-contract decision point

- Audited Stage1/Stage2 RNG ownership before implementation.
- Source-backed finding: Stage1 and Stage2 initialize replicas/slots with derived seeds, then reset `mt95` to `base_seed` and consume a shared global serial RNG stream for local updates; Stage2 swaps also draw from global `grnd()`.
- `mt95:gaussrnd` keeps hidden Box-Muller spare state (`gset`, `iset`) that is not captured by the existing `mtsave`/`mtget` state API.
- Added `codex/workspaces/fortran_modernization/runbooks/CV011_RNG_WORKSPACE_DECISION_PACKET_20260512.md`.
- Updated `CAVEATS.tsv`, `OPEN_ITEMS.tsv`, and `STATE_BRIEF.md` so CV-011 is marked `decision_needed`.
- Stop condition: choose A strict legacy serial first, B per-replica/per-slot RNG now, or C dual-mode legacy default plus opt-in per-replica mode before any CV-011 source change.

## 2026-05-12 JST - CV-011 route-B per-replica RNG implementation

- User selected route B: per-replica/per-slot RNG now.
- Implemented `mt95_state_t`, `mt95_seed_state`, `mt95_get_state`, and `mt95_set_state`; explicit state includes MT vector/index plus `gaussrnd` Box-Muller spare state.
- `sgrnd` now resets Gaussian spare state when reseeding.
- Stage1 replicas and Stage2 slots now own local-update RNG state; initialization seeds/saves the stream, local updates load/save it around Metropolis updates.
- Stage2 swap acceptance now uses a separate deterministic swap RNG stream derived from `CHAIN_RNG_SEED`.
- Stage1/Stage2 summaries and Stage2 v1 manifests label `rng_stream_contract=per_replica_rng_v1`; same-seed finite trajectories can differ from old shared-serial-RNG outputs by design.
- Added and passed `test_mt95_state_contract`; updated `test_tltm_swap_kernel_contract` for explicit swap RNG state; wired the RNG state test into M4.
- Smoke verification passed for tiny Stage1 and Stage2 runs with `CHAIN_RNG_SEED=12345`.
- CV-011 remains open for remaining non-RNG module workspace/state ownership and deterministic serial/reentrant checks.

## 2026-05-12 JST - Modernization finish and redo boundary

- User confirmed the final modernization target must include full OpenMP/thread-safe productization.
- Route-B RNG stream migration is only the first CV-011 implementation slice; remaining behavior-bearing module state, counters, diagnostics, policy state, and deterministic serial/reentrant checks remain modernization work.
- User also confirmed production redo should be completely separated from modernization.
- Redo now belongs to `tltm_production_comparison` and consumes only a frozen modernization commit plus declared contracts; redo queueing/readback/promotion must not be run from the modernization tree.
- Modernization can be called finished by source/product readiness gates even before final production-output redo completion, as long as redo can consume the frozen commit and contracts cleanly.
- Next execution order: checkpoint the verified foundation/RNG work, add a post-B deterministic reference anchor for `per_replica_rng_v1`, then continue CV-011 OpenMP/thread-safe productization.

## 2026-05-12 JST - Post-B RNG reference anchor

- Added `post_b_rng_reference_anchor.py` and `POST_B_RNG_REFERENCE_ANCHOR_V1.json`.
- The gate runs tiny Stage1 and Stage2 jobs twice with `CHAIN_RNG_SEED=12345`, normalizes `elapsed_sec` and `runtime_sec`, verifies repeat hashes, and compares the result against the frozen reference JSON.
- Frozen normalized hashes:
  - Stage1 summary: `bafe7ce2089cfc2af646f4d216f3b7ec915e0f329b44e96a4becaf723236ab79`
  - Stage2 summary: `b3c3b9192018337e633b9183e5ed74c62358109058b75d8484d589d682f70dfd`
  - Stage2 label trace: `7a6a9b82a0e7c78fed27357ff95649ad0c467c220f29a46db91d6042303bf299`
- Verification passed:
  - `python3 -m py_compile codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py scripts/run_m4_guardrails.py`
  - `python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags '' --update-reference`
  - `python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags ''`
  - `python3 -m py_compile codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py scripts/run_m4_guardrails.py codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py`
  - `python3 codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py --repo-root .`
  - `make -C build FC=gfortran LDFLAGS= post_b_rng_reference_anchor`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

## 2026-05-12 JST - CV-011 decompose2 workspace slice

- Migrated `hmc_kernels:decompose2` away from subroutine-local `save` scratch arrays.
- Added `decompose2_workspace_t`; callers may pass explicit workspace, and legacy no-workspace callers fall back to automatic local workspace instead of shared hidden state.
- Added `decompose2_workspace_t` to `rattle_step_workspace_t` so the active RATTLE core path owns the final projection workspace explicitly.
- Behavior boundary: no RNG, solver policy, reverse-gate/Metropolis acceptance, or output schema change intended.
- Verification passed:
  - `make -C build FC=gfortran LDFLAGS= test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

## 2026-05-12 JST - CV-011 QN linear workspace slice

- Migrated `quasi_newton_linear_solver_mod` away from module-level `save` scratch arrays.
- Added `qn_linear_workspace_t`; public helper calls accept optional explicit workspace and otherwise use automatic local workspace.
- Behavior boundary: no official DFO-LS preset, QN residual definition, RNG, or output schema change intended.
- A direct make run without `TLTM_OFFICIAL_DFOLS_PYTHONPATH` failed as expected with `ModuleNotFoundError: No module named 'dfols'`; reran with the same official DFO-LS env that M4 injects.
- Verification passed with official DFO-LS Python env loaded:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$(.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract post_b_rng_reference_anchor`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

## 2026-05-12 JST - CV-011 Newton workspace slice

- Migrated `hmc_constraints:solve_constraint_newton` away from subroutine-local `save` scratch arrays.
- Added `newton_constraint_workspace_t`; public solve call accepts optional explicit workspace and otherwise uses automatic local workspace.
- Added `newton_constraint_workspace_t` to `rattle_step_workspace_t` so the active RATTLE core path owns Newton scratch state explicitly.
- Behavior boundary: no Newton formula, ODEX policy, QN fallback policy, RNG, or output schema change intended.
- Verification passed:
  - `make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract post_b_rng_reference_anchor`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

## 2026-05-12 JST - CV-011 remaining-state decision point

- Scanned remaining `save` state after route-B RNG streams and three scratch-workspace migrations.
- Remaining classes are flow/ODEX workspaces and counters, QN residual/trace/capture/backend state, constraint/reverse-gate counters and capture files, Stage2 diagnostic file handles, model tape/cache state, config mirror, and profiling state.
- This is now a product-context decision rather than another isolated scratch migration.
- Recommendation recorded: introduce a top-level TLTM run context as the product direction, then incrementally thread sub-contexts through Stage1/Stage2 paths while retaining compatibility wrappers.

## 2026-05-12 JST - CV-011 top-level run context first slice

- User selected route A: top-level TLTM run context first, then continue until the next required decision.
- Added `tltm_run_context_mod` with `tltm_run_context_t` and `tltm_hmc_context_t`.
- Threaded HMC context through `metropolis_step`, `integrate_hmc_proposal`, `integrate_hmc_warmup`, and Stage1/Stage2 local-update paths.
- Stage1 owns one run context per replica; Stage2 owns one run context per slot.
- Behavior boundary: workspace ownership only; no physics equation, solver policy, reverse-gate policy, Metropolis acceptance, output schema, or post-B RNG-stream change intended.
- Production redo remains fully isolated in `tltm_production_comparison`; modernization work did not sync, stage, or modify the production tree.
- Verification passed:
  - `make -C build ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `make -C build FC=gfortran LDFLAGS= test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

## 2026-05-12 JST - CV-011 Stage2 audit context slice

- Migrated Stage2 audit file state out of module-level `save` storage.
- Added `stage2_audit_context_t` for RG-reject audit and local-transition audit loaded/enabled flags, file units, file paths, max-row setting, and row counter.
- `execute_tltm_stage2` owns the audit context and passes it through local updates to the audit writers.
- Behavior boundary: diagnostics state ownership only; no physics, Metropolis, solver route, output summary, or RNG contract change intended.
- Verification passed:
  - `make -C build ../bin/run_tltm_stage2`
  - tiny Stage2 run with `TLTM_RG_REJECT_AUDIT_FILE` and `TLTM_LOCAL_TRANSITION_AUDIT_FILE` enabled; local-transition audit wrote header plus two rows, RG-reject audit wrote header-only for no reject.
  - `make -C build FC=gfortran LDFLAGS= post_b_rng_reference_anchor`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`

## 2026-05-12 JST - CV-011 flow context decision point

- Inspected `solve_flow.f90` and `odex_backend.f90` after the Stage2 audit context slice.
- Found that flow/Jacobian RHS scratch state is coupled to the callback interface `ode_rhs(y)`, which has no explicit user/context argument.
- Recorded options in `CV011_FLOW_CONTEXT_DECISION_POINT_20260512.md`.
- Recommendation: choose option A, redesign the local ODEX callback context path, then migrate flow/Jacobian RHS scratch into the top-level run context.
- Stop condition: user decision required before changing the ODEX callback interface.

## 2026-05-13 JST - CV-011 flow/ODEX context slice

- User selected option A for the flow/ODEX callback-context decision.
- Added a context-aware ODEX callback path while preserving the legacy endpoint API.
- Added `flow_workspace_t` and moved flow endpoint buffers, vector/Jacobian RHS scratch, `flow_vec_rhs_scale`, and ODEX endpoint workspace out of module-level SAVE state.
- Added optional flow workspaces to `flow`, `flowz`, and `flowzr`; legacy callers use automatic local workspaces, while Stage1 initialization and Stage2 initialization/swap reflow now use per-replica/per-slot run-context flow workspaces.
- Updated the Stage2 swap kernel contract to pass run contexts into `attempt_adjacent_swap`.
- Behavior boundary: state ownership only; no intended physics, ODEX policy, QN route, reverse-gate, Metropolis, RNG-stream, or schema change.
- Verification passed:
  - `make -C build FC=gfortran LDFLAGS= test_odex_flow_jacobian_contract test_odex_solver test_odex_foundation_contract`
  - `make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `make -C build FC=gfortran LDFLAGS= test_tltm_swap_kernel_contract`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Full M4 passed; production-comparison tree was not synchronized, staged, or modified.

## 2026-05-13 JST - CV-011 HMC/QN flow-context threading slice

- Threaded optional `flow_workspace_t` through `metropolis_step`, HMC proposal/warmup/reverse-probe, `rattle_step_core`, Newton constraint solve, QN residual evaluation, QN rescue/recovery, and final RATTLE flow.
- Stage1 and Stage2 local updates now pass `run_context%flow%workspace`, so active per-replica/per-slot proposal paths use explicit flow workspace ownership.
- The official DFO-LS C callback path can use the active flow workspace for residual evaluations, but its callback context still relies on module-level `qn_official_*` state.
- Verification passed:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Stop condition: decide whether to redesign the official DFO-LS callback to use the C bridge `ctx` pointer for per-attempt context before continuing deeper QN backend state migration.

## 2026-05-13 JST - CV-011 QN official callback context slice

- User selected option A for official DFO-LS callback context.
- Added a per-attempt `qn_official_callback_context_t` and passed it through the C bridge `ctx` pointer.
- `qn_official_dfols_eval_callback` now recovers `xt`, `z`, `del_z`, `jac`, and active `flow_workspace_t` from `ctx` instead of module-level `qn_official_*` context arrays.
- Removed the active-route dependency on the module-level official callback active flag and callback arrays.
- Verification passed:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Stop condition: QN trace/capture/eval context ownership needs a decision before moving `quasi_last_trace_*`, watchdog, attempt-capture, eval-flow counters, and backend policy cache.

## 2026-05-13 JST - CV-011 QN trace/eval context slice

- User selected option A for QN trace/capture/eval context ownership.
- Added `qn_context_t` plus `release_qn_context` in `quasi_newton_solver_mod`.
- Moved active-route QN residual scratch, proposed/flowed eval cache, last-trace buffers, trace route/iteration state, watchdog scope/last status, and per-attempt residual eval count into `qn_context_t`.
- Preserved legacy/direct-call compatibility with module fallback `module_qn_context`.
- Added `tltm_qn_context_t` under `tltm_run_context_t` and threaded `run_context%qn%workspace` through Stage1/Stage2 local updates, `metropolis_step`, HMC proposal/warmup/reverse-probe, `rattle_step_core`, QN solves, QN reverse-gate replay, and trace readers.
- Extended the official QN route retained-core test with `qn_context_trace_isolation`, which proved two QN contexts keep independent traces while the official DFO-LS callback uses the selected context.
- Verification passed:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Stop condition: QN attempt-capture files/counters, eval-flow/global-filter counters, and backend policy cache need a diagnostics ownership decision before migration.

## 2026-05-13 JST - CV-011 QN diagnostics context slice

- User selected option A for QN capture/diagnostics context ownership.
- Added `qn_diagnostics_context_t` plus `release_qn_diagnostics_context` in `quasi_newton_solver_mod`.
- Moved QN attempt-capture policy flags, file units, file-ready/write-error state, sample counters, stride/limit, and capture directory into `qn_diagnostics_context_t`.
- Moved QN eval-flow status counters and QN global-filter candidate/pass/reject counters into `qn_diagnostics_context_t`.
- Preserved legacy/direct-call compatibility with module fallback `module_qn_diagnostics_context`.
- Stage1 and Stage2 now own one run-level diagnostics sink and pass it through `metropolis_step`, HMC proposal/warmup/reverse-probe, `rattle_step_core`, QN reverse-gate replay, and QN solve paths.
- Extended the official QN route retained-core test with `qn_diagnostics_context_isolation`, which proved two diagnostics sinks keep independent QN eval-flow counters.
- Verification passed:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Stop condition: QN backend/watchdog policy cache ownership needs a decision before migration.

## 2026-05-13 JST - CV-011 QN policy context slice

- User selected option A for QN backend/watchdog policy context ownership.
- Added `qn_policy_context_t` plus `release_qn_policy_context` in `quasi_newton_solver_mod`.
- Moved QN backend policy cache, official DFO-LS preset values, watchdog policy cache, force-best proposal controls, backend notice state, and official bridge failure warning state into `qn_policy_context_t`.
- Preserved legacy/direct-call compatibility with module fallback `module_qn_policy_context`.
- Stage1 and Stage2 now own one run-level QN policy context and pass it through `metropolis_step`, HMC proposal/warmup/reverse-probe, `rattle_step_core`, QN reverse-gate replay, and QN solve paths.
- Extended the official DFO-LS preset contract with `policy_context_isolation`, which proved two explicit QN policy contexts can keep independent DFO-LS preset values in the same process.
- Verification passed:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_official_dfols_preset_contract test_retained_core_qn_route_contract`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Production-comparison tree was not synchronized, staged, or modified.
- Stop condition: HMC fallback/reverse-gate policy cache, `qn_reverse_gate_active`, and reverse-gate replay status counters need an ownership decision before migration.

## 2026-05-13 JST - CV-011 HMC policy/reverse-gate context slice

- User selected option A for HMC fallback/reverse-gate context ownership.
- Added `hmc_policy_context_t`, `hmc_replay_runtime_context_t`, and `hmc_replay_diagnostics_context_t` in `hmc_integrator_core`.
- Moved S1 fallback/reverse-gate env policy cache into `hmc_policy_context_t`.
- Moved `qn_reverse_gate_active` into per-HMC `hmc_replay_runtime_context_t`, stored under `tltm_hmc_context_t`.
- Moved reverse-gate replay status counters into Stage/run-owned `hmc_replay_diagnostics_context_t`.
- Preserved legacy/direct-call compatibility with module fallback contexts.
- Stage1 and Stage2 now own one run-level HMC policy context and one run-level replay diagnostics context, and pass them through Metropolis/HMC/RATTLE/QN reverse-gate paths.
- Extended the retained-core RATTLE/RG contract with `replay_diagnostics_context_isolation`, which proved two HMC replay diagnostics contexts retain independent status counters.
- Verification passed:
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2`
  - `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Production-comparison tree was not synchronized, staged, or modified.
- Stop condition: triage the next remaining behavior-bearing state boundary before migrating more module state.

## 2026-05-13 JST - CV-011 profiler context slice

- Chose the profiling-counter boundary as the next low-risk CV-011 state slice.
- Added `perf_profile_context_t` in `perf_profile` and moved profiler
  accumulators, call counters, enabled flag, and initialization flag behind the
  context.
- Preserved legacy/direct-call compatibility through a module fallback context,
  so existing `perf_tic`, `perf_toc`, `perf_reset`, and `perf_report` callers
  keep their behavior.
- Added optional context arguments to profiler APIs plus
  `release_perf_profile_context`.
- Replaced the placeholder `tltm_profile_context_t%reserved` field with
  `tltm_profile_context_t%profiler`, owned by `tltm_run_context_t`.
- Added `test_perf_profile_context_contract` and wired it into the build and
  M4 target list.
- Verification passed:
  - `make -C build test_perf_profile_context_contract`
  - `make -C build ../bin/run_tltm_stage2`
  - `git diff --check`
- Production-comparison tree was not synchronized because live PBS jobs
  `15098`-`15105` are running and merge job `15106` is held, all pinned to
  production-comparison commit `6f98b5b`.
- Stop condition: continue CV-011 with solver/flow/reversibility diagnostics,
  model tape/cache, config mirror, or deterministic serial/reentrant checks.

## 2026-05-13 JST - CV-011 HMC reversibility diagnostics context slice

- Chose the HMC reversibility/progress diagnostic boundary as the next
  behavior-adjacent CV-011 state slice.
- Added `hmc_reversibility_context_t` in `hmc_reversibility_checks`.
- Moved reversibility-probe loaded/enabled/fallback-only/limit/count state and
  state-progress diagnostic loaded/enabled/limit/count state behind the
  context.
- Preserved legacy/direct-call compatibility through a module fallback context.
- Added optional context arguments to reversibility/progress diagnostic APIs
  plus `release_hmc_reversibility_context`.
- Replaced the placeholder diagnostics field with
  `tltm_run_context_t%diagnostics%hmc_reversibility`.
- Threaded the context through Stage1/Stage2 local updates,
  `metropolis_step`, HMC proposal/warmup, RATTLE, and reverse-probe reporting.
- Added `test_hmc_reversibility_context_contract` and wired it into the build
  and M4 target list.
- Verification passed:
  - `git diff --check`
  - `make -C build test_hmc_reversibility_context_contract`
  - `make -C build ../bin/run_tltm_stage2`
  - `make -C build test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- Production-comparison tree was not synchronized because formalized assist
  bridge jobs remain pinned to production-comparison commit `6f98b5b`.
- Stop condition: continue CV-011 with solver/flow diagnostics, model
  tape/cache, config mirror, or deterministic serial/reentrant checks.

## 2026-05-13 JST - CV-011 Newton eval-flow status context slice

- Chose the Newton eval-flow status counters as the next small CV-011
  diagnostics ownership slice.
- Added `newton_eval_flow_status_context_t` in `hmc_constraints`.
- Moved Newton eval-flow success/zero-time/stiff-rescue/solver-assist and
  failure/unknown status counters behind the context.
- Preserved legacy/direct-call compatibility through a module fallback context.
- Added optional context arguments to Newton eval-flow reset/get/record APIs,
  `solve_constraint_newton`, and Stage2 adaptive preflow warmup.
- Threaded a Stage/run-owned context through Stage1/Stage2 local updates,
  Stage2 adaptive preflow, `metropolis_step`, HMC proposal/warmup, RATTLE,
  reverse-gate replay, and the Newton constraint solve path.
- Stage1/Stage2 summary writers now read Newton eval-flow status counters from
  the Stage/run-owned context instead of module state.
- Added `test_newton_eval_flow_status_context_contract` and wired it into the
  build and M4 target list.
- Verification passed:
  - `git diff --check`
  - `make -C build test_newton_eval_flow_status_context_contract`
  - `make -C build ../bin/run_tltm_stage2`
  - `make -C build test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity`
  - `python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags '' --output-root output/tests/post_b_rng_reference_anchor_newton_flow_context_check`
  - `PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going`
- First full-M4 attempt caught an incomplete Stage2 adaptive-preflow context
  thread as a post-B Stage2 summary hash mismatch. Stage1 summary and Stage2
  label trace were unchanged; after threading adaptive preflow into the same
  Stage/run context, the frozen post-B hash passed again.
- Production-comparison tree was not synchronized because formalized assist
  bridge jobs remain pinned to production-comparison commit `6f98b5b`.
- Stop condition: continue CV-011 with constraint-solver aggregate/failure
  capture diagnostics, solve-flow fallback/trace/failure state, model
  tape/cache, config mirror, or deterministic serial/reentrant checks.

## 2026-05-13 JST - Modernization cleanup vs correctness sweep split

- User raised the risk that strict output-preserving modernization can preserve
  minor-but-important bugs as golden behavior.
- Recorded deferred F16 in `OPEN_ITEMS.tsv` and created
  `runbooks/POST_MODERNIZATION_CORRECTNESS_SWEEP_PLAN_20260513.md`.
- User clarified that obvious dead triggers and strange internal names are
  modernization cleanup when behavior can be preserved, not something to defer
  past modernization closure.
- Added
  `runbooks/MODERNIZATION_LEGACY_TRIGGER_NAMING_CLEANUP_20260513.md`, and moved
  behavior-preserving `eo`/`istest`/`testmom` and `rattle2`/`decompose2` cleanup
  under F9/W11 with F8 guardrails.
- Boundary: deferred F16 is only for candidate bugs whose fix may intentionally
  change output, counters, route selection, or public schema meaning.
- Behavior-changing fixes require an evidence packet, explicit approval,
  focused tests, and separate commits from pure modernization cleanup.

## 2026-05-14 JST - Assist diagnostic branch closed; trees converged

- User reported the assist discrepancy/root-cause problem is solved and selected
  a tree-convergence plan.
- Active work is narrowed back to `fortran_modernization` and
  `tltm_production_comparison`.
- Modernization remains the source/product closure tree.  Production should wait
  until the modernization fix is complete, then sync to the selected fixed commit
  and regenerate production from a clean namespace.
- Do not keep expanding the assist diagnostic side tree as modernization work.
- Cleanup correction: removed the diagnostic ODEX legacy-sequence source diff
  from `src/physics/odex_backend.f90`; it must not enter canonical
  modernization.  The assist-regression tiny reproducer was moved out of the
  modernization workspace archive and into the production-comparison archive as
  historical evidence only.

## 2026-05-14 JST - Stage2 RNG v2 design made discoverable

- User noticed new modernization sessions could not find the RNG v2 design after
  side-tree cleanup.
- Added `runbooks/CV011_STAGE2_KERNEL_RNG_V2_DESIGN_20260514.md` as the
  modernization-tree entry point for `stage2_kernel_rng_v2`.
- Updated `STATE_BRIEF.md`, `WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`,
  `MODERNIZATION_FORWARD_WORKSTEPS_20260511.md`, and OPEN_ITEMS so future
  modernization sessions do not treat `per_replica_rng_v1` as production
  equivalent by default.

## 2026-05-14 JST - Stage2 RNG v2 implemented

- Implemented `TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2` as the Stage2 default.
- Added domain-separated kernel RNG seeding for Stage2 initialization, local momentum, local Metropolis accept, and swap accept domains.
- Threaded optional explicit MT95 state through HMC momentum and Metropolis accept draws while preserving legacy/global callers.
- Kept `per_replica_rng_v1` available for the post-B reference anchor and `legacy_global_v0` as historical compatibility.
- Updated Stage2 summaries/manifests and Stage3 production driver provenance so production runs record `stage2_kernel_rng_v2` explicitly.
- Verification passed: py_compile, Stage2/eval build, `test_tltm_swap_kernel_contract`, `test_mt95_state_contract`, `stage2_rng_v2_anchor`, `post_b_rng_reference_anchor`, Stage3 dry-run, and `git diff --check`.
- Full M4 build/smoke/science checks passed on the first attempt; M4 correctly failed governance because new source/script files were still untracked and must be staged before final evidence acceptance.
- After intentional staging, full M4 guardrails passed with the new source/script files included.
- The production-comparison branch/worktree was synchronized to the committed Stage2 RNG v2 modernization state; production should next regenerate from a clean namespace, not from the historical assist-diagnostic outputs.

## 2026-05-16 JST - CVODE max-step fail-fast rejected

- Implemented CVODE-only fail-fast controls at `1d750409`: `TLTM_CVODE_MAX_STEPS`, `TLTM_CVODE_MIN_STEP`, `TLTM_CVODE_MAX_ERR_TEST_FAILS`, `TLTM_CVODE_MAX_CONV_FAILS`, and `TLTM_CVODE_MAX_NONLIN_ITERS`.
- Local/default validation passed: SUNDIALS stub contract, Stage2/eval build, Stage3 driver py_compile, `git diff --check`, and full M4 guardrails. Remote enabled CVODE build and contract passed, including the deliberate max-step failure case.
- Ran the 1k fail-fast screen and selected only `TLTM_CVODE_MAX_STEPS=320` for 10seed/10k scale-up; `s100` was pathological, and `s160`/`s240`/combo had unacceptable 1k drift.
- Ran `cvode_failfast_s320_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260516T000908_1d750409cf3e`: jobs `15496.anode01` (`no_fb`) and `15497.anode01` (`fb_norefine`) both completed with `Exit_status=0`.
- Readback is negative despite faster runtime: `no_fb` runtime `696.20`, proposal failures `14941`, mean Re `-0.1730188`, Zmean Re `-3.892`; `fb_norefine` runtime `734.52`, proposal failures `14833`, mean Re `-0.1782486`, Zmean Re `-4.220`.
- Conclusion: strict CVODE remains disabled-by-default comparison-only; do not scale max-step fail-fast further unless a different package route or non-kernel-changing performance path is explicitly selected.

## 2026-05-16 JST - CVODE non-max-step fail-fast sweep rejected

- Tested the remaining CVODE fail-fast knobs at `d24acef` using official DFO-LS
  `npt5_r0055`, true Stage2 RNG v2, assist off, strict tolerance,
  `TLTM_CVODE_FIXEDPOINT_M=0`, and both `no_fb` / `fb_norefine`.
- Round 1 `20260516T003745`: `h1e8`, `h1e6`, `err4`, `conv4`, `iter2`, jobs
  `15498-15507.anode01`. `h1e6` hard-failed initialization; `h1e8` changed
  the `fb_norefine` proposal/failure surface; `err4` was no useful effect;
  `conv4` was clean at 1k; `iter2` had no clean payoff.
- Round 2 `20260516T004754`: `conv2`, `conv6`, `conv4_iter2`, `err2`, `h1e9`,
  jobs `15508-15517.anode01`. `err2` and `h1e9` changed `fb_norefine`;
  `conv2` was clean at 1k; `conv6` was no useful gain; `conv4_iter2` was not
  clean for `fb_norefine`.
- Round 3 `20260516T005611`: `conv1`, jobs `15518-15519.anode01`, was clean at
  1k and selected for 10k because it was the strongest clean convergence-limit
  candidate.
- Ran `cvode_failfast_conv1_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260516T010335_d24acef0e890`:
  jobs `15520.anode01` (`no_fb`) and `15521.anode01` (`fb_norefine`) both
  completed with `Exit_status=0`.
- Readback: `TLTM_CVODE_MAX_CONV_FAILS=1` matched strict CVODE exactly for
  pair0 accept, unresolved failures, proposal failures, RG rejects, means, and
  Zmean at 10seed/10k, but was slower (`1.085x` no_fb and `1.120x`
  `fb_norefine`).
- Conclusion: not only max steps can fail fast, but all tested CVODE fail-fast
  knobs are rejected as canonical/performance routes. Strict CVODE stays
  disabled-by-default comparison-only unless F18 switches to a different mature
  package route or a non-kernel-changing performance strategy.

## 2026-05-16 JST - F18b handwritten endpoint ODEX hardening opened

- User selected returning to handwritten ODEX hardening after the negative F18
  CVODE tuning readback.
- Added `runbooks/F18B_HANDWRITTEN_ODEX_ENDPOINT_HARDENING_20260516.md`.
- New claim boundary: TLTM endpoint ODEX/GBS with Hairer `IWORK(3)=3`.
  `h0`, h-min, step/order, rejection, signed interval, and stability are not
  yet decided; they must first be observed/frozen by deterministic tests and
  then accepted, patched, or deferred by explicit decision.
- Explicitly blocked claim: full Hairer ODEX paper correctness.
- SUNDIALS CVODE remains disabled-by-default comparison-only evidence; no more
  fail-fast package tuning is active.
- Immediate next step is F18b.0/F18b.1: create the behavior-free source
  map/decision table and add deterministic controller observation tests that
  freeze current `h0`, h-min, step/order, rejection, signed-interval, and
  stability behavior as evidence for later decisions, not as already-set
  policy.

## 2026-05-16 JST - F18b.0/F18b.1 ODEX controller observation implemented

- Added behavior-neutral `odex_observe_*` helpers for h-min, first-step,
  controller step/work estimates, large-error threshold, and conservative
  stability predicate.
- Added `test_odex_controller_observation_contract` and wired it into the
  build plus M4.
- The focused contract freezes current `h0 = 0.01*t`, h-min component formula,
  `IWORK(3)=3` rows, signed `h`/positive work estimate, `1.0e-14` error floor,
  max-step failure, NaN-RHS rejection-to-h-min behavior, and default/off vs
  conservative stability predicate behavior.
- Updated the F18b runbook, workstream matrix, state brief, and open items so
  the next step is F18b.2 accept/patch/defer decision work before any
  behavior-changing ODEX controller patch.
- Verification passed: focused controller observation target, `python3 -m
  py_compile scripts/run_m4_guardrails.py scripts/fortran_module_deps.py`,
  `git diff --check`, and full M4 with official DFO-LS venv.

## 2026-05-16 JST - F18b.2 ODEX controller decision packet

- Added `F18B_CONTROLLER_DECISION_PACKET_20260516.md`.
- Decision: preserve current handwritten endpoint ODEX controller behavior as
  TLTM endpoint policy for modernization closure, while explicitly blocking
  full Hairer ODEX paper-correctness claims.
- Accepted/scoped surfaces: endpoint-only scope, Hairer `IWORK(3)=3`, signed
  intervals with positive work estimates, current `h0`, h-min floor/status,
  order/rejection predicates, large-error threshold, strict-double error
  floor, default no-stability-control policy, and disabled-by-default CVODE
  comparison.
- No behavior-changing controller patch is authorized. Future controller
  alignment patches require explicit selection plus F8, M4, focused tests, and
  affected-baseline screens.
- Updated F18b runbook, workstream matrix, state brief, and open items so the
  next ODEX source-facing slice is F18b.3 state productization unless a
  behavior-changing controller patch is explicitly selected.

## 2026-05-16 JST - F18b.3 ODEX/flow behavior-correction boundary

- Added
  `F18B3_ODEX_FLOW_STATE_AND_BEHAVIOR_CORRECTION_DECISION_20260516.md`.
- Decision: the next ODEX/flow source slice is behavior-preserving state
  productization, not an ODEX controller behavior patch.
- Selected implementation shape: split runtime trace/context attribution from
  run-level INTODE/ODEX diagnostics; move fallback counters, context bins,
  disabled-by-default CVODE counters, and last-failure snapshots into an
  explicit run diagnostics context with legacy module fallback.
- Behavior-correction rule: if implementation reveals a public
  counter/status/schema semantic issue, stop and write a separate F4/F7/F8
  packet; endpoint, final-flow, reverse-gate, or proposal behavior changes
  remain separate numerical behavior changes requiring explicit approval,
  M4, and affected-baseline evidence.
- Updated F18b runbooks, workstream matrix, state brief, open items, and
  decision registry so the next operational source patch is F18b.3a
  diagnostics/runtime-trace context ownership.
