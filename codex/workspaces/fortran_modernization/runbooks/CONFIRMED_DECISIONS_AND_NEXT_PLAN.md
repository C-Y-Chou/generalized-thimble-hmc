# Confirmed Decisions And Next Plan

Updated: 2026-05-09
Scope: governing roadmap for TLTM Fortran modernization after planning discussion and the first canonicalization source wave.

## Confirmed Decisions

1. Canonical naming

- Use `BTN` as the canonical name.
- `BTM` was a typo and may appear only as a historical alias note.

2. Production quasi route

- Only the current p28 route is production-canonical.
- Canonical p28 route: Newton first, then QN S1 probe with `QN_S1_PROBE_MAX_ITER=28`, DFO-LS on `evaluate_constraint_residual`, reverse gate, then Metropolis.
- Non-p28 quasi routes were legacy/deletion candidates and have been removed from active source after validation and user approval: DFO-GN paper route, Broyden/line-search route, global continuation/restart fallback routes, and other known non-p28 variants.
- Post-refine has been removed from active source. It is not part of the canonical p28 route unless explicitly re-promoted later as a separate research mode.

3. Stage workflow and wrapper target

- Current Stage2/Stage3/Stage3_4 workflow is transitional experiment/debug scaffolding.
- Short-term Stage3_4-facing outputs remain frozen for compatibility.
- Long-term target is a unified TLTM wrapper/runner with config-driven modes and versioned output schema.
- Stage-specific scripts should become compatibility layers or internal implementation details.

4. Baseline source

- Existing `output/tests` artifacts are historical/reference evidence only.
- Official modernization baselines will be regenerated after Stage3_4/TLTM judgment completes.
- Fresh baselines must use clean, explicitly selected configs and comparison rules.

5. Reverse gate

- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It is not a temporary debug guard or optional diagnostic mode.
- Modernization must preserve RG tolerance, `x/z/jac/p` comparison, replay counter suppression, and live-slot identity on reject.

6. Flow backend

- Current canonical flow policy: ODEX primary integration, solver-internal ODE assist for NT/QN residual evaluation, and strict final proposal/live-state flow.
- Pure ODEX-only is retained as a comparison artifact, not the current production target, because validation showed avoidable robustness loss.
- Radau rescue, fixed/chunked Radau rescue, and JFNK support paths have been removed from active source.
- ODE solver-assist remains explicit and may not construct final physical proposals.

7. Thread-safety/reentrancy

- Long-term target: in-process parallel/OpenMP-capable TLTM execution.
- Hidden module-level `save` workspaces, counters, RNG state, traces, and policies should progressively move behind explicit context/workspace objects.
- No source-level context refactor before Stage3_4/TLTM judgment and fresh baselines.

8. Code hygiene / sloppy artifact cleanup

- Sloppy handwritten implementation cleanup is in scope.
- It should be a formal workstream, not ad hoc cleanup mixed into algorithm refactors.
- Formatting, naming, dead-code inventory, duplicate helper inventory, comments/equation notes, and static audit plans can start during planning.
- Source cleanup that can affect behavior must wait for baselines and be staged by risk.


## Scope Correction - 2026-05-08

The five core algorithm audits are safety gates, not the center of the full modernization roadmap.

They cover the highest-risk numerical/physics surfaces:

- ODEX/flow.
- simplified Newton/RATTLE.
- p28 quasi-Newton projection.
- HMC/Metropolis.
- TLTM driver/orchestration.

But repo-wide modernization is broader. It must also cover cross-cutting infrastructure outside those algorithms:

- `utils` and real/complex/state mapping helpers.
- RNG and seed management.
- config/parameter parsing and validation.
- build system and dependency management.
- tests, benchmark runners, and CI/reproducibility tooling.
- diagnostics, logging, counters, traces, and failure capture.
- output/history/evaluation schema.
- scripts/PBS orchestration and future wrapper interface.
- memory/workspace ownership and module `save` state.
- error handling and status-code conventions.
- documentation and developer/user onboarding.

Therefore the roadmap below is repo-wide. Algorithm audit is `Gate 0`, while the modernization center is behavior-preserving productization of TLTM as a maintainable, testable, unified wrapper/library project.

## Complete Modernization Workstreams

### Gate 0 / Workstream A: Algorithm Definition And Reference Mapping

Purpose: safety-gate numerical/physics changes so implementation work is not blind. This is necessary but not sufficient for full repo modernization.

Includes:

- TLTM/HMC mapping to `1912.13303`.
- Simplified Newton/RATTLE/HMC mapping to `2311.10663v4`.
- ODEX mapping to Hairer SODE I Section II.9 and ODEX appendix.
- DFO-LS/DFO-GN mapping to `1804.00154v2` and `s12532-019-00161-7`.
- User original quasi projection loss mapping to `new_algorithm__Copy_.pdf`.
- BTN naming and formulation cleanup.

Deliverables:

- Algorithm review notes per subsystem.
- Residual equation contracts.
- Legacy route classification.

### Workstream B: Behavior Preservation And Baselines

Purpose: prevent modernization from changing physics, sampling, or accepted outputs silently.

Includes:

- Fresh baseline generation after Stage3_4/TLTM judgment.
- Flow/ODEX endpoint baselines.
- Newton/RATTLE baselines.
- p28 QN route baselines.
- RG pass/reject baselines.
- Metropolis/RNG-order baselines.
- Stage output/wrapper schema baselines.
- Performance and route-counter baselines.

Deliverables:

- Official baseline fixture set.
- Comparison scripts/rules.
- Tolerance policy.
- Counter/schema contract.

### Workstream C: Code Hygiene And Fortran Modernization Cleanup

Purpose: clean sloppy handwritten artifacts without changing algorithmic behavior.

Includes:

- `implicit none`/`intent`/interface audit.
- Dead code and legacy route inventory.
- Duplicate helper inventory.
- Long subroutine decomposition plan.
- Naming cleanup plan for `u`, `lambda`, `ld`, `Jl`, `del_z`, residuals, route codes.
- Formatting and logging style cleanup.
- Error handling convention.
- Allocation/workspace style cleanup.
- Static analysis/lint plan.

Rules:

- Planning/inventory can start now.
- Source edits wait for baselines unless provably non-behavioral and isolated.
- No cleanup may change RNG order, solver route order, tolerances, counters, or output schema without a baseline row.

Deliverables:

- `CODE_HYGIENE_AUDIT.md`.
- File-by-file cleanup queue.
- Safe cleanup checklist.
- Deprecated/legacy deletion plan.

### Workstream D: Architecture And API Redesign

Purpose: transform the repo from experiment-stage code into a mature product/library structure.

Includes:

- Module boundary redesign: flow, solver, HMC, TLTM wrapper, diagnostics, config.
- Mechanism vs policy separation.
- Public API design for unified TLTM wrapper.
- Versioned output schema design.
- Compatibility layer for stage scripts.
- Explicit context/workspace objects for reentrancy.

Deliverables:

- Target architecture spec.
- Public wrapper API spec.
- Output schema version spec.
- Module migration plan.

### Workstream E: Legacy Route Deletion And Simplification

Purpose: remove old experiments after canonical decisions and baselines make deletion safe.

Includes deletion candidates:

- Non-p28 quasi routes.
- DFO-GN paper route, unless explicitly retained for research mode.
- Broyden/line-search route.
- Global continuation/restart fallback routes outside production p28.
- Radau/JFNK secondary-integrator rescue stack, already deleted from active source.
- Legacy `final_resort` compatibility names for solver-assist counters/API fields, to be renamed only with output-schema versioning.
- Stage-specific scripts once unified wrapper is mature.
- Post-refine, already deleted from active source.

Deliverables:

- Deletion candidate registry.
- Dependency checks.
- Before/after baseline comparison.
- Compatibility/deprecation notes.

### Workstream F: Parallelism And Reentrancy

Purpose: make TLTM suitable for in-process parallel/OpenMP-capable execution.

Includes:

- Inventory of all module-level `save` state.
- RNG context design.
- Solver/flow workspace context design.
- Counter/trace context design.
- Per-run/per-replica state objects.
- Deterministic parallel testing strategy.

Deliverables:

- State inventory.
- Context API design.
- Reentrant execution tests.
- OpenMP safety checklist.

### Workstream H: Cross-Cutting Infrastructure Modernization

Purpose: cover repo-wide infrastructure that sits outside the five core algorithm audits but strongly affects maturity and correctness.

Includes:

- `utils` API audit: real/complex conversions, state vector helpers, norm helpers, allocation helpers, filesystem/string helpers.
- RNG and seed policy: deterministic seeding, per-run/per-replica streams, OpenMP-safe RNG context, test reproducibility.
- Config system: parameter parsing, validation, defaults, legacy globals, environment overrides, manifest provenance.
- Build system: dependency declaration, compiler flags, debug/release/profile modes, reproducible build instructions.
- I/O and output schema: binary histories, summaries, manifests, evaluation outputs, versioned schema.
- Diagnostics/logging: structured counters, traces, failure captures, verbosity controls, machine-readable diagnostics.
- Scripts/PBS layer: separate production wrapper, cluster launchers, merge/evaluation tools, compatibility scripts.
- Error handling conventions: status codes, logical error flags, fatal vs recoverable errors, diagnostic messages.
- Memory/workspace ownership: allocation helpers, workspace lifetimes, module `save` migration inventory.

Deliverables:

- `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`.
- RNG/config/output schema design notes.
- utils cleanup map.
- build/test/tooling modernization plan.
- diagnostics/logging contract.

### Workstream G: Testing, Benchmarking, And Product Readiness

Purpose: make the project publishable and maintainable.

Includes:

- Unit tests for mapping/residual/helpers.
- Integration tests for flow, RATTLE, p28, RG, Metropolis, swaps.
- Scientific invariant tests.
- Performance benchmarks.
- Documentation and runbooks.
- Reproducible examples.
- CI or reproducible local test workflow.

Deliverables:

- Test suite roadmap and implementation.
- Benchmark suite.
- User-facing documentation.
- Developer architecture docs.
- Release/readiness checklist.

## Proposed Full Stage Order

### M0: Planning Freeze And Decision Capture

Status: complete as the initial governance layer; keep updating live status and decisions as source modernization proceeds.

- Capture confirmed decisions.
- Correct roadmap scope to repo-wide modernization.
- Finish pre-Stage3_4 static planning artifacts.
- No source edits.

### M1: Temporary Characterization Baseline

Status: complete enough to support the first canonicalization wave.

Purpose: measure current behavior before canonical numerical changes, without freezing it as the final target.

- Record current flow rescue counters, p28 route counters, RG pass/reject, acceptance rates, failure rates, output schema, and representative observables.
- Historical refine/norefine and flow-rescue evidence is retained in runbooks; official baselines still need regeneration from the final canonical configuration.

### M2: Core Numerical Canonicalization

Purpose: settle behavior-changing numerical decisions before official regression freeze.

- Confirm p28-only route and delete/disable non-p28 legacy candidates when safe. Status: active-source deletion complete for known non-p28 routes.
- Decide post-refine retention/removal. Status: removed from active source.
- Decide flow backend policy. Status: ODEX primary + solver-internal residual assist + strict final proposal/live-state flow.
- Preserve RG as permanent p28 requirement.
- Clean residual/route definitions only with characterization evidence.

### M3: Official Canonical Baseline Freeze

Purpose: freeze the confirmed canonical TLTM algorithm, not the transitional implementation.

- Generate official fresh baselines from clean configs.
- Establish comparison rules and output schema contracts.
- Define exact tolerances and counter equality requirements.
- This becomes the regression target for repo-wide modernization.

### M4: Static Audit And Cleanup Queue

- Build detailed code hygiene audit.
- Build `save` state inventory.
- Build legacy route deletion registry from dependency checks.
- Build target module boundary map.
- Build cross-cutting infrastructure designs for RNG/config/output/diagnostics.

### M5: Test Harness And Residual Contracts

- Add microtests for residuals, mapping, RNG/config helpers, and utilities.
- Add integration baseline tests for flow/RATTLE/p28/RG.
- Add summary/schema contract tests.
- Add deterministic RNG-order tests.

### M6: Low-Risk Hygiene Cleanup

- Formatting, naming, comments, local helper cleanup.
- No route/tolerance/RNG/output changes unless intentionally versioned.
- Each change must pass affected baselines.

### M7: Legacy Deletion And Simplification Wave

- Delete or disable non-p28 quasi routes after dependency check.
- Remove post-refine if evidence and user decision support removal.
- Remove Radau/JFNK/final-resort stack if ODEX-only comparison supports deletion.
- Deprecate stage-specific scripts only after wrapper compatibility exists.

### M8: Architecture Refactor And Unified Wrapper

- Separate mechanism from policy.
- Split modules by responsibility.
- Introduce stable user-facing TLTM wrapper/runner.
- Internalize stage-specific workflow.
- Version output schema.
- Preserve compatibility wrappers during migration.

### M9: Reentrancy/OpenMP And Product Readiness

- Complete context/state migration.
- Add deterministic parallel tests.
- Validate per-replica/per-run isolation.
- Finish documentation, examples, benchmark report, architecture guide, and reproducibility package.

## Completeness Assessment

The modernization plan is structurally complete at the planning level after correcting scope: the five core algorithms are audit gates, while the roadmap is repo-wide. It covers:

- Repo-wide modernization scope, including cross-cutting infrastructure beyond the five core algorithms.
- Algorithm reference correctness as a safety gate.
- Behavior preservation.
- Baseline strategy.
- Code hygiene/sloppy artifact cleanup.
- Utils/RNG/config/I/O/build/scripts/diagnostics modernization.
- Architecture/product wrapper direction.
- Legacy deletion strategy.
- ODEX primary flow with explicit solver-internal residual assist and strict final proposal/live-state flow.
- Permanent RG requirement.
- Reentrant/OpenMP-capable long-term target.
- Testing/benchmark/product readiness.

Remaining open items are not missing workstreams; they are future gates:

- exact official baseline configs.
- input-compatibility policy for legacy positional `parameters.dat` and the unused `initial_x.dat` slot.
- final wrapper API shape.
- output schema version details.

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine has been removed from active source and should not be part of the final canonical p28 route unless explicitly re-promoted later.

## Historical flow backend decision - 2026-05-08
- Historical note: pure ODEX-only was considered the canonical long-term flow backend target before the 2026-05-09 solver-assist validation revised the decision.
- Radau rescue, fixed/chunked Radau rescue, and JFNK source has since been deleted after flow-level characterization and validation.
- Solver-internal residual assist remains explicit; future cleanup should remove compatibility `final_resort` names only with schema versioning.

## Revised flow backend decision - 2026-05-09
- User accepted the solver-assist validation observation: pure ODEX-only is not the final production policy.
- Current canonical candidate is ODEX primary integration plus solver-internal ODE assist for NT/QN residual evaluation plus strict final proposal flow.
- Future flow refactor work must preserve explicit residual-assist semantics and prove final proposal strictness.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, then deleted only after validation.
- That staged validation/dependency gate has passed for the QN-clean canonical route; DFO-GN paper, Broyden/line-search, global continuation/restart, and known non-p28 implementation paths have been removed from active source.
