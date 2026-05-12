# TLTM Codex L0 Boot

Generated: 2026-05-12T18:33:42+09:00
Remote refreshed: 2026-05-12T18:32:26+09:00

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

- `tltm_production_comparison_provisional`: branch `codex/tltm-production-comparison-official-dfols`, commit `a22de1c19633793cf9c3ff7037b7cbc399e1b568`, 3 active jobs, examples: 14951.anode01,14952.anode01,14953.anode01, pinned `a22de1c19633793cf9c3ff7037b7cbc399e1b568`. Do not fast-forward.

## Active Local Risk

- No local worktree risk recorded in `codex/state/LOCAL_WORKTREES.tsv`.

## Active/Pending Jobs

- `14951.anode01` `pc_pre10_m` queue `C8` state `R` dataset `prodcomp_preredo_a22de1c_10seed_10k_20260512`.
- `14952.anode01` `pc_pre10_m` queue `C8` state `R` dataset `prodcomp_preredo_a22de1c_10seed_10k_20260512`.
- `14953.anode01` `pc_pre10_mg` queue `C8` state `H` dataset `prodcomp_preredo_a22de1c_10seed_10k_20260512`.

## Active/Decision Caveats

- `CV-001` status `active` kernel_correctness_audit blocks `final_publication_production`: Proposal-kernel correctness evidence is sampled/provisional, not a publishable proof for every official DFO-LS piecewise route. Rerun trigger: Changing solver backend, route order, tolerances, reverse gate, final-flow policy, Metropolis acceptance, counter timing, or making a final correctness claim.
- `CV-002` status `active` tltm_production_comparison blocks `final_publication_dataset`: Production-comparison outputs before modernization convergence are provisional-discussion datasets, not final publication datasets. Rerun trigger: Any change to method mapping, public schema, counter/status semantics, wrapper behavior, RNG ownership, proposal construction, solver policy, tolerances, or final-flow policy.
- `CV-003` status `active` tltm_production_comparison blocks `production_job_submission`: Production-comparison jobs must execute from the synchronized production-comparison worktree, not from the modernization source worktree. Rerun trigger: Only misrouted jobs/artifacts rerun; docs, route guards, and state-register fixes do not invalidate correctly routed scientific outputs.
- `CV-004` status `active` fortran_modernization blocks `source_code_modernization`: Post-M6 source refactors need an accepted reference package or an explicit narrower baseline before touching behavior-relevant code. Rerun trigger: Any source change that can affect RNG order, proposal construction, solver route, failure classification, counters, schema meaning, or public wrapper behavior.
- `CV-006` status `active` fortran_modernization blocks `dfols_claims_and_outputs`: Historical TLTM "DFO-LS" or "DFO-LS-style" QN paths were in-house implementations, not the official DFO-LS package. Official DFO-LS claims require the embedded official backend and package provenance. Rerun trigger: Any dataset or claim labeled official DFO-LS without ENABLE_OFFICIAL_DFOLS, QN_SOLVER_BACKEND=official_dfols, stable preset provenance, and TLTM residual-gate readback must be rerun or relabeled.
- `CV-007` status `active` fortran_modernization blocks `odex_backend_full_hairer_endpoint_package`: User reopened ODEX scope for a complete standalone/full Hairer ODEX endpoint package and an observable degeneracy test for disabling solver assist. Dense output is explicitly out of scope by user decision. Standalone endpoint backend now exists in src/physics/odex_backend.f90 with explicit options/workspace/result/status contracts, Hairer IWORK(3)=3 sequence, endpoint-only API, conservative stability-control surface, and package/TLTM-wrapper guardrails. The remaining blocker is observable evidence: 10seed x 10k assist-on/off shows solver-health degradation but does not prove observable degeneracy. Rerun trigger: Changing ODEX sequence, stability-control policy, tolerance floors, solver-internal assist, final-flow strictness, or publishing a broader ODEX-completeness claim requires rerun of affected flow/proposal/reference/observable gates.
- `CV-009` status `decision_pending` fortran_modernization blocks `retained_core_deterministic_evidence`: The retained Newton, RATTLE, QN/BTN, HMC/Metropolis, and reverse-gate cores now have deterministic guardrails for Newton replay, successful RATTLE/RG pass replay, BTN residual reconstruction, official package-success route census, stub no-fallback route behavior, RG reject stay-put identity, and failure-as-rejection accounting. Rerun trigger: Any source change touching residuals, projection, route budgets, reverse gate, failure-as-rejection, Metropolis acceptance, or final correctness claims requires the affected deterministic evidence to pass or be explicitly re-scoped.
- `CV-010` status `decision_pending` fortran_modernization blocks `diagnostics_state_accounting`: Diagnostic counters, failure capture, status propagation, reverse replay accounting, and solver-assist labels have compatibility slices and sidecars, but not one typed event context for all proposal/replay/residual/probe/reject/accept events. Rerun trigger: Changing counter/status semantics, capture controls, replay suppression, output schema, wrapper behavior, or using diagnostics for final claims requires schema/versioned readback and affected reference comparisons.

## High-Priority Open Items

- `CP-001` status `active` control_plane: Keep L0/L1 current after remote/job changes Next: Run refresh_remote_state and render_l0_boot before remote/PBS work
- `CP-003` status `active` cluster02: Record new queue failures/successes into scheduler observations Next: Use fresh qstat/probes for current scheduling; record notable future outcomes as priors, not fixed availability
- `CP-008` status `active` tltm_production_comparison: Read M6 R1-R4 as production-calibration aliases Next: Build a read-only production-calibration report from accepted M6 packages, then decide the next seed/cycle grid
- `CP-010` status `active` control_plane: Keep material caveats in the caveat register before changing work scope Next: Run the caveat audit steps, update CAVEATS.tsv, and add blocking caveats to OPEN_ITEMS.tsv before major workflow continuation
- `CP-011` status `active` kernel_correctness_audit: Decide the official-DFO-LS-line kernel correctness gate before final publication production Next: Current official DFO-LS gates may continue as provisional, but final publication production needs the CV-001 correctness gate or explicit accepted limitation
- `CP-012` status `active` tltm_production_comparison: Maintain provisional-vs-final production boundary Next: Official DFO-LS c0e4021 256seed/200k production-comparison artifact has completed and merged, but it is not a rerun after the latest modernization HEAD and remains provisional until final wrapper/schema/naming/counter conventions are frozen or final regeneration is scheduled
- `CP-015` status `active` tltm_production_comparison: Monitor modernization-head production pre-redo gate Next: Campaign prodcomp_preredo_a22de1c_10seed_10k_20260512 is submitted from production worktree commit a22de1c with assist off; monitor jobs 14951/14952/14953 and read back the pre_redo report before any further production sync
- `FM-001` status `active` fortran_modernization: Reset modernization around foundation completeness Next: Treat M6 as a behavior baseline, not completed foundation; use FOUNDATION_COMPLETENESS_RESET_20260511 before any source modernization step
- `FM-002` status `active` fortran_modernization: Fix DFO-LS evidence and implementation boundary Next: Separate historical in-house/DFO-LS-style evidence from official-package evidence, then finish official solver integration/preset work before final claims
- `FM-003` status `active` fortran_modernization: Complete the ODEX assist-off observable decision Next: CV-007 package work is implemented locally: standalone endpoint backend, Hairer IWORK(3)=3 package contract, conservative stability-control surface, and wrapper guardrails pass. Remaining action is the larger official DFO-LS assist-on/off observable gate before F14 production regeneration. Dense output is out of scope.
- `FM-005` status `decision_pending` fortran_modernization: Build retained-core deterministic evidence pack Next: Deterministic guardrails now cover Newton, successful RATTLE/RG, BTN residual, official package-success route census, stub no-fallback route behavior, RG reject identity, and failure-as-rejection accounting; decide whether to accept this branch coverage or require a formal local-volume/branch-measure proof before F14
- `FM-006` status `decision_pending` fortran_modernization: Repair diagnostics/status/accounting foundation Next: Decide whether to implement typed diagnostics/accounting context before final production or explicitly accept the current compatibility-first counter/sidecar surface as reduced scope

## Recent Decisions

- 2026-05-11 `fortran_modernization`: Accept official DFO-LS backend replacement for the representative scope
- 2026-05-11 `fortran_modernization`: Keep CV-009 open after first retained-core evidence slice
- 2026-05-11 `fortran_modernization`: Define current official QN route surface separately from legacy internal p28 machinery
- 2026-05-12 `fortran_modernization`: Stop at F14 production-regeneration decision point
- 2026-05-12 `remote`: Quarantine qn_error_handling_validation as deletion candidate
- 2026-05-12 `remote`: Delete qn_error_handling_validation after artifact rehome/archive

## Pointers

- L1 index: `codex/indexes/L1_INDEX.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`
- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`
- Caveats: `codex/state/CAVEATS.tsv`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
