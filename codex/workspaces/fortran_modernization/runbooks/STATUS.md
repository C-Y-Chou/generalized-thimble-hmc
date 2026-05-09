# Task Status: fortran_modernization

Updated: 2026-05-09 17:48 JST

## Objective
- Define the governing principles, workstreams, milestones, and verification rules for systematic TLTM Fortran modernization.
- Keep behavior preservation explicit: engineering changes must not silently change the underlying physics or accepted reference outputs.

## Current state
- Initial modernization governance set established.
- User-confirmed alias: "code refine" means this `fortran_modernization` task, not a separate workspace.
- Algorithm reference bundle is collected under `references/`, including TLTM HMC, simplified Newton/RATTLE/HMC, DFO-GN/DFO-LS, Hairer ODEX, and the user original quasi-Newton projection formulation.
- Planning-only low-level algorithm review set is complete enough for user discussion:
  - `runbooks/ODEX_FLOW_REVIEW_NOTES.md`
  - `runbooks/SIMPLIFIED_NEWTON_RATTLE_REVIEW_NOTES.md`
  - `runbooks/QUASI_NEWTON_PROJECTION_REVIEW_NOTES.md`
  - `runbooks/HMC_METROPOLIS_TLTM_REVIEW_NOTES.md`
  - `runbooks/BASELINE_VERIFICATION_MATRIX.md`
  - `runbooks/PLANNING_DISCUSSION_BRIEF.md`
- Current flow-policy candidate is ODEX primary integration with solver-internal ODE assist for NT/QN residual evaluation and strict final proposal flow.

## Current architecture understanding
- `solve_flow.f90` is flow mapping plus ODEX-like integration plus Radau/JFNK/final-resort policy plus diagnostics.
- `hmc_integrator_core.f90` is the central proposal hub: Newton, quasi fallback, post-refine, reverse gate, flow/Jacobian update, momentum projection, and solver statistics.
- `quasi_newton_solver.f90` mixes residual definitions, DFO-LS/DFO-GN/Broyden solver families, continuation/restart policy, traces, watchdog/final-resort budgets, and route counters.
- `tltm_stage2_driver.f90` owns production orchestration and output/counter contracts used by Stage3_4 interpretation.

## State/information propagation refine queue - 2026-05-09 JST
- User clarified that the flagged `h==0` issue means Hamiltonian `H==0` when a proposal is rejected, not ODE step size.
- Added `runbooks/STATE_INFORMATION_PROPAGATION_REFACTOR.md` as the broader workflow item replacing the narrower error-handling framing.
- Future target: typed state/status propagation for ODE integration, residual evaluation, solver convergence, proposal construction, reverse-gate rejection, Metropolis rejection, and live-chain state update.
- Policy boundary: solver-internal ODE assist may help NT/QN residual evaluation, but strict final `flow(...)` must construct the actual proposal.
- Solver-assist 10k -> 50k -> 100k validation is complete and analyzed; source-level state/status refactor still requires explicit user confirmation patch-by-patch.

## HMC unavailable-Hamiltonian sentinel patch - 2026-05-09 JST
- First source slice implemented in local worktree: failed/unavailable HMC Hamiltonians now use IEEE quiet NaN instead of `0.0` sentinel values.
- Updated Hamiltonian conservation test to use `proposal_ok` plus finite-Hamiltonian checks.
- Updated warmup guard in `markovchain_mod.f90` to exit on unavailable/non-finite Hamiltonians rather than `H==0`.
- Local verification: `make -C build FC=gfortran LDFLAGS= ../bin/test_program` and `make -C build FC=gfortran LDFLAGS= test1` pass on macOS/gfortran.
- Local Stage2 smoke with `TLTM_STAGE2_CYCLES=2`, `TLTM_STAGE2_NUM_REPLICAS=2`, `TLTM_STAGE2_MAX_FLOW_TIME=0.1` still fails slot-1 initialization; the same smoke fails on clean `HEAD`, so this is not attributable to the sentinel patch.

## Proposal status surface patch - 2026-05-09 JST
- Next state/status audit finding: `proposal_failed` is still a compatibility boolean that conflates proposal construction failure, reverse-gate rejection, unavailable Hamiltonian, invalid `Delta H`, and ordinary Metropolis rejection context.
- Implemented a narrow status-surface patch without changing the acceptance rule, RNG draw point, or output schema:
  - `hmc_integrator_core.f90` now exposes optional RATTLE-step status codes.
  - `hmc.f90` maps step status to proposal status and exposes optional proposal status from `integrate_hmc_proposal`.
  - `markovchain_metropolis.f90` maps proposal status to optional transition status while preserving `accept` and `proposal_failed`.
  - `tests/test_hamiltonian_conservation.f90` now verifies successful proposals return `hmc_proposal_status_success`.
- Verification: after a clean rebuild, `make -C build FC=gfortran LDFLAGS= ../bin/test_program`, `make -C build FC=gfortran LDFLAGS= test1`, and `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2` pass/build locally.
- Build-system note: incremental build after public module API changes can leave stale objects because the local makefile lacks complete Fortran module dependency tracking. Use a clean rebuild for this patch; proper dependency/build tooling remains a modernization item.

## Fortran module dependency build patch - 2026-05-09 JST
- Promoted `build/makefile` into tracked source by narrowing `.gitignore` from ignoring all of `build/` to ignoring `build/*` except `build/makefile`.
- Added `scripts/fortran_module_deps.py`, a conservative scanner for Fortran `module`/`use` relationships.
- `build/makefile` now generates and includes `.obj/fortran_module_deps.mk`; consumer objects depend on provider objects, preventing stale-object ABI crashes after public module API changes.
- Incremental rebuild check: after `touch src/sampler/hmc.f90`, `make -C build FC=gfortran LDFLAGS= ../bin/test_program` rebuilt `hmc.o`, downstream sampler/driver consumers, and `tests/test_hamiltonian_conservation.o`.
- Verification: `make -C build clean && make -C build FC=gfortran LDFLAGS= ../bin/test_program`, `make -C build FC=gfortran LDFLAGS= test1`, and `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2` pass/build locally.

## State/information propagation audit - 2026-05-09 JST
- Added `runbooks/STATE_INFORMATION_PROPAGATION_AUDIT.md`.
- Audit result: live-chain state update on reject appears safe, but failed/unavailable Hamiltonian is still encoded as `0.0` in `hmc.f90`, `markovchain_mod.f90`, and `tests/test_hamiltonian_conservation.f90`.
- First proposed code patch before broader typed-status redesign: replace `H=0` failure sentinels with explicit proposal status/non-finite unavailable Hamiltonian handling while preserving Metropolis physics.

## Next action
Review/commit the Fortran module dependency build patch. Next implementation slice can safely split Stage1/Stage2 counters using the new proposal/transition statuses.

## After confirmation
- Build baseline harness design first.
- Do not start Fortran source modernization until affected baseline rows in `BASELINE_VERIFICATION_MATRIX.md` are satisfied.

## Quasi route decision - 2026-05-08 JST
- Production-canonical quasi route: current p28 path (`QN_S1_PROBE_MAX_ITER=28`) using DFO-LS BTN/backflow rescue on `evaluate_constraint_residual` after Newton failure.
- Legacy/deletion candidates: non-p28 quasi routes, DFO-GN paper route, Broyden/line-search route, and global continuation/restart fallback routes outside current p28 production policy.
- Post-refine remains under observation and may be removed after refine-vs-norefine evidence is reviewed.

## Wrapper direction decision - 2026-05-08 JST
- Current Stage2/Stage3/Stage3_4 workflow is transitional scaffolding.
- After TLTM construction/Stage3_4 judgment, modernization should converge to a unified TLTM wrapper/runner with versioned output schema.
- Short-term output contracts remain frozen for Stage3_4 compatibility.

## Baseline source decision - 2026-05-08 JST
- Official modernization baselines will be regenerated after Stage3_4/TLTM judgment completes.
- Existing `output/tests` artifacts remain historical/reference evidence only.

## Reverse gate decision - 2026-05-08 JST
- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It must be preserved and baselined during modernization.

## Flow backend direction decision - revised 2026-05-09 JST
- Pure ODEX-only is retained as a comparison artifact, not the final production policy.
- Current canonical candidate is ODEX primary integration plus solver-internal ODE assist for NT/QN residual evaluation plus strict final proposal flow.
- Radau/JFNK/final-proposal rescue acceptance remains a legacy deletion candidate; solver-internal assist must be kept or explicitly redesigned before deletion.

## Thread-safety decision - 2026-05-08 JST
- Long-term modernization target is in-process parallel/OpenMP-capable TLTM execution.
- Hidden module `save` workspaces/counters/RNG/traces/policies should eventually become explicit context/workspace state.
- No source refactor before Stage3_4/TLTM judgment and fresh baselines.

## Confirmed roadmap update - 2026-05-08 JST
- Added `runbooks/CONFIRMED_DECISIONS_AND_NEXT_PLAN.md`.
- Modernization workstreams now include algorithm mapping, behavior baselines, code hygiene cleanup, architecture/API redesign, legacy deletion, reentrancy/OpenMP, and product readiness.
- Plan is structurally complete at planning level; remaining items are future decision gates after Stage3_4/TLTM judgment.

## Scope correction - 2026-05-08 JST
- Five core algorithm audits are safety gates, not the center of the full modernization roadmap.
- Full modernization is repo-wide and includes utils, RNG, config, I/O/output schema, build/test tooling, scripts/PBS orchestration, diagnostics/logging, memory/workspace ownership, and documentation.
- `CONFIRMED_DECISIONS_AND_NEXT_PLAN.md` updated with cross-cutting infrastructure modernization scope.

## Pre-Stage3_4 planning completion - 2026-05-08 JST
- Added `PRE_STAGE3_4_COMPLETION_PLAN.md`, `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`, `CODE_HYGIENE_AUDIT.md`, `LEGACY_DELETION_CANDIDATES.md`, and `PLANNING_INDEX.md`.
- Roadmap sequence corrected: Stage3_4/TLTM judgment -> temporary characterization baseline -> core numerical canonicalization -> official canonical baseline freeze -> repo-wide modernization.
- M0 planning artifacts are initially complete; no source edits or jobs were performed.

## M1 characterization update - 2026-05-08 JST
- Stage3_4 128seed/100k p28 RG report is available and characterized.
- Added `runbooks/M1_TEMPORARY_CHARACTERIZATION_BASELINE.md`.
- Added `runbooks/M2_CORE_CANONICALIZATION_QUEUE.md`.
- Added `state/M1_CHARACTERIZATION_METRICS_20260508.tsv`.
- Key primary characterization: `fb_norefine` reduces unresolved failures from 946129 to 224439 versus `no_fb`, increases RG rejects from 136997 to 200447, and increases mean runtime by about 1680 seconds per seed.
- This is temporary characterization, not official canonical baseline freeze.

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine is a deletion candidate and should not be part of the final canonical p28 route unless explicitly re-promoted later.
- M2c implementation may remove or disable post-refine after comparison harness coverage.

## Canonical flow backend decision - revised 2026-05-09
- User accepted the solver-assist validation observation: pure ODEX-only should not be the final policy because it introduces avoidable solver robustness loss.
- Current canonical candidate: ODEX primary integration, solver-internal ODE assist for NT/QN residual evaluation, strict final proposal flow.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and final-proposal rescue acceptance remain deletion candidates.
- Any deletion/refactor must preserve explicit residual-assist semantics and prove final proposal strictness.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- Until that validation gate passes, DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants remain legacy/quarantine candidates rather than approved deletions.

## M2 execution policy - 2026-05-08 JST
- Non-ODEX cleanup before ODEX-only is limited to behavior-neutral canonical route documentation, legacy/quarantine labeling, dependency inventory, and test planning.
- ODEX-only is the first numerical canonicalization step expected to possibly change trajectories; it requires staged 10k -> 50k -> 100k validation focused on physical observables and diagnostics.
- Added `runbooks/M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md` and `runbooks/ODEX_ONLY_STAGED_VALIDATION_PLAN.md`.
- No Fortran source edits have been performed for this policy step.

## ODEX-only source policy change - 2026-05-08 JST
- Updated `src/physics/solve_flow.f90` so the production `intode` failure path no longer enables Radau rescue or final-resort acceptance.
- Legacy Radau/JFNK routines remain in source as quarantine/reference code until staged validation approves deletion.
- No production job was submitted for this change.

## Retained-core correctness audit correction - 2026-05-08 JST
- User identified a critical gap: prior audits emphasized which legacy/rescue paths to disable, but did not yet prove that the retained five core numerical implementations are correct.
- Added `runbooks/M2_CORE_NUMERICAL_IMPLEMENTATION_AUDIT_PLAN.md`.
- ODEX-only 10k -> 50k -> 100k validation is now blocked until retained ODEX, simplified Newton, RATTLE, QN p28 loss, and HMC/Metropolis/RG boundary code are accepted for staged validation.
- No production job was submitted for this correction.

## M2 retained-core audit completion - 2026-05-08 JST
- Added `runbooks/M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`.
- Static source-level retained-core audit is complete enough for user discussion.
- ODEX-only staged validation remains blocked until the identified bug candidates and derivation/signoff items are resolved.
- Key blockers/signoff items: inverse-flow semantics are clarified as reversed RHS under nonnegative production flow time; remaining items are ODEX signed-interval robustness, simplified Newton residual/update now matched to GT-HMC but still needing replay/normalization tests, QN p28 residual signoff against the original formulation, `x(2)`-only RATTLE progress guard, and reverse-gate replay diagnostic accounting.
- No production job was submitted for this audit.

## Inverse-flow clarification - 2026-05-08 JST
- User confirmed `flowzr` is the inverse flow of `flow`.
- Audit wording was corrected: current `flowzr` reverses the RHS with nonnegative production flow time, so signed `calculate_wk` is not evidence of wrong current inverse-flow behavior.
- `calculate_wk` remains a latent/general ODEX robustness issue if negative integration intervals are ever supported.

## Simplified Newton GT-HMC mapping - 2026-05-08 JST
- Checked GT-HMC simplified RATTLE equations from `2311.10663v4.pdf`, especially Eqs. (3.37)-(3.44).
- Code residual `B = z + del_z - ld - flowz(xt+u)` matches the paper's `B = z + Delta z - lambda - znew` when `del_z=Delta z` and `ld=lambda`.
- `solve_projected_step` matches the paper decomposition `B = E B0,v + Bn`, with `Delta u = B0,v` and `Delta lambda = Bn`.
- Remaining checks are deterministic residual replay, `del_z`/`partial V` normalization, and ensuring the Jacobian is the fixed base Jacobian required by simplified Newton.

## Reference-backed retained-core re-audit - 2026-05-08 JST
- Added `runbooks/M2_REFERENCE_BACKED_CORE_AUDIT.md`.
- The earlier retained-core audit is now explicitly marked as a source-level risk scan, not final reference-backed signoff.
- Key correction: simplified Newton signs and `Delta z` normalization match GT-HMC/TLTM for unit mass.
- Key correction: active p28 QN residual is BTN/backflow rescue after standard Newton failure, not standard `(u,lambda)` residual.
- ODEX sequence decision: use Hairer ODEX `IWORK(3)=3` (`2,4,6,8,12,16,24,32,...`); current sequence is legacy until updated/tested.
- ODEX-only long validation remains blocked pending these decisions and deterministic replay tests.

## ODEX sequence decision - 2026-05-08 JST
- User selected Hairer ODEX `IWORK(3)=3` as the canonical modernization sequence.
- Target sequence: `2,4,6,8,12,16,24,32,...`.
- Current code sequence `2,4,6,12,18,36,...` is now legacy.
- Future implementation must update `build_nsteps` and `calculate_ak` together, clean signed-interval/work-estimate robustness in the same patch, and run ODE solver self-consistency tests before ODEX-only long validation.
- Radau/JFNK/final-resort code should be kept in the easiest later-deletion quarantine form: explicit disabled entry points/switches, no hidden production fallback.

## QN p28 BTN sign convention - 2026-05-08 JST
- User confirmed p28 should be treated as BTN/backflow rescue after standard Newton failure.
- Historical sign convention before the source cleanup had `xi1=-b`, `xi2=-a`; modernization target is paper variables `xi1=b`, `xi2=a`.
- Source cleanup is now implemented: correction uses `-J*(xi2+i*xi1)`, and `initial_guess_from_jacobian` solves `J dz=+del_z`.
- Older planning text saying p28 is a standard `(u,lambda)` residual is superseded by the reference-backed audit.

## QN p28 paper-variable decision - 2026-05-08 JST
- User requested BTN variables follow the paper directly.
- Implemented target: `xi1=b`, `xi2=a`.
- Implemented residual correction: `residual_jlc = -J*(xi2 + i*xi1)`.
- Implemented initial guess: solve `J dz = +del_z`, then `xi1=Im(dz)`, `xi2=Re(dz)`.
- `Jl`/recovery continue treating `Jl` as the actual correction added to `z+del_z`; no extra recovery sign flip is applied.
- Optional post-refine seed mapping was updated to use `ld0=b_qn` under paper variables; canonical p28 remains no-refine.

## BTN validation policy - 2026-05-08 JST
- User decided not to require old-convention/new-convention regression equivalence for BTN variable cleanup.
- Required validation is the BTN residual contract itself: after convergence, build `ztrial = z + del_z + Jl`, verify `Imag(flowzr(ztrial))` is small, and verify the second residual block `a` is small.
- `Jl`/recovery should be judged by whether this reconstructed `ztrial` satisfies the inverse-flow manifold condition, not by matching a previous coordinate convention.

## State representation / RATTLE progress decision - 2026-05-08 JST
- User identified that `state_has_progress` cannot be repaired cleanly as a single-line RATTLE fix because the whole codebase encodes `x(1)` as flow time and `x(2:)` as physical seed/state.
- Current `x(2)`-only progress guard is therefore a state-layout symptom and should be marked legacy/diagnostic, not promoted as a publishable algorithmic criterion.
- Short-term proposal validity should rely on solver convergence, constraint residual contract, reverse gate, and Metropolis rejection boundary.
- Long-term modernization should introduce typed state/workspace APIs separating `flow_time` from physical coordinates, then migrate kernels away from implicit positional indexing.

## Failure-as-rejection MCMC policy - 2026-05-08 JST
- User decided failure-as-rejection is the project policy and can be a valid MCMC transition boundary.
- Conditions to preserve: failed proposal/integration/projection/RG paths set `accept=.false.` or `proposal_ok=.false.`, live chain state is updated only when `accepted=.true.`, and successful proposals retain the required constraint/reverse-gate checks before Metropolis acceptance.
- Failed proposal output buffers may contain partial/intermediate values; this is acceptable only because callers must not commit them to live state on rejection.
- Publishable documentation should phrase failure as a stay-put event in the marginal chain, replacing the paper's momentum-flip/replacement fallback at the implementation boundary.

## Reverse gate proposal-boundary decision - 2026-05-08 JST
- User confirmed reverse gate is part of the proposal definition, not a debug-only diagnostic.
- Reverse-gate failure is handled as proposal failure and therefore as failure-as-rejection/stay-put in the marginal chain.
- Accepted proposals must satisfy the reverse-gate contract; rejected/RG-failed proposals must not update live chain state.

## Diagnostics/counters modernization decision - 2026-05-08 JST
- User confirmed diagnostic accounting must be repaired, but not as a narrow reverse-gate replay patch.
- The current count/capture/switch design is patchwork across ODE, QN, RATTLE, reverse gate, probes, rescue/failure paths, and Stage2 output contracts.
- Future modernization should introduce a typed diagnostics/accounting context that separates forward proposal work, reverse-gate replay, probes/debug, rescue attempts, failed proposal work, accepted-proposal counters, and output-schema reporting.
- Until the redesign, benchmark/validation reports must state whether counters include replay/probe/failure work.

## ODEX canonicalization scope decision - 2026-05-08 JST
- User selected synchronous cleanup for ODEX canonicalization: Hairer `IWORK(3)=3` sequence, matching `calculate_ak`, and signed-interval/work-estimate robustness should be handled together.
- Pre-long-validation test target is ODE solver self-consistency, not old/new trajectory equality: analytic ODE convergence/order sanity, step subdivision consistency, inverse/round-trip checks where applicable, and failure classification sanity.
- Radau/JFNK/final-resort legacy code should be arranged in the most convenient later-deletion form: isolated quarantine with explicit disabled entry points/switches and no hidden production fallback.

## ODEX canonicalization implementation - 2026-05-08 JST
- Implemented Hairer ODEX `IWORK(3)=3` step sequence in `src/physics/solve_flow.f90`: `2,4,6,8,12,16,24,32,...`.
- `build_nsteps` and `calculate_ak` now share `odex_iwork3_nstep`, so the extrapolation sequence and work-estimate cost model cannot silently diverge.
- `calculate_wk` now uses `abs(h)` for the positive work measure and guards non-finite/tiny candidate steps; `calculate_hk` remains signed so integration direction is unchanged.
- Local checks passed: `git diff --check`; build of `../bin/scan_flow_vs_flowz` and `../bin/scan_flowzr_stability`; `flowz`/`flow` 21-point scan with max `|delta z| = 5.00e-16`; `flowzr` signed roundtrip 81/81 with max roundtrip `4.42e-15`; 2-cycle local `test_tltm_stage2` smoke.
- No production job was submitted. Long ODEX-only validation still requires the planned 10k -> 50k -> 100k physical-observable sequence.

## ODEX solver-level analytic check - 2026-05-08 JST
- Added `tests/test_odex_solver.f90` plus `scripts/run_odex_solver_check.sh` as the preferred pre-tolerance-tuning ODE solver test.
- The test calls `intode` directly with module-level RHS callbacks to avoid GNU Fortran internal-procedure trampoline issues under `-Wl,-z,noexecstack`.
- Coverage: scalar exponential forward/backward integration, harmonic oscillator forward/backward integration, full-step vs two-half-step consistency for both systems, and zero fallback attempts/failures.
- Local run passed at `abs_tol=rel_tol=3.0e-14`: max observed analytic/split errors were `5.33e-15` or smaller for exponential/backward checks, `7.77e-16` or smaller for oscillator checks, and fallback attempts/failures were 0.

## ODEX TLTM-wrapper preflight and 10k protocol - 2026-05-08 JST
- Added `scripts/run_odex_flow_wrapper_check.sh` for TLTM-specific flow wrapper checks using existing `scan_flow_vs_flowz` and `scan_flowzr_stability` apps.
- Local wrapper check passed for flow times `0.1` and `0.3`: `flowz/flow` success 21/21 for both, `flowzr` roundtrip success 81/81 for both, fallback attempts/failures 0/0.
- Observed wrapper maxima: `max|flowz-flow| = 5.00e-16` at t=0.1 and `1.31e-13` at t=0.3; max roundtrip errors `4.42e-15` at t=0.1 and `1.39e-14` at t=0.3.
- Added `runbooks/ODEX_10K_VALIDATION_PROTOCOL.md`; no production job was submitted.

## Current discussion scope - 2026-05-08 JST
- User narrowed the active discussion scope back to the five retained core numerical blocks.
- Typed state API redesign, diagnostics context redesign, repo-wide module/API cleanup, utilities/RNG/I/O/output-schema modernization, and broader productization remain recorded as future modernization blocks, but should not drive the immediate discussion sequence.

## QN invalid-evaluation handling - 2026-05-09 JST
- Implemented QN/DFO failure signaling cleanup in `src/sampler/quasi_newton_solver.f90`: invalid constraint evaluations now return `ierr=.true.` with neutral `fq=0`/`Jl=0`, rather than artificial `fq=1e10`.
- Initial evaluation retry seeds now use `x=0`, matching the user decision that failed trust-region attempts should not poison later retries.
- This is an error-handling/code-design change, not a physics-model change; failed solver attempts remain proposal failures/rejections unless a later valid trial converges and passes reverse gate/Metropolis.
- The pending ODEX scale-up jobs were stopped because they predated this QN change and must be regenerated after the new QN handling is validated.

## QN error-handling 10k validation - 2026-05-09 JST
- Dedicated validation branch/worktree: `codex/qn-error-handling-validation` at commit `7b2971c`.
- Initial validation job completed the 10 seed x 10k stage2 trajectories but failed during final evaluation because the PBS script had built only `run_tltm_stage2`, not `evaluate_expectations`.
- Workflow was fixed so future validation PBS builds both required binaries; an evaluation-only recovery wrapper was added to reuse completed stage2 outputs without rerunning trajectories.
- Recovery PBS job `14323.anode01` completed successfully with `Exit_status=0`.
- Artifacts: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/tests/qn_error_handling/20260509_10seed_10k_fb_norefine_ct1e13_qn1e13/`.
- Aggregate result: `mean Re<O>=-0.0386029170`, `mean Im<O>=0.0183377376`, `Zmean Re=-0.491730824`, `Zmean Im=0.576115891`, unresolved failures `2521`, projection failures mean `408.5`, reverse-gate rejects `1564`, pair0 accept rate `0.44008`.
- This is the first 10k check after the QN invalid-evaluation cleanup. It is not a 50k/100k signoff.
- Immediate priority: complete decisions/signoff prerequisites for ODEX, simplified Newton, RATTLE, QN p28/BTN, and HMC/Metropolis/reverse-gate before moving to other cross-cutting refactors.

## ODEX 10k baseline supersession - 2026-05-09 JST
- User correctly identified that the original `ODEX_10K_VALIDATION_RESULT_20260508.md` predates the QN invalid-evaluation handling cleanup and should not govern forward ODEX scale-up.
- The 2026-05-08 ODEX 10k result is now marked superseded/historical only.
- The QN-clean 10k result was copied into the active ODEX validation namespace at `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`.
- Added `runbooks/ODEX_10K_VALIDATION_RESULT_20260509_QNCLEAN.md` as the active 10k ODEX baseline for the next 50k gate.
- Raw historical output was not deleted; a supersession marker was written beside the old 2026-05-08 output so future work does not confuse it with the active baseline.

## QN-clean promotion and ODEX scale-up submission - 2026-05-09 JST
- Promoted QN-clean state into the canonical `codex/preprod-hardening` branch without force-pushing. Merge/promotion commit: `4bd26b3`; PBS scale-up commit: `5b93aaa`.
- Updated the production worktree `/lustre1/home/cychou/TLTM` (`/home/cychou/TLTM` resolves to the same path) to `5b93aaa`.
- Copied the active QN-clean 10k baseline into the production ODEX namespace: `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`.
- Cleaned stale build module/object cache and rebuilt `bin/run_tltm_stage2` plus `bin/evaluate_expectations` with `compiler/2025.3.0`, `mpi/2021.17`, and `mkl/2025.3`.
- Submitted refreshed QN-clean ODEX scale-up jobs from the canonical production worktree:
  - 32seed x 50k job: `14324.anode01`, output `output/tests/odex_validation/20260509_32seed_50k_qnclean_fb_norefine_ct1e13_qn1e13`.
  - 128seed x 100k chunks: `14325.anode01` through `14332.anode01`, offsets `0,16,32,48,64,80,96,112`.
  - 100k merge dependency job: `14333.anode01`, held on `afterok` of all eight chunks.
- The side worktree `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation` is no longer the active source of truth; it remains only as temporary historical/backup context until the refreshed ODEX validation finishes.

## QN-clean ODEX 50k/100k completion - 2026-05-09 JST
- Refreshed QN-clean ODEX validation completed successfully and produced reports for 32seed x 50k and 128seed x 100k.
- 50k result: `mean Re<O>=-0.0190826825`, `mean Im<O>=0.0037547361`, `Zmean Re=-1.450635`, `Zmean Im=0.567061`, unresolved failures `40715`, reverse-gate rejects `24986`, mean pair0 accept `0.438705`.
- 100k result: `mean Re<O>=0.0017729074`, `mean Im<O>=-0.0005999719`, `Zmean Re=0.385239`, `Zmean Im=-0.200998`, unresolved failures `326569`, reverse-gate rejects `202530`, mean pair0 accept `0.438907`.
- ODE failure-boundary counters: 100k fallback attempts `2862514`, success `0`, failure `2862514`, invalid `0`, h-min `2862168`, max-steps `346`.
- Compared with the pre-ODEX 128seed/100k `fb_norefine` characterization, ODEX-only increases unresolved failures by `102130` and projection failures by `104213`, but physical observables remain compatible with zero and RG/acceptance diagnostics remain stable.
- Judgment recorded in `runbooks/ODEX_50K_100K_VALIDATION_RESULT_20260509_QNCLEAN.md`: staged ODEX-only validation passes the physical-observable gate, with higher failure counters documented as the expected failure-as-rejection tradeoff.

## QN p28 BTN source cleanup - 2026-05-08 JST
- Implemented the first M2 core source patch for QN p28/BTN paper variables.
- Changed `evaluate_constraint_residual` to build `ztrial = z + del_z - J*(a+i*b)` with `xi1=b`, `xi2=a`.
- Changed `initial_guess_from_jacobian` to solve `J dz=+del_z` for the paper-variable seed.
- Kept `Jl` recovery semantics unchanged: `Jl` is the actual correction used in `ztrial = z + del_z + Jl`.
- Updated optional post-refine seed mapping to use `ld0=b_qn`; canonical p28 remains no-refine.
- Verified by rebuilding `../bin/replay_quasi_failures` and running a 2-cycle local `test_tltm_stage2` smoke; no production job was submitted.

## QN p28 BTN contract verification - 2026-05-08 JST
- Added BTN contract diagnostics to `src/apps/replay_quasi_failures.f90`: `btn_contract_ok`, `btn_flow_im_norm`, and `btn_a_norm`.
- Diagnostic reconstructs `ztrial = z + del_z + Jl`, calls `flowzr(ztrial)`, and reports `max|Imag(flowzr(ztrial))|` plus `max|a|` from the paper-variable solution.
- Local replay on `output/production/constraint_solver_fail_{z0,delz,x0}.dat` with `tol=1e-13`, `max_iter=28` produced 26/26 solver successes and 26/26 BTN contract OK.
- Observed maxima: `max|Imag(flowzr(ztrial))| = 6.77e-14`, `max|a| = 6.72e-16`, `max min_res = 6.77e-14`.
- Output CSV was written under ignored test output (`output/tests/btn_contract/replay_btn_contract_p28.csv`); no production job was submitted.

## ODEX 10k validation result - 2026-05-08 JST
- Completed ODEX-only 10seed/10k `fb_norefine` validation on commit `ae234a2` with p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`.
- Result artifacts are under `output/tests/odex_validation/20260508_10seed_10k_fb_norefine_ct1e13_qn1e13`.
- Aggregate observable readout remains compatible with the target: mean `Re<O> = -0.0386029`, mean `Im<O> = 0.0183377`, `Zmean Re = -0.491731`, `Zmean Im = 0.576116`.
- Acceptance and reverse-gate diagnostics are stable relative to the closest 10seed/10k baseline: pair0 accept `0.44008` vs `0.43984`; reverse-gate rejects `1566` vs `1585`.
- Projection/unresolved failures increased relative to the closest baseline (`2519` vs `1769` unresolved; mean projection failures/seed `408.5` vs `335.4`), so these are required 50k watch items.
- ODEX-only fallback semantics are active as expected: fallback success is `0`, invalid fallback count is `0`, and fallback failures are almost entirely h-min classified (`21761/21762`) with one max-step-classified failure.
- Judgment recorded in `runbooks/ODEX_10K_VALIDATION_RESULT_20260508.md`: provisional pass to matching 50k validation, not final physics signoff.

## ODEX 50k/100k validation submission - 2026-05-08 JST
- Added and submitted matching ODEX-only `fb_norefine` scale-up jobs from commit `4b5b99a`.
- 50k job: `14306.anode01`, PBS `codex/workspaces/fortran_modernization/tasks/pbs/odex_50k_validation_20260508_fb_norefine.pbs`, config `docs/stage_3_4_t035_paired_10seed_50k_rg.json`.
- 100k job: `14307.anode01`, PBS `codex/workspaces/fortran_modernization/tasks/pbs/odex_100k_validation_20260508_fb_norefine.pbs`, config `docs/stage_3_4_t035_paired_10seed_100k_rg.json`.
- Both jobs use 10 matched seeds, p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`, `jobs=20`, `stage2_threads=1`, `eval_threads=1`.
- Output directories:
  - `output/tests/odex_validation/20260508_10seed_50k_fb_norefine_ct1e13_qn1e13`
  - `output/tests/odex_validation/20260508_10seed_100k_fb_norefine_ct1e13_qn1e13`
- Log directories:
  - `output/logs/odex_validation/20260508_10seed_50k_fb_norefine_ct1e13_qn1e13`
  - `output/logs/odex_validation/20260508_10seed_100k_fb_norefine_ct1e13_qn1e13`
- At submission check, both jobs were running on C12 with start time `2026-05-08 23:44 JST`; requested walltimes are 4h for 50k and 8h for 100k.
- ETA from the 10k measured walltime is approximately 60-75 minutes for 50k and 2-2.5 hours for 100k, assuming similar node behavior.

## ODEX 50k/100k scale-up correction - 2026-05-08 JST
- Correction: the first submitted 50k/100k jobs used only 10 seeds and did not match the original Stage3_4 scale-up seed counts.
- Cancelled incorrect jobs:
  - `14306.anode01` (`odex50k_fbnr`), cancelled after about 2m48s, `Exit_status=271`.
  - `14307.anode01` (`odex100k_fbnr`), cancelled after about 2m48s, `Exit_status=271`.
- Removed the incorrect 10seed scale-up PBS/config files from HEAD and cleaned their partial 10seed 50k/100k output/log directories.
- Corrected script commit: `334e114`.
- Correct 50k validation now matches the original intermediate scale: 32 seeds x 50k cycles, `fb_norefine` only.
  - Job: `14308.anode01`
  - PBS: `codex/workspaces/fortran_modernization/tasks/pbs/odex_32seed_50k_validation_20260508_fb_norefine.pbs`
  - Config: `docs/stage_3_4_t035_paired_32seed_50k_rg.json`
  - Output: `output/tests/odex_validation/20260508_32seed_50k_fb_norefine_ct1e13_qn1e13`
  - Logs: `output/logs/odex_validation/20260508_32seed_50k_fb_norefine_ct1e13_qn1e13`
- Correct 100k validation now matches the original final gate seed count: 128 seeds x 100k cycles, `fb_norefine` only, split into 8 chunks x 16 seeds.
  - Chunks: `14309.anode01` offset 0 C8, `14310.anode01` offset 16 C8, `14311.anode01` offset 32 C8, `14312.anode01` offset 48 C8, `14313.anode01` offset 64 G, `14314.anode01` offset 80 G, `14315.anode01` offset 96 G, `14316.anode01` offset 112 F.
  - Merge dependency job: `14317.anode01`, `afterok` on all 8 chunks.
  - PBS: `codex/workspaces/fortran_modernization/tasks/pbs/odex_128seed_100k_validation_20260508_fb_norefine_chunk.pbs`
  - Merge PBS: `codex/workspaces/fortran_modernization/tasks/pbs/odex_128seed_100k_validation_20260508_fb_norefine_merge.pbs`
  - Config: `docs/stage_3_4_t035_paired_128seed_100k_rg_nofb_fbnorefine.json`
  - Output root: `output/tests/odex_validation/20260508_128seed_100k_fb_norefine_ct1e13_qn1e13`
  - Logs root: `output/logs/odex_validation/20260508_128seed_100k_fb_norefine_ct1e13_qn1e13`
- At submission check, `14308` and all 8 compute chunks `14309`-`14316` were running; merge job `14317` was held by dependency as intended.

## QN invalid-evaluation handling and ODEX scale-up stop - 2026-05-09 JST
- User clarified that QN/DFOLS trust-region failures are valid trial failures, but must not be encoded as artificial residuals that can pollute the model or progress logic.
- Implemented QN evaluator contract cleanup: invalid constraint/flow evaluations now return neutral `fq=0`, `Jl=0`, and `ierr=.true.` via `mark_constraint_eval_invalid`; solver logic must branch on `ierr`/`eval_ok`, not sentinel residual magnitude.
- Changed the non-paper-exact initial-evaluation retry seed in DFO-LS, DFO-GN/Broyden, and non-paper DFO-GN paper-attempt fallback from `x=xt` to `x=0`.
- Preserved trace semantics: failed trials are still recorded as `eval_ok=.false.` and cannot count as accepted progress.
- Local verification: rebuilt `../bin/run_tltm_stage2` successfully in the dedicated QN validation worktree.
- Stopped the in-flight ODEX-only scale-up because QN error handling changes invalidate it as the next comparison gate. Cancelled `14308`-`14316`; cancelled held merge `14318`. The scale-up will be rerun from the QN-cleaned state after a fresh 10k validation.
- Added PBS `codex/workspaces/fortran_modernization/tasks/pbs/qn_error_handling_10k_validation_20260509_fb_norefine.pbs` for a fresh 10seed x 10k `fb_norefine`, p28, reverse-gate, post-refine-off validation at `ct=1e-13`, `QN=1e-13`.

## Local transition counter split - 2026-05-09 JST
- Implemented the next state/information propagation slice: Stage1/Stage2 local transitions now record detailed Metropolis transition-status counters while preserving old accept/reject and `projection_failure_count` semantics.
- Added lightweight `markovchain_transition_status` module so transition-status constants are shared without making TLTM type definitions depend on the Metropolis implementation module.
- Added counters for ordinary Metropolis rejection, reverse-gate rejection, proposal construction failure, invalid Hamiltonian, invalid `Delta H`, and output-size mismatch.
- Stage1/Stage2 summary rows append the new counters after legacy columns; Stage2 also writes `# local_transition_totals ...` for robust parser consumption.
- RG reject audit CSV now includes `transition_status`, so future analysis can distinguish reverse-gate rejection from other failed-proposal modes without overloading `proposal_failed`.
- `scripts/run_stage3_3_multiseed.py` and `scripts/merge_stage3_multiseed_chunks.py` now carry the new local transition counters through per-seed and aggregate CSV output.
- Behavior-preservation note: no proposal, reverse-gate, Metropolis acceptance, RNG, or live-state update logic was changed; this patch is output/status observability only.
- Verification passed: `python3 -m py_compile ...`; `git diff --check`; `make -C build FC=gfortran LDFLAGS= test1`; Stage1/Stage2 executable build; tiny local Stage2 smoke and parser readback of the new counters.

## ODE/flow status surface - 2026-05-09 JST
- Implemented the next state/information propagation slice: `intode`, `flowz`, `flowzr`, and `flow` now expose optional integer status outputs while preserving the existing `logical error_flag` callers.
- New `intode_status_*` values distinguish strict ODEX success, zero-time no-op success, legacy stiff-rescue success, solver-internal assist success, and failures from max-step, invalid-state, or h-min boundaries.
- Added the existing ODEX analytic test to the build as `make test_odex_solver` and extended it to assert status values.
- Behavior-preservation note: ODEX/Radau/assist decisions, fallback counters, final proposal strictness, and all existing callers remain unchanged; the status is a contract surface for later patches.
- Verification passed: `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `git diff --check`; `make -C build FC=gfortran LDFLAGS= test1`; Stage1/Stage2 executable build; tiny local Stage2 smoke.

## Strict final proposal flow gate - 2026-05-09 JST
- Implemented the next state/information propagation slice: RATTLE final proposal `flow(...)` now consumes the optional ODE/flow status.
- Only strict ODEX success and zero-time no-op are accepted as final proposal flow success; max-step, invalid-state, h-min, and unexpected non-strict success statuses become explicit final-flow step failures.
- Proposal-level compatibility is preserved by mapping these detailed step statuses back to the existing final-flow failure category in `hmc.f90`.
- Behavior-preservation note: current canonical paths should be unchanged because solver-internal assist is already gated to Newton/QN residual contexts and stiff rescue is disabled; the patch fails closed if a future legacy path tries to finalize a proposal through non-strict flow.
- Verification passed: `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `git diff --check`; `make -C build FC=gfortran LDFLAGS= test1`; Stage1/Stage2 executable build; tiny local Stage2 smoke.

## QN residual flow-status counters - 2026-05-09 JST
- Implemented the next state/information propagation slice: QN residual evaluators now request optional ODE/flow status from `flowzr(...)` and `flowz(...)`.
- Added counters for strict success, zero-time success, stiff rescue, solver assist, max-step failure, invalid-state failure, h-min failure, and unknown status.
- Stage1/Stage2 summaries now write `# qn_eval_flow_status ...`; multiseed run/merge scripts carry the new per-seed and aggregate columns.
- Behavior-preservation note: this is observability only. `ierr` remains the behavior-bearing residual validity signal, and trust-region, line-search, acceptance, reverse-gate, RNG, and final proposal logic are unchanged.
- Verification passed: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke, and parser readback of the new columns.

## Strict initialization flow gate - 2026-05-09 JST
- Implemented the next state/information propagation slice: Stage1/Stage2 initialization now requests optional `flow(...)` status and accepts only strict ODEX success or zero-time no-op.
- Added shared helper `intode_status_is_strict_success(...)` in `solve_flow.f90`; HMC final proposal flow now uses the same helper instead of a private duplicate.
- Behavior-preservation note: current canonical strict ODEX and zero-time initialization paths are unchanged. Non-strict solver-assist or legacy rescue success is fail-closed for initialization, matching the final physical proposal boundary.
- Verification passed: `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, Stage1/Stage2 executable build, `make -C build FC=gfortran LDFLAGS= test1`, and tiny local Stage2 smoke.

## Strict physical flow call sites - 2026-05-09 JST
- Implemented the next state/information propagation slice: remaining physical-state `flow(...)` call sites now consume optional status and require strict success.
- Updated generic Markov-chain initial flow, warmup reflow, adaptive preflow trial flow, and Stage2 adjacent-swap reflow candidates.
- Behavior-preservation note: canonical strict ODEX/zero-time paths are unchanged. Solver-internal assist remains confined to residual-evaluation contexts and cannot construct live chain, warmup, preflow, swap, initialization, or final proposal states.
- Verification passed: `git diff --check`, Stage1/Stage2 executable build, `make -C build FC=gfortran LDFLAGS= test1`, and tiny local Stage2 smoke with swap enabled.

## Newton residual flow-status counters - 2026-05-09 JST
- Implemented the next state/information propagation slice: simplified Newton residual `flowz(...)` calls now request optional ODE/flow status and record diagnostic counters.
- Added Stage1/Stage2 `# newton_eval_flow_status ...` summary lines; multiseed run/merge scripts carry the new per-seed and aggregate CSV columns.
- Behavior-preservation note: Newton convergence, failure returns, line-search/rescue behavior, and HMC/RATTLE acceptance logic are unchanged. `solve_failed` remains the behavior-bearing signal.
- Verification passed: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke, and parser readback with observed Newton zero-time residual-flow counts.

## Reverse-gate replay status counters - 2026-05-09 JST
- Implemented the next state/information propagation slice: reverse-gate replay now records the nested `rattle_step_core(...)` step status.
- Added Stage1/Stage2 `# reverse_gate_replay_status ...` summary lines; multiseed run/merge scripts carry the new per-seed and aggregate CSV columns.
- Behavior-preservation note: RG replay, tolerance comparison, pass/reject decision, and counter suppression semantics are unchanged. The new counters describe replay construction status, not the tolerance comparison outcome.
- Verification passed: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke/parser readback, and RG-enabled tiny smoke observing `reverse_gate_replay_success=80`.

## Source hygiene cleanup - 2026-05-09 JST
- Removed tracked backup artifact `src/sampler/hmc_integrator_core.f90.bak_codex_20260429`.
- Behavior-preservation note: the file was not a build source and only polluted source search/audit results.
- Verification: `rg --files src | rg "bak|backup|copy|old|legacy"` no longer reports tracked backup source artifacts.

## Test strict-flow contract cleanup - 2026-05-09 JST
- Updated `tests/test_hamiltonian_conservation.f90` so initial flow requests optional ODE status and requires strict success.
- Behavior-preservation note: this changes only the test guard; successful strict ODEX initialization and the Hamiltonian convergence calculation are unchanged.
- Verification passed: `git diff --check` and `make -C build FC=gfortran LDFLAGS= test1`.

## Legacy diagnostic and post-refine deletion - 2026-05-09 JST
- Deleted the tracked root-level Fortran copies `hmc_integrator_core.f90` and `constraint_solver_stats.f90`; they were not build sources and polluted source search/audit.
- Deleted standalone diagnostic apps and build targets: `sample_flow_manifold`, `replay_quasi_failures`, `probe_hmc_volume`, `scan_flow_vs_flowz`, and `scan_flowzr_stability`.
- Deleted helper scripts that depended on those removed diagnostic binaries, and removed the replay command section from `docs/commands.md`.
- Removed the post-refine executable path from HMC/QN fallback: no `QN_POST_NEWTON_REFINE_*` environment controls remain in active `src/`, no post-refine solver attempt/capture code remains, and Stage2/multiseed output schemas no longer report post-refine counters.
- Preserved the canonical p28 QN route as fallback-enabled without post-refine; the `fb_norefine` method name remains as a compatibility alias in the Stage3 runner.
- Behavior-preservation note: production proposal physics, ODEX/RATTLE/HMC acceptance logic, reverse gate decisions, RNG, and live-state updates were not intentionally changed by the deletion. Removed Newton `rescue_mode` branches were unreachable from active callers and corresponded to the deleted post-refine/newton-rescue path.
- Verification passed: `python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/merge_stage3_multiseed_chunks.py scripts/fortran_module_deps.py`; `git diff --check`; production executable build; `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `make -C build FC=gfortran LDFLAGS= test1`; tiny Stage2 smoke with explicit `TLTM_STAGE2_INIT_SIGMA=0.1`.
- Follow-up decision needed: Stage2 currently has an existing aliasing hazard in `parse_real_env("TLTM_STAGE2_INIT_SIGMA", init_sigma, init_sigma)`. Without explicit `TLTM_STAGE2_INIT_SIGMA`, the local smoke printed `init_sigma=0.0000` and could fail initialization. Fixing this would change default initialization behavior for runs that do not set the variable, so it should be handled as a separate behavior-reviewed config/state cleanup.

## Stage env-parser default repair - 2026-05-09 JST
- Fixed the Stage1/Stage2 environment parser helper interface to keep defaults in the caller and overwrite only when a valid environment value is present.
- Removed same-variable default/output aliasing for `TLTM_STAGE1_*` and `TLTM_STAGE2_*` integer, real, and logical parser calls.
- Behavior-preservation note: runs that explicitly set these environment variables keep the same intended override behavior. Runs that omit them now receive the intended defaults instead of nonconforming alias-dependent values such as `init_sigma=0.0000`.
- Verification passed: `git diff --check`; no remaining three-argument parser calls in `src/sampler`; Stage1/Stage2 executable build; `make -C build FC=gfortran LDFLAGS= test_odex_solver`; tiny Stage1 smoke without `TLTM_STAGE1_INIT_SIGMA` observed `init_sigma=0.1000`; tiny Stage2 smoke without `TLTM_STAGE2_INIT_SIGMA` observed `init_sigma=0.1000`; explicit Stage2 override `TLTM_STAGE2_INIT_SIGMA=0.2` observed `init_sigma=0.2000`.
