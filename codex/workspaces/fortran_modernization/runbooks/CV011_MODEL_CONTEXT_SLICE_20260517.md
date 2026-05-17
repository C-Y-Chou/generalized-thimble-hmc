# CV-011 Model Tape/Cache Context Slice - 2026-05-17

## Scope

This slice moves the generated-model tape/cache state off implicit module SAVE arrays for current serial product paths while preserving the existing `model` wrappers and numerical behavior.

The change is intentionally conservative:

- `model_tape_ad` now owns tape arrays and counters in `model_tape_context_t`, with a module fallback context for legacy direct callers.
- generated `model_generated` code now owns `tape_ready`, `tape_point_ready`, `tape_n`, `tape_out_id`, `tape_alpha`, `tape_beta`, `tape_last_z`, and the paired tape context in `model_context_t`.
- `model` re-exports the context binding API, and Stage1/Stage2 bind one run-level model context after `read_parameters()`.
- Existing public wrappers `calculate_action`, `ds`, `hessian`, and `hessian_vec` retain their call signatures and math.

This is a context-ownership/productization slice, not a physics/output change and not a final public wrapper/API-schema decision.

## Source Changes

- `src/physics/model_tape_ad.f90`
  - added `model_tape_context_t`;
  - added active context binding/release helpers;
  - routed tape construction, input updates, forward values, gradients, and Hessian-vector products through the active context.
- `scripts/generate_model_generated.py`
  - updated the tape backend template to emit `model_context_t`;
  - added bind/release helpers and context-coupled tape binding;
  - kept a no-op context surface for symbolic backend compatibility.
- `src/physics/model_generated.f90`
  - regenerated with `GEN_BACKEND=tape`.
- `src/physics/model.f90`
  - re-exported `model_context_t`, `bind_model_context`, `bind_module_model_context`, and `release_model_context`.
- `src/sampler/tltm_stage1_driver.f90` and `src/sampler/tltm_stage2_driver.f90`
  - bind one run-level model context for the driver lifetime.
- `tests/test_action_derivatives.f90`
  - added `model_context_isolation`, proving two explicit model contexts preserve independent cached tape state across rebinds.

## Verification

Commands run locally:

```sh
make -C build GEN_BACKEND=tape regen_model_derivatives
make -C build GEN_BACKEND=tape ../bin/test_program2 ../bin/run_tltm_stage1 ../bin/run_tltm_stage2
make -C build test2
make -C build test_retained_core_newton_contract
make -C build test_retained_core_rattle_rg_contract
make -C build test_tltm_swap_kernel_contract
make -C build test_odex_flow_jacobian_contract
TLTM_OFFICIAL_DFOLS_PYTHONPATH=/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/lib/python3.11/site-packages make -C build test_retained_core_qn_route_contract
make -C build modernization_guardrails
python3 scripts/inventory_fortran_state.py --repo-root . --out-tsv codex/workspaces/fortran_modernization/state/M5_STATE_CONFIG_OWNERSHIP_INVENTORY.tsv --out-summary codex/workspaces/fortran_modernization/runbooks/M5_STATE_CONFIG_OWNERSHIP_INVENTORY_SUMMARY.md
```

Key observed checks:

- `test_action_derivatives` still matches closed-form action, `ds`, Hessian, and Hv references.
- `model_context_isolation` passed with zero action/ds/Hv rebind drift and nonzero distinct-context separation.
- ODEX flow/Jacobian contract passed, including explicit flow-context equality and no-fallback checks.
- Retained-core Newton, RATTLE/RG, swap-kernel, and official DFO-LS QN route contracts passed.
- Full M4 guardrails passed.
- State inventory dropped `model_tape_cache` rows from 22 to 4 and total SAVE declarations from 113 to 95.

## Remaining Boundary

This closes the model tape/cache ownership slice for current serial product paths. Remaining CV-011 closeout is now narrower:

- final config/product schema and wrapper API cleanup;
- later per-thread constraint-stats merge/capture schema if threaded product scope is implemented;
- CVODE callback bridge state only if threaded CVODE comparison becomes product scope;
- broader OpenMP/thread-safe productization tests and production-comparison gates.

Do not claim final product/API/schema completion from this slice alone.
