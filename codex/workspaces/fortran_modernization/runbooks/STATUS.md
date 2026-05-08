# Task Status: fortran_modernization

Updated: 2026-05-08 23:25 JST

## Objective
- Define the governing principles, workstreams, milestones, and verification rules for systematic TLTM Fortran modernization.
- Keep behavior preservation explicit: engineering changes must not silently change the underlying physics or accepted reference outputs.

## Current state
- Initial modernization governance set established.
- Algorithm reference bundle is collected under `references/`, including TLTM HMC, simplified Newton/RATTLE/HMC, DFO-GN/DFO-LS, Hairer ODEX, and the user original quasi-Newton projection formulation.
- Planning-only low-level algorithm review set is complete enough for user discussion:
  - `runbooks/ODEX_FLOW_REVIEW_NOTES.md`
  - `runbooks/SIMPLIFIED_NEWTON_RATTLE_REVIEW_NOTES.md`
  - `runbooks/QUASI_NEWTON_PROJECTION_REVIEW_NOTES.md`
  - `runbooks/HMC_METROPOLIS_TLTM_REVIEW_NOTES.md`
  - `runbooks/BASELINE_VERIFICATION_MATRIX.md`
  - `runbooks/PLANNING_DISCUSSION_BRIEF.md`
- ODEX-only source policy has been implemented in `src/physics/solve_flow.f90`; no production job submissions have been performed for this modernization task.

## Current architecture understanding
- `solve_flow.f90` is flow mapping plus ODEX-like integration plus Radau/JFNK/final-resort policy plus diagnostics.
- `hmc_integrator_core.f90` is the central proposal hub: Newton, quasi fallback, post-refine, reverse gate, flow/Jacobian update, momentum projection, and solver statistics.
- `quasi_newton_solver.f90` mixes residual definitions, DFO-LS/DFO-GN/Broyden solver families, continuation/restart policy, traces, watchdog/final-resort budgets, and route counters.
- `tltm_stage2_driver.f90` owns production orchestration and output/counter contracts used by Stage3_4 interpretation.

## Next action
Next discussion after ODEX sequence decision: QN p28 as BTN rescue, RATTLE failure/progress semantics, deterministic replay tests, and reverse-gate diagnostic accounting.

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

## Flow backend direction decision - 2026-05-08 JST
- Canonical long-term publishable target: ODEX-only flow backend.
- Radau/JFNK/final-resort rescue stack is a legacy robustness layer/deletion candidate.
- No change before Stage3_4/TLTM judgment; after judgment, run fresh baseline and ODEX-only comparison before deletion.

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

## Canonical flow backend decision - 2026-05-08
- User confirmed ODEX-only as the canonical long-term flow backend target.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and ODE final-resort acceptance are deletion candidates.
- M2c implementation may remove or disable the rescue stack after flow-level characterization and ODEX-only comparison coverage.
- If ODEX-only failure rate is unacceptable, improve ODEX/step control/failure handling rather than preserving a hidden secondary integrator stack by default.

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
- Immediate priority: complete decisions/signoff prerequisites for ODEX, simplified Newton, RATTLE, QN p28/BTN, and HMC/Metropolis/reverse-gate before moving to other cross-cutting refactors.

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
