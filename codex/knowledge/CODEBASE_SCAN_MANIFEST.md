# Codebase Scan Manifest

Updated: 2026-05-07 JST

This manifest exists to keep source-audit context stable across chat compression.

## Repository roots
- Remote source of truth: `/home/cychou/TLTM`.
- Local mirror used in this scan: `/Users/ccy/Documents/New project/TLTM_repo`.
- Remote login: `cychou@ithems_fe02.intra.riken.jp`.

## Inventory snapshot
- Remote tree count from `find src scripts tests docs codex -type f`:
  - total files: 213
  - `src`: 41
  - `scripts`: 45
  - `tests`: 2
  - `docs`: 52
  - `codex`: 73
- Local mirror count from `find src scripts tests docs codex -type f`:
  - total files: 205
  - `src`: 40
  - `scripts`: 44
  - `tests`: 2
  - `docs`: 55
  - `codex`: 64
- Source-code file set comparison for `src/`, `scripts/`, and `tests` with extensions `*.f90`, `*.inc`, `*.py`, `*.sh`:
  - local and remote lists match.
  - files: 83
  - lines: 36677
  - `src` lines: 21866
  - `scripts` lines: 14431
  - `tests` lines: 380

## Main source inventory
- `src/apps`: executable entrypoints and expectation analysis application.
- `src/config`: parameter parsing and legacy-global synchronization.
- `src/core`: RNG, utility, profiling, LAPACK fallback.
- `src/physics`: model action/derivatives and holomorphic flow/inverse-flow solvers.
- `src/sampler`: Stage1/Stage2 drivers, Metropolis, HMC/RATTLE, Newton, canonical p28 QN, reverse gate, counters, history I/O.
- `scripts`: multiseed orchestration, merge/report generation, geometry plotting, replay analysis, legacy campaign runners.
- `tests`: derivative and Hamiltonian conservation tests.
- `docs`: agent guide, theory references, campaign JSON protocols, policy/design notes.
- `codex`: persistent Codex control plane and task workspaces.

## Deep-read coverage
- Deep-read complete for the current Stage3_3/Stage3_4 production path:
  - `scripts/run_stage3_3_multiseed.py`
  - `scripts/merge_stage3_multiseed_chunks.py`
  - `src/config/param_mod.f90`
  - `src/apps/run_tltm_stage2.f90`
  - `src/sampler/tltm_stage2_driver.f90`
  - `src/sampler/markovchain_metropolis.f90`
  - `src/sampler/hmc.f90`
  - `src/sampler/hmc_integrator_core.f90`
  - `src/sampler/hmc_constraints.f90`
  - `src/sampler/quasi_newton_solver.f90`
  - `src/sampler/quasi_newton_linear_solver.f90`
  - `src/sampler/constraint_solver_stats.f90`
  - `src/sampler/hmc_kernels.f90`
  - `src/sampler/hmc_reversibility_checks.f90`
  - `src/physics/solve_flow.f90`
  - `src/physics/model.f90`
  - `src/physics/model_generated.f90`
  - `src/apps/evaluate_expectations.f90`
- Theory/design references checked for consistency:
  - `docs/1912.13303 Implementation of the HMC algorithm on the tempered Lefschetz thimble method.pdf`
  - `docs/fallback_policy_s1.md`
  - `docs/qn_policy_review_and_first_matrix_2026-04-27.md`
  - `docs/qn_added_proposal_analysis_2026-04-27.md`

## Indexed but not exhaustively deep-read
- Stage1-only path: `src/apps/run_tltm_stage1.f90`, `src/sampler/tltm_stage1_driver.f90`.
- Legacy single-chain path: `src/apps/generate_markov_chain.f90`, `src/sampler/markovchain_mod.f90`.
- Auxiliary plotting/analysis scripts under `scripts/`.
- Historical shell campaign runners under `scripts/`.
- Source-transform backend scripts under `scripts/st_backends/`.

## Re-scan commands
Use these before any major source edit:

```bash
cd /home/cychou/TLTM
find src scripts tests -type f \( -name '*.f90' -o -name '*.inc' -o -name '*.py' -o -name '*.sh' \) | sort
find src scripts tests -type f \( -name '*.f90' -o -name '*.inc' -o -name '*.py' -o -name '*.sh' \) -print0 | xargs -0 wc -l | sort -n
grep -RInE '^[[:space:]]*(program|module|subroutine|function)[[:space:]]+' src tests scripts/*.py
```

If `rg` is available locally, prefer the equivalent `rg` commands.

## Important caveat
"Full scan" means the inventory, module map, and current production execution path have been systematically reviewed. It does not mean every auxiliary or historical script has been line-by-line audited for future use. Before using an indexed auxiliary script for a claim, deep-read that script and update this manifest.
