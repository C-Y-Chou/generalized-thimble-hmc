# CV-011 QN Policy Context Slice

Updated: 2026-05-13 JST

## Decision

User selected option A from
`CV011_QN_BACKEND_POLICY_CONTEXT_DECISION_POINT_20260513.md`: introduce an
explicit Stage/run-owned QN policy/config context, separate from both
per-replica QN scratch (`qn_context_t`) and run-output diagnostics
(`qn_diagnostics_context_t`).

## Implemented Slice

- Added `qn_policy_context_t` plus `release_qn_policy_context` in
  `quasi_newton_solver_mod`.
- Moved QN backend policy cache, official DFO-LS preset values, backend notice
  state, official bridge failure warning state, watchdog budgets, force-best
  proposal controls, and watchdog policy-loaded state into `qn_policy_context_t`.
- Preserved legacy/direct-call compatibility with module fallback
  `module_qn_policy_context`.
- Extended QN solve, official DFO-LS attempt/callback context, internal DFO-LS
  attempt, GN Jacobian probing, residual evaluation, rescue/recovery helpers,
  trace append, watchdog helpers, backend policy loaders, and public
  preset/policy readers to accept an explicit policy context.
- Threaded optional QN policy through `rattle_step_core`, reverse-gate replay,
  HMC proposal/warmup/reverse-probe, `metropolis_step`, and Stage1/Stage2
  local-update paths.
- Stage1/Stage2 now own one run-level `qn_policy_context_t` and pass it through
  local updates alongside `qn_diagnostics_context_t`.
- Extended `test_official_dfols_preset_contract` with
  `policy_context_isolation`, proving two explicit policy contexts can hold
  different DFO-LS presets in the same process.

## Behavior Boundary

This is a policy ownership/productization slice only.

No intended change to:

- TLTM physics equations;
- BTN residual definition;
- official DFO-LS default backend or `stable_gate77` values;
- QN acceptance/residual gate;
- reverse-gate policy;
- Metropolis acceptance;
- route-B RNG stream contract;
- public output schema.

## Verification

Passed:

```sh
PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
make -C build FC=gfortran LDFLAGS= \
  test_official_dfols_preset_contract \
  test_retained_core_qn_route_contract
```

Passed:

```sh
PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
make -C build FC=gfortran LDFLAGS= \
  test_retained_core_newton_contract \
  test_retained_core_rattle_rg_contract \
  test_retained_core_qn_route_contract \
  test_retained_core_rg_reject_identity \
  post_b_rng_reference_anchor \
  ../bin/run_tltm_stage1 \
  ../bin/run_tltm_stage2
```

Passed:

```sh
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Full M4 result: all guardrails passed; artifacts in `output/tests/m4_guardrails`.

## Remaining Open Boundary

The next module-state boundary is not another QN-specific cache. The largest
active proposal-path `save` cluster now sits in `hmc_integrator_core`:

- S1 fallback and reverse-gate policy cache:
  `s1_fallback_policy_loaded`, S1 probe/full iteration controls,
  near/non-near rescue toggles, `qn_reverse_gate_enabled`,
  `qn_reverse_gate_tol`, and `qn_quasi_tol_override`;
- reverse-gate replay recursion/runtime flag:
  `qn_reverse_gate_active`;
- reverse-gate replay status counters.

Those fields mix product policy, per-call recursion state, and run diagnostics.
The next stop is
`CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_DECISION_POINT_20260513.md`.
