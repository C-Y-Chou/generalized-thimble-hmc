# M6 Reference Dataset Generation And Coverage Plan

Updated: 2026-05-10 JST

Scope: define the exact plan up to, but not including, modernization reference dataset generation.

This document does not run jobs, generate outputs, edit Fortran, or touch production artifacts. It defines what will be generated later, why each reference exists, and which future modernization work each reference can protect.

## Current Position

Modernization is stopped at the pre-generation gate.

Completed planning inputs:

- Stage3_4 is a workflow/design context, not a required result source.
- The target workflow context is `nofb` vs `withfb` at `t=0.35`, `L=2`, `nstep=20`.
- Current method mapping is `nofb == no_fb` and `withfb == fb_norefine` unless intentionally renamed later.
- Canonical numerical route is Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Flow policy is ODEX primary plus solver-internal residual assist, with strict final `flow(...)` for live proposals.
- Tempering protocol is `local update -> swap -> measure/history/label trace`.
- Local M4 guardrails exist through `make -C build modernization_guardrails`.

Reference dataset generation itself is the next distinct phase and should not begin until this plan is reviewed or explicitly accepted.

## Reference Dataset Levels

### Level R0: Local Guardrail Artifacts

Purpose:

- verify build, parser, sidecar, audit, and merge plumbing;
- catch obvious accidental breakage;
- support documentation and tooling edits.

Status:

- already covered by M4 guardrails;
- not a reference dataset;
- not sufficient for behavior-changing source modernization.

Can protect:

- docs-only changes;
- read-only auditor/checklist updates;
- local parser/report additions that preserve existing fields;
- build dependency hygiene that does not affect compiler flags or runtime behavior.

Cannot protect:

- RNG order changes;
- state/status ownership changes;
- solver route changes;
- public schema meaning changes;
- physics-output-preservation claims.

### Level R1: Deterministic Micro Reference

Purpose:

- create a small, fixed-seed, sidecar-enabled reference package for route/counter/readback checks;
- exercise both `no_fb` and `withfb` under the Stage3_4 workflow context;
- validate manifest/readback tooling before expensive runs.

Proposed shape:

- physical point: `t=0.35`, `L=2`, `nstep=20`;
- methods: `no_fb`, `fb_norefine`;
- seeds: small matched set;
- cycles: tiny enough for quick rerun;
- sidecars: on;
- protocol audit: on and fail-on-error;
- output root: under a modernization reference namespace, not Stage3_4 production.

Can protect:

- readback tooling;
- v0/v1 sidecar preservation;
- method mapping;
- protocol timing checks;
- local counter presence/field compatibility.

Cannot protect:

- statistical physics conclusions;
- performance baselines;
- RNG/state refactors that can alter long-run trajectory properties.

### Level R2: 10k Matched Reference

Purpose:

- first serious behavior-preservation reference for source modernization;
- capture matched `no_fb` vs `withfb` behavior under the real workflow context;
- provide enough diagnostic counters to detect major route/failure-status regressions.

Proposed shape:

- physical point: `t=0.35`, `L=2`, `nstep=20`;
- methods: `no_fb`, `fb_norefine`;
- matched seeds;
- cycles: 10k;
- sidecars: on;
- protocol audit: on and fail-on-error;
- merged per-seed and aggregate summaries;
- evaluation summary for physical observables.

Can protect:

- low-risk sloppy implementation cleanup outside hot numerical kernels;
- parser/reporting additions preserving fields;
- narrow state/status patches that are expected to preserve algorithm semantics;
- early wrapper/readback scaffolding that does not change RNG order or proposal route.

Needs caution:

- trajectory-changing refactors can be compared diagnostically but should not be fully accepted from R2 alone unless user approves the risk.

### Level R3: 50k Matched Reference

Purpose:

- medium-scale guard against subtle route, status, and acceptance-rate regressions;
- strengthen confidence before broader module/API cleanup.

Proposed shape:

- same physical point, method mapping, sidecar/audit, and matched-seed policy as R2;
- cycles: 50k;
- aggregate diagnostic and observable summaries.

Can protect:

- moderate module cleanup;
- state/status information-flow refactors when RNG/proposal semantics are not expected to change;
- diagnostic taxonomy cleanup;
- wrapper orchestration that preserves execution semantics.

Still should not alone approve:

- RNG stream migration;
- module `save` workspace migration;
- broad `param_mod` global replacement;
- public schema deletion/renaming.

### Level R4: 100k Matched Reference

Purpose:

- main modernization reference baseline before high-risk code ownership refactors;
- provide stronger physical-observable and diagnostic stability checks.

Proposed shape:

- same physical point, method mapping, sidecar/audit, and matched-seed policy as R2/R3;
- cycles: 100k;
- merged summaries, audit summaries, diagnostics, and evaluation outputs.

Can protect:

- higher-risk state/status refactors;
- wrapper/API migration that preserves public semantics;
- config/context ownership changes with strict comparison;
- gradual module-boundary cleanup.

Still requires explicit decision for:

- RNG stream redesign;
- OpenMP/reentrant execution changes;
- large module `save` workspace migration;
- public schema field removal/renaming;
- any algorithmic change to p28, reverse gate, ODE assist boundary, final-flow strictness, or Metropolis semantics.

## Coverage Matrix

| Future modernization area | Minimum reference level before source changes | Notes |
| --- | --- | --- |
| Documentation-only updates | R0 | No dataset generation required. |
| Read-only audit/readback tooling | R0 | Tooling must not mutate outputs. |
| Local parser/report additions preserving fields | R0 or R1 | R1 if package metadata is touched. |
| Code hygiene in non-physics utilities | R2 | Must preserve output schema and RNG/proposal behavior. |
| Diagnostic/counter naming additions | R2 | Existing fields must remain stable. |
| State/status propagation cleanup | R2 -> R4 | Use R2 for narrow patches; R4 for broader ownership changes. |
| HMC/Markov state object redesign | R4 plus explicit decision | High risk for live-state semantics. |
| `param_mod` global replacement | R4 plus explicit decision | Requires config/context comparison plan. |
| RNG ownership or seed-stream migration | R4 plus explicit decision | RNG order is behavior. |
| Module `save` workspace migration | R4 plus explicit decision | Risk to counters, caches, and execution order. |
| Wrapper/API replacing Stage behavior | R3/R4 plus explicit interface decision | Must preserve compatibility or version migration. |
| Public output schema removal/renaming | R4 plus explicit schema decision | v0 readers must not be broken silently. |
| Numerical algorithm policy changes | Separate physics decision | Not a modernization cleanup. |

## Required Outputs For R1-R4

Each generated reference package should include:

- manifest with package id, class, branch, commit, dirty status, compiler summary, config digests, seed policy, method mapping, and output roots;
- v0 compatibility outputs;
- v1alpha manifest/protocol sidecars where enabled;
- protocol audit JSON/text or summary;
- per-seed summary table;
- aggregate summary/report;
- evaluation output for physical observables;
- diagnostic counters for proposal failures, reverse gate, ODE/final-flow status, Newton/QN residuals, solver assist, acceptance, and runtime;
- package-specific readback note;
- row in `state/M6_REFERENCE_PACKAGES.tsv`.

## Pre-Generation Checklist

Before starting R1 generation:

- worktree is clean or the doc-only planning commit is complete;
- current branch and commit are recorded;
- `make -C build modernization_guardrails` passes;
- reference package output root naming is chosen;
- seed policy is chosen and recorded;
- `no_fb` and `fb_norefine` method mapping is confirmed;
- sidecars and protocol audit are enabled for reference-grade runs;
- R1 command plan is written down without ambiguity;
- no Stage3_4 production output path is reused.

Before starting R2/R3/R4:

- previous lower level is accepted or explicitly waived;
- readback plan has been exercised at the previous level;
- output root and seed policy are frozen;
- expected runtime/resource impact is recorded;
- user explicitly starts that reference generation level.

## Stop-For-Decision Points

Stop before generation if:

- `withfb` naming should no longer be `fb_norefine`;
- seed policy is not obvious;
- reference output root could conflict with Stage3_4 production;
- sidecar/audit requirements would materially increase runtime or storage;
- user wants 3_4 production to own part of the reference generation;
- a refactor needs a narrower baseline than R1-R4;
- any planned reference would alter the physical algorithm.

## Ready-To-Generate Definition

Modernization is ready to start R1 reference generation when:

- this plan is committed;
- renamed M6 reference-dataset docs are committed;
- the worktree is clean;
- local guardrails pass;
- the user explicitly says to start reference dataset generation.

Until then, no reference dataset generation, production job submission, output cleanup, or source-code modernization should occur in this workstream.
