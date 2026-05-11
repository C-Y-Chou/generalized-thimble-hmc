# TLTM Codex L0 Boot

Generated: 2026-05-11T16:46:06+09:00
Remote refreshed: 2026-05-11T16:36:18+09:00

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
- Default read set is `HANDOFF_MIN -> L0_BOOT -> CAVEATS -> L1_INDEX -> chosen workspace STATE_BRIEF`.

## Active Remote Risk

- `tltm_production_comparison_provisional`: branch `codex/tltm-production-comparison-official-dfols`, commit `d3f133d1fd7de2ec6a5b7ac27840c01287be5be7`, 5 active jobs, examples: 14770.anode01,14771.anode01,14772.anode01,14773.anode01,14774.anode01, pinned `d3f133d1fd7de2ec6a5b7ac27840c01287be5be7`. Do not fast-forward.

## Active Local Risk

- No local worktree risk recorded in `codex/state/LOCAL_WORKTREES.tsv`.

## Active/Pending Jobs

- `14770.anode01` `pc32_wfb_00` queue `C8` state `R` dataset `official_dfols_gate_20260511_32seed_50k`.
- `14771.anode01` `pc32_wfb_01` queue `C8` state `R` dataset `official_dfols_gate_20260511_32seed_50k`.
- `14772.anode01` `pc32_wfb_02` queue `C8` state `R` dataset `official_dfols_gate_20260511_32seed_50k`.
- `14773.anode01` `pc32_wfb_03` queue `C8` state `R` dataset `official_dfols_gate_20260511_32seed_50k`.
- `14774.anode01` `pc32_merge` queue `C8` state `H` dataset `official_dfols_gate_20260511_32seed_50k`.

## Active Caveats

- `CV-001` kernel_correctness_audit blocks `final_publication_production`: Proposal-kernel correctness evidence is sampled/provisional, not a publishable proof for every official DFO-LS piecewise route. Rerun trigger: Changing solver backend, route order, tolerances, reverse gate, final-flow policy, Metropolis acceptance, counter timing, or making a final correctness claim.
- `CV-002` tltm_production_comparison blocks `final_publication_dataset`: Production-comparison outputs before modernization convergence are provisional-discussion datasets, not final publication datasets. Rerun trigger: Any change to method mapping, public schema, counter/status semantics, wrapper behavior, RNG ownership, proposal construction, solver policy, tolerances, or final-flow policy.
- `CV-003` tltm_production_comparison blocks `production_job_submission`: Production-comparison jobs must execute from the synchronized production-comparison worktree, not from the modernization source worktree. Rerun trigger: Only misrouted jobs/artifacts rerun; docs, route guards, and state-register fixes do not invalidate correctly routed scientific outputs.
- `CV-004` fortran_modernization blocks `source_code_modernization`: Post-M6 source refactors need an accepted reference package or an explicit narrower baseline before touching behavior-relevant code. Rerun trigger: Any source change that can affect RNG order, proposal construction, solver route, failure classification, counters, schema meaning, or public wrapper behavior.
- `CV-006` fortran_modernization blocks `dfols_claims_and_outputs`: Historical TLTM "DFO-LS" or "DFO-LS-style" QN paths were in-house implementations, not the official DFO-LS package. Official DFO-LS claims require the embedded official backend and package provenance. Rerun trigger: Any dataset or claim labeled official DFO-LS without ENABLE_OFFICIAL_DFOLS, QN_SOLVER_BACKEND=official_dfols, stable preset provenance, and TLTM residual-gate readback must be rerun or relabeled.
- `CV-007` fortran_modernization blocks `odex_backend_completeness`: Current ODEX is a partially completed endpoint extrapolation backend plus TLTM flow policy, not yet a publication-grade standalone ODEX solver contract. Rerun trigger: Changing ODEX sequence, stability control, tolerance floors, solver-internal assist, final-flow strictness, or publishing an ODEX-completeness claim requires rerun of affected flow/proposal/reference gates.
- `CV-008` fortran_modernization blocks `official_dfols_backend_completeness`: Official DFO-LS is embedded and tuned enough for provisional gates, but the official solver replacement is not finished until official-alone preset policy, package provenance, representative comparison, and TLTM residual readback are complete. Rerun trigger: Changing official DFO-LS package version, preset, residual callback, acceptance gate, maxfun/trust-region settings, or making final official-solver claims requires rerun of affected QN/backend/reference gates.
- `CV-009` fortran_modernization blocks `retained_core_deterministic_evidence`: The retained Newton, RATTLE, QN/BTN, HMC/Metropolis, and reverse-gate cores were reference-audited, but several required deterministic replay/contract tests are still missing. Rerun trigger: Any source change touching residuals, projection, route budgets, reverse gate, failure-as-rejection, Metropolis acceptance, or final correctness claims requires the affected deterministic evidence to pass or be explicitly re-scoped.
- `CV-010` fortran_modernization blocks `diagnostics_state_accounting`: Diagnostic counters, failure capture, status propagation, reverse replay accounting, and solver-assist labels remain patchwork and can change interpretation even when physics is unchanged. Rerun trigger: Changing counter/status semantics, capture controls, replay suppression, output schema, wrapper behavior, or using diagnostics for final claims requires schema/versioned readback and affected reference comparisons.

## High-Priority Open Items

- `CP-001` control_plane: Keep L0/L1 current after remote/job changes Next: Run refresh_remote_state and render_l0_boot before remote/PBS work
- `CP-003` cluster02: Record new queue failures/successes into scheduler observations Next: Use fresh qstat/probes for current scheduling; record notable future outcomes as priors, not fixed availability
- `CP-008` tltm_production_comparison: Read M6 R1-R4 as production-calibration aliases Next: Build a read-only production-calibration report from accepted M6 packages, then decide the next seed/cycle grid
- `CP-010` control_plane: Keep material caveats in the caveat register before changing work scope Next: Run the caveat audit steps, update CAVEATS.tsv, and add blocking caveats to OPEN_ITEMS.tsv before major workflow continuation
- `CP-011` kernel_correctness_audit: Decide the official-DFO-LS-line kernel correctness gate before final publication production Next: Current official DFO-LS gates may continue as provisional, but final publication production needs the CV-001 correctness gate or explicit accepted limitation
- `CP-012` tltm_production_comparison: Maintain provisional-vs-final production boundary Next: Treat official DFO-LS production-comparison gates as provisional until final wrapper/schema/naming/counter conventions are frozen or final regeneration is scheduled
- `FM-001` fortran_modernization: Reset modernization around foundation completeness Next: Treat M6 as a behavior baseline, not completed foundation; use FOUNDATION_COMPLETENESS_RESET_20260511 before any source modernization step
- `FM-002` fortran_modernization: Fix DFO-LS evidence and implementation boundary Next: Separate historical in-house/DFO-LS-style evidence from official-package evidence, then finish official solver integration/preset work before final claims
- `FM-003` fortran_modernization: Implement the ODEX completeness workstream Next: First deterministic test slice is complete; next implement or explicitly scope backend result/workspace/status API, stability control, flow-wrapper/Jacobian tests, and ODEX-only vs assist revalidation
- `FM-004` fortran_modernization: Finish official DFO-LS backend replacement policy Next: Design official-alone preset tuning, in-package robustness choices, provenance/readback, captured comparison, and TLTM residual gate acceptance without external rescue wrappers
- `FM-005` fortran_modernization: Build retained-core deterministic evidence pack Next: Cover Newton, RATTLE, QN/BTN, HMC/Metropolis, reverse-gate pass/reject, and official-DFO-LS-line route behavior before treating the numerical foundation as complete
- `FM-006` fortran_modernization: Repair diagnostics/status/accounting foundation Next: Move patchwork counters/status/capture/replay accounting toward a typed diagnostics context before final schema or production regeneration

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
- Caveats: `codex/state/CAVEATS.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
