# Task Status: fortran_modernization

Updated: 2026-05-08 21:50 JST

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
Discuss and resolve `runbooks/M2_REFERENCE_BACKED_CORE_AUDIT.md`, especially ODEX step-sequence policy, QN p28 as BTN rescue, RATTLE failure/progress semantics, deterministic replay tests, and reverse-gate diagnostic accounting.

## After confirmation
- Build baseline harness design first.
- Do not start Fortran source modernization until affected baseline rows in `BASELINE_VERIFICATION_MATRIX.md` are satisfied.

## Quasi route decision - 2026-05-08 JST
- Production-canonical quasi route: current p28 path (`QN_S1_PROBE_MAX_ITER=28`) using DFO-LS on `evaluate_constraint_residual` after Newton failure.
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
- Canonical route: Newton -> QN S1 p28 DFO-LS standard residual -> reverse gate -> Metropolis.
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
- Key new blocker: current ODEX step sequence is not one of the Hairer ODEX listed sequences and needs policy decision or tests.
- ODEX-only long validation remains blocked pending these decisions and deterministic replay tests.
