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

The active milestone map is M0-M6:

- M0: planning and governance established.
- M1: temporary characterization baseline collected from the completed Stage3_4/TLTM judgment context.
- M2: canonical numerical route and core legacy deletion/canonicalization completed for the current p28 policy.
- M3: architecture, tempering protocol, output schema, Stage2 sidecars, and Stage3 protocol propagation.
- M4: guardrail tests, parser/readback checks, protocol audits, and benchmark harnesses.
- M5: repo-wide refactor waves for typed config, explicit state/status propagation, diagnostics, output ownership, RNG/state inventory, and module boundaries.
- M6: pre-dataset product-readiness package, unified wrapper direction, provenance contract, docs, examples, and release/checklist notes.

Current sequencing decision:

- Official dataset regeneration waits until after M6.
- Small smoke/regression runs may still be used during development, but they are not official regenerated datasets.
- See `M3_TO_M6_BEFORE_DATASET_PLAN.md` for the executable gate sequence.

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
