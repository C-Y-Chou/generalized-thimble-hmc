# TLTM Repo Structure and Git Policy

## Source of truth
- Canonical code root: `/home/cychou/TLTM`.
- This directory is now a git repository (`main` as baseline branch).

## Tracked content
- `src/`, `scripts/`, `tests/`, `docs/`, `codex/`
- Top-level experiment launchers and helper scripts (`run_stage*.pbs`, `merge_stage*.pbs`, `*.f90`, `*.py`, `*.json`).

## Ignored content
- Heavy runtime artifacts: `output/`
- Build/binaries: `build/`, `bin/`, `*.o`, `*.mod`, `*.a`, `*.so`
- Queue stdout/stderr dumps: `*.pbs.out`, `*.pbs.err`, `*.o[0-9]*`, `*.e[0-9]*`
- Volatile codex temp/log files.

## Required reproducibility record
For every production run, record at minimum:
1. `git rev-parse HEAD`
2. PBS script path + queue + walltime
3. key env vars (`QN_*`, `TLTM_STAGE2_*`, tolerance overrides)
4. output root path

## Workflow
1. Create branch: `exp/<short-name>` from `main`.
2. Commit code/config before submit.
3. Submit jobs.
4. Write run manifest in `codex/state/session_log.md` and runbook.
5. Merge back after validation.
