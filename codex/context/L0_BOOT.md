# TLTM Codex L0 Boot

Generated: 2026-05-15T16:02:12+09:00
Remote refreshed: 2026-05-15T15:58:24+09:00

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

- `local_legacy_diagnostic_checkout`: branch `codex/tltm-observable-regression-10k-isolation`, commit `9d9e13c11a403cfa70c5f34af8fdfbd8bdbdc758`, dirty `14`, ahead `0`, behind `0`, stashes `1`, safe_to_pull `no_dirty_worktree`.

## Active/Pending Jobs

- No active jobs in `codex/state/JOBS.tsv`.

## Active/Decision Caveats

- `CV-001` status `active` kernel_correctness_audit blocks `final_publication_production`: Proposal-kernel correctness evidence is sampled/provisional, not a publishable proof for every official DFO-LS piecewise route. Rerun trigger: Changing solver backend, route order, tolerances, reverse gate, final-flow policy, Metropolis acceptance, counter timing, or making a final correctness claim.
- `CV-002` status `active` tltm_production_comparison blocks `final_publication_dataset`: Production-comparison outputs before modernization convergence are provisional-discussion datasets, not final publication datasets. Rerun trigger: Any change to method mapping, public schema, counter/status semantics, wrapper behavior, RNG ownership, proposal construction, solver policy, tolerances, or final-flow policy.
- `CV-003` status `active` tltm_production_comparison blocks `production_job_submission`: Production-comparison jobs must execute from the synchronized production-comparison worktree, not from the modernization source worktree. Rerun trigger: Only misrouted jobs/artifacts rerun; docs, route guards, and state-register fixes do not invalidate correctly routed scientific outputs.
- `CV-004` status `active` fortran_modernization blocks `source_code_modernization`: Post-M6 source refactors need an accepted reference package or an explicit narrower baseline before touching behavior-relevant code. Rerun trigger: Any source change that can affect RNG order, proposal construction, solver route, failure classification, counters, schema meaning, or public wrapper behavior.
- `CV-006` status `active` fortran_modernization blocks `dfols_claims_and_outputs`: Historical TLTM "DFO-LS" or "DFO-LS-style" QN paths were in-house implementations, not the official DFO-LS package. Official DFO-LS claims require the embedded official backend and package provenance. Rerun trigger: Any dataset or claim labeled official DFO-LS without ENABLE_OFFICIAL_DFOLS, QN_SOLVER_BACKEND=official_dfols, stable preset provenance, and TLTM residual-gate readback must be rerun or relabeled.
- `CV-007` status `active` fortran_modernization blocks `solver_assist_deletion_policy`: Endpoint-only ODEX product boundary remains accepted for TLTM; dense output and a general-purpose Hairer ODEX library remain out of scope. The 2026-05-15 solver-policy decision demotes F15 fallback-on assist to historical/diagnostic evidence and schedules solver assist for deletion. Current baseline is true Stage2 RNG v2 plus official DFO-LS npt5_r0055 with method-level assist off. Rerun trigger: Changing ODEX sequence, stability-control policy, solver-internal assist policy, final-flow strictness, QN route, reverse gate, Metropolis acceptance, or publishing a broader ODEX/completeness claim requires affected flow/proposal/reference/observable gates.
- `CV-009` status `decision_pending` fortran_modernization blocks `retained_core_deterministic_evidence`: The retained Newton, RATTLE, QN/BTN, HMC/Metropolis, and reverse-gate cores now have deterministic guardrails for Newton replay, successful RATTLE/RG pass replay, BTN residual reconstruction, official package-success route census, stub no-fallback route behavior, RG reject stay-put identity, and failure-as-rejection accounting. Rerun trigger: Any source change touching residuals, projection, route budgets, reverse gate, failure-as-rejection, Metropolis acceptance, or final correctness claims requires the affected deterministic evidence to pass or be explicitly re-scoped.
- `CV-010` status `decision_pending` fortran_modernization blocks `diagnostics_state_accounting`: Diagnostic counters, failure capture, status propagation, reverse replay accounting, and solver-assist labels have compatibility slices and sidecars, but not one typed event context for all proposal/replay/residual/probe/reject/accept events. Rerun trigger: Changing counter/status semantics, capture controls, replay suppression, output schema, wrapper behavior, or using diagnostics for final claims requires schema/versioned readback and affected reference comparisons.

## High-Priority Open Items

- `CP-001` status `active` control_plane: Keep L0/L1 current after remote/job changes Next: Run refresh_remote_state and render_l0_boot before remote/PBS work
- `CP-003` status `active` cluster02: Record new queue failures/successes into scheduler observations Next: Use fresh qstat/probes for current scheduling; record notable future outcomes as priors, not fixed availability
- `CP-008` status `active` tltm_production_comparison: Read M6 R1-R4 as production-calibration aliases Next: Build a read-only production-calibration report from accepted M6 packages, then decide the next seed/cycle grid
- `CP-010` status `active` control_plane: Keep material caveats in the caveat register before changing work scope Next: Run the caveat audit steps, update CAVEATS.tsv, and add blocking caveats to OPEN_ITEMS.tsv before major workflow continuation
- `CP-011` status `active` kernel_correctness_audit: Decide the official-DFO-LS-line kernel correctness gate before final publication production Next: Current official DFO-LS gates may continue as provisional, but final publication production needs the CV-001 correctness gate or explicit accepted limitation
- `CP-012` status `active` tltm_production_comparison: Maintain provisional-vs-final production boundary Next: Official DFO-LS c0e4021 256seed/200k production-comparison artifact has completed and merged, but it is not a rerun after the latest modernization HEAD and remains provisional until final wrapper/schema/naming/counter conventions are frozen or final regeneration is scheduled
- `FM-001` status `active` fortran_modernization: Reset modernization around foundation completeness Next: Treat M6 as a behavior baseline, not completed foundation; use FOUNDATION_COMPLETENESS_RESET_20260511 before any source modernization step
- `FM-002` status `active` fortran_modernization: Fix DFO-LS evidence and implementation boundary Next: Separate historical in-house/DFO-LS-style evidence from official-package evidence, then finish official solver integration/preset work before final claims
- `FM-003` status `active` fortran_modernization: Complete solver-assist deletion baseline Next: CV-007 endpoint-only ODEX package work remains closed for dense-output/general-library scope. The 2026-05-15 decision demotes F15 fallback-on assist to diagnostic history and schedules solver assist for deletion.
- `FM-005` status `decision_pending` fortran_modernization: Build retained-core deterministic evidence pack Next: Deterministic guardrails now cover Newton, successful RATTLE/RG, BTN residual, official package-success route census, stub no-fallback route behavior, RG reject identity, and failure-as-rejection accounting; decide whether to accept this branch coverage or require a formal local-volume/branch-measure proof before F14
- `FM-006` status `decision_pending` fortran_modernization: Repair diagnostics/status/accounting foundation Next: Decide whether to implement typed diagnostics/accounting context before final production or explicitly accept the current compatibility-first counter/sidecar surface as reduced scope
- `FM-010` status `active` fortran_modernization: Preserve npt5 assist-off baseline while deleting assist Next: Direct rerun wrapper is codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_npt5_assistoff_10seed_10k_20260515.pbs; expected 10seed/10k readback is nofb failures 8340 mean Re -0.002818340294982019 and withfb failures 167 mean Re 0.02974362444598664.

## Recent Decisions

- 2026-05-11 `fortran_modernization`: Keep CV-009 open after first retained-core evidence slice
- 2026-05-11 `fortran_modernization`: Define current official QN route surface separately from legacy internal p28 machinery
- 2026-05-12 `fortran_modernization`: Stop at F14 production-regeneration decision point
- 2026-05-12 `remote`: Quarantine qn_error_handling_validation as deletion candidate
- 2026-05-12 `remote`: Delete qn_error_handling_validation after artifact rehome/archive
- 2026-05-15 `fortran_modernization`: Schedule solver assist for deletion and use npt5 assist-off as baseline

## Pointers

- L1 index: `codex/indexes/L1_INDEX.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`
- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`
- Caveats: `codex/state/CAVEATS.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
