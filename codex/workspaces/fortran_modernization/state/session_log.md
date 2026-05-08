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
- Post-refine remains under observation and may also be removed depending on refine-vs-norefine evidence.

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
- 2026-05-08 JST: User selected Hairer ODEX `IWORK(3)=3` (`2,4,6,8,12,16,24,32,...`) as canonical sequence; current sequence is legacy until patched/tested.
- 2026-05-08 JST: Confirmed p28 QN as BTN/backflow rescue; sign convention is `xi1=-b`, `xi2=-a` (`a=-xi2`, `b=-xi1`).
- 2026-05-08 JST: Decided future p28 BTN code should use paper variables `xi1=b`, `xi2=a`; residual correction and initial guess RHS must both flip sign together.
