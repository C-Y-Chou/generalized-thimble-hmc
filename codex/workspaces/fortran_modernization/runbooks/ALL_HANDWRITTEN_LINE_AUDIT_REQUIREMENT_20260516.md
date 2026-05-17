# All-Handwritten Line Audit Requirement

Date: 2026-05-16 JST

Status: active modernization requirement.

## Decision

The ODEX line audit is not a one-off exception.  Before claiming publication
grade paper-correctness or numerical-soundness for the modernization tree, every
handwritten numerical/code path must receive the same level of inspection:

- line-level source readback;
- comparison against the relevant paper/reference implementation where one
  exists;
- numerical-algorithm judgment where no exact paper line exists;
- classification into matched core, paper mismatch, project policy, or
  bug-candidate;
- durable handling plan for each bug-candidate or non-paper-exact surface;
- focused tests or affected-baseline gates before behavior/API changes.

## Minimum Scope

At minimum, this applies to:

- handwritten ODEX / flow integration;
- Simplified Newton / RATTLE / HMC constraint path;
- QN wrapper and residual/certification logic around official DFO-LS;
- Metropolis live-state and rejection output buffers;
- Stage2 swap/tempering/RNG protocol code;
- model/action/Jacobian generated-versus-handwritten boundaries;
- diagnostics/counter/status semantics when they affect public claims.

## Complete Coverage Queue

This queue is the working checklist.  Do not rely on ad hoc user reminders to
add handwritten numerical/code-policy areas one at a time.

| ID | Area | Main source surfaces | Current coverage | Required next packet or closure |
| --- | --- | --- | --- | --- |
| HWA-ODEX | ODEX endpoint backend/controller | `src/physics/odex_backend.f90`, `src/physics/solve_flow.f90` | ODEX-equivalent audit and Hairer-aligned endpoint route are implemented for the current endpoint-only scope. | Reopen only for dense output/general ODEX scope, new controller evidence, or production-comparison sync claims. |
| HWA-FLOW | Flow/inverse-flow/Jacobian RHS | `src/physics/solve_flow.f90`, `src/physics/model*.f90` | Flow/model/action line audit, RHS/Jacobian derivation readback, direct flow API hardening, and focused proof tests are implemented for the current valid-route scope. | Closed for current scope; reopen if flow RHS/Jacobian convention, failure-output API, ODE backend status mapping, precision policy, or model/cache state ownership changes. |
| HWA-MODEL | Action, derivatives, determinant/phase conventions | `src/physics/model_action_body.inc`, `src/physics/model_generated.f90`, `src/physics/model_autodiff.f90`, `src/physics/model_tape_ad.f90`, `src/sampler/markovchain_phase.f90`, determinant helpers in `src/core/utils.f90` | Action/derivative/phase line audit, closed-form derivative proof tests, phase shape guard, and principal-log branch convention documentation are implemented for the current model. | Closed for current scope; reopen if action expression, generated derivative pipeline, determinant/phase convention, model tape/cache state, or public energy/schema semantics change. |
| HWA-NT | Simplified Newton constraint solver | `src/sampler/hmc_constraints.f90` | Line-audit, reference mapping, direct API hardening, projection-split proof, replay proof, and failed-output tests are implemented for the current simplified-Newton scope. | Closed for current scope; reopen only if Newton controller behavior, tolerance policy, failure classification, status schema, flow status handling, or public API semantics change. |
| HWA-RATTLE | RATTLE/HMC proposal and reverse gate | `src/sampler/hmc_integrator_core.f90`, `src/sampler/hmc.f90`, `src/sampler/hmc_kernels.f90`, `src/sampler/hmc_reversibility_checks.f90` | Line-audit, full derivation/readback, source hardening, and proof tests are implemented and M4-passed for the current rejection-as-stay-put scope. | Closed for current scope; reopen only for RATTLE/HMC behavior, status/schema, legacy trigger, or policy changes. |
| HWA-QN | BTN/QN residual, loss, official DFO-LS bridge, and TLTM certification | `src/sampler/quasi_newton_solver.f90`, `src/sampler/quasi_newton_linear_solver.f90`, `src/external/official_dfols_c_bridge.c`, QN block in `src/sampler/hmc_integrator_core.f90` | Line-audit, BTN residual/seed readback, official-package wrapper boundary, direct API hardening, and focused package-route tests are implemented for the current official DFO-LS wrapper scope. | Closed for current scope; reopen only if package/preset/callback policy, BTN residual, seed mapping, TLTM residual gate, final-flow/RG certification, trace classification semantics, or public route schema changes. |
| HWA-MET | Metropolis accept/reject and live-state outputs | `src/sampler/markovchain_metropolis.f90`, `src/sampler/markovchain_transition_status.f90`, `src/sampler/tltm_types.f90` | HWM-MET-001 finite-reject output contract is implemented and M4-passed. | Reopen if transition status schema, public output contract, or caller commit semantics change. |
| HWA-STAGE1 | Stage1 local-update driver and measurement/expectation path | `src/sampler/tltm_stage1_driver.f90`, `src/apps/run_tltm_stage1.f90`, `src/apps/evaluate_expectations.f90` | Remaining-surfaces closure packet read back Stage1 as a local-update-only validation surface sharing the already-audited Metropolis/HMC/RATTLE/flow kernel; config/env hardening is implemented. | Closed for current source-contract scope; reopen if Stage1 becomes a publication/product route, uses a new RNG contract, or changes measurement/output semantics. |
| HWA-STAGE2 | Stage2 tempering, swap, measurement, labels, and schedule | `src/sampler/tltm_stage2_driver.f90`, `src/apps/run_tltm_stage2.f90` | Stage2/RNG protocol line audit, swap kernel state-transition proof, measurement/label timing readback, invalid energy hardening, and focused swap tests are implemented for the current Stage2 unit scope. | Closed for current scope; reopen if cycle order, measurement boundary, label/slot semantics, swap acceptance draw boundary, output schema, history policy, or production-redo contract changes. |
| HWA-RNG | RNG primitives and stream ownership | `src/core/mt95.f90`, `src/core/mtdefs.f90`, `src/core/tltm_rng.f90`, Stage1/Stage2 RNG use sites | Stage2 RNG v2 domain separation, Philox known-answer vectors, deterministic normal replay, and MT95 Gaussian-spare replay are covered for the current Stage2 protocol scope. | Closed for current Stage2 scope; reopen for Stage1-wide RNG claims, new compatibility modes, reproducibility manifest changes, OpenMP scheduling claims, or single/mixed precision implications. |
| HWA-DIAG | Diagnostics, statuses, counters, failure capture, replay/probe accounting | `src/sampler/constraint_solver_stats.f90`, `src/sampler/tltm_types.f90`, `src/physics/solve_flow.f90`, Stage sidecars | Remaining-surfaces closure packet documents F4 local-transition denominators/status maps and implements accepted-event canonicalization for contradictory direct inputs. | Closed for current source-contract scope; reopen for public status/counter/schema semantic changes or new failure-capture/replay accounting claims. |
| HWA-CONFIG | Config/env/tolerance/precision policy | `src/config/param_mod.f90`, `src/config/runtime_env_mod.f90`, precision constants in `src/core/utils.f90`, PBS/wrapper manifest fields | Remaining-surfaces closure packet hardens real env parsing, flow-ladder parsing, Stage1/Stage2 finite controls, and top-level tolerance validation for strict double baseline. | Closed for current strict-double source-contract scope; F20 remains open for future single/mixed precision, weaker tolerances, manifests, and affected-baseline certification. |
| HWA-IO | Markov-chain I/O, output schema, wrapper products | `src/sampler/markovchain_io.f90`, `src/sampler/markovchain*.f90`, `src/apps/*.f90` | Remaining-surfaces closure packet reads current stream I/O and Stage summary/v1alpha sidecar surfaces as evidence/product scaffolding, not hidden numerical kernels. | Closed for current source-contract scope; reopen for product release, field/API cleanup, schema version changes, or output compatibility changes. |
| HWA-HELPERS | Numerical helper routines used by algorithm claims | `src/core/utils.f90`, `src/core/lapack_fallback.f90`, `src/core/perf_profile.f90`, helper workspaces | Remaining-surfaces closure packet hardens pack/unpack/logdet failed outputs, `decompose2` shape guards, Hamiltonian shape guard, and adds focused helper tests. | Closed for current source-contract scope; reopen for determinant branch-policy changes, helper API changes, LAPACK replacement, precision-profile changes, or profiler semantics changes. |
| HWA-BRIDGES | Optional external C bridges | `src/external/official_dfols_c_bridge.c`, `src/external/sundials_cvode_bridge.c` | Remaining-surfaces closure packet documents official DFO-LS as package bridge plus TLTM gates, CVODE as comparison-only, and hardens C bridge failed outputs to stay-put. | Closed for current bridge-boundary scope; reopen for package versions, callback semantics, threading/single-precision scope, or making CVODE/product bridge behavior canonical. |
| HWA-LEGACY | Legacy triggers and strange names | `istest`, `testmom`, `eo`, `rattle2`, old compatibility envs and aliases | Remaining-surfaces closure packet classifies `istest/testmom` as test-only, `eo` as legacy analysis, and `rattle2/decompose2` as compatibility names around audited routines. | Closed for paper-correctness scope; F9 product cleanup/renaming/deletion still requires exact-output or affected-baseline protection. |

## Current State

ODEX has now received this level of line audit through
`F18B4F_PRE_IMPLEMENTATION_HANDWRITTEN_ODEX_LINE_AUDIT_20260516.md`.

RATTLE/HMC has a line-audit packet in
`HWM_RATTLE_HMC_LINE_AUDIT_20260517.md` plus a full pre-source-change
derivation/readback packet in
`HWM_RATTLE_HMC_DERIVATION_PACKET_20260517.md`.  Its source-facing API
hardening/proof-test packet is implemented and M4-passed in
`HWM_RATTLE_HMC_PROOF_TEST_API_HARDENING_20260517.md`, covering direct
`rattle_step_core` failed outputs, warmup failed outputs, and HMC-status to
Metropolis-status mapping under the selected rejection-as-stay-put policy.

Simplified Newton has a line-audit/source-hardening/proof-test packet in
`HWM_NEWTON_CONSTRAINT_LINE_AUDIT_20260517.md`, covering the residual/update
mapping, fixed-base projection split, direct API guards, and failed-output
contracts while documenting controller thresholds as TLTM project policy.

QN/BTN has a line-audit/source-hardening/proof-test packet in
`HWM_QN_OFFICIAL_DFOLS_LINE_AUDIT_20260517.md`, covering BTN residual/seed
mapping, the official DFO-LS wrapper, TLTM residual certification, direct API
guards, and package-route tests.

Flow/model/action has a line-audit/source-hardening/proof-test packet in
`HWM_FLOW_MODEL_ACTION_LINE_AUDIT_20260517.md`, covering action derivatives,
flow RHS/Jacobian signs, inverse-flow sign policy, phase/logdet conventions,
direct flow API failed-output contracts, and phase dimension guards. Model
tape/cache state remains a CV-011 productization boundary rather than a current
valid-route math bug.

Stage2/RNG has a line-audit/source-hardening/proof-test packet in
`HWM_STAGE2_RNG_PROTOCOL_LINE_AUDIT_20260517.md`, covering Stage2 cycle order,
swap state transitions, measurement/label boundaries, Stage2 RNG v2 domain
separation, MT95 compatibility replay, and invalid effective-energy handling.

Remaining Stage1/diagnostic/config/I/O/helper/bridge/legacy surfaces have an
M4-passed closure packet in
`HWM_REMAINING_HANDWRITTEN_SURFACES_CLOSURE_20260517.md`.
That packet implements helper/config/diagnostic/bridge hardening where needed
and classifies Stage1/I/O/legacy as current-scope closures with product/F9/F20
reopen boundaries.  The HWA queue is now complete for the current
source-contract/paper-correctness audit scope, while production redo, final
public schema/API cleanup, precision-profile certification, and thread-safe
productization remain separate modernization closeout work.
