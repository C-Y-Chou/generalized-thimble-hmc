# Source Audit Bootstrap

Updated: 2026-05-07 JST

Use this file when a new Codex conversation needs to resume source-level work without relying on compressed chat context.

## Entry order
1. Read `codex/context/CORE.md`.
2. Read `codex/context/HANDOFF_MIN.txt`.
3. Read `codex/runbooks/GLOBAL_STATUS.md`.
4. Read `codex/runbooks/task_registry.tsv`.
5. Read this file.
6. Read `codex/knowledge/CODEBASE_SCAN_MANIFEST.md`.
7. Read `codex/knowledge/FULL_PROGRAM_MAP_CHECK.md`.
8. If the task is queue/output related, refresh `codex/runbooks/LIVE_BOARD.md`.

## Source-of-truth rule
- Remote working tree of record: `/home/cychou/TLTM`.
- Local mirror may be useful for fast reading, but must not be treated as the authoritative runtime state.
- Before code changes or production runs, verify remote git state with:

```bash
ssh cychou@ithems_fe02.intra.riken.jp 'cd /home/cychou/TLTM && git status -sb && git rev-parse --abbrev-ref HEAD && git rev-parse HEAD'
```

## Production git gate
- Do not submit validation or production jobs from a dirty working tree.
- Do not submit validation or production jobs from an unpushed branch.
- Record the pushed branch and commit SHA in the relevant task workspace before `qsub`.
- See `codex/runbooks/GIT_WORKFLOW.md` for the exact checks.

## Audit scope rule
- `CODEBASE_SCAN_MANIFEST.md` records the source inventory and coverage boundary.
- `FULL_PROGRAM_MAP_CHECK.md` records the current full-program risk map.
- Do not infer that a risk is resolved just because it disappeared from chat context.
- When a risk is fixed or disproved, update `FULL_PROGRAM_MAP_CHECK.md` and append `codex/state/session_log.md`.

## Current deep-read path
- Stage driver and report aggregation: `scripts/run_stage3_3_multiseed.py`.
- Config parsing: `src/config/param_mod.f90`.
- Stage2 runtime: `src/apps/run_tltm_stage2.f90`, `src/sampler/tltm_stage2_driver.f90`.
- Local HMC/Metropolis/RATTLE: `src/sampler/markovchain_metropolis.f90`, `src/sampler/hmc.f90`, `src/sampler/hmc_integrator_core.f90`.
- Constraint solvers: `src/sampler/hmc_constraints.f90`, `src/sampler/quasi_newton_solver.f90`, `src/sampler/quasi_newton_linear_solver.f90`.
- Statistics/capture: `src/sampler/constraint_solver_stats.f90`.
- Flow and model: `src/physics/solve_flow.f90`, `src/physics/model*.f90`.
- Evaluation: `src/apps/evaluate_expectations.f90`.

## Boundary statement
The full source inventory has been enumerated. The production path above has been deep-read. Auxiliary plotting, historical shell runners, one-off analysis scripts, and Stage1-only code have been indexed and lightly checked for integration risk, but should be deep-read before they become part of a new claim or production workflow.
