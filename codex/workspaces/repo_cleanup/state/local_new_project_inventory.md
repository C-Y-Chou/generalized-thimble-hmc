# Local `New project` Root Inventory

Captured: 2026-05-08 JST

## Problem
- `/Users/ccy/Documents/New project` is not just a navigation folder right now.
- It contains the canonical repo `TLTM_repo/`, but also scattered TLTM source files, PBS scripts, docs, tools, Python cache, and old experiment configs outside the canonical repo.
- This makes new Codex sessions ambiguous: it is easy to enter the wrong root or read stale copies.

## Canonical Repo
- `/Users/ccy/Documents/New project/TLTM_repo`

## Local Root Items That Should Not Stay Long-Term
- Source-like files outside canonical repo:
  - `constraint_solver_stats.f90`
  - `hmc.f90`
  - `hmc_constraints.f90`
  - `hmc_integrator_core.f90`
  - `markovchain_metropolis.f90`
  - `quasi_newton_linear_solver.f90`
  - `quasi_newton_solver.f90`
  - `replay_quasi_failures.f90`
  - `solve_flow.f90`
  - `tltm_stage2_driver.f90`
- Runner/config/script copies outside canonical repo:
  - `run_stage3_3_multiseed.py`
  - `merge_stage3_multiseed_chunks.py`
  - `stage_3_3_minimal_ladder_1024seed_50k.json`
  - `stage_3_3_minimal_ladder_1024seed_200k.json`
  - root-level `run_stage*.pbs` and `merge_stage*.pbs`
- Directories outside canonical repo that need classification:
  - `docs/`
  - `scripts/`
  - `tools/`
  - `newproject/`
  - `__pycache__/`
- Stray files:
  - `.DS_Store`
  - `0,nz,sum,s) PY`

## Target Local Structure
- Keep `/Users/ccy/Documents/New project` as a thin navigation folder.
- Keep only:
  - `TLTM_repo/`
  - optional human-facing navigation files such as `START_HERE.md` or `README.md`
  - optional local archive folder with date-stamped moved files, if needed
- Move or archive everything else after verifying it is duplicated or obsolete.

## Cleanup Rule
- Do not delete local scattered files blindly.
- First compare each file against `TLTM_repo/` or git history.
- If unique, move it into a dated archive and write an index.
- If duplicate/generated, remove only after a snapshot list is recorded.

## Implemented In Fortran Modernization Worktree - 2026-05-09 JST
- Deleted tracked root-level stale Fortran artifacts `quasi_newton_solver.f90`, `tltm_stage2_driver.f90`, and `replay_quasi_failures.f90` after confirming active canonical sources live under `src/` and `build/makefile` does not reference the root copies.
