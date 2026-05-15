# TLTM Codex L0 Boot

Generated: 2026-05-16T01:55:38+09:00
Remote refreshed: 2026-05-16T01:55:29+09:00

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

- `local_fortran_modernization`: branch `codex/fortran-modernization`, commit `d24acef0e890487fda766a1bdf18414337d45ee8`, dirty `11`, ahead `0`, behind `0`, stashes `1`, safe_to_pull `no_dirty_worktree`.

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
- `FM-012` status `active` fortran_modernization: Evaluate mature ODE package backend Next: SUNDIALS CVODE is buildable on the remote target as `/lustre1/home/cychou/TLTM/.deps/sundials-7.7.0-cvode-serial`; the disabled-by-default backend is implemented, local/default M4 passed, the first 10seed/10k comparison completed cleanly, the parallel 10seed/1k fixed-point sweep rejected `TLTM_CVODE_FIXEDPOINT_M=2/4/8`, the `TLTM_CVODE_MAX_STEPS=320` fail-fast 10seed/10k check was rejected for proposal/failure-surface and observable drift, and the non-max-step fail-fast sweep found `TLTM_CVODE_MAX_CONV_FAILS=1` exact vs strict CVODE at 10seed/10k but slower; keep strict CVODE comparison-only unless a different package route or non-kernel-changing performance path is selected.

## Recent Decisions

- 2026-05-15 `fortran_modernization`: Delete internal DFO-like QN backend from active source
- 2026-05-15 `fortran_modernization`: Delete solver assist from active source
- 2026-05-15 `fortran_modernization`: Finish precision/GPU readiness before modernization closeout
- 2026-05-15 `fortran_modernization`: Keep CVODE fixed-point m=0 after first tuning sweep
- 2026-05-16 `fortran_modernization`: Reject CVODE max-step fail-fast as canonical candidate
- 2026-05-16 `fortran_modernization`: Reject tested CVODE non-max-step fail-fast tuning as performance route

## Pointers

- L1 index: `codex/indexes/L1_INDEX.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`
- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`
- Caveats: `codex/state/CAVEATS.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
