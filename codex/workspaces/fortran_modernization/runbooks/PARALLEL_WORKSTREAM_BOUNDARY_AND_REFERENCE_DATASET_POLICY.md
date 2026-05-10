# Parallel Workstream Boundary And Reference Dataset Policy

Updated: 2026-05-10 JST

Scope: define the boundary between the `tltm_production_comparison` production-comparison work and the Fortran modernization work. This document is a guardrail against mixing production-job planning with modernization baseline planning.

## Two Parallel Workstreams

### TLTM Production Comparison

Owner workspace: `codex/workspaces/tltm_production_comparison`

Legacy alias: `stage3_4`

Purpose:

- complete the `nofb` vs `withfb` TLTM production comparison;
- manage production/intermediate job scheduling, queue usage, output roots, merges, and analysis;
- own any deletion, relocation, or archival of legacy Stage3_4 and current production-comparison artifacts.

Modernization may read its outputs, but must not silently submit, delete, rename, or reinterpret production-comparison work.

### Fortran Modernization / Code Refine

Owner workspace: `codex/workspaces/fortran_modernization`

Purpose:

- modernize/refactor the Fortran code while preserving physics behavior;
- maintain local guardrails, protocol audits, provenance/readback checks, and sidecar contracts;
- define the reference dataset/package needed to protect later modernization work;
- use the production-comparison task as workflow context when designing modernization references.

This workspace does not own the plan for completing the final `nofb` vs `withfb` production campaign.

## Terminology

- `Local smoke / guardrail artifact`: tiny generated outputs used only to verify builds, parsers, sidecars, and protocol-audit plumbing.
- `Production-comparison intermediate`: outputs from the `nofb` vs `withfb` production comparison path, including validation/judgment chunks and merged summaries.
- `Modernization reference dataset/package`: a curated behavior-preservation package used by future code-refine work. It can be designed to match the production-comparison workflow context, but it is not itself the final physics-production campaign.
- `Final analysis dataset`: the downstream physics-analysis product after the production comparison workflow has produced and interpreted its official outputs.

## Modernization Reference Dataset Target

The modernization reference package should be aligned with the production comparison target:

- comparison: `nofb` vs `withfb`;
- current method mapping: `nofb == no_fb`, `withfb == canonical fallback-enabled no-post-refine p28 route` unless `tltm_production_comparison` records a newer canonical name;
- physical point: `t = 0.35`, `L = 2`, `nstep = 20`;
- route: Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis;
- flow policy: ODEX primary integration plus solver-internal residual assist, with strict final `flow(...)` for live proposals;
- protocol: replica-exchange-style `local update -> swap -> measure/history/label trace`;
- provenance: commit, config, seed policy, env overrides, sidecars, audit verdict, merged summaries, and evaluation outputs.

This target is a design contract for modernization. The `tltm_production_comparison` workspace owns how the production comparison is actually completed.

## What Modernization May Do

- Build local smoke/guardrail artifacts.
- Add or improve readers, auditors, sidecar readback, provenance validators, and summary comparators.
- Define the reference-package manifest and acceptance criteria.
- Generate or register reference datasets that align with the production-comparison workflow context when needed.
- Use the reference package to guard later refactors, cleanup, state redesign, wrapper work, or output-schema migration.

## What Modernization Must Not Do

- Submit production-comparison jobs from this workspace.
- Delete or move production-comparison intermediate outputs.
- Decide final production queue strategy, chunking, or workspace renaming.
- Treat local `output/tests` smoke artifacts as the final dataset.
- Call the production comparison complete merely because modernization guardrails pass.

## Reference Package Acceptance Criteria

Before using a production-comparison-context-aligned package as a modernization reference baseline, confirm:

- branch and commit are recorded;
- config files and seed policy are frozen or archived;
- v0 summaries and v1alpha sidecars are present where required;
- protocol audit passes for all included seeds/chunks;
- merged per-seed summaries preserve sidecar/audit metadata columns;
- key physical observables and diagnostic counters are summarized;
- any known deviations from earlier production-comparison characterization are documented;
- the package location is recorded in `state/` and in the modernization status runbook.

## Current Decision

User clarification on 2026-05-10 JST:

- `output/tests` and legacy Stage3_4 chunk outputs should not be described as the dataset itself.
- The final production comparison is a separate `tltm_production_comparison` workstream: `nofb` vs `withfb` at `t=0.35`, `L=2`, `nstep=20`.
- The modernization workstream should use that work only as a reference source for future behavior-preserving refactors.
