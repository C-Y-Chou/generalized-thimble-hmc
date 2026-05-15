# TLTM Codex L0 Boot

Generated: 2026-05-15T19:46:35+09:00
Remote refreshed: 2026-05-15T19:46:32+09:00

## Canonical Entry

- Local source of truth: `/Users/ccy/Documents/TLTM_qn_error_handling` on `codex/fortran-modernization`.
- Modernization/source execution target: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- Production-comparison execution target: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` after sync to the chosen modernization fixed commit.
- `/Users/ccy/Documents/New project/TLTM_repo` is a legacy/diagnostic local checkout unless explicitly requested.
- Side diagnostic trees are retired; active TLTM work should stay on modernization or production-comparison.

## Hard Rules

- Heavy TLTM execution must use PBS compute nodes, not the login/frontend node.
- Before remote SSH/PBS/git cleanup work, run `bash codex/tasks/refresh_remote_state.sh` and `bash codex/tasks/render_l0_boot.sh`.
- Before local TLTM `git pull`, branch switch, cleanup, or overwrite, run `bash codex/tasks/refresh_local_state.sh` and `bash codex/tasks/render_l0_boot.sh`.
- If a remote worktree has active pinned jobs, do not fast-forward or clean it.
- For cluster02 queue choice, work splitting, submission, or job repair, use the cluster02 scheduling agent.
- Do not use `qmove` as the official repair path; cancel/resubmit/rebuild dependencies.
- Default read set is `HANDOFF_MIN -> L0_BOOT -> CAVEATS -> L1_INDEX -> chosen workspace STATE_BRIEF`.

## Active Remote Risk

- No unsafe worktree recorded in the latest registry. If cache is stale, refresh before acting.

## Active Local Risk

- `local_fortran_modernization`: branch `codex/fortran-modernization`, commit `3d63d4c846b4134859be731b8ec5bd5643dfc991`, dirty `33`, ahead `0`, behind `0`, stashes `1`, safe_to_pull `no_dirty_worktree`.

## Active/Pending Jobs

- No active jobs in `codex/state/JOBS.tsv`.

## Active/Decision Caveats

- `CV-002` status `active` tltm_production_comparison blocks `final_publication_dataset`: Production-comparison outputs before modernization convergence are provisional-discussion datasets, not final publication datasets. Rerun trigger: Any change to method mapping, public schema, counter/status semantics, wrapper behavior, RNG ownership, proposal construction, solver policy, tolerances, or final-flow policy.
- `CV-003` status `active` tltm_production_comparison blocks `production_job_submission`: Production-comparison jobs must execute from the synchronized production-comparison worktree, not from the modernization source worktree. Rerun trigger: Only misrouted jobs/artifacts rerun; docs, route guards, and state-register fixes do not invalidate correctly routed scientific outputs.

## High-Priority Open Items

- `CP-001` status `active` control_plane: Keep L0/L1 current after remote/job changes Next: Run refresh_remote_state and render_l0_boot before remote/PBS work
- `CP-003` status `active` cluster02: Record new queue failures/successes into scheduler observations Next: Use fresh qstat/probes for current scheduling; record notable future outcomes as priors, not fixed availability
- `CP-008` status `active` tltm_production_comparison: Read M6 R1-R4 as production-calibration aliases Next: Build a read-only production-calibration report from accepted M6 packages, then decide the next seed/cycle grid
- `CP-010` status `active` control_plane: Keep material caveats in the caveat register before changing work scope Next: Run the caveat audit steps, update CAVEATS.tsv, and add blocking caveats to OPEN_ITEMS.tsv before major workflow continuation
- `CP-012` status `active` tltm_production_comparison: Maintain provisional-vs-final production boundary Next: Official DFO-LS c0e4021 256seed/200k production-comparison artifact has completed and merged, but it is not a rerun after the latest modernization HEAD and remains provisional until final wrapper/schema/naming/counter conventions are frozen or final regeneration is scheduled
- `FM-001` status `active` fortran_modernization: Reset modernization around foundation completeness Next: Treat M6 as a behavior baseline, not completed foundation; use FOUNDATION_COMPLETENESS_RESET_20260511 before any source modernization step
- `FM-011` status `active` fortran_modernization: Maintain all-handwritten algorithm claim boundary Next: Post-correction current-head audit is complete in HANDWRITTEN_ALGORITHM_CURRENT_HEAD_AUDIT_20260515.md, and the stronger all-handwritten paper-correctness/numerical-soundness audit is complete in HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md; universal paper-correctness remains blocked until the listed surfaces are closed or explicitly scoped.
- `FM-012` status `active` fortran_modernization: Evaluate mature ODE package backend Next: User selected mature ODE package adoption as the preferred way to close handwritten ODEX-controller risk; keep current endpoint-only ODEX as the baseline while evaluating SUNDIALS CVODE primary and ODEPACK fallback.

## Recent Decisions

- 2026-05-12 `remote`: Quarantine qn_error_handling_validation as deletion candidate
- 2026-05-12 `remote`: Delete qn_error_handling_validation after artifact rehome/archive
- 2026-05-15 `fortran_modernization`: Schedule solver assist for deletion and use npt5 assist-off as baseline
- 2026-05-15 `fortran_modernization`: Use integrated algorithm modernization plan after all-handwritten audit
- 2026-05-15 `fortran_modernization`: Delete internal DFO-like QN backend from active source
- 2026-05-15 `fortran_modernization`: Delete solver assist from active source

## Pointers

- L1 index: `codex/indexes/L1_INDEX.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`
- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`
- Caveats: `codex/state/CAVEATS.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
