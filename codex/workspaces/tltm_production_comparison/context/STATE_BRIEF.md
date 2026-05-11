# TLTM Production Comparison State Brief

Updated: 2026-05-11 JST

## Current Position

- `tltm_production_comparison` is the canonical workspace for TLTM `nofb` vs `withfb` production-comparison work.
- Legacy name: `stage3_4`. Treat old `stage3_4` paths, configs, and output roots as historical/provisional artifacts, not the long-term workspace identity.
- This workstream is logically separate from `fortran_modernization`. Modernization supplies the official-DFO-LS code commit; production-comparison runs execute from the synchronized production worktree.
- Current production-comparison status is provisional-discussion, not final publication data. It may be used for collaborator discussion, workflow rehearsal, queue scaling, and physical trend checks; final datasets should be regenerated after modernization converges.
- Existing long `runbooks/STATUS.md` contains historical production and validation details. Read `runbooks/SOFT_DECOUPLING_AND_PROVISIONAL_CONTRACT.md` for the current boundary.
- Cleanup of legacy production-comparison outputs/logs is allowed only after dataset/job/worktree registry refresh and summary/archive decisions.
- Legacy Stage1 to Stage3_4 raw outputs/logs were cleared on 2026-05-10 after preserving key summaries. See `runbooks/LEGACY_STAGE_OUTPUT_CLEANUP_20260510.md`.
- Obsolete ODEX validation raw data was also cleared because accepted M6 modernization reference datasets now own the modernization baseline.
- Accepted M6 reference datasets are also production-calibration aliases for the same `t=0.35,L=2,nstep=20` `nofb`/`withfb` point. Read `runbooks/M6_REFERENCE_AS_PRODUCTION_CALIBRATION_PLAN.md` before choosing the next seed/cycle scale.
- On 2026-05-11, the non-official legacy production output `gate_20260511_128seed_200k_p28_rg_nofb_fbnorefine` was archived out of active `provisional/` to avoid confusion with the current official DFO-LS comparison line. Its output/logs now live under `output/production_comparison/archive/non_official_legacy_20260511/` and `output/logs/production_comparison/archive/non_official_legacy_20260511/`.

## Important Correction

- `runbooks/QUEUE_OPTIMIZATION.md` is superseded for current queue decisions.
- Use the shared cluster02 scheduler policy instead of the old Stage3_4 queue playbook.

## Decoupled Worktree Model

- Production comparison execution target: `tltm_production_comparison_provisional`.
- Production comparison execution branch: `codex/tltm-production-comparison-official-dfols`.
- Production comparison execution worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Official DFO-LS source branch to sync from: `codex/fortran-modernization`.
- Current redo execution must happen from the production-comparison worktree after it is synced to the chosen official-DFO-LS commit.
- Modernization remote target: `fortran_modernization`.
- Modernization branch: `codex/fortran-modernization`.
- Modernization remote worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.

## Next Action

Before production continuation:

1. Run `bash codex/tasks/refresh_remote_state.sh`.
2. Sync `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` to the chosen official-DFO-LS modernization commit from `codex/fortran-modernization`.
3. Submit `codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preflight_build.pbs` and wait for it to build with `ENABLE_OFFICIAL_DFOLS=1`; on Rocky 8 it also prepares local Python 3.11 headers under `.deps/` if the system devel package is missing.
4. Submit production chunks from the production-comparison worktree pinned to the same commit; chunks now use `QN_SOLVER_BACKEND=official_dfols` and `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
5. Register any new production-comparison outputs in `codex/state/DATASETS.tsv`.
6. Confirm no active pinned jobs depend on the target worktree before any fast-forward or cleanup.
7. Archive or summarize evidence before deleting any newly generated outputs/logs.
8. For any new provisional run, write outputs under a production-comparison namespace, preferably `output/production_comparison/provisional/...`, not a new `output/tests/stage3_4/...` namespace.
