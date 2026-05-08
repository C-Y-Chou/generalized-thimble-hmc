# Code Hygiene Audit

Updated: 2026-05-08
Scope: sloppy handwritten artifact cleanup and Fortran modernization, behavior-preserving and baseline-gated.

## Purpose

Clean implementation quality without changing physics, sampling, or output behavior. This is a formal modernization workstream, not ad hoc cleanup.

## Categories

### Safe planning-only inventory

- Long subroutines and modules.
- Duplicate helper functions.
- Ambiguous variable names.
- Mixed mechanism/policy/diagnostic code.
- Module-level `save` workspaces and counters.
- Logging format inconsistencies.
- Repeated allocation/deallocation patterns.
- Legacy/research/deletion-candidate code paths.
- Error flag/status convention inconsistencies.

### Potentially safe after baselines

- Rename local variables with no semantic change.
- Add comments/equation notes around residuals and route decisions.
- Split pure helper routines from large modules.
- Consolidate duplicate allocation helpers.
- Centralize string/log formatting.
- Introduce derived workspace/context types while preserving public wrappers.

### Blocked until canonicalization and official baseline

- Any cleanup touching residual equations, flow direction, ODEX constants, route thresholds, RNG order, Metropolis/RG logic, counters, or output schema.
- Any deletion of legacy routes.
- Any module split that changes initialization order or environment loading order.

## Initial High-Risk Files

- `/home/cychou/TLTM/src/physics/solve_flow.f90`: flow, ODEX, Radau/JFNK/final-resort, diagnostics in one module.
- `/home/cychou/TLTM/src/sampler/hmc_integrator_core.f90`: RATTLE, Newton/QN fallback, post-refine, RG, counters in one core routine.
- `/home/cychou/TLTM/src/sampler/quasi_newton_solver.f90`: residuals, DFO-LS, DFO-GN, Broyden, fallback policy, traces, watchdogs.
- `/home/cychou/TLTM/src/sampler/tltm_stage2_driver.f90`: orchestration, summaries, histories, swaps, config/env parsing.
- `/home/cychou/TLTM/src/apps/evaluate_expectations.f90`: evaluation, diagnostics, plotting metadata, statistics, I/O.
- `/home/cychou/TLTM/src/core/utils.f90`: mapping helpers, state helpers, I/O helpers, math helpers.
- `/home/cychou/TLTM/src/core/mt95.f90`: global RNG state.
- `/home/cychou/TLTM/src/config/param_mod.f90`: config + legacy global sync.

## Pre-Stage3_4 Actions

- Do not edit source.
- Build line/function-level inventory for high-risk files.
- Mark possible pure helpers vs behavior-sensitive blocks.
- Create later cleanup tickets with required baseline rows.
- Identify comments/equation docs that should be added after baseline.

## Cleanup Rule

Every code hygiene change must declare one of:

- No behavior path touched.
- Covered by a specific baseline row.
- Intentional algorithm version change approved by user.
