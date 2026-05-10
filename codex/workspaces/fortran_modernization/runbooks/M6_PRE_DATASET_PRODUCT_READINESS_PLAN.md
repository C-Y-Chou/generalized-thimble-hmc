# M6 Pre-Dataset Product Readiness Plan

Updated: 2026-05-10 JST

Scope: define the product-readiness gate that must be satisfied before official regenerated TLTM datasets begin. This is a planning/contract document, not a production job submission and not a final public wrapper-name decision.

## M6 Goal

M6 makes the current TLTM implementation interpretable as a mature coding project/product before expensive datasets are regenerated.

M6 does not require deleting Stage scripts or completing long-term OpenMP/reentrant architecture work. It requires that the retained Stage workflow, v1 sidecars, provenance fields, audit commands, and dataset start checklist are coherent enough that new datasets will not need to be reinterpreted later from private context.

## Product Interface Direction

Current compatibility entry points remain valid:

- `make -C build tltm_stage2`
- `make -C build stage3_3`
- `scripts/run_stage3_3_multiseed.py`
- `scripts/merge_stage3_multiseed_chunks.py`
- `scripts/audit_tltm_tempering_protocol.py`

M6 target interface:

- Keep Stage2/Stage3 scripts as compatibility/internal tools.
- Add a thin TLTM runner/wrapper path later that orchestrates the same config, Stage2 execution, audit, sidecar package, merge, and evaluation steps.
- Do not choose the final public executable name in this document.
- Do not delete existing scripts/PBS wrappers before wrapper compatibility exists and the user explicitly approves deletion.

Recommended wrapper modes:

- `production`: run the canonical p28 TLTM chain with v1 sidecars and v0 compatibility outputs.
- `diagnostic`: run small fixed-seed checks with expanded counters and protocol audit.
- `benchmark`: run timing/guardrail workloads without declaring official datasets.
- `regression`: run deterministic local smokes used by modernization guardrails.

## Canonical Algorithm Contract For New Datasets

The canonical algorithm contract to declare in run provenance is:

- Canonical route: Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Flow policy: ODEX primary integration plus solver-internal ODE assist for Newton/QN residual evaluation.
- Final proposal policy: strict final `flow(...)`; solver assist cannot finalize live-chain proposals.
- Tempering convention: replica-exchange-style `local update -> swap -> measure/history/label trace`.
- Swap kernel: adjacent exchange with invalid reflow treated as rejection without state mutation.
- Reverse gate: permanent part of the proposal definition, not a debug-only diagnostic.
- Failure-as-rejection: valid MCMC handling for proposal construction failure, with explicit status/counter reporting.

## Provenance Contract

Every official regenerated run must record:

- git commit and branch
- compiler and linked numerical libraries
- algorithm id
- canonical route id
- flow policy id
- ODEX sequence id
- QN p28 policy and budgets
- reverse-gate policy and tolerance
- tempering protocol id
- sweep order and measurement boundary
- flow ladder
- Stage2/Stage3 config snapshot or digest
- env overrides
- seed list and seed policy
- output writer/schema version
- v0 compatibility-output status
- protocol-audit command and verdict
- M4 guardrail command and verdict

The current v1alpha sidecars already cover part of this contract. M6 should finish the documentation/readback contract before dataset regeneration.

## Output Package Contract

Short-term:

- Continue writing v0 summaries, label traces, histories, and Stage3 CSVs so existing readers remain usable.
- Enable v1alpha sidecars for official regenerated datasets.
- Preserve sidecar paths and protocol-audit verdicts through Stage3 per-seed and aggregate summaries.

Target v1 package:

- `manifest.json`: provenance, config, env overrides, seed policy, algorithm/policy ids, output compatibility status.
- `protocol.json`: local kernel, swap kernel, sweep order, measurement boundary, failure-as-rejection semantics.
- `diagnostics/`: local transition counters, swap counters, label accounting, solver/flow/reverse-gate summaries.
- `observables/`: per-slot phase/observable summaries and evaluation metadata.
- `compatibility/`: copied or referenced v0 outputs when needed for transition.

Do not rename or remove v0 public fields until v1 readers and a migration map exist.

## M6 Required Deliverables

M6 is complete when these are present and current:

- M6 product-readiness plan: this document.
- Dataset-regeneration checklist with exact preflight, run, audit, and analysis steps.
- Provenance/readback checklist for v1alpha sidecars and Stage3 summaries.
- README/docs update pointing new work to the current M3-M6 workflow and guardrails.
- Explicit deferral list for RNG ownership, large `save` workspace migration, model/tape cache ownership, public schema deprecation, and full `param_mod` global replacement.

## Dataset Regeneration Start Checklist

Official regeneration may start only when all are true:

- Git worktree is clean.
- The intended branch/commit is recorded.
- `make -C build modernization_guardrails` passes.
- No direct env reads exist outside `runtime_env_mod`.
- Stage3 sidecar-on tiny smoke passes and preserves sidecar metadata through merge.
- Stage2 protocol audit passes for the intended configuration.
- v1alpha sidecars are enabled for production runs.
- The config, seed list, flow ladder, sweep order, measurement boundary, and output directories are recorded.
- The run plan starts with 10k -> 50k -> 100k validation before larger campaigns.
- Physical observables, acceptance/reverse-gate diagnostics, failure counters, and protocol audit verdicts are reviewed at each scale.

## Not In M6

- Final public wrapper executable naming.
- Deleting Stage scripts/PBS wrappers.
- Moving RNG ownership or changing stream semantics.
- Large solver/flow/HMC/model workspace migration.
- Removing v0 output fields.
- Changing p28 route, reverse gate, ODE assist boundary, final-flow strictness, or Metropolis acceptance semantics.

## Immediate Next Slice

The next M6 slice should be documentation/readback, not physics code:

- Add the dataset-regeneration checklist.
- Update project README/docs to point to M4 guardrails, M5 gate assessment, and M6 pre-dataset requirements.
- Keep all production jobs paused until the user explicitly starts dataset regeneration.
