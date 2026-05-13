# CV-011 QN Official Callback Context Slice

Updated: 2026-05-13 JST

## Decision

The user selected option A from
`CV011_QN_OFFICIAL_CALLBACK_CONTEXT_DECISION_POINT_20260513.md`: use the C
bridge `ctx` pointer for per-attempt official DFO-LS callback context.

## Implementation

- Added `qn_official_callback_context_t` as a C-interoperable round-trip context
  record.
- `run_official_dfols_attempt` initializes one context per official DFO-LS
  attempt and passes `c_loc(callback_context)` into `tltm_official_dfols_solve`.
- `qn_official_dfols_eval_callback` now recovers callback state from `ctx`
  instead of module-level `qn_official_*` active state.
- Removed the active-route module-level official callback arrays, active flag,
  and flow-workspace pointer.
- The callback still uses the existing residual evaluator and active
  `flow_workspace_t`; no residual formula or acceptance policy changed.

## Behavior Boundary

This is a callback context ownership refactor only.

No intended change to:

- official DFO-LS package/preset parameters;
- BTN residual definition;
- TLTM residual acceptance gate;
- QN route code semantics;
- solver-assist/default-off policy;
- reverse-gate policy;
- Metropolis acceptance;
- route-B RNG stream contract;
- output schema.

## Verification

Passed:

```bash
PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract
PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Full M4 result: all guardrails passed; artifacts in `output/tests/m4_guardrails`.

## Subsequent Update

The first QN trace/eval context slice is now implemented in
`CV011_QN_TRACE_EVAL_CONTEXT_SLICE_20260513.md`.

The remaining QN decision is capture/diagnostics ownership:

- QN attempt-capture files and counters;
- QN eval-flow and global-filter counters;
- backend policy cache and notice flags.

See `CV011_QN_CAPTURE_DIAGNOSTICS_CONTEXT_DECISION_POINT_20260513.md`.
