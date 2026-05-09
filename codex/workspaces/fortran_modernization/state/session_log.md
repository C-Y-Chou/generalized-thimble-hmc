# Session Log: fortran_modernization

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
