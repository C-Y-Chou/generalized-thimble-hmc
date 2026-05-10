# M3 To M6 Before Modernization Reference Package Plan

Updated: 2026-05-10 JST
Scope: sequencing decision and executable modernization plan from the current M3 state to the M6 modernization reference-package gate.

## Purpose

The modernization workstream will not build/register reference datasets immediately after the M3 Stage2 protocol/schema work.

User decision, 2026-05-10 JST:

- Continue modernization through M6 first.
- Build/register modernization reference datasets only after the M6 gate is satisfied.
- Keep final `nofb` vs `withfb` production completion in the Stage3_4 workstream.
- Old dataset timing compatibility is not a constraint; the selected tempering convention is `local update -> swap -> measure/history/label trace`.

This avoids freezing modernization reference baselines against a still-moving wrapper, schema, config, RNG, diagnostics, and state-ownership surface.

## Current Position

M2 is functionally complete for the current canonical numerical route:

- Canonical p28 route: Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Flow policy: ODEX primary integration with solver-internal ODE assist only for NT/QN residual evaluation.
- Final proposal/live-chain construction: strict final `flow(...)`; solver assist cannot finalize proposals.
- Removed active legacy code: Radau/JFNK rescue, non-p28 QN families, global continuation/restart, post-refine route, positional config parsing, and unused initial-state file compatibility.
- State/status surface has started moving away from sentinel values and ambiguous booleans.

M3/M4/M5/M6 current status:

- M3 protocol/schema propagation is complete for the current Stage workflow: architecture contract, TLTM/replica-exchange protocol design, v0 inventory, parser-only audit, swap-kernel test, opt-in Stage2 v1alpha sidecars, Stage3 sidecar propagation, and post-swap measurement/history/label trace are in place.
- M4 local guardrail entry point is complete: `make -C build modernization_guardrails` covers Python compile, diff hygiene, direct-env centralization, Stage2/eval build, ODEX/swap tests, protocol audit, sidecar-on/off smokes, and chunk-merge metadata preservation.
- M5 direct-env/config ownership and pre-M6 gate assessment are complete. High-risk RNG/workspace/model-cache/schema-removal/global-config replacement work is explicitly deferred until stronger baselines or user decisions exist.
- M6 reference-dataset product-readiness docs are in place: product-readiness plan, reference checklist, provenance/readback checklist, parallel-workstream boundary policy, reference-dataset design spec, readback plan, and code-entry gate.

The remaining work is not Stage3_4 production. It is completing the product/software surface needed before modernization references deserve to be built/registered and trusted.

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

Initial implementation status:

- Completed on 2026-05-10 JST: `scripts/run_m4_guardrails.py` and `make -C build modernization_guardrails` provide the first repeatable local guardrail entry point.
- Verification passed through both direct script invocation and the make target.

## M5 Definition Of Done

M5 is the repo-wide refactor phase.

Required deliverables:

- Typed config ownership advances beyond documentation and starts replacing direct legacy-global coupling at selected module boundaries.
- Diagnostics and output writing are separated from numerical kernels and orchestration where safe.
- State/status/result propagation uses explicit result categories for proposal construction, reverse-gate rejection, invalid Hamiltonian, invalid `Delta H`, ODE failure, solver convergence, and ordinary Metropolis rejection.
- Module-level `save` state, RNG ownership, and workspaces have a source-backed inventory and at least one completed behavior-preserving migration slice.
- Stage-specific scripts are cleaner compatibility layers, not the only source of product semantics.

M5 may include multiple commits and must proceed slice-by-slice with affected regression gates.

Implementation status:

- Completed Lane A direct-env/config ownership consolidation on 2026-05-10 JST.
- All direct `get_environment_variable` calls are centralized in `runtime_env_mod`.
- Source-backed M5 inventory and pre-M6 gate assessment are available in `M5_STATE_CONFIG_OWNERSHIP_PLAN.md` and `M5_PRE_M6_GATE_ASSESSMENT.md`.
- Deferred items are documented rather than silently skipped.

## M6 Definition Of Done

M6 is the modernization reference-dataset product-readiness gate.

Required deliverables:

- A coherent TLTM runner/wrapper plan or implementation path is in place, with current Stage entry points either wrapped or explicitly retained as compatibility tools.
- The output package contract is versioned and documented enough for modernization reference packages to be interpreted without private context.
- Provenance fields are sufficient: git commit, algorithm id, flow policy, QN route, reverse-gate policy, tempering protocol, sweep order, measurement boundary, config, env overrides, seed policy, and writer version.
- Documentation, examples, audit commands, and release/checklist notes are synchronized with the current code.
- The project has a clear "modernization reference package starts here" checklist.

M6 is the point after which the modernization workstream can build/register 10k -> 50k -> 100k and larger reference datasets. The final `nofb` vs `withfb` production comparison remains a separate Stage3_4 workstream.

Implementation status:

- `M6_REFERENCE_DATASET_PRODUCT_READINESS_PLAN.md` records the wrapper/product direction and provenance contract.
- `M6_REFERENCE_DATASET_CHECKLIST.md` records the modernization reference-package preflight and 10k -> 50k -> 100k validation ladder.
- `M6_PROVENANCE_READBACK_CHECKLIST.md` records v1alpha sidecar, Stage3 metadata, audit, and merge-readback requirements.
- `PARALLEL_WORKSTREAM_BOUNDARY_AND_REFERENCE_DATASET_POLICY.md` records the boundary between Stage3_4 production and modernization reference data.
- `M6_REFERENCE_DATASET_DESIGN_SPEC.md` records the modernization reference-dataset design, using Stage3_4 as workflow context rather than a required result source.
- `M6_REFERENCE_DATASET_READBACK_PLAN.md` records acceptance states and readback checks.
- `M6_REFERENCE_DATASET_GENERATION_AND_COVERAGE_PLAN.md` records R0-R4 reference levels, refactor coverage, and the ready-to-generate gate.
- `M6_TO_CODE_MODERNIZATION_ENTRY_GATE.md` records when source-code modernization can resume.
- Modernization reference-dataset construction/registration is still paused at the R1 generation gate until the user explicitly starts it.

## Modernization Reference-Package Gate

Do not build/register modernization reference datasets until all of these are true:

- M3 protocol/schema propagation is complete.
- M4 guardrails can be run routinely.
- M5 refactor slices that can affect output interpretation, status semantics, config, RNG, or state ownership are complete or explicitly deferred.
- M6 product-readiness docs and provenance contract are current.
- The command set for reference-dataset construction/registration, validation, and audit is written down.

Temporary smoke runs remain allowed for development, but they are not the final dataset and are not sufficient as modernization reference packages.

## Stop-For-Decision Rule

Do not stop for routine approval.

Stop for user decision only when the next step has multiple reasonable paths, no clear engineering or scientific winner, and the choice would affect at least one of these:

- physical definition or canonical algorithm semantics
- data/sample/history interpretation
- RNG or seed-stream semantics
- public output schema meaning, removal, or renaming
- long-term TLTM wrapper/product interface
- production workflow deletion
- modernization reference-package cost or provenance interpretation

Do not stop for:

- behavior-preserving hygiene/refactor
- source-backed audit/readback/test additions
- parser/reporting improvements that preserve existing fields
- already-confirmed M3 -> M6 sequencing work
- clear bug fixes to unsafe status, sentinel, or state-propagation handling
- appending sidecar/provenance metadata while preserving v0 compatibility readers

## Immediate Next Slice

The next executable action is user review of the M6/reference-package gate, not Stage3_4 production.

If the user starts modernization reference-dataset construction/registration later:

- Run `make -C build modernization_guardrails`.
- Freeze branch/commit/config/seed list/output roots.
- Enable Stage2 v1alpha sidecars and protocol audit.
- Start the validation ladder at 10k before 50k and 100k.
- If aligning to the Stage3_4 production task, record the Stage3_4 context assumptions: `nofb` vs `withfb`, `t=0.35`, `L=2`, `nstep=20`, method mapping, protocol, and diagnostics to preserve.

Until then, only small local smoke/audit checks should run.
