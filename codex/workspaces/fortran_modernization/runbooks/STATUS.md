# Task Status: fortran_modernization

Updated: 2026-05-08 18:05 JST

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
- No Fortran source edits, production job submissions, or production worktree mutations have been performed for this modernization task.

## Current architecture understanding
- `solve_flow.f90` is flow mapping plus ODEX-like integration plus Radau/JFNK/final-resort policy plus diagnostics.
- `hmc_integrator_core.f90` is the central proposal hub: Newton, quasi fallback, post-refine, reverse gate, flow/Jacobian update, momentum projection, and solver statistics.
- `quasi_newton_solver.f90` mixes residual definitions, DFO-LS/DFO-GN/Broyden solver families, continuation/restart policy, traces, watchdog/final-resort budgets, and route counters.
- `tltm_stage2_driver.f90` owns production orchestration and output/counter contracts used by Stage3_4 interpretation.

## Next action
Discuss and confirm `runbooks/PLANNING_DISCUSSION_BRIEF.md`, especially:
- canonical BTN naming;
- canonical quasi route set;
- Stage2 output freeze policy;
- whether existing `output/tests` artifacts can seed formal baselines;
- reverse-gate and final-resort long-term status;
- whether thread-safety/reentrancy is an explicit modernization goal.

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
- Tentative long-term publishable target: ODEX-only flow backend.
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
