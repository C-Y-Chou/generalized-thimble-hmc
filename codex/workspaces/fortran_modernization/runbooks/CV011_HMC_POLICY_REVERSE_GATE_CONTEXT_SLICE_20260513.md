# CV-011 HMC Policy And Reverse-Gate Context Slice

Updated: 2026-05-13 JST

## Decision

User selected option A from
`CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_DECISION_POINT_20260513.md`: split HMC
fallback/reverse-gate state into three explicit concepts instead of keeping a
single module-global cluster:

- a Stage/run-owned HMC policy context for S1 fallback and reverse-gate env
  policy;
- a per-HMC-context replay runtime flag for active reverse-gate recursion;
- a Stage/run-owned replay diagnostics context for reverse replay status
  counters.

## Implemented Slice

- Added `hmc_policy_context_t`, `hmc_replay_runtime_context_t`, and
  `hmc_replay_diagnostics_context_t` in `hmc_integrator_core`.
- Moved S1 fallback and reverse-gate policy cache into
  `hmc_policy_context_t`:
  `s1_fallback_policy_loaded`, S1 probe/full iteration controls,
  near/non-near rescue toggles, `qn_reverse_gate_enabled`,
  `qn_reverse_gate_tol`, and `qn_quasi_tol_override`.
- Moved `qn_reverse_gate_active` into `hmc_replay_runtime_context_t`.
- Moved reverse-gate replay status counters into
  `hmc_replay_diagnostics_context_t`.
- Preserved legacy/direct-call compatibility with module fallback contexts.
- Threaded HMC policy and replay diagnostics through `metropolis_step`,
  HMC proposal/warmup/reverse-probe, `rattle_step_core`, and QN reverse-gate
  replay.
- Added the replay runtime context under `tltm_hmc_context_t`, so each
  replica/slot HMC path owns its active reverse-gate recursion flag.
- Stage1/Stage2 now own one run-level `hmc_policy_context_t` and one run-level
  `hmc_replay_diagnostics_context_t`.
- Extended `test_retained_core_rattle_rg_contract` with
  `replay_diagnostics_context_isolation`, proving two explicit replay
  diagnostics contexts keep independent status counters in the same process.

## Behavior Boundary

This is a state ownership/productization slice only.

No intended change to:

- TLTM physics equations;
- BTN residual definition;
- official DFO-LS backend or preset values;
- S1 fallback/reverse-gate policy values;
- reverse-gate accept/reject tolerance;
- Metropolis acceptance;
- route-B RNG stream contract;
- public output schema.

## Verification

Passed:

```sh
PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
make -C build FC=gfortran LDFLAGS= \
  test_retained_core_rattle_rg_contract \
  test_retained_core_rg_reject_identity
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

This closes the active HMC fallback/reverse-gate proposal-path `save` cluster
for the Stage1/Stage2 local-update product path.

CV-011 remains open for the next state categories:

- solver and reverse-gate diagnostics counters outside this slice;
- flow/ODEX counters, runtime traces, and last-failure snapshots;
- model tape/cache ownership;
- `param_mod` config mirror replacement or scoped product boundary;
- reversibility/progress probe config and counters;
- profiling counters;
- deterministic serial/reentrant checks across the remaining migrated contexts.

Production redo remains external to modernization and belongs to
`tltm_production_comparison`.
