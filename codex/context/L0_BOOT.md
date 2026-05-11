# TLTM Codex L0 Boot

Generated: 2026-05-11T15:25:18+09:00
Remote refreshed: 2026-05-11T15:25:14+09:00

## Canonical Entry

- Local source of truth: `/Users/ccy/Documents/TLTM_qn_error_handling`.
- Default branch/workline: `codex/fortran-modernization` with embedded official DFO-LS as the default QN backend.
- Modernization/source execution target: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- Production-comparison execution target: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` after sync to the chosen official-DFO-LS commit.
- `/Users/ccy/Documents/New project/TLTM_repo` is legacy unless the user explicitly asks for legacy/control-plane work.

## Hard Rules

- Heavy TLTM execution must use PBS compute nodes, not the login/frontend node.
- Before remote SSH/PBS/git cleanup work, run `bash codex/tasks/refresh_remote_state.sh` and `bash codex/tasks/render_l0_boot.sh`.
- Before local TLTM `git pull`, branch switch, cleanup, or overwrite, run `bash codex/tasks/refresh_local_state.sh` and `bash codex/tasks/render_l0_boot.sh`.
- If a remote worktree has active pinned jobs, do not fast-forward or clean it.
- For cluster02 queue choice, work splitting, submission, or job repair, use the cluster02 scheduling agent.
- Do not use `qmove` as the official repair path; cancel/resubmit/rebuild dependencies.
- Default read set is `HANDOFF_MIN -> L0_BOOT -> L1_INDEX -> chosen workspace STATE_BRIEF`.

## Active Remote Risk

- No unsafe worktree recorded in the latest registry. If cache is stale, refresh before acting.

## Active Local Risk

- `local_canonical_official_dfols`: branch `codex/fortran-modernization`, commit `d3f133d1fd7de2ec6a5b7ac27840c01287be5be7`, dirty `4`, ahead `0`, behind `0`, stashes `1`, safe_to_pull `no_dirty_worktree`.

## Active/Pending Jobs

- `14766.anode01` `pc32_nofb_00` queue `C8` state `H` dataset `unknown`.
- `14767.anode01` `pc32_nofb_01` queue `C8` state `H` dataset `unknown`.
- `14768.anode01` `pc32_nofb_02` queue `C8` state `H` dataset `unknown`.
- `14769.anode01` `pc32_nofb_03` queue `C8` state `H` dataset `unknown`.
- `14770.anode01` `pc32_wfb_00` queue `C8` state `H` dataset `unknown`.
- `14771.anode01` `pc32_wfb_01` queue `C8` state `H` dataset `unknown`.
- `14772.anode01` `pc32_wfb_02` queue `C8` state `H` dataset `unknown`.
- `14773.anode01` `pc32_wfb_03` queue `C8` state `H` dataset `unknown`.
- `14774.anode01` `pc32_merge` queue `C8` state `H` dataset `unknown`.

## High-Priority Open Items

- `CP-001` control_plane: Keep L0/L1 current after remote/job changes Next: Run refresh_remote_state and render_l0_boot before remote/PBS work
- `CP-003` cluster02: Record new queue failures/successes into scheduler observations Next: Use fresh qstat/probes for current scheduling; record notable future outcomes as priors, not fixed availability
- `CP-008` tltm_production_comparison: Read M6 R1-R4 as production-calibration aliases Next: Build a read-only production-calibration report from accepted M6 packages, then decide the next seed/cycle grid

## Recent Decisions

- 2026-05-10 `tltm_production_comparison`: Clear legacy Stage3_4 raw output/log folders before rerun
- 2026-05-10 `global`: Clear legacy Stage1-Stage3_3 and obsolete ODEX validation raw datasets
- 2026-05-10 `tltm_production_comparison`: Reuse accepted M6 reference datasets as first production-calibration tier
- 2026-05-11 `repo_cleanup`: Track local TLTM worktrees as first-class state
- 2026-05-11 `remote_control_plane`: Rename codex/preprod-hardening to codex/control-plane
- 2026-05-11 `control_plane`: Canonical handoff now defaults to official DFO-LS line

## Pointers

- L1 index: `codex/indexes/L1_INDEX.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`
- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
