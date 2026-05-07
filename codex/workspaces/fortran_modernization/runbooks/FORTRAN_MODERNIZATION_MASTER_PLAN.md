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

### 7. Productization and publication readiness
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
- split solver kernels from routing logic
- slim large integrator and driver modules
- externalize diagnostics and counters where appropriate

### Phase 4. Productization
- finalize documentation, review checklists, release discipline, and publication-facing artifacts

## Success criteria
- major modules have stable, limited responsibilities
- solver behavior is explainable and test-protected
- reference outputs are preserved or changes are explicitly justified
- new contributors can navigate and modify the code without re-discovery
- the project can support publication, reuse, and long-term maintenance
