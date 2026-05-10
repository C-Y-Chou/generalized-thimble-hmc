# Parallel Workstream Boundary And Reference Dataset Policy

Updated: 2026-05-10 JST

Scope: define the boundary between the Stage3_4 production comparison work and the Fortran modernization work. This document is a guardrail against mixing production-job planning with modernization baseline planning.

## Two Parallel Workstreams

### Stage3_4 Production Comparison

Owner workspace: `codex/workspaces/stage3_4`

Purpose:

- complete the `nofb` vs `withfb` TLTM production comparison;
- manage production/intermediate job scheduling, queue usage, output roots, merges, and analysis;
- decide whether the Stage3_4 workspace should be renamed/reorganized for continuity with later production work;
- own any deletion, relocation, or archival of Stage3_4 production/intermediate artifacts.

Modernization may read its outputs, but must not silently submit, delete, rename, or reinterpret Stage3_4 production work.

### Fortran Modernization / Code Refine

Owner workspace: `codex/workspaces/fortran_modernization`

Purpose:

- modernize/refactor the Fortran code while preserving physics behavior;
- maintain local guardrails, protocol audits, provenance/readback checks, and sidecar contracts;
- define the reference dataset/package needed to protect later modernization work;
- use the Stage3_4 production-comparison task as workflow context when designing modernization references.

This workspace does not own the plan for completing the final `nofb` vs `withfb` production campaign.

## Terminology

- `Local smoke / guardrail artifact`: tiny generated outputs used only to verify builds, parsers, sidecars, and protocol-audit plumbing.
- `Stage3_4 production intermediate`: outputs from the `nofb` vs `withfb` production comparison path, including validation/judgment chunks and merged summaries.
- `Modernization reference dataset/package`: a curated behavior-preservation package used by future code-refine work. It can be designed to match the Stage3_4 workflow context, but it is not itself the final physics-production campaign.
- `Final analysis dataset`: the downstream physics-analysis product after the production comparison workflow has produced and interpreted its official outputs.

## Modernization Reference Dataset Target

The modernization reference package should be aligned with the production comparison target:

- comparison: `nofb` vs `withfb`;
- current method mapping: `nofb == no_fb`, `withfb == canonical fallback-enabled no-post-refine p28 route` unless Stage3_4 records a newer canonical name;
- physical point: `t = 0.35`, `L = 2`, `nstep = 20`;
- route: Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis;
- flow policy: ODEX primary integration plus solver-internal residual assist, with strict final `flow(...)` for live proposals;
- protocol: replica-exchange-style `local update -> swap -> measure/history/label trace`;
- provenance: commit, config, seed policy, env overrides, sidecars, audit verdict, merged summaries, and evaluation outputs.

This target is a design contract for modernization. The Stage3_4 workspace owns how the production comparison is actually completed.

## What Modernization May Do

- Build local smoke/guardrail artifacts.
- Add or improve readers, auditors, sidecar readback, provenance validators, and summary comparators.
- Define the reference-package manifest and acceptance criteria.
- Generate or register reference datasets that align with the Stage3_4 workflow context when needed.
- Use the reference package to guard later refactors, cleanup, state redesign, wrapper work, or output-schema migration.

## What Modernization Must Not Do

- Submit Stage3_4 production jobs from this workspace.
- Delete or move Stage3_4 production/intermediate outputs.
- Decide final production queue strategy, chunking, or workspace renaming.
- Treat local `output/tests` smoke artifacts as the final dataset.
- Call the production comparison complete merely because modernization guardrails pass.

## Reference Package Acceptance Criteria

Before using a Stage3_4-context-aligned package as a modernization reference baseline, confirm:

- branch and commit are recorded;
- config files and seed policy are frozen or archived;
- v0 summaries and v1alpha sidecars are present where required;
- protocol audit passes for all included seeds/chunks;
- merged per-seed summaries preserve sidecar/audit metadata columns;
- key physical observables and diagnostic counters are summarized;
- any known deviations from earlier Stage3_4 characterization are documented;
- the package location is recorded in `state/` and in the modernization status runbook.

## Current Decision

User clarification on 2026-05-10 JST:

- `output/tests` and Stage3_4 chunk outputs should not be described as the dataset itself.
- The final production comparison is a separate Stage3_4 workstream: `nofb` vs `withfb` at `t=0.35`, `L=2`, `nstep=20`.
- The modernization workstream should use that work only as a reference source for future behavior-preserving refactors.
