# Behavior-Preserving Algorithm Audit Plan

Updated: 2026-05-08 JST

## Purpose
This is the first executable planning deliverable for TLTM Fortran modernization. It defines how to review the core algorithms before any code refactor, with the explicit goal of preserving physics, proposal semantics, and approved output behavior.

The audit must be reference-driven. Engineering cleanup is only allowed after the algorithm contract and regression surface are clear.

## Governing rules
- Do not modify Fortran code during this audit phase.
- Do not submit jobs or touch production worktrees from this planning task.
- Every algorithm review must start from the relevant reference source, then compare implementation behavior.
- DFO-GN/DFO-LS references support the solver mechanism layer; they do not replace the project-specific projection-loss design.
- The current quasi-Newton projection loss is canonical current design.
- `nofb` means standard `(u, lambda)` formulation.
- `fg` means standard formulation first; when standard fails, use BTM/BTN fallback formulation.


## Audit scope correction - 2026-05-08

This audit is not only a route-pruning or legacy-disablement exercise. For every retained core numerical block, the implementation itself must be checked against its reference contract and invariants. Disabling Radau, post-refine, or non-p28 routes is insufficient unless the remaining ODEX, simplified Newton, RATTLE, QN p28 loss, and HMC/Metropolis/RG code are also audited for implementation correctness.

See `M2_CORE_NUMERICAL_IMPLEMENTATION_AUDIT_PLAN.md` for the retained-core correctness gate that must precede 10k -> 50k -> 100k validation.

## Deliverables from this audit phase
1. Algorithm contract summary for each core area.
2. Implementation responsibility map for each core module.
3. Risk ranking by behavior-preservation sensitivity.
4. Baseline/regression requirements before any future code change.
5. First-wave refactorability assessment: what can be reorganized safely, what requires stronger baselines first.

## Audit Area 1: TLTM / HMC Framework
### References
- `references/1912.13303_TLTM_HMC.pdf`

### Main implementation files
- `src/apps/run_tltm_stage2.f90`
- `src/sampler/tltm_stage2_driver.f90`
- `src/sampler/hmc.f90`
- `src/sampler/markovchain_metropolis.f90`
- `src/sampler/markovchain_phase.f90`

### Review goals
- Confirm the current Stage2/TLTM workflow matches the intended TLTM/HMC sampling framework.
- Identify which parts are physics/sampling contract versus reporting or orchestration code.
- Confirm Metropolis boundary semantics: proposal generation, Hamiltonian accounting, failure rejection, and phase handling.
- Check whether history-writing conventions and swap timing are explicitly part of the current sampling definition.

### Behavior risks to track
- Accidental change to acceptance/rejection behavior.
- Accidental change to phase/reweighting conventions.
- Accidental change to history timing or replica/label semantics.
- Treating reporting cleanup as if it were behavior-neutral when counters are part of regression output.

### Required baselines before code changes
- Fixed-seed Stage2 summary metrics.
- Acceptance/rejection counts.
- Solver route counts as seen by the driver.
- Representative history/output file checksums or structured summaries.
- Phase/reweighting evaluation smoke check.

## Audit Area 2: ODEX Flow Integration
### References
- `references/Hairer_Norsett_Wanner_SODE_I_Nonstiff_Problems_full.pdf`
- `references/Hairer_SODE_I_II9_Extrapolation_Methods_pdfpages_237_270.pdf`
- `references/Hairer_SODE_I_Appendix_Subroutine_ODEX_pdfpages_494_496.pdf`
- `references/ODEX_LOCATION_GUIDE.md`

### Main implementation files
- `src/physics/solve_flow.f90`
- `src/physics/model.f90`
- `src/physics/model_generated.f90`
- `src/physics/model_action_body.inc`

### Review goals
- Identify the ODEX/extrapolation-method contract used by flow, inverse flow, and flow-with-Jacobian paths.
- Map `flow`, `flowz`, and `flowzr` responsibilities and failure semantics.
- Separate ODE mechanism from trace, fallback, rescue, and diagnostic code.
- Confirm tolerance meaning for `at`, `rt`, and any internal floors or rescue tolerances.
- Determine whether ODE behavior is deterministic and reproducible under fixed config.

### Behavior risks to track
- Changing tolerance interpretation.
- Changing failure/retry thresholds.
- Changing flow/inverse-flow equivalence behavior.
- Introducing hidden changes in action/gradient evaluation order.
- Misclassifying ODE rescue behavior as behavior-neutral cleanup.

### Required baselines before code changes
- Flow/inverse-flow round-trip checks for representative states.
- Fixed tolerance success/failure matrix for known difficult states.
- Derivative/Hessian consistency checks after any model/flow adjacency change.
- Runtime and failure-count baseline for representative flow-heavy paths.

## Audit Area 3: Simplified Newton / RATTLE
### References
- `references/2311.10663v4.pdf`

### Main implementation files
- `src/sampler/hmc_constraints.f90`
- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/hmc.f90`
- `src/sampler/hmc_kernels.f90`
- `src/sampler/hmc_state_buffers.f90`

### Review goals
- Map paper-defined RATTLE steps to implementation-level subroutines.
- Clarify the meaning of `B`, `u`, `ld`, `Jl`, `del_z`, lambda, and lambda-prime equivalents.
- Identify where simplified Newton mechanism ends and rescue/fallback policy begins.
- Confirm projection residual and momentum update semantics.
- Identify subroutine/API smells that obscure the RATTLE contract.

### Behavior risks to track
- Sign or convention drift in residual/lambda variables.
- Changing projection acceptance semantics while simplifying subroutines.
- Moving diagnostics in a way that changes counters or reverse-gate inputs.
- Changing workspace reuse in a way that affects hidden state behavior.

### Required baselines before code changes
- Hamiltonian conservation trend.
- Reversibility diagnostics on successful proposals.
- Newton success/fail counts for fixed seeds.
- Constraint residual statistics before/after proposal generation.
- Representative projection failure cases, if available.

## Audit Area 4: Quasi-Newton Projection Loss
### References
- `references/new_algorithm__Copy_.pdf`
- `references/s12532-019-00161-7_DFO_GN.pdf`
- `references/1804.00154v2.pdf`

### Main implementation files
- `src/sampler/quasi_newton_solver.f90`
- `src/sampler/quasi_newton_linear_solver.f90`
- `src/sampler/quasi_newton_jacobian_update.f90`
- `src/sampler/quasi_newton_line_search.f90`
- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/constraint_solver_stats.f90`

### Review goals
- Identify the active residual/loss for standard `(u, lambda)` and BTM/BTN fallback routes.
- Separate geometry layer, parametrization layer, and solver layer in the implementation.
- Classify each QN component as project-specific projection-loss design, DFO-GN/DFO-LS mechanism, or implementation policy.
- Document Broyden update and line-search as implementation mechanisms under DFO-GN/DFO-LS-inspired solver layer.
- Determine whether route classification, continuation, watchdogs, and rescue behavior are testable and observable.

### Behavior risks to track
- Replacing canonical project-specific projection loss with generic DFO-GN/DFO-LS objective.
- Collapsing standard and BTM/BTN formulation semantics during cleanup.
- Changing route mixture behavior without proposal correctness evidence.
- Changing solver counters that are used for production diagnostics.
- Refactoring hidden saved state without understanding reuse assumptions.

### Required baselines before code changes
- Fixed-seed QN route census.
- Standard-fail to BTM/BTN fallback counts.
- Solver residual trace summaries.
- Reverse-gate candidate/pass/reject counts.
- Successful-proposal reversibility checks for QN-used proposals.
- Local volume / branch-stability checks where relevant.

## Audit Area 5: Metropolis / Proposal Boundary
### References
- `references/1912.13303_TLTM_HMC.pdf`
- `references/2311.10663v4.pdf`
- `references/new_algorithm__Copy_.pdf`

### Main implementation files
- `src/sampler/hmc.f90`
- `src/sampler/markovchain_metropolis.f90`
- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/hmc_reversibility_checks.f90`
- `src/sampler/tltm_stage2_driver.f90`

### Review goals
- Confirm proposal success/failure surface and Metropolis rejection behavior.
- Confirm reverse-gate behavior and replay diagnostics are separated from physical proposal counts.
- Determine what output behavior must remain exact for Level A refactors.
- Identify where proposal correctness depends on solver route symmetry, reversibility, or volume behavior.

### Behavior risks to track
- Incorrectly treating failed proposals as accepted/rejected physical proposals.
- Changing Hamiltonian sentinel behavior or non-finite proposal handling.
- Mixing diagnostic replay counters with outer proposal counters.
- Weakening reverse-gate or branch-stability evidence.

### Required baselines before code changes
- Proposal success/failure counts.
- Metropolis acceptance/rejection counts.
- Reverse-gate replay counter separation checks.
- Reversibility check output for successful proposals.
- Summary comparison for fixed seeds and representative configs.

## Cross-Cutting Audit: State, Config, and Observability
### References
- `runbooks/BEHAVIOR_PRESERVATION_PROTOCOL.md`
- `runbooks/SUBROUTINE_API_REDESIGN_GUIDE.md`
- `runbooks/TEST_AND_BENCHMARK_ROADMAP.md`

### Main implementation files
- `src/config/param_mod.f90`
- `src/sampler/constraint_solver_stats.f90`
- `src/core/perf_profile.f90`
- `src/core/utils.f90`

### Review goals
- Identify global state dependencies that affect algorithm behavior.
- Classify runtime knobs as stable config, research toggle, or diagnostic flag.
- Identify counters that are part of behavior-preservation regression output.
- List module-level `SAVE` state that blocks OpenMP or in-process parallelism.

### Required baselines before code changes
- Resolved config manifest for representative runs.
- Environment override manifest.
- Counter snapshot schema.
- Performance baseline for hot paths.

## Review order
1. ODEX flow integration.
2. Simplified Newton / RATTLE.
3. Quasi-Newton projection loss.
4. Metropolis / proposal boundary.
5. TLTM / HMC framework and driver-level orchestration.
6. Cross-cutting config/state/observability.

Rationale: start with the lowest algorithmic substrate whose semantics feed every higher-level proposal path, then move outward to projection, QN fallback, proposal acceptance, and finally driver orchestration.

## Output format for each deep review
Each deep review should produce a compact note with these sections:
- Reference definition.
- Implementation map.
- Behavior-preservation risks.
- Baseline requirements.
- Refactorability assessment.
- Open questions.

## Immediate next deliverable
Produce `ODEX_FLOW_REVIEW_NOTES.md` as the first deep review note. It should remain planning-only unless a separate implementation task is opened.
