# M3 To M6 Before Dataset Regeneration Plan

Updated: 2026-05-10 JST
Scope: sequencing decision and executable modernization plan from the current M3 state to the pre-dataset M6 gate.

## Purpose

The project will not regenerate official datasets immediately after the M3 Stage2 protocol/schema work.

User decision, 2026-05-10 JST:

- Continue modernization through M6 first.
- Regenerate datasets only after the M6 pre-dataset gate is satisfied.
- Old dataset timing compatibility is not a constraint; the selected tempering convention is `local update -> swap -> measure/history/label trace`.

This avoids freezing new datasets against a still-moving wrapper, schema, config, RNG, diagnostics, and state-ownership surface.

## Current Position

M2 is functionally complete for the current canonical numerical route:

- Canonical p28 route: Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Flow policy: ODEX primary integration with solver-internal ODE assist only for NT/QN residual evaluation.
- Final proposal/live-chain construction: strict final `flow(...)`; solver assist cannot finalize proposals.
- Removed active legacy code: Radau/JFNK rescue, non-p28 QN families, global continuation/restart, post-refine route, positional config parsing, and unused initial-state file compatibility.
- State/status surface has started moving away from sentinel values and ambiguous booleans.

M3 is active:

- Architecture contract exists.
- TLTM plus standard replica-exchange tempering protocol design exists.
- v0 output inventory and protocol-audit plan exists.
- Parser-only Stage2 protocol audit exists.
- Adjacent-swap kernel contract test exists.
- Stage2 v1alpha sidecars exist behind opt-in env variables.
- Stage2 measurement/history/label trace now follows the selected post-swap boundary.

The remaining work is not dataset production. It is completing the product/software surface needed before datasets deserve to be regenerated.

## M3 Definition Of Done

M3 is complete when the selected tempering/output contract is executable and auditable across the current Stage workflow.

Required deliverables:

- Stage2 v1alpha sidecars are stable enough for downstream orchestration.
- Stage3 multiseed orchestration can preserve or report v1 sidecar paths per seed/run.
- Protocol audit can be run on Stage2 outputs and Stage3 summaries without manual reconstruction.
- v0 compatibility outputs remain readable while v1 sidecars declare protocol metadata explicitly.
- The selected post-swap measurement boundary is reflected in manifest/protocol metadata, audit checks, and status documents.

M3 does not require the final unified wrapper yet.

## M4 Definition Of Done

M4 is the guardrail phase.

Required deliverables:

- A repeatable local regression suite for core numerical kernels, Stage2 protocol invariants, sidecar schema checks, and parser readback.
- A documented minimal comparison matrix for source patches that touch proposal/control flow, RNG, output schema, config, or state ownership.
- Benchmark or timing harnesses for representative hot paths and workflows.
- Clear make/script entry points for audits so future refactors do not depend on memory of ad hoc commands.

M4 should protect behavior before broad refactors resume.

## M5 Definition Of Done

M5 is the repo-wide refactor phase.

Required deliverables:

- Typed config ownership advances beyond documentation and starts replacing direct legacy-global coupling at selected module boundaries.
- Diagnostics and output writing are separated from numerical kernels and orchestration where safe.
- State/status/result propagation uses explicit result categories for proposal construction, reverse-gate rejection, invalid Hamiltonian, invalid `Delta H`, ODE failure, solver convergence, and ordinary Metropolis rejection.
- Module-level `save` state, RNG ownership, and workspaces have a source-backed inventory and at least one completed behavior-preserving migration slice.
- Stage-specific scripts are cleaner compatibility layers, not the only source of product semantics.

M5 may include multiple commits and must proceed slice-by-slice with affected regression gates.

## M6 Definition Of Done

M6 is the pre-dataset product-readiness gate.

Required deliverables:

- A coherent TLTM runner/wrapper plan or implementation path is in place, with current Stage entry points either wrapped or explicitly retained as compatibility tools.
- The output package contract is versioned and documented enough for regenerated datasets to be interpreted without private context.
- Provenance fields are sufficient: git commit, algorithm id, flow policy, QN route, reverse-gate policy, tempering protocol, sweep order, measurement boundary, config, env overrides, seed policy, and writer version.
- Documentation, examples, audit commands, and release/checklist notes are synchronized with the current code.
- The project has a clear "dataset regeneration starts here" checklist.

M6 is the point after which official 10k -> 50k -> 100k and larger dataset regeneration can start.

## Dataset Regeneration Gate

Do not regenerate official datasets until all of these are true:

- M3 protocol/schema propagation is complete.
- M4 guardrails can be run routinely.
- M5 refactor slices that can affect output interpretation, status semantics, config, RNG, or state ownership are complete or explicitly deferred.
- M6 product-readiness docs and provenance contract are current.
- The command set for dataset regeneration, validation, and audit is written down.

Temporary smoke runs remain allowed for development, but they are not official datasets.

## Stop-For-Decision Rule

Do not stop for routine approval.

Stop for user decision only when the next step has multiple reasonable paths, no clear engineering or scientific winner, and the choice would affect at least one of these:

- physical definition or canonical algorithm semantics
- data/sample/history interpretation
- RNG or seed-stream semantics
- public output schema meaning, removal, or renaming
- long-term TLTM wrapper/product interface
- production workflow deletion
- dataset regeneration cost or provenance interpretation

Do not stop for:

- behavior-preserving hygiene/refactor
- source-backed audit/readback/test additions
- parser/reporting improvements that preserve existing fields
- already-confirmed M3 -> M6 sequencing work
- clear bug fixes to unsafe status, sentinel, or state-propagation handling
- appending sidecar/provenance metadata while preserving v0 compatibility readers

## Immediate Next Slice

The next executable modernization slice is M3 completion, not dataset production:

- Integrate Stage2 v1alpha sidecar paths into Stage3 multiseed orchestration.
- Add a Stage3-level protocol audit/readback path for sidecar-aware runs.
- Keep v0 compatibility outputs readable.
- Run only small local smoke/audit checks unless explicitly starting a production job later.

Implementation status:

- Completed on 2026-05-10 JST: `scripts/run_stage3_3_multiseed.py` gained opt-in Stage2 v1alpha sidecar propagation and protocol audit/readback.
- Chunk merge preserves the new sidecar/audit metadata columns when present.
- Verification included sidecar-on and sidecar-off tiny Stage3 smokes plus a one-chunk merge smoke.
