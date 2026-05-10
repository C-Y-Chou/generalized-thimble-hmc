# Workstream Matrix And Current Position

Updated: 2026-05-10 JST

Scope: replace the misleading impression that M0-M6 is a linear "modernization completion" ladder. This file is the compact status matrix for what has actually been completed, what is active, what is deferred, and where the modernization workstream is now.

## Position Summary

Current position:

```text
Completed foundation -> Accepted M6 reference baseline -> Remaining modernization blocks
```

Interpretation:

- M0-M6 did not complete all Fortran modernization.
- M0-M6 established the canonical numerical route, deleted major legacy paths, added guardrails/provenance infrastructure, and accepted the first R1-R4 modernization reference baseline.
- The active baseline gate is now accepted. Larger architecture/API/RNG/state/schema refactors should use the accepted M6 packages as comparison anchors.
- The next roadmap should be organized by workstream status, not by pretending the M-number ladder is a complete modernization sequence.

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
| W1 | Reference-backed algorithm audit | done | TLTM/HMC, GT-HMC Newton/RATTLE/HMC, DFO-LS/DFO-GN, ODEX, and user QN formulation references collected; five core audit notes written | revisit only when a new algorithm mode or paper formulation is introduced | reference changes |
| W2 | Canonical numerical route and legacy deletion | done for current route | canonical p28 route selected; non-p28 QN, Broyden/line-search, global continuation/restart, post-refine, Radau/JFNK removed; strict final-flow policy recorded | rename legacy compatibility labels such as `fb_norefine` and `final_resort` only under versioned schema | schema/wrapper gate |
| W3 | Behavior baselines and reference packages | done for M6 gate | M6 R1-R4 accepted; package registry rows recorded; readback report exists | formal read-only comparison tooling and future baseline expansion as needed | comparison tooling gate |
| W4 | Guardrails, tests, and benchmarks | partial | `make -C build modernization_guardrails`, ODEX/swap tests, protocol audit, Stage3 sidecar smoke, module dependency build support | official reference comparison harness, benchmark baselines, CI-like fast/slow suite split | after accepted reference package |
| W5 | Config and provenance governance | partial | key-value config only; direct env reads centralized in `runtime_env_mod`; sidecar manifest/protocol started | replace `param_mod` legacy global mirror, define product config schema, strengthen manifest/provenance contract | reference package or explicit narrow baseline |
| W6 | State/status/information propagation | partial | `H==0` sentinel replaced in first slice; proposal status surface added; state-propagation audit/refactor docs exist | typed result/status objects across flow, solver, RATTLE, HMC, reverse gate, Metropolis; eliminate ambiguous logical/error plumbing | reference package |
| W7 | Diagnostics/counter/accounting taxonomy | partial | known issue recorded; reverse-gate replay/counter suppression preserved; current output compatibility protected | typed diagnostics context separating forward proposal, reverse replay, solver assist, debug probe, rejected stay-put, accepted event | schema/versioning gate |
| W8 | Architecture, module boundaries, and subroutine APIs | planned | master plan and subroutine/API redesign guide exist; high-risk modules identified | target architecture spec, module dependency map, split mechanism/policy/diagnostics, slim large procedures | after W3 acceptance |
| W9 | RNG, workspace ownership, and reentrancy | deferred | thread-safety target recorded; module-level state risks inventoried at high level | per-run/per-replica RNG streams, explicit workspaces, module `save` migration, deterministic parallel tests | accepted baselines plus explicit RNG decision |
| W10 | I/O, output schema, and wrapper/product interface | partial | Stage2 v1alpha sidecars, Stage3 propagation, protocol audit, M6 package design docs | unified TLTM runner, versioned public schema, `withfb`/algorithm-id naming, Stage script compatibility layer/deprecation | wrapper/schema decision |
| W11 | Repo-wide code hygiene and Fortran cleanup | partial | explicit `only:` imports for `param_mod`/`utils`, duplicated env helpers removed, stale root Fortran artifacts deleted, build deps improved | long subroutine decomposition, naming cleanup, duplicate helper cleanup, allocation/workspace style cleanup, comments/equation notes | affected baseline row |
| W12 | Scripts, PBS orchestration, and cluster operations | partial | cluster02 scheduler agent, dynamic M6 launcher, probe-first queue optimization, shared-cluster model, soft-decoupled production-comparison workspace | mature production/reference launch interface and future archive cleanup | after explicit run/readback scope |
| W13 | Documentation, onboarding, and publishable release | planned | many runbooks and reference docs exist; README pointers improved | coherent user/dev docs, examples, release checklist, citation/reproducibility package, reviewer-facing workflow | after wrapper/schema stabilization |

## What Is Already Done

These should not be reopened unless new evidence appears:

- Five-core reference-backed audit reached discussion/decision level.
- Canonical p28 route is Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine is deleted from active source.
- Known non-p28 QN route families are deleted from active source.
- Radau/JFNK rescue stack is deleted from active source.
- Current flow policy is ODEX primary with solver-internal residual assist only; final proposals use strict final `flow(...)`.
- M3 Stage protocol/schema propagation is complete for the current Stage workflow.
- M4 local guardrail runner exists.
- M5 Lane A direct-env/config ownership slice is complete.
- Cluster02 scheduling is no longer ad hoc; it uses persistent priors plus fresh live state/probes.

## What Is Active Now

Active focus:

- Select the next remaining modernization block using this matrix.
- Do not start high-risk source refactors without an explicit reference-comparison plan against the accepted M6 packages or a narrower affected baseline.
- Remote cleanup, fast-forward, or rename is now possible only after a fresh refresh and explicit scope check.

Current active remote target:

- semantic id: `fortran_modernization`
- physical path: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- branch: `codex/fortran-modernization`
- generation commit: `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`
- latest refresh: no active pinned M6 jobs remain

## What Remains After M6 Baseline Acceptance

Recommended order after accepted M6 reference package:

1. Build read-only reference comparison tooling around the accepted package.
2. Normalize public method names and schema roles: keep raw legacy aliases readable, but expose canonical roles such as `nofb` and `withfb` or explicit algorithm IDs.
3. Start architecture/API design slices in non-physics utility/config/output layers first.
4. Move state/status/result propagation toward typed objects.
5. Refactor diagnostics/counters into a structured accounting context.
6. Only then approach RNG/reentrancy/module-workspace migration.
7. Build unified TLTM wrapper and gradually demote Stage scripts to compatibility layers.

## Rule For Future Planning

Do not describe modernization progress as "M6 means done."

Use this phrasing instead:

```text
M6 is the accepted reference-baseline gate. The modernization foundation is complete enough to protect behavior with accepted packages, but the main architecture/API/state/RNG/schema/productization blocks remain as separate workstreams.
```
