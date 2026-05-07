# Repo Mental Model (TLTM)

Updated: 2026-04-30 JST

## Purpose
This document captures the operational understanding required to work effectively in TLTM without re-discovery.

## Layered architecture
- apps -> sampler -> physics -> config -> core
- Primary runtime kernels for our current work live in:
  - `src/sampler/hmc_integrator_core.f90`
  - `src/sampler/tltm_stage2_driver.f90`
  - `src/sampler/constraint_solver_stats.f90`
- Stage3 multiseed orchestration lives in:
  - `scripts/run_stage3_3_multiseed.py`
  - `scripts/merge_stage3_multiseed_chunks.py`

## Runtime flow (high level)
1. Build binaries in `build/` -> `bin/run_tltm_stage2`, `bin/evaluate_expectations`.
2. `run_stage3_3_multiseed.py` creates isolated per-seed workdirs and parameters.
3. Stage2 run emits summary/trace/stat artifacts per seed.
4. Eval aggregates chain outputs.
5. Per-seed and aggregated CSV/MD reports are generated.

## Important policy coupling
- Method `no_fb` in multiseed runner sets `enable_quasi_fallback=false` in generated `parameters.dat`.
- Reverse gate behavior is controlled in kernel (`hmc_integrator_core.f90`), not only by PBS env knobs.

## Current gate semantics (as of this update)
- Reverse gate condition has been unified to run when RG is enabled and gate is not already active.
- Intended structure: `nofb/withfb -> RG -> Metropolis` (no branch split by fallback trigger status).

## Artifact contract for stage3_4 campaigns
- Output root: `output/tests/stage3_4/<campaign>/<policy>/chunk_*`
- Log root: `output/logs/<campaign>/<policy>/chunk_*`
- Merge output expected at policy root:
  - `per_seed_summary_table.csv`
  - `aggregated_summary_table.csv`
  - `<log_prefix>_report.md`
