# ODEX 10k Validation Protocol

Updated: 2026-05-08
Status: protocol ready; no production job submitted by this planning/check step.

## Purpose

This protocol is the first physical-observable validation gate after ODEX canonicalization. It is not a byte-for-byte trajectory regression: the ODEX step-number sequence and controller choices may alter trajectories. The required outcome is that physical observables and failure/rejection diagnostics remain scientifically acceptable and explainable.

## Source Boundary

Current ODEX-canonical branch state includes:

- ODEX-only failure policy gates: Radau/JFNK/final-resort rescue paths disabled from production entry points.
- Hairer ODEX `IWORK(3)=3` sequence: `2,4,6,8,12,16,24,32,...`.
- Matching `calculate_ak` work estimate from the same sequence helper.
- Positive work estimate in `calculate_wk`; signed `calculate_hk` preserved for integration direction.

Reference point for isolating the ODEX sequence/controller effect:

- Pre-ODEX-sequence commit: `1dcfa33 add BTN contract replay diagnostics`.
- ODEX sequence commit: `028fd6e canonicalize ODEX step sequence`.
- Solver/wrapper check additions are test infrastructure and should not change production physics.

## Required Preflight

Before submitting any 10k job, the following local checks must pass on the exact source revision to be validated:

1. `git status --short` must be clean except intentionally ignored output artifacts.
2. `scripts/run_odex_solver_check.sh` must pass.
3. A short local Stage2 smoke must pass if the executable or linked objects changed since the last smoke.
4. Record compiler, branch, commit, parameter file, command line, and output directory in the run manifest.

Current local preflight evidence after ODEX canonicalization:

- `run_odex_solver_check`: analytic exponential/oscillator checks pass; fallback attempts/failures are 0.
- Standalone flow-wrapper scan binaries were deleted with the legacy diagnostic app cleanup; use `test_odex_solver` plus Stage2 smoke/regression outputs as the active local gate.

## Canonical Configuration

Primary route:

- Canonical p28 production route: `fb_norefine`.
- Reverse gate: enabled and treated as part of proposal validity.
- Post-refine: deleted from the active code path.
- Quasi p28 max iteration: current production p28 setting.
- Constraint tolerances: use the current production-canonical values unless this protocol is explicitly updated.

Optional companion route:

- `no_fb` may be run as a control/diagnostic route if cost is acceptable, but `fb_norefine` is the required route.

## Comparison Design

Use matched-control comparison whenever feasible:

- Same seed list between baseline and ODEX-canonical run.
- Same chain length per seed: 10k for this first gate.
- Same TLTM ladder, RG policy, p28 settings, output schema, and analysis script versions.
- Same production-style build flags unless the validation question is explicitly about compiler behavior.

Preferred baseline:

- If feasible, compare current ODEX-canonical source against the immediate pre-sequence baseline at `1dcfa33` using the same route and seeds.
- If rerunning the pre-sequence baseline is too expensive, compare against the existing Stage3_4 characterization family and clearly label the comparison as historical rather than paired.

## Required Readout

Collect at minimum:

- Physical observables and uncertainties used for TLTM judgment.
- Z means and related normalization diagnostics.
- Metropolis acceptance rate and rejection classes.
- Reverse-gate rejects/failures.
- Newton success/failure counts.
- QN p28/BTN rescue attempts, successes, failures, residual statistics if available.
- ODE failure counters, fallback counters, h-min/max-step/invalid classifications.
- Flow wrapper/runtime diagnostics if available.
- Per-seed runtime and any severe outliers.
- Output schema version or commit hash for every generated summary table.

## Pass Criteria

The 10k gate may pass when:

- Physical observables show no major unexplained shift relative to the comparison uncertainty and expected trajectory-policy differences.
- Z means remain plausible and consistent with the intended TLTM interpretation.
- ODE failure/fallback counters do not show runaway behavior.
- Reverse-gate and failure-as-rejection semantics remain intact.
- Per-seed outliers are explainable and do not dominate the aggregate.

## Stop Criteria

Stop and discuss before 50k if any of the following occur:

- A physical observable shifts in a way that is large and not explained by statistical noise or known ODEX trajectory differences.
- ODEX failures, h-min hits, invalid states, or max-step failures become operationally dominant.
- RG failures or proposal failures suggest live-chain state is being updated after a failed proposal.
- Output counters are ambiguous enough that the failure source cannot be separated between ODE, Newton/QN, RG, and Metropolis.
- Runtime becomes unexpectedly worse without a clear diagnostic explanation.

## Deliverable

The 10k validation should produce a single directory containing:

- Run manifest with branch, commit, compiler, exact commands, parameters, and seed list.
- Raw outputs or references to raw outputs.
- Aggregated comparison table.
- Per-seed diagnostic table.
- Short written judgment: pass to 50k, rerun/expand 10k, or stop for code investigation.
