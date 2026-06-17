# Modernization Main Workflow

Updated: 2026-06-18 JST

This is the single active operational workflow for the current TLTM Fortran
modernization effort.  Use this file together with
`codex/runbooks/MODERNIZATION_STATUS.md`.  Generated runbooks are evidence
packets only; do not use them as workflow routers unless this file or the
status file explicitly names them.

## Required Read Order

1. `codex/runbooks/MODERNIZATION_WORKFLOW.md`
2. `codex/runbooks/MODERNIZATION_STATUS.md`
3. `codex/runbooks/WV_HMC_POLICY_BENCHMARK_SUMMARY_20260616.md`

## Milestone Rule

Modernization TODOs are now tracked as GitHub-commit milestones.  A task is a
milestone only if it can end in a meaningful public repository commit, tag, or
release-note update.  Internal control-plane work can support a milestone, but
it is not itself a GitHub milestone.

Public milestone examples:

- user-facing documentation, examples, validation summaries, and release notes;
- source changes to sampler/model-provider behavior or public wrappers;
- small reproducible validation assets that do not depend on local cluster
  paths;
- benchmark summaries that are compact and provenance-rich.

Internal support work:

- scheduler observations, queue ledgers, source-pin manifests, remote live
  caches, and local job state;
- large generated output dumps and exploratory runbook archives;
- PBS scripts tied to the private cluster unless they are explicitly part of a
  reproducibility support packet.

Internal support work should be cleaned, archived, or ignored before a public
commit is prepared.  It should not be promoted into a GitHub commit merely to
show activity.

## Cleanup Sprint Rule

Internal cleanup is not a public GitHub milestone, but it is still scheduled
work.  It must appear in this workflow when it blocks a clean release candidate
or would otherwise be forgotten.

Cleanup sprint outputs may be local-only or may end in a small governance
commit, but they must not add private scheduler ledgers, queue caches, source
pin manifests, or large generated dumps to the public repository.

## Execution Rules

- Production-scale validation should use the authorized scheduler workflow for
  the target cluster, not ad hoc local runs.
- Private scheduler implementations, queue ledgers, source pins, remote live
  caches, and repair records are local control-plane state.  They must not be
  committed as modernization evidence.
- Before choosing a queue or repairing a failed job, consult the local
  scheduler observations for the target cluster.
- WV-HMC production-like jobs must use a source pin or runtime snapshot and
  must not depend on compute-node `git` or node-local Python.
- Generated evidence packets are not workflow entrypoints.

## Active WV-HMC Policy Route

Main policy:

- `normal_reflect`

Optional benchmark:

- `full_bounce`

Historical/diagnostic only:

- `stay_reject`
- `paper_bounce_reject`

This closes the previous four-policy ambiguity.  The next WV-HMC validation
should start from `normal_reflect` and only use `full_bounce` when a direct
policy benchmark is part of the question.

## GitHub Commit Milestone Queue

The queue below is the active modernization TODO ledger.  Every active or
deferred modernization item must appear here, even if it is not itself a
public GitHub commit.  Each row states how the work is expected to surface:

- `github`: public source/docs/example/benchmark commit;
- `internal`: local governance, scheduler, archive, or workspace maintenance;
- `technical`: source/algorithm work that will later become one or more GitHub
  commits;
- `external`: separate workstream, not completed from this modernization repo.

### GHM-001: Public WV-HMC Validation Path

Goal: make the current dense WV-HMC policy selection externally readable and
reproducible without private cluster assumptions.

Commit target:

- public docs state `normal_reflect` as the default WV-HMC policy;
- `full_bounce` is documented only as an optional benchmark;
- a small reproducible WV-HMC smoke/validation command exists;
- `CHANGELOG.md` or release notes summarize the 2026-06-16 policy/default
  change;
- claim boundary is explicit: dense explicit-J WV-HMC is validated at the
  Stephanov benchmark level, not yet high-dimensional production.

### CLEAN-001: Workspace Classification Before GHM-001

Target window: 2026-06-16 to 2026-06-17.

Goal: prevent internal support files from leaking into `GHM-001`.

Completion criteria:

- current dirty worktree is classified into public milestone, internal support,
  and old archive;
- scheduler ledgers, queue observations, source pins, live caches, and large
  generated outputs are explicitly excluded from `GHM-001`;
- any public-facing file needed by `GHM-001` is identified before staging.

### GHM-002: Model-Provider Onboarding Contract

Goal: make it clear how a new physics model is added without editing canonical
sampler code.

Commit target:

- document action, manual gradient, Hessian/Hessian-vector, observables, and
  small-reference validation requirements;
- include a minimal provider checklist;
- keep model choice out of canonical sampler code.

### GHM-003: DOP853 Public Surface Cleanup

Goal: make the public flow-backend story match the current default.

Commit target:

- public docs say DOP853 is the default backend;
- ODEX is not presented as the normal user path;
- any remaining ODEX deletion or quarantine work is scoped before source
  deletion begins.

### GHM-004: Minimal Reproducible Examples

Goal: provide examples that a new user can run locally for smoke tests and on a
cluster for production-scale validation.

Commit target:

- small Stephanov example with command, parameter file, expected output shape,
  and validation notes;
- no large datasets;
- no private scheduler assumptions in public docs.

### GHM-005: Dense WV-HMC Follow-up Validation Packet

Goal: when the next validation run is completed, commit only the compact
readback and reproducibility metadata.

Commit target:

- seed/bootstrap/block/window stability summary;
- comparison of `normal_reflect` and optional `full_bounce` only if both were
  intentionally run;
- no raw large output dumps;
- no scheduler cache or source-pin manifest churn.

### CLEAN-002: Full Modernization Cleanup Sprint

Status: complete on 2026-06-18.

Completion record:

- `codex/runbooks/CLEAN_002_RECONCILIATION_20260618.md`

Original target window: 2026-06-19 to 2026-06-23, after `GHM-001` and before
the next release-candidate tag.

Goal: make the workspace and governance state match the active modernization
workflow.

Completion criteria:

- `OPEN_ITEMS.tsv` and `CAVEATS.tsv` are reconciled with this milestone queue;
- stale active rows are marked closed, superseded, deferred, or moved into a
  clearly external workstream;
- generated runbooks and cluster-output evidence are reduced to compact
  pointers or archived outside the public commit path;
- private scheduler state remains local/internal and is not treated as public
  repo progress;
- `MODERNIZATION_WORKFLOW.md` and `MODERNIZATION_STATUS.md` remain the only
  active entrypoints.

This cleanup sprint is complete.  The local archives remain available in the
working tree but are ignored by Git unless a future milestone deliberately
promotes a compact evidence artifact.

### TECH-001: DOP853 Default / ODEX Deletion

Surface: `technical`, later `github`.

Status: queued after `GHM-001` / cleanup reconciliation.

Goal: finish the staged transition from legacy ODEX to DOP853 default.

`GHM-003` completed the public documentation surface.  This technical block is
the remaining source/diagnostic cleanup and must not delete legacy source until
the DOP853-default validation gate is accepted.

Completion criteria:

- public docs present DOP853 as the normal backend;
- ODEX-only tests/scripts are quarantined or deleted;
- neutral diagnostic names replace legacy ODEX-specific naming where needed;
- a DOP853-default validation gate is recorded before deleting legacy source;
- handwritten ODEX source and ODEX-only wrappers are removed only after the
  affected-baseline gate is accepted.

### TECH-002: WV-HMC Matrix-Free / BiCGStab Trajectory

Surface: `technical`, later `github`.

Status: deferred until the dense explicit-J public path and product package are
stable.

Goal: add the matrix-free WV-HMC route needed for high-dimensional work.

Completion criteria:

- explicit-J dense route remains the validation oracle;
- matrix-free projection / decomposition / solver contracts are specified;
- BiCGStab or equivalent iterative linear solve is tested against dense
  fixtures;
- trajectory reversibility, volume/phase, and observable smoke gates pass;
- performance/scaling readback is recorded separately from correctness gates.

### TECH-003: High-Dimensional Model Validation

Surface: `technical`, later `github`.

Status: deferred until model-provider onboarding and matrix-free planning are
ready.

Goal: validate that the generalized-thimble infrastructure can support a
non-toy high-dimensional model.

Completion criteria:

- model contract is frozen before sampler code changes;
- action, manual gradient, Hessian/Hessian-vector, and observables are
  independently validated;
- small-reference or exact/semianalytic checks exist where possible;
- HMC/WV/TLTM parameters are tuned by documented SOP, not by blind production
  runs;
- performance and correctness claims are separated.

### TECH-004: Reentrancy / OpenMP Readiness

Surface: `technical`, later `github`.

Status: deferred; do not claim OpenMP-ready before this closes.

Goal: remove or explicitly scope remaining shared-state and threading
boundaries.

Completion criteria:

- product-facing config/runtime state ownership is explicit;
- constraint statistics and captures have a merge/capture design for threaded
  scope;
- model/cache/tape state is audited for threaded product use;
- deterministic serial tests remain unchanged;
- OpenMP or library-parallel claims are only made after focused tests.

### TECH-005: TLTM Follow-Up Validation / Production Evidence

Surface: `technical`, later `github` only as compact readback.

Status: queued when a new TLTM validation question is selected.

Goal: keep TLTM as the mature canonical production workflow while WV-HMC
remains development-level.

Completion criteria:

- any new TLTM run has a clear physics question and source pin;
- compact observable/ESS/mixing readbacks are preferred over raw output dumps;
- scheduler artifacts remain internal;
- public claims use only compact, reviewed evidence.

### DOC-001: Release Candidate / Funding-Facing Package

Surface: `github`.

Status: next after `CLEAN-002`.

Goal: prepare a coherent release-candidate state for external review.

Completion criteria:

- README, user guide, sampler docs, validation docs, references, and changelog
  are mutually consistent;
- internal cluster assumptions are absent from public docs;
- release notes explain what is mature TLTM, what is dense WV-HMC validation,
  and what remains deferred;
- tag/release decision records exact commit and test evidence.

### EXT-001: Production-Comparison / Nofb Diagnostics Workstreams

Surface: `external`.

Status: tracked but not completed in this repo.

Goal: avoid mixing external production-comparison or nofb-diagnostics tasks
with this modernization workspace.

Completion criteria:

- external workstream TODOs are referenced only as boundaries;
- no production-comparison job is launched from this modernization repo;
- external outputs are not promoted as modernization GitHub milestones unless
  converted into compact public evidence.

## Dense WV-HMC Validation SOP

1. Fix the physics target, model provider, and parameter file.
2. Select the sampler interval `[T0,T1]` and soft-wall widths `[D0,D1]`.
3. Tune `W(t)` for flow-time coverage before relying on observable windows.
4. Tune `epsilon` from acceptance and movement.
5. Tune `nstep` / `L = epsilon*nstep` from configuration and flow-time
   movement.
6. Keep `boundary_policy=normal_reflect` unless explicitly benchmarking
   `full_bounce`.
7. Record measurement cuts separately from transition settings.  Measurement
   cuts must not feed back into transitions.
8. For Stephanov `n=6`, inspect burn and middle-flow-time windows; current
   benchmark evidence favors burn `2k..15k` and middle windows around
   `[0.006,0.024]` to `[0.008,0.022]`.
9. Use ratio-preserving seed jackknife for chiral condensate and number
   density.
10. Do not claim final WV-HMC production correctness from a single diagnostic
    window; require stability under seed/bootstrap/block/window checks.

## Product-Readiness Route

Before public/product claims:

- Public wrappers must default to `normal_reflect`.
- Product manifests must record `boundary_policy`.
- Documentation must state that `full_bounce` is optional benchmark behavior.
- TLTM remains the canonical mature production workflow.
- WV-HMC dense explicit-J remains validation/development level until
  high-dimensional and matrix-free validation is completed.

## Deferred Modernization Blocks

- WV-HMC matrix-free / BiCGStab trajectory wiring.
- High-dimensional model performance validation.
- Historical cluster output archive compaction.
- Broader documentation cleanup after the next release candidate.

## Workspace Cleanup Before Each Commit

Before preparing a GitHub commit:

1. Run `git status --short`.
2. Classify dirty files as public milestone, internal support, or old archive.
3. Stage only files belonging to the current GitHub milestone.
4. Leave scheduler ledgers, queue observations, source pins, live caches, and
   large generated dumps unstaged unless the milestone explicitly requires a
   compact reproducibility artifact.
5. Run the relevant build/test/docs checks for the staged scope.
6. Commit with a message that names the milestone.
