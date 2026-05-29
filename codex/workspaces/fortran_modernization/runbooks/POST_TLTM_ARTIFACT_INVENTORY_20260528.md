# Post-TLTM Artifact Inventory

Date: 2026-05-28

Scope: post-TLTM inventory for repository hygiene.  This document classifies
current source, scripts, runbooks, generated analysis artifacts, and historical
evidence surfaces before raw archive movement/deletion decisions.

This inventory is nonbehavioral.  It does not delete, move, rename, or
reinterpret production outputs.

## Classification Rules

| Class | Meaning | Treatment |
| --- | --- | --- |
| canonical | Required for the planned TLTM production path. | Document and preserve. |
| SOP support | Required to run or explain the canonical workflow. | Document and preserve. |
| validation/readback support | Required to check behavior, observables, or analysis. | Document and preserve. |
| legacy/archive | Historical or compatibility material that may be needed for reproduction. | Document only; do not delete. |
| experimental opt-in | Implemented or planned experiment not promoted to canonical. | Document as opt-in; do not enable by default. |
| delete candidate | Not needed for canonical, readback, reproduction, or future model work. | Mark only; delete after guardrails and approval. |
| blocked | Must wait for final production or accepted baseline. | Do not execute now. |

## Canonical TLTM Source Surface

| Surface | Classification | Treatment |
| --- | --- | --- |
| `src/physics/model.f90` | canonical provider facade | Keep as sampler-facing API.  Future model swaps should stay behind this boundary. |
| `src/physics/model_stephanov.f90` | canonical validation provider | Keep Stephanov as provider/validation model, not sampler control logic. |
| `src/physics/model_observables.f90` | canonical observable surface | Keep observable registry model-owned. |
| `src/physics/solve_flow.f90` | canonical flow interface | Preserve current behavior; backend changes require guardrails. |
| `src/physics/odex_backend.f90` | canonical/near-canonical flow backend support | Preserve; DOP853/ODE backend selection must remain explicit in runbooks and configs. |
| `src/sampler/tltm_stage2_driver.f90` | canonical TLTM driver surface | Preserve until final production closes.  Later contraction must be behavior-preserving. |
| `src/sampler/tltm_stage1_driver.f90` | SOP support | Keep for current workflow support. |
| `src/sampler/hmc*.f90`, `markovchain*.f90`, `quasi_newton*.f90` | canonical sampler internals | Preserve behavior; withfb/DFO-LS remains default-off legacy diagnostic unless frozen gates change that. |
| `src/config/param_mod.f90` | canonical config plus legacy mirrors | Stale `wv` flag removed in the first source hygiene slice.  Broader mirror migration remains deferred. |
| `src/core/tltm_rng.f90`, `src/core/mt95.f90` | canonical RNG support | Do not migrate ownership or stream order before accepted baseline. |

## Application And Build Surface

| Surface | Classification | Treatment |
| --- | --- | --- |
| `src/apps/run_tltm_stage1.f90` | SOP support | Keep as current Stage1 entry. |
| `src/apps/run_tltm_stage2.f90` | SOP support | Keep as current Stage2 entry. |
| `src/apps/evaluate_expectations.f90` | validation/readback support | Keep for observable readback. |
| `src/apps/build_flow_bank_dense.f90` | SOP support | Keep for flow-bank initialization support. |
| `src/apps/compare_swap_reflow_backends.f90` | experimental opt-in | Keep for backend comparison; not canonical production route. |
| `src/apps/evaluate_btn_residual_case.f90`, `src/apps/replay_flowz_cases.f90` | validation/readback support | Keep diagnostic replay surfaces. |
| `src/apps/generate_markov_chain.f90` | legacy/development compatibility | Keep until raw compatibility policy is closed. |
| `build/makefile` | canonical build control | Keep as authoritative local build and guardrail surface. |

## Data And Model-Spec Surface

| Surface | Classification | Treatment |
| --- | --- | --- |
| `data/parameters_stephanov_n6_mu06_t0.dat` | SOP support | Keep as selected Stephanov working-point preset. |
| `data/parameters_stephanov_n6_mu06_t1e6_eps008_nstep2.dat` | SOP support | Keep local-development nofb protocol preset. |
| `data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat` | validation/readback support | Keep for comparison and examples. |
| `data/parameters_t*.dat` | legacy/archive or experimental opt-in | Do not delete before archive review. |
| `model_specs/high_dimensional/` | SOP support for next model | Keep as staging area for future high-dimensional model definitions. |

## Runbooks And Generated Evidence

| Surface | Classification | Treatment |
| --- | --- | --- |
| `TLTM_CANONICAL_SOP_20260528.md` | canonical SOP | Keep as production workflow anchor. |
| `MODERNIZATION_POST_TLTM_WORKFLOW_20260528.md` | canonical governance | Keep as post-TLTM sequence and handoff-TODO crosswalk. |
| `runbooks/generated/withfb_criterion_framework_20260527/` | canonical governance | Frozen gates; do not retune thresholds after final data. |
| `runbooks/generated/stephanov_n6_final_observable_z_20260529_complete/` | validation/readback support | Final observable/z and convergence packet used for the closure. |
| `STEPHANOV_N6_DATASET_ARCHIVE_GROUPS_20260528.md` | SOP support | Compact final rows are filled; raw archive movement/deletion remains deferred. |
| `runbooks/generated/post_tltm_wv_hmc_ready_20260529/` | canonical closure packet | Final criterion closure, runtime exclusion note, and four-group registry used before WV-HMC work. |
| superseded intermediate generated readback folders | local workbook cleanup | Removed from the local workbook after final closure packets were created; do not use as current handoff artifacts. |
| old Stage3/F20/F14/M6 runbooks | legacy/archive or validation support | Keep until final archive pass. |

## Script And PBS Surface

| Surface | Classification | Treatment |
| --- | --- | --- |
| `scripts/run_m4_guardrails.py` | validation/readback support | Keep as local guardrail entry. |
| `scripts/fortran_module_deps.py` | canonical build support | Keep. |
| `scripts/merge_stage3_multiseed_chunks.py`, `scripts/run_stage3_3_multiseed.py`, `scripts/run_tltm_product.py` | SOP/validation support | Keep until wrapper handoff and raw Stage policy close. |
| `codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py` | SOP support | Keep for current Stephanov TLTM chunks and snapshot/flow-bank support. |
| `codex/workspaces/fortran_modernization/tasks/scripts/write_stephanov_n6_*.py` | validation/readback support | Keep for current and final result packets. |
| `codex/workspaces/fortran_modernization/tasks/scripts/submit_fixed_tau_*.py` | validation/readback support | Keep until fixed-tau comparison is archived. |
| `codex/workspaces/fortran_modernization/tasks/scripts/benchmark_*cache*.py` | experimental opt-in | Keep for runtime studies; do not promote without benefit. |
| old `scripts/run_t*.sh`, old Stage2.5/Stage3.4 helpers | legacy/archive | Keep until archive/deletion pass; do not use as current evidence. |
| historical PBS files under `tasks/pbs/odex_*`, `m6_*`, old qn routes | legacy/archive | Keep quarantined by script evidence audit. |
| current Stephanov n6 PBS files under `tasks/pbs/stephanov_n6_*` | SOP/validation support | Keep until final dataset archive and criterion readback finish. |
| `__pycache__/` under task scripts | delete candidate | Generated Python cache; can be removed after production if it is not needed for provenance. |

## Documentation Surface

| Surface | Classification | Treatment |
| --- | --- | --- |
| `docs/readme.md` | canonical overview | Correct stale WV-HMC claim now; no runtime behavior impact. |
| `docs/module_architecture.md`, `docs/file_layout.md` | canonical architecture docs | Keep; update as sibling TLTM/WV-HMC architecture becomes real. |
| `docs/state_vector_convention.md` | canonical state contract | Keep; flow time remains metadata, not physical `x`. |
| `docs/model_observables.md` | canonical provider/observable doc | Keep. |
| historical JSON evidence under `docs/` | legacy/archive | Keep until final archive pass. |

## Delete Candidates Not Executed Now

These are marked only.  They are not removed without guardrails and approval:

- generated `__pycache__/` directories under task scripts;
- superseded old 1D/Stage2.5/Stage3.4 JSON/runbook artifacts after archive map
  exists;
- historical helper scripts that the script evidence audit already quarantines.

## Blocked Until Production Finishes

- raw archive movement/deletion;
- raw Stage entry-point deprecation;
- RNG stream ownership migration;
- large module `save` workspace migration;
- model/tape cache migration;
- diagnostics schema migration;
- source deletion that changes public config/schema/output behavior.
