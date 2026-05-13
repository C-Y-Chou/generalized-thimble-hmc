# CV-011 QN Diagnostics Context Slice

Updated: 2026-05-13 JST

## Decision

User selected option A from
`CV011_QN_CAPTURE_DIAGNOSTICS_CONTEXT_DECISION_POINT_20260513.md`: keep
per-replica QN scratch in `qn_context_t`, and introduce a Stage/run-owned
diagnostics sink for shared QN capture files and aggregate counters.

## Implemented Slice

- Added `qn_diagnostics_context_t` in `quasi_newton_solver_mod`.
- Moved QN attempt-capture policy flags, file units, file-ready/write-error
  state, sample counters, stride/limit, and capture directory into
  `qn_diagnostics_context_t`.
- Moved QN eval-flow status counters and QN global-filter candidate/pass/reject
  counters into `qn_diagnostics_context_t`.
- Added `release_qn_diagnostics_context`.
- Added a module fallback `module_qn_diagnostics_context` so legacy/direct
  callers retain previous serial behavior when they do not pass a diagnostics
  sink.
- Extended QN solve, official DFO-LS attempt/callback context, internal DFO-LS
  attempt, GN Jacobian probing, residual evaluation, capture helpers, and
  summary counter readers/resetters to accept an explicit diagnostics sink.
- Threaded optional QN diagnostics through `rattle_step_core`,
  reverse-gate replay, HMC proposal/warmup/reverse-probe, `metropolis_step`,
  and Stage1/Stage2 local-update paths.
- Stage1/Stage2 now own one run-level `qn_diagnostics_context_t`; summaries read
  QN eval-flow/global-filter counts from that sink, and normal completion
  releases any capture file units through `release_qn_diagnostics_context`.
- Extended `test_retained_core_qn_route_contract` with
  `qn_diagnostics_context_isolation`, proving two diagnostics sinks keep
  independent QN eval-flow counters while QN contexts keep independent traces.

## Behavior Boundary

This is a diagnostics ownership/productization slice only.

No intended change to:

- TLTM physics equations;
- Newton/QN residual definition;
- official DFO-LS preset or acceptance policy;
- reverse-gate policy;
- Metropolis acceptance;
- route-B RNG stream contract;
- public output schema.

## Verification

Passed:

```sh
PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract
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

This slice intentionally does not migrate QN backend/watchdog policy caches:

- `quasi_solver_assist_budget`, `quasi_accepted_iter_budget`,
  `qn_force_best_proposal_enabled`, `qn_force_best_proposal_tol`, and
  `quasi_watchdog_policy_loaded`;
- `qn_backend_policy_loaded`, `qn_solver_backend`,
  `qn_backend_notice_printed`, `qn_official_dfols_failure_warned`, and the
  official DFO-LS preset values.

Those are product policy/config state rather than diagnostics sink state. The
next stop is `CV011_QN_BACKEND_POLICY_CONTEXT_DECISION_POINT_20260513.md`.
