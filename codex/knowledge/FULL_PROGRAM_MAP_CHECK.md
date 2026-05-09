# Full Program Map Check

Updated: 2026-05-09 JST

Purpose: persistent full-program risk map for TLTM Stage3_3/Stage3_4 work. This file is intentionally independent of chat context.

## Program map
- Driver and reports: `scripts/run_stage3_3_multiseed.py` creates per-seed workdirs, writes `parameters.dat`, applies method env overrides, runs `bin/run_tltm_stage2`, runs `bin/evaluate_expectations`, and builds per-seed/aggregate reports.
- Config: `src/config/param_mod.f90` reads `parameters.dat`, validates config, and syncs legacy globals such as `cttol` and `quasi_fallback_enabled`.
- Stage2: `src/sampler/tltm_stage2_driver.f90` initializes replica slots, runs local HMC updates, writes history, attempts swaps, updates label traces, and writes summary counters.
- Metropolis/HMC: `src/sampler/markovchain_metropolis.f90` calls `integrate_hmc_proposal`; `src/sampler/hmc.f90` generates/project momenta and runs RATTLE steps.
- Constraint stage: `src/sampler/hmc_integrator_core.f90` does Newton first, then optional canonical p28 QN fallback, reverse gate, then returns to Metropolis.
- Newton loss: `src/sampler/hmc_constraints.f90` solves independent `u, ld` variables for the Newton/RATTLE constraint.
- QN loss: `src/sampler/quasi_newton_solver.f90` contains the retained p28 BTN/backflow rescue residual and DFO-LS-style solver machinery. Legacy DFO-GN/Broyden/global-continuation/post-refine routes have been removed from active source.
- Flow/model: `src/physics/solve_flow.f90` implements forward flow `flow/flowz` and inverse flow `flowzr`; `src/physics/model*.f90` defines action and derivatives.
- Counters/capture: `src/sampler/constraint_solver_stats.f90` owns solver/fallback/reverse-gate/status counters and failure capture; some legacy-compatible output labels remain for schema stability.
- Evaluation: `src/apps/evaluate_expectations.f90` reads binary histories and computes phase-reweighted observable means, robust errors, and diagnostics.

## Current high-priority risks
- QN fallback route selection is not yet proven volume-preserving or proposal-density-correct at publishable-proof level. Current Metropolis ratio remains `exp(-(H_final-H_initial))`. RG is a necessary guard but not by itself a proof for the piecewise Newton -> QN -> RG proposal map.
- Stage2 writes fixed max-flow-slot history before swap. This is a valid convention only if explicitly treated as the sampling definition; it can confuse first-N-cycle comparisons.
- `state_has_progress` checks only `x(2)`. This is acceptable for current one-dimensional physical state conventions, but unsafe for general multi-dimensional extensions.
- Many modules use `SAVE` or module-global workspaces. Current PBS process-level parallelism is okay, but OpenMP or in-process replica parallelism would be unsafe without refactoring.

## Fixed pre-production risks
- 2026-05-07: reverse-gate replay statistics are suppressed during the internal reverse `rattle_step_core` call. Outer forward proposals still record solver/failure counters, and outer RG candidate/pass/reject counters are still recorded. This prevents RG diagnostic replay from inflating production `failure` or `fallback_trigger` counts.
- 2026-05-09: post-refine, DFO-GN/Broyden/global-continuation, Radau/JFNK rescue, and root-level stale Fortran artifacts were deleted from active source after validation and user approval.
- 2026-05-07: reverse gate now compares carried `jac` in addition to `x/z/p`, using the same `QN_REVERSE_GATE_TOL`. This aligns the gate with the actual state consumed later by projection, phase, and swap energy.
- 2026-05-07: Metropolis no longer uses `h_final == 0` as the proposal-failure sentinel. HMC now returns an explicit `proposal_ok`; Metropolis rejects only failed or non-finite Hamiltonian proposals before computing the acceptance probability.
- 2026-05-07: Stage3 multiseed configs now fail fast if `warmup_cycles_optional != 0`, because the current Stage2/evaluation production path does not implement a separate discarded warmup window.
- 2026-05-07: each Stage3 seed/method run now writes `run_manifest.json` with the resolved method, setup, selected algorithm env vars, thread env vars, output paths, and isolated `parameters.dat` path.

## Current consistency checks
- TLTM/GTM measure split appears internally consistent for the baseline path: local HMC uses `Re(S)`, swap uses `Re(S)-Re(logdetJ)`, and final observable evaluation uses phase `exp(-i Im(S) + i Im(logdetJ))`.
- The report-level `Zmean` formula in `scripts/run_stage3_3_multiseed.py` matches the requested sample-standard-error denominator across seed means.
- Production smoke after pre-production fixes: local 1-replica, 1-cycle, RG-on Stage2 run completed; with `nstep=20`, `constraint_stats total=20` and `reverse_gate_route_candidates total=20`, confirming RG reverse replay no longer doubles solver counters in this smoke.
- Remote and local source-code file lists match for `src/`, `scripts/`, and `tests` over `*.f90`, `*.inc`, `*.py`, and `*.sh` as of this scan.

## Required next discussion before new 3_4 production
- Decide how to audit or enforce proposal symmetry/volume correctness for QN fallback route mixtures.
- Decide whether Stage2 history timing should remain "pre-swap fixed max-flow slot" or be changed/documented more explicitly.

## Active audit sequence
- Probe 1: deterministic/single-valued repeatability in `codex/workspaces/kernel_correctness_audit` completed as PASS on 2026-05-07 for one historical 500-cycle withfb/RG/p28/post-refine seed plus captured-case replay. This is historical evidence only; post-refine is no longer active.
- Probe 2a: captured failure-case replay reversibility returned report status FAIL, but this input source is not a valid accepted/successful proposal audit; use only as a failed probe design note.
- Probe 2b: successful-proposal reversibility audit `R(F(y)) = y` through the main HMC `[REVCHK]` hook completed as PASS on 2026-05-07. It checked 100 successful proposals: 4 fallback_used and 96 nonfallback, with max `dx/dz/dj/dp` all around `1e-11`.
- Probe 2c: RG-reject identity audit completed as PASS on 2026-05-07. It checked one historical 10k withfb/RG/p28/post-refine seed with 188 RG rejects; every positive RG-reject update had `accepted=F`, `proposal_failed=T`, zero live slot `x/z/jac` change, and CSV reject deltas matched Stage2 summary reject total. This is historical evidence only; post-refine is no longer active.
- Probe 3: local volume audit completed as PASS on 2026-05-07 for sampled branch-stable successful proposal points. The implementation uses 1D coordinates `(q,c)` with tangent momentum `p=J(q)c`, and checks metric-corrected `log|det d(q',c')/d(q,c)| + 2log|J_out| - 2log|J_in|`. It passed at eps `3e-5`, `1e-5`, and `3e-6`; each eps had 16 stable rows and 2 QN-used stable rows.
- Probe 4a: fallback-only `REVCHK` completed as PASS on 2026-05-07. It checked 50 fallback-used successful proposals, with 0 nonfallback records, 0 bad rows, and max `dx/dz/dj/dp <= 1.1e-9`.
- Next active risk: QN-enriched local volume coverage, then branch-measure symmetry of the piecewise `NT -> QN -> RG -> Metropolis` proposal map. Probe 4b targets at least 20 QN-used branch-stable local-volume rows per eps.

## Update rule
When a risk is fixed, disproved, or intentionally accepted, update this file and append the decision to `codex/knowledge/DECISIONS_AND_RISKS.md` plus `codex/state/session_log.md`.
