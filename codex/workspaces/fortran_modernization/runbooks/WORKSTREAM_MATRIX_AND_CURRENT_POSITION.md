# Workstream Matrix And Current Position

Updated: 2026-05-14 JST

Scope: replace the misleading impression that M0-M6 is a linear "modernization completion" ladder. This file is the compact status matrix for what has actually been completed, what is active, what is deferred, and where the modernization workstream is now after the 2026-05-11 foundation-completeness reset.

## Position Summary

Current position:

```text
Reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> post-B RNG anchor added -> top-level TLTM run context selected -> flow/ODEX/HMC/QN flow context implemented -> official DFO-LS callback context implemented -> QN trace/eval context implemented -> QN diagnostics context implemented -> QN policy context implemented -> HMC policy/reverse-gate context implemented -> F15 navigation-assist candidate implemented and then demoted -> profile context implemented -> HMC reversibility diagnostics context implemented -> Newton eval-flow status context implemented -> Stage2 RNG v2 implemented -> assist deletion scheduled against official DFO-LS npt5_r0055 assist-off baseline -> remaining constraint/flow/model/config state boundaries
```

Interpretation:

- M0-M6 did not complete all Fortran modernization, and it did not complete the foundation.
- M0-M6 established a canonical numerical route, deleted major legacy paths, added guardrails/provenance infrastructure, and accepted the first R1-R4 modernization behavior baseline.
- The active baseline gate is accepted as a behavior anchor. It is not evidence that every productization foundation is complete. ODEX is now closed by an explicit endpoint-only product boundary, official DFO-LS kernel correctness has a formal local gate, retained-core deterministic tests and diagnostics/accounting are closed for the pre-redo gate, route-B RNG stream ownership is implemented, flow/ODEX/HMC/QN trace/eval/diagnostics/policy context slices are implemented, HMC fallback/reverse-gate policy/runtime/replay diagnostics context is implemented, F15 navigation-assist strict-certification policy is implemented and M4-gated locally but no longer canonical after the 2026-05-15 assist-deletion decision, profiler context ownership, HMC reversibility diagnostics context ownership, and Newton eval-flow status context ownership are implemented, while full OpenMP/thread-safe productization remains open.
- Current solver-policy starting point is `ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md`: official DFO-LS `npt5_r0055`, true Stage2 RNG v2, method-level assist off, with 10seed/10k readback `nofb` failures `8340` mean Re `-0.002818340294982019`, and `withfb` failures `167` mean Re `0.02974362444598664`.
- Production redo is no longer a modernization-tree completion gate. Redo must run in `tltm_production_comparison` and consume a frozen modernization commit plus declared contracts.
- The 2026-05-13 assist-diagnostic branch is no longer an active production path.  Keep those readbacks as evidence, but active work has converged back to `fortran_modernization` source closure and `tltm_production_comparison` post-fix regeneration.  Its RNG finding is a modernization requirement: use `CV011_STAGE2_KERNEL_RNG_V2_DESIGN_20260514.md` before further RNG/reentrancy work.
- The 2026-05-14 handwritten-algorithm detail audit gap is active as CV-012.  Reference-backed core mapping, deterministic guardrails, M4/F8, and production readbacks are not enough to claim every hand-authored controller/detail branch is paper-correct.  Use `HANDWRITTEN_ALGORITHM_DETAIL_AUDIT_GAP_REPORT_20260514.md`, `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`, and `HANDWRITTEN_ALGORITHM_CURRENT_ANALYSIS_REPORT_20260514.md` before making paper-level implementation claims or changing controller constants/branches as cleanup.
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
| W1 | Reference-backed algorithm audit | active | TLTM/HMC, GT-HMC Newton/RATTLE/HMC, DFO-LS/DFO-GN, ODEX, and user QN formulation references collected; five core audit notes written; ODEX and official DFO-LS have scoped completion evidence; CV-012 gap report, ODEX controller detail audit, and handwritten-algorithm current analysis report now separate reference mapping, behavior baselines, deterministic evidence, and paper-level implementation-detail signoff | convert ODEX controller open-needs-proof surfaces into deterministic tests and explicit accept/patch decisions, then continue BTN/QN controller policy, RATTLE failure/status paths, Stage2 tempering/swap replay, and diagnostics/counters | CV-012 detail-audit packet |
| W2 | Canonical numerical route and legacy deletion | partial for final production, active for assist deletion | canonical p28 route selected; non-p28 QN, Broyden/line-search, global continuation/restart, post-refine, Radau/JFNK removed; typed F15 solver-assist policy implemented and then demoted to historical/diagnostic evidence; 2026-05-15 decision schedules solver assist for deletion against the official DFO-LS `npt5_r0055` assist-off baseline; ODEX is closed by endpoint-only product boundary; F3 retained-core pre-redo harness, CV-001 official-line kernel gate, and F7 method aliases pass | remove solver-assist policy/machinery under F8/M4 after preserving the assist-off baseline; audit withfb feedback-kernel measure preservation separately; production-comparison redo scope/scale and CV-002 promotion stay outside the modernization tree | assist-off deletion baseline plus production-comparison redo boundary |
| W3 | Behavior baselines and reference packages | done for M6 gate | M6 R1-R4 accepted; package registry rows recorded; readback report exists | formal read-only comparison tooling and future baseline expansion as needed | comparison tooling gate |
| W4 | Guardrails, tests, and benchmarks | partial | `make -C build modernization_guardrails`, ODEX/swap tests, official DFO-LS preset contract, protocol audit, Stage3 sidecar smoke, module dependency build support, offline external DFO-LS BTN residual comparison bridge, small embedded official DFO-LS captured-case gate, representative official DFO-LS embedded 10seed x 10k gate, retained-core Newton/RATTLE/QN/RG guardrails, complete F14 F3/F4/F7/F8 pre-redo gate, and CV-001 official-line kernel correctness gate | benchmark baselines, CI-like fast/slow suite split, and script-audit coverage | script-audit then RNG/reentrancy |
| W5 | Config and provenance governance | partial | key-value config only; direct env reads centralized in `runtime_env_mod`; sidecar manifest/protocol started; Stage2 sidecars guardrail official DFO-LS runtime env provenance keys; package-version provenance readback exists for `DFO-LS==1.6.5` / `GPL-3.0-or-later`; `DFOLS_CLAIM_PROVENANCE_POLICY_V1` separates official package evidence from historical/internal evidence | replace `param_mod` legacy global mirror, define product config schema, freeze final production provenance and compatibility conventions | script-audit then product schema |
| W6 | State/status/information propagation | partial | `H==0` sentinel replaced in first slice; proposal status surface added; state-propagation audit/refactor docs exist | typed result/status objects across flow, solver, RATTLE, HMC, reverse gate, Metropolis; eliminate ambiguous logical/error plumbing | reference package |
| W7 | Diagnostics/counter/accounting taxonomy | partial | local-transition typed event source, event-derived local counters, F4 audit schema, reverse-gate replay/counter suppression preserved, current output compatibility protected | broader status/result object propagation beyond the local-transition event and final product docs | post-redo architecture gate |
| W8 | Architecture, module boundaries, and subroutine APIs | planned | master plan and subroutine/API redesign guide exist; high-risk modules identified | target architecture spec, module dependency map, split mechanism/policy/diagnostics, slim large procedures | after W3 acceptance |
| W9 | RNG, workspace ownership, and reentrancy | active | route-B per-replica/per-slot RNG streams implemented; explicit mt95 state includes Gaussian spare state; Stage2 has a separate swap stream; post-B reference anchor is in M4; later assist-regression evidence shows `per_replica_rng_v1` is not production-equivalent by default; Stage2 RNG v2 is implemented and recorded in `CV011_STAGE2_KERNEL_RNG_V2_IMPLEMENTATION_20260514.md`; `decompose2`, QN linear-solver, Newton scratch, Stage2 audit state, flow/ODEX RHS scratch, HMC/QN local-update flow threading, official DFO-LS callback context, active QN trace/eval/watchdog context, QN diagnostics/capture sink context, QN backend/watchdog policy context, HMC fallback/reverse-gate policy/runtime/replay diagnostics context, profiler context ownership, HMC reversibility/progress diagnostic context ownership, and Newton eval-flow status context ownership no longer use active shared `save` state on their implemented product paths; top-level `tltm_run_context_t` route selected with HMC/flow/QN/profile/diagnostics sub-contexts started | continue full OpenMP/thread-safe productization: explicit model/config workspaces, remaining behavior-bearing module `save` migration or scoping, constraint/flow diagnostics state, and deterministic serial/reentrant tests | Stage2 RNG v2 anchor plus M4 |
| W10 | I/O, output schema, and wrapper/product interface | partial | Stage2 v1alpha sidecars, Stage3 propagation, protocol audit, M6 package design docs, F7 `nofb`/`withfb` aliases, and F8 patch-local reference statement schema | unified TLTM runner, full product schema, Stage script compatibility layer/deprecation | F14 scope/scale then wrapper productization |
| W11 | Repo-wide code hygiene and Fortran cleanup | partial | explicit `only:` imports for `param_mod`/`utils`, duplicated env helpers removed, stale root Fortran artifacts deleted, build deps improved | behavior-preserving dead-trigger cleanup, strange-name cleanup, long subroutine decomposition, duplicate helper cleanup, allocation/workspace style cleanup, comments/equation notes | affected baseline row |
| W12 | Scripts, PBS orchestration, and cluster operations | partial | cluster02 scheduler agent, dynamic M6 launcher, probe-first queue optimization, shared-cluster model, soft-decoupled production-comparison workspace | mature production/reference launch interface and future archive cleanup | after explicit run/readback scope |
| W13 | Documentation, onboarding, and publishable release | partial | many runbooks and reference docs exist; README pointers improved; GPL-3.0-or-later root license and third-party notices started for official DFO-LS/Tapenade toolchain | coherent user/dev docs, examples, release checklist, citation/reproducibility package, reviewer-facing workflow, complete third-party dependency lock/notices | after wrapper/schema stabilization |

## What Is Already Done

These should not be reopened unless new evidence appears:

- Five-core reference-backed audit reached discussion/decision level, but this is not final foundation signoff.
- Canonical p28 route is Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine is deleted from active source.
- Known non-p28 QN route families are deleted from active source.
- Radau/JFNK rescue stack is deleted from active source.
- Current flow policy is endpoint-only ODEX backend for TLTM flow endpoint evaluation, closed by explicit product boundary rather than reduced scope.  The older "solver-internal residual assist is default-off, diagnostic opt-in only" statement is superseded by implemented F15 policy: fallback-on is now the canonical candidate, with strict NT, QN navigation assist, and unassisted certification/final-flow/RG/Metropolis.
- M3 Stage protocol/schema propagation is complete for the current Stage workflow.
- M4 local guardrail runner exists.
- External official-DFO-LS comparison bridge exists for captured BTN residual cases, with double-precision callback checks.
- GPL-compatible product direction is selected for official DFO-LS production replacement; Tapenade AD is recorded as an external MIT-licensed code-generation tool.
- Foundation gaps are now explicit: ODEX is closed by endpoint-only product boundary; official DFO-LS backend replacement is accepted for the current representative scope; CV-001 official-line kernel correctness is closed by formal gate; CV-006 claim policy is closed; CV-005 script/evidence audit is closed by a machine-checked registry; F3/F4/F7/F8 pre-redo gates are complete without reduced-scope acceptance; F15 navigation-assist strict-certification policy is implemented and locally gated; CV-011 has route-B RNG stream ownership, top-level HMC context ownership, Stage2 audit context ownership, flow/ODEX context ownership, HMC/QN local-update flow threading, official DFO-LS callback context, active QN trace/eval/watchdog context, QN diagnostics/capture sink context, QN backend/watchdog policy context, HMC fallback/reverse-gate context, profiler context ownership, HMC reversibility/progress diagnostic context ownership, and Newton eval-flow status context ownership implemented but full OpenMP/thread-safe productization stays open. CV-002 final production-output promotion is external to modernization and belongs to `tltm_production_comparison`.
- M5 Lane A direct-env/config ownership slice is complete.
- Cluster02 scheduling is no longer ad hoc; it uses persistent priors plus fresh live state/probes.

## What Is Active Now

Active focus:

- Follow `FOUNDATION_CLOSURE_DECISIONS_20260512.md`, `MODERNIZATION_FINISH_DECISIONS_20260512.md`, `POST_B_RNG_REFERENCE_ANCHOR_20260512.md`, `CV011_STAGE2_KERNEL_RNG_V2_IMPLEMENTATION_20260514.md`, `CV011_TOP_LEVEL_RUN_CONTEXT_SLICE_20260512.md`, `CV011_FLOW_CONTEXT_SLICE_20260513.md`, `CV011_HMC_QN_FLOW_CONTEXT_SLICE_20260513.md`, `CV011_QN_OFFICIAL_CALLBACK_CONTEXT_SLICE_20260513.md`, `CV011_QN_TRACE_EVAL_CONTEXT_SLICE_20260513.md`, `CV011_QN_DIAGNOSTICS_CONTEXT_SLICE_20260513.md`, `CV011_QN_POLICY_CONTEXT_SLICE_20260513.md`, `CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_SLICE_20260513.md`, `CV011_PROFILE_CONTEXT_SLICE_20260513.md`, `CV011_HMC_REVERSIBILITY_CONTEXT_SLICE_20260513.md`, and `CV011_NEWTON_FLOW_STATUS_CONTEXT_SLICE_20260513.md` for the current closure queue. The immediate modernization-tree technical work is now triaging the next remaining behavior-bearing state boundary. Production redo scope/scale remains in the separate `tltm_production_comparison` tree.
- Keep `HANDWRITTEN_ALGORITHM_DETAIL_AUDIT_GAP_REPORT_20260514.md`, `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`, and `HANDWRITTEN_ALGORITHM_CURRENT_ANALYSIS_REPORT_20260514.md` active for claim boundaries.  They do not block behavior-preserving source work by themselves, but they block publication-grade statements that all handwritten numerical algorithms are paper-correct until detail-audit packets close the touched surfaces.
- F15 fallback-on solver policy is implemented and locally M4-gated, but it is no longer canonical.  The 2026-05-15 decision schedules solver assist for deletion and fixes the next modernization entry point at `ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md`.  Its PBS wrapper now separates the evidence SHA from the explicitly pinned run SHA, so later governance-only HEADs are not confused with the readback-producing commit.  The later assist/root-cause diagnostic tree is closed; production now waits for a clean modernization commit with an affected-baseline gate before any regeneration.
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
7. Continue RNG/reentrancy/module-workspace migration through full OpenMP/thread-safe productization, with deterministic serial/reentrant checks. The HMC fallback/reverse-gate, profiler, HMC reversibility diagnostics, and Newton eval-flow status context slices are closed; remaining targets include constraint aggregate/failure-capture diagnostics state, solve-flow fallback/trace/failure state, model tape/cache state, and config mirror ownership.
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
