# Workstream Matrix And Current Position

Updated: 2026-05-11 JST

Scope: replace the misleading impression that M0-M6 is a linear "modernization completion" ladder. This file is the compact status matrix for what has actually been completed, what is active, what is deferred, and where the modernization workstream is now after the 2026-05-11 foundation-completeness reset.

## Position Summary

Current position:

```text
Reference-audited core + accepted M6 behavior baseline -> foundation gaps still active -> source modernization remains gated
```

Interpretation:

- M0-M6 did not complete all Fortran modernization, and it did not complete the foundation.
- M0-M6 established a canonical numerical route, deleted major legacy paths, added guardrails/provenance infrastructure, and accepted the first R1-R4 modernization behavior baseline.
- The active baseline gate is accepted as a behavior anchor. It is not evidence that ODEX, official DFO-LS, retained-core deterministic tests, diagnostics/accounting, RNG/workspace ownership, or wrapper/schema foundations are complete.
- The next roadmap should be organized by workstream status, not by pretending the M-number ladder is a complete modernization sequence.
- `FOUNDATION_COMPLETENESS_RESET_20260511.md` is now required reading before continuing modernization.

## Status Legend

- `done`: complete for the current canonical route, with normal maintenance only.
- `partial`: meaningful implementation exists, but the workstream still has major remaining blocks.
- `active`: current operational focus.
- `deferred`: intentionally postponed until accepted reference package, wrapper/schema decision, or explicit user approval.
- `planned`: identified but not yet implemented.

## Workstream Matrix

| ID | Workstream | Status | Completed / Current Assets | Remaining Work | Next Gate |
| --- | --- | --- | --- | --- | --- |
| W0 | Governance, memory, and remote safety | partial | L0/L1 control-plane memory, remote/job/worktree registries, cluster02 scheduler agent, no-`qmove` repair policy | keep registries fresh; remote branch/worktree semantic rename after pinned jobs finish | ongoing maintenance |
| W1 | Reference-backed algorithm audit | partial | TLTM/HMC, GT-HMC Newton/RATTLE/HMC, DFO-LS/DFO-GN, ODEX, and user QN formulation references collected; five core audit notes written | promote all open audit findings into foundation work; ODEX completeness, official DFO-LS completion, retained-core deterministic evidence, and diagnostics accounting remain active | foundation reset gate |
| W2 | Canonical numerical route and legacy deletion | partial for foundation, done for current route | canonical p28 route selected; non-p28 QN, Broyden/line-search, global continuation/restart, post-refine, Radau/JFNK removed; strict final-flow policy recorded; ODEX is accepted reduced-scope endpoint backend | current route still needs official-DFO-LS-line correctness evidence, retained-core deterministic replay, and schema-compatible naming cleanup | deterministic evidence gate |
| W3 | Behavior baselines and reference packages | done for M6 gate | M6 R1-R4 accepted; package registry rows recorded; readback report exists | formal read-only comparison tooling and future baseline expansion as needed | comparison tooling gate |
| W4 | Guardrails, tests, and benchmarks | partial | `make -C build modernization_guardrails`, ODEX/swap tests, official DFO-LS preset contract, protocol audit, Stage3 sidecar smoke, module dependency build support, offline external DFO-LS BTN residual comparison bridge | official reference comparison harness, benchmark baselines, CI-like fast/slow suite split, official DFO-LS captured-case readback, retained-core deterministic replay pack | foundation reset gate |
| W5 | Config and provenance governance | partial | key-value config only; direct env reads centralized in `runtime_env_mod`; sidecar manifest/protocol started; Stage2 sidecars now guardrail official DFO-LS runtime env provenance keys; local package-version provenance readback exists for `DFO-LS==1.6.5` / `GPL-3.0-or-later` | replace `param_mod` legacy global mirror, define product config schema, carry package provenance through representative remote/production runs | reference package or explicit narrow baseline |
| W6 | State/status/information propagation | partial | `H==0` sentinel replaced in first slice; proposal status surface added; state-propagation audit/refactor docs exist | typed result/status objects across flow, solver, RATTLE, HMC, reverse gate, Metropolis; eliminate ambiguous logical/error plumbing | reference package |
| W7 | Diagnostics/counter/accounting taxonomy | partial | known issue recorded; reverse-gate replay/counter suppression preserved; current output compatibility protected | typed diagnostics context separating forward proposal, reverse replay, solver assist, debug probe, rejected stay-put, accepted event | schema/versioning gate |
| W8 | Architecture, module boundaries, and subroutine APIs | planned | master plan and subroutine/API redesign guide exist; high-risk modules identified | target architecture spec, module dependency map, split mechanism/policy/diagnostics, slim large procedures | after W3 acceptance |
| W9 | RNG, workspace ownership, and reentrancy | deferred | thread-safety target recorded; module-level state risks inventoried at high level | per-run/per-replica RNG streams, explicit workspaces, module `save` migration, deterministic parallel tests | accepted baselines plus explicit RNG decision |
| W10 | I/O, output schema, and wrapper/product interface | partial | Stage2 v1alpha sidecars, Stage3 propagation, protocol audit, M6 package design docs | unified TLTM runner, versioned public schema, `withfb`/algorithm-id naming, Stage script compatibility layer/deprecation | wrapper/schema decision |
| W11 | Repo-wide code hygiene and Fortran cleanup | partial | explicit `only:` imports for `param_mod`/`utils`, duplicated env helpers removed, stale root Fortran artifacts deleted, build deps improved | long subroutine decomposition, naming cleanup, duplicate helper cleanup, allocation/workspace style cleanup, comments/equation notes | affected baseline row |
| W12 | Scripts, PBS orchestration, and cluster operations | partial | cluster02 scheduler agent, dynamic M6 launcher, probe-first queue optimization, shared-cluster model, soft-decoupled production-comparison workspace | mature production/reference launch interface and future archive cleanup | after explicit run/readback scope |
| W13 | Documentation, onboarding, and publishable release | partial | many runbooks and reference docs exist; README pointers improved; GPL-3.0-or-later root license and third-party notices started for official DFO-LS/Tapenade toolchain | coherent user/dev docs, examples, release checklist, citation/reproducibility package, reviewer-facing workflow, complete third-party dependency lock/notices | after wrapper/schema stabilization |

## What Is Already Done

These should not be reopened unless new evidence appears:

- Five-core reference-backed audit reached discussion/decision level, but this is not final foundation signoff.
- Canonical p28 route is Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine is deleted from active source.
- Known non-p28 QN route families are deleted from active source.
- Radau/JFNK rescue stack is deleted from active source.
- Current flow policy is accepted reduced-scope ODEX endpoint extrapolation with solver-internal residual assist only for residual evaluation; final proposals use strict final `flow(...)`.
- M3 Stage protocol/schema propagation is complete for the current Stage workflow.
- M4 local guardrail runner exists.
- External official-DFO-LS comparison bridge exists for captured BTN residual cases, with double-precision callback checks.
- GPL-compatible product direction is selected for official DFO-LS production replacement; Tapenade AD is recorded as an external MIT-licensed code-generation tool.
- Foundation gaps are now explicit: ODEX is accepted reduced scope; official DFO-LS backend completion, retained-core deterministic evidence, diagnostics/accounting, and RNG/workspace ownership are not complete.
- M5 Lane A direct-env/config ownership slice is complete.
- Cluster02 scheduling is no longer ad hoc; it uses persistent priors plus fresh live state/probes.

## What Is Active Now

Active focus:

- Follow `FOUNDATION_COMPLETENESS_RESET_20260511.md` and `MODERNIZATION_FORWARD_WORKSTEPS_20260511.md` for the foundation-gap-gated forward queue.
- Do not start high-risk source refactors without an explicit reference-comparison plan against the accepted M6 packages or a narrower affected baseline.
- Remote cleanup, fast-forward, or rename is now possible only after a fresh refresh and explicit scope check.

Current active remote target:

- semantic id: `fortran_modernization`
- physical path: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- branch: `codex/fortran-modernization`
- generation commit: see `codex/state/WORKTREES.tsv` for the latest refresh
- latest refresh: no active pinned M6 jobs remain in the modernization worktree; production-comparison jobs may be active in the separate provisional worktree

## What Remains After M6 Baseline Acceptance

Recommended order after accepted M6 reference package, now refined by the foundation-gap reset:

1. Reset foundation status and keep all active foundation gaps in `CAVEATS.tsv`/`OPEN_ITEMS.tsv`.
2. Complete official DFO-LS embedded-backend captured-attempt comparison and TLTM residual readback.
3. Build retained-core deterministic evidence for Newton/RATTLE/QN/HMC/RG.
4. Repair diagnostics/status/accounting foundation.
5. Build read-only reference comparison tooling around the accepted package.
6. Normalize public method names and schema roles only after the relevant foundation rows are clear.
7. Start architecture/API design slices under explicit affected-baseline rows.
9. Only then approach RNG/reentrancy/module-workspace migration and wrapper productization.

The operational runbook for this sequence is:

- `runbooks/FOUNDATION_COMPLETENESS_RESET_20260511.md`
- `runbooks/MODERNIZATION_FORWARD_WORKSTEPS_20260511.md`

## Rule For Future Planning

Do not describe modernization progress as "M6 means done."

Use this phrasing instead:

```text
M6 is the accepted behavior-baseline gate. The numerical/software foundation is not complete; active foundation gaps must be resolved or explicitly scoped before production-grade source modernization or final production regeneration.
```
