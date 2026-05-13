# Workstream Matrix And Current Position

Updated: 2026-05-13 JST

Scope: replace the misleading impression that M0-M6 is a linear "modernization completion" ladder. This file is the compact status matrix for what has actually been completed, what is active, what is deferred, and where the modernization workstream is now after the 2026-05-11 foundation-completeness reset.

## Position Summary

Current position:

```text
Reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> post-B RNG anchor added -> top-level TLTM run context selected -> flow/ODEX/HMC/QN flow context implemented -> official DFO-LS callback context implemented -> QN trace/eval context implemented -> QN diagnostics context implemented -> QN policy context implemented -> HMC policy/reverse-gate context decision point
```

Interpretation:

- M0-M6 did not complete all Fortran modernization, and it did not complete the foundation.
- M0-M6 established a canonical numerical route, deleted major legacy paths, added guardrails/provenance infrastructure, and accepted the first R1-R4 modernization behavior baseline.
- The active baseline gate is accepted as a behavior anchor. It is not evidence that every productization foundation is complete. ODEX is now closed by an explicit endpoint-only product boundary, official DFO-LS kernel correctness has a formal local gate, retained-core deterministic tests and diagnostics/accounting are closed for the pre-redo gate, route-B RNG stream ownership is implemented, flow/ODEX/HMC/QN trace/eval/diagnostics/policy context slices are implemented, while full OpenMP/thread-safe productization remains open.
- Production redo is no longer a modernization-tree completion gate. Redo must run in `tltm_production_comparison` and consume a frozen modernization commit plus declared contracts.
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
| W1 | Reference-backed algorithm audit | partial | TLTM/HMC, GT-HMC Newton/RATTLE/HMC, DFO-LS/DFO-GN, ODEX, and user QN formulation references collected; five core audit notes written; ODEX and official DFO-LS have scoped completion evidence | promote remaining open audit findings into foundation work; retained-core deterministic evidence and diagnostics accounting remain active | foundation reset gate |
| W2 | Canonical numerical route and legacy deletion | partial for final production, done for current modernization kernel route | canonical p28 route selected; non-p28 QN, Broyden/line-search, global continuation/restart, post-refine, Radau/JFNK removed; strict final-flow policy recorded; ODEX is closed by endpoint-only product boundary; F3 retained-core pre-redo harness, CV-001 official-line kernel gate, and F7 method aliases pass | current route still needs production-comparison redo scope/scale and CV-002 promotion boundary outside the modernization tree | production-comparison redo boundary |
| W3 | Behavior baselines and reference packages | done for M6 gate | M6 R1-R4 accepted; package registry rows recorded; readback report exists | formal read-only comparison tooling and future baseline expansion as needed | comparison tooling gate |
| W4 | Guardrails, tests, and benchmarks | partial | `make -C build modernization_guardrails`, ODEX/swap tests, official DFO-LS preset contract, protocol audit, Stage3 sidecar smoke, module dependency build support, offline external DFO-LS BTN residual comparison bridge, small embedded official DFO-LS captured-case gate, representative official DFO-LS embedded 10seed x 10k gate, retained-core Newton/RATTLE/QN/RG guardrails, complete F14 F3/F4/F7/F8 pre-redo gate, and CV-001 official-line kernel correctness gate | benchmark baselines, CI-like fast/slow suite split, and script-audit coverage | script-audit then RNG/reentrancy |
| W5 | Config and provenance governance | partial | key-value config only; direct env reads centralized in `runtime_env_mod`; sidecar manifest/protocol started; Stage2 sidecars guardrail official DFO-LS runtime env provenance keys; package-version provenance readback exists for `DFO-LS==1.6.5` / `GPL-3.0-or-later`; `DFOLS_CLAIM_PROVENANCE_POLICY_V1` separates official package evidence from historical/internal evidence | replace `param_mod` legacy global mirror, define product config schema, freeze final production provenance and compatibility conventions | script-audit then product schema |
| W6 | State/status/information propagation | partial | `H==0` sentinel replaced in first slice; proposal status surface added; state-propagation audit/refactor docs exist | typed result/status objects across flow, solver, RATTLE, HMC, reverse gate, Metropolis; eliminate ambiguous logical/error plumbing | reference package |
| W7 | Diagnostics/counter/accounting taxonomy | partial | local-transition typed event source, event-derived local counters, F4 audit schema, reverse-gate replay/counter suppression preserved, current output compatibility protected | broader status/result object propagation beyond the local-transition event and final product docs | post-redo architecture gate |
| W8 | Architecture, module boundaries, and subroutine APIs | planned | master plan and subroutine/API redesign guide exist; high-risk modules identified | target architecture spec, module dependency map, split mechanism/policy/diagnostics, slim large procedures | after W3 acceptance |
| W9 | RNG, workspace ownership, and reentrancy | active | route-B per-replica/per-slot RNG streams implemented; explicit mt95 state includes Gaussian spare state; Stage2 has a separate swap stream; post-B reference anchor is in M4; `decompose2`, QN linear-solver, Newton scratch, Stage2 audit state, flow/ODEX RHS scratch, HMC/QN local-update flow threading, official DFO-LS callback context, active QN trace/eval/watchdog context, QN diagnostics/capture sink context, and QN backend/watchdog policy context no longer use active shared `save` state; top-level `tltm_run_context_t` route selected with HMC/flow/QN sub-contexts started | full OpenMP/thread-safe productization: HMC fallback/reverse-gate policy/runtime/counters, explicit model/config/profile workspaces, behavior-bearing module `save` migration or scoping, counters/diagnostics/policy state, and deterministic serial/reentrant tests | decide HMC policy/reverse-gate context route |
| W10 | I/O, output schema, and wrapper/product interface | partial | Stage2 v1alpha sidecars, Stage3 propagation, protocol audit, M6 package design docs, F7 `nofb`/`withfb` aliases, and F8 patch-local reference statement schema | unified TLTM runner, full product schema, Stage script compatibility layer/deprecation | F14 scope/scale then wrapper productization |
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
- Current flow policy is endpoint-only ODEX backend for TLTM flow endpoint evaluation, closed by explicit product boundary rather than reduced scope. Solver-internal residual assist is default-off, diagnostic opt-in only, and not part of the canonical production policy.
- M3 Stage protocol/schema propagation is complete for the current Stage workflow.
- M4 local guardrail runner exists.
- External official-DFO-LS comparison bridge exists for captured BTN residual cases, with double-precision callback checks.
- GPL-compatible product direction is selected for official DFO-LS production replacement; Tapenade AD is recorded as an external MIT-licensed code-generation tool.
- Foundation gaps are now explicit: ODEX is closed by endpoint-only product boundary; official DFO-LS backend replacement is accepted for the current representative scope; CV-001 official-line kernel correctness is closed by formal gate; CV-006 claim policy is closed; CV-005 script/evidence audit is closed by a machine-checked registry; F3/F4/F7/F8 pre-redo gates are complete without reduced-scope acceptance; CV-011 has route-B RNG stream ownership, top-level HMC context ownership, Stage2 audit context ownership, flow/ODEX context ownership, HMC/QN local-update flow threading, official DFO-LS callback context, active QN trace/eval/watchdog context, QN diagnostics/capture sink context, and QN backend/watchdog policy context implemented but full OpenMP/thread-safe productization stays open. CV-002 final production-output promotion is external to modernization and belongs to `tltm_production_comparison`.
- M5 Lane A direct-env/config ownership slice is complete.
- Cluster02 scheduling is no longer ad hoc; it uses persistent priors plus fresh live state/probes.

## What Is Active Now

Active focus:

- Follow `FOUNDATION_CLOSURE_DECISIONS_20260512.md`, `MODERNIZATION_FINISH_DECISIONS_20260512.md`, `POST_B_RNG_REFERENCE_ANCHOR_20260512.md`, `CV011_TOP_LEVEL_RUN_CONTEXT_SLICE_20260512.md`, `CV011_FLOW_CONTEXT_SLICE_20260513.md`, `CV011_HMC_QN_FLOW_CONTEXT_SLICE_20260513.md`, `CV011_QN_OFFICIAL_CALLBACK_CONTEXT_SLICE_20260513.md`, `CV011_QN_TRACE_EVAL_CONTEXT_SLICE_20260513.md`, `CV011_QN_DIAGNOSTICS_CONTEXT_SLICE_20260513.md`, `CV011_QN_POLICY_CONTEXT_SLICE_20260513.md`, and `CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_DECISION_POINT_20260513.md` for the current closure queue. The immediate modernization-tree technical work is now the HMC fallback/reverse-gate context decision, with the post-B RNG reference anchor protecting the accepted route-B stream contract. Production redo scope/scale remains in the separate `tltm_production_comparison` tree.
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
2. Maintain the completed representative official DFO-LS backend evidence and reopen only on package/preset/callback/runtime/QN-route changes.
3. Keep production redo scope/scale in the production-comparison tree.
4. Deep-audit relevant tracked scripts before using them as modernization evidence.
5. Use the completed F8 harness for any behavior-relevant source patch.
6. Keep the post-B route-B RNG reference anchor in M4.
7. Continue RNG/reentrancy/module-workspace migration through full OpenMP/thread-safe productization, with deterministic serial/reentrant checks.
8. Only then start broader architecture/API and wrapper productization slices.

The operational runbook for this sequence is:

- `runbooks/FOUNDATION_COMPLETENESS_RESET_20260511.md`
- `runbooks/MODERNIZATION_FORWARD_WORKSTEPS_20260511.md`

## Rule For Future Planning

Do not describe modernization progress as "M6 means done."

Use this phrasing instead:

```text
M6 is the accepted behavior-baseline gate. The numerical/software foundation is not complete; active foundation gaps must be resolved or explicitly scoped before production-grade source modernization or final production regeneration.
```
