# TLTM Fortran Modernization Master Plan

## Mission
Turn the TLTM Fortran codebase into a mature, maintainable, verifiable, and publishable scientific software project while preserving the underlying physics and approved numerical behavior.

## End-state qualities
- architecture is explicit and enforced by practice, not only by documentation
- core solver semantics are understandable and locally reasoned about
- outputs are reproducible and protected by regression checks
- performance is measured and defended with benchmarks
- the project is approachable for new contributors and external reviewers

## Primary workstreams
### 1. Architecture recovery
- audit actual module dependencies
- identify responsibility violations and oversized modules
- define a target architecture with stable boundaries

### 2. Subroutine and API redesign
- reduce oversized procedure responsibilities
- define explicit contracts for solver inputs, outputs, workspaces, and failures
- eliminate semantic drift in shared mathematical objects

### 3. Constraint-solver chain redesign
- separate residual model, Newton solver, quasi-Newton solver, rescue policy, and diagnostics
- move research routing logic out of the deepest numerical kernels

### 4. Configuration and state governance
- reduce legacy-global leakage from `param_mod`
- classify stable config, research toggles, and environment overrides
- keep run provenance explicit

### 5. Verification and regression protection
- establish baseline tests and reference runs
- build solver-level regression checks and scientific invariants
- define exact-preservation versus numerical-equivalence acceptance rules

### 6. Observability and performance engineering
- unify diagnostic taxonomy and machine-readable summaries
- maintain benchmark baselines for hot paths and representative workflows

### 7. State, status, and information propagation
- replace ambiguous logical error chains and sentinel numeric values with typed status contracts
- separate live chain state, trial proposal state, strict proposal construction, solver-internal assist, and diagnostics
- make rejected proposal, unavailable Hamiltonian, invalid residual, ODE boundary, solver convergence, and proposal-failure states explicit
- ensure counters distinguish physical proposal events from diagnostic/replay/assist work

### 8. Productization and publication readiness
- keep documentation synchronized with implementation
- define release, reproducibility, and review expectations
- make the codebase legible to new developers and external evaluators

## Execution phases
### Phase 0. Audit and baselines
- produce architecture and module risk audit
- map solver-chain control flow
- record verification baselines for representative workloads

### Phase 1. Design freeze
- write target architecture and API redesign specs
- define solver-chain redesign boundaries
- define config governance and observability schema

### Phase 2. Guardrails first
- add regression tests, invariant checks, and benchmark harnesses
- make behavior-preservation checks runnable and routine

### Phase 3. Core refactor sequence
- clean config/state coupling
- consolidate residual semantics
- refactor state/status propagation and ODE failure/assist status handling
- split solver kernels from routing logic
- slim large integrator and driver modules
- externalize diagnostics and counters where appropriate

### Phase 4. Productization
- finalize documentation, review checklists, release discipline, and publication-facing artifacts

## Current Milestone Map - 2026-05-10

Important clarification:

- M0-M6 is not a full modernization-completion ladder.
- M0-M6 is the completed foundation plus active reference-baseline/product-readiness gate.
- Use `WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md` as the compact source of truth for what is done, active, deferred, and still planned.

The historical milestone map is M0-M6:

- M0: planning and governance established.
- M1: temporary characterization baseline collected from the completed Stage3_4/TLTM judgment context.
- M2: canonical numerical route and core legacy deletion/canonicalization completed for the current p28 policy.
- M3: architecture, tempering protocol, output schema, Stage2 sidecars, and Stage3 protocol propagation.
- M4: guardrail tests, parser/readback checks, protocol audits, and benchmark harnesses.
- M5: repo-wide refactor waves for typed config, explicit state/status propagation, diagnostics, output ownership, RNG/state inventory, and module boundaries.
- M6: modernization reference-dataset product-readiness package, unified wrapper direction, provenance contract, docs, examples, and release/checklist notes. This is a baseline gate, not modernization completion.

Current sequencing decision:

- The Stage3_4 workstream owns final `nofb` vs `withfb` production completion.
- Modernization reference-dataset construction/registration waits until after M6.
- Small smoke/regression runs may still be used during development, but they are not final datasets and are not sufficient modernization reference packages.
- See `M3_TO_M6_BEFORE_REFERENCE_DATASET_PLAN.md` for the executable gate sequence.

Current implementation status:

- M3 protocol/schema propagation is complete for the current Stage workflow.
- M4 local guardrails are available through `make -C build modernization_guardrails`.
- M5 direct-env/config ownership is complete; high-risk RNG/workspace/model-cache/schema-removal/global-config replacement work is explicitly deferred in `M5_PRE_M6_GATE_ASSESSMENT.md`.
- M6 product-readiness docs are available in `M6_REFERENCE_DATASET_PRODUCT_READINESS_PLAN.md`, `M6_REFERENCE_DATASET_CHECKLIST.md`, `M6_PROVENANCE_READBACK_CHECKLIST.md`, `PARALLEL_WORKSTREAM_BOUNDARY_AND_REFERENCE_DATASET_POLICY.md`, `M6_REFERENCE_DATASET_DESIGN_SPEC.md`, `M6_REFERENCE_DATASET_READBACK_PLAN.md`, `M6_REFERENCE_DATASET_GENERATION_AND_COVERAGE_PLAN.md`, and `M6_TO_CODE_MODERNIZATION_ENTRY_GATE.md`.
- Modernization is active at the reference-dataset generation/readback gate.
- Future source-code modernization is gated by an accepted reference package or explicit user approval of a narrower baseline.

## Post-TLTM Workflow Update - 2026-05-29

The active modernization sequence has narrowed around TLTM closure before adding
a second sampler path.

Authoritative workflow documents:

- `PARAMETER_TUNING_SOP_20260531.md`: repository-wide dependency order for
  sampler parameter tuning across TLTM and WV-HMC.
- `INIT_BANK_TUNING_SOP_20260531.md`: repository-wide initial-bank build,
  validation, safe-flow filtering, and record-selection policy.
- `TLTM_CANONICAL_SOP_20260528.md`: TLTM production workflow order and canonical
  nofb boundary.
- `MODERNIZATION_POST_TLTM_WORKFLOW_20260528.md`: repository-level sequence for
  closing TLTM, stabilizing shared infrastructure, and then adding WV-HMC.  It
  also contains the explicit crosswalk from earlier handoff/open-item TODOs to
  the post-TLTM wrapup phases.
- `POST_TLTM_PRE_PRODUCTION_COMPLETION_20260528.md`,
  `POST_TLTM_ARTIFACT_INVENTORY_20260528.md`,
  `POST_TLTM_SOURCE_BOUNDARY_AUDIT_20260528.md`, and
  `POST_TLTM_GUARDRAIL_CHECKLIST_20260528.md`: post-TLTM hygiene and guardrail
  artifacts.
- `WV_HMC_IMPLEMENTATION_PLAN_20260529.md`: staged WV-HMC implementation plan,
  starting with deterministic math kernels before any sampler driver.
- `runbooks/generated/wv_hmc_verification_workflow_20260602/CURRENT_CODE_VERIFICATION_LEDGER_AND_TODO_WORKFLOW.md`:
  current WV-HMC trust-boundary ledger and follow-up workflow.  This is the
  active gate for distinguishing code that is actually verified from code that
  is only partially checked or still open.
- `runbooks/generated/productization_closure_workflow_20260603/PRODUCTIZATION_CLOSURE_WORKFLOW_20260603.md`:
  current publication/credit-application closure workflow.  This document is
  the active source of truth for what must happen before the repository is
  packaged for external review.
- `runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`:
  final frozen-gate closure for the Stephanov `n=6` `nofb`/`withfb`
  comparison.

Sequencing decision:

1. Close the TLTM canonical path first.
2. Keep `nofb` as TLTM production default.
3. Keep `withfb` / DFO-LS fallback in legacy diagnostic status because the
   frozen final gates did not show a downstream correctness, ratio-stability,
   severe ergodicity, or wall-clock need.
4. Stabilize shared model-provider, derivative, observable, IO, snapshot,
   readback, and validation infrastructure.
5. Add WV-HMC only as a sibling sampler path after TLTM closure, not as a hidden
   mode inside TLTM.

WV-HMC must follow both
`WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md` and
`WV_HMC_MATH_PHYSICS_REVIEW_20260529.md`, sequenced by
`WV_HMC_IMPLEMENTATION_PLAN_20260529.md`, and must not reuse the old dead `wv`
flag semantics.  The first WV-HMC source slice should be math-kernel and
dense-oracle validation, not a production driver.

WV-HMC update, 2026-06-02:

- deterministic math/constraint/oracle gates are recorded, but WV-HMC
  production correctness remains open;
- the next blocking item is an exact positive-target invariant-measure test of
  the dense explicit-J production kernel;
- long validation and matrix-free/BiCGStab trajectory wiring are deferred until
  that trust-boundary gate is closed.

Productization closure update, 2026-06-03:

- TLTM is frozen around canonical `nofb`; `withfb`/DFO-LS is legacy diagnostic
  and must be removed from the active product dependency/license surface;
- WV-HMC dense explicit-J is the only active WV-HMC path before publication;
- the Stephanov `n=6` long dense WV-HMC validation readback is recorded in
  `runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md`;
- that readback is not a clean all-cycle pass, but it is bounded by a
  startup-transient caveat and supports moving to productization closure with
  WV-HMC burn-in/claim boundaries documented;
- the current blockers are license cleanup, public docs, evidence packet,
  guardrails, and OSS/credit application package;
- matrix-free/BiCGStab, high-dimensional performance optimization, deep module
  refactor, and any DFO-LS revival are deferred until after the
  credit-application-ready package is complete.

## Success criteria
- major modules have stable, limited responsibilities
- solver behavior is explainable and test-protected
- reference outputs are preserved or changes are explicitly justified
- new contributors can navigate and modify the code without re-discovery
- the project can support publication, reuse, and long-term maintenance

## Product Interface Direction - 2026-05-08
- Current Stage2/Stage3/Stage3_4 workflows are transitional experiment/debug scaffolding.
- After TLTM construction and Stage3_4 judgment complete, the modernization target is a unified TLTM wrapper/runner.
- Stage-specific scripts should become compatibility layers or internal implementation details.
- The final publishable project should expose a coherent config-driven TLTM product interface with versioned output schema and reproducible provenance.

## Flow Backend Direction Decision - revised 2026-05-09
- Pure ODEX-only passed physical-observable validation but caused a large solver robustness loss.
- Current canonical candidate: ODEX primary flow plus solver-internal ODE assist for NT/QN residual evaluation plus strict final proposal flow.
- Assist is a residual-evaluation progress aid only; it must not finalize a proposal or replace strict final `flow(...)`.
- Radau rescue, fixed/chunked Radau rescue, and JFNK support paths have been deleted from active source after the strict final-flow/state-status gates.
- Solver-internal assist remains active only in residual-evaluation contexts; legacy `final_resort` output/API names are compatibility aliases until schema versioning.
- Do not delete assist-related code unless a replacement preserves residual-assist semantics and proves final proposal strictness.

## State/Information Propagation Direction Update - 2026-05-09
- Current evidence suggests solver-internal ODE assist may be needed for NT/QN robustness, but it must not become final proposal acceptance.
- The near-term canonical candidate is ODEX primary flow plus solver-internal residual assist plus strict final proposal flow.
- State/status/information propagation is now a formal whole-code refine workstream, recorded in `STATE_INFORMATION_PROPAGATION_REFACTOR.md`.
- Specific future cleanup includes typed transition/result returns, no sentinel residual or Hamiltonian values, explicit HMC rejection-state semantics, and diagnostics that separate assist/replay/proposal counters.

## Thread-Safety / Reentrancy Decision - 2026-05-08
- Long-term modernization target: support in-process parallelism/OpenMP-capable TLTM execution.
- Hidden module-level `save` workspaces, counters, RNG state, traces, and solver policies should be progressively moved behind explicit context/workspace objects.
- Short-term production behavior remains serial/process-level until Stage3_4/TLTM judgment and fresh baselines are complete.
- No source-level context refactor should start until affected baseline rows are covered.
- Final wrapper design should make per-run/per-replica state explicit enough for deterministic parallel execution.
