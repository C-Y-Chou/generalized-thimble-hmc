# CV-011 QN Trace/Eval Context Slice

Updated: 2026-05-13 JST

## Decision

User selected option A from `CV011_QN_TRACE_CAPTURE_CONTEXT_DECISION_POINT_20260513.md`:
introduce run-owned QN context and keep compatibility module fallback for
legacy/direct tests.

## Implemented Slice

- Added `qn_context_t` in `quasi_newton_solver_mod`.
- Moved active-route QN residual scratch, proposed/flowed eval cache,
  `quasi_last_trace_*` buffers, trace route/iteration state, watchdog scope/last
  status, and per-attempt residual eval count into `qn_context_t`.
- Added `release_qn_context`.
- Added a module fallback `module_qn_context` so legacy callers that do not pass
  a QN context retain the previous API behavior.
- Extended `solve_constraint_quasi_newton`, `evaluate_constraint_residual`,
  official DFO-LS callback context, internal DFO-LS path, trace readers, and
  watchdog status reader to accept optional/explicit QN context.
- Added `tltm_qn_context_t` under `tltm_run_context_t`.
- Threaded `run_context%qn%workspace` through Stage1/Stage2 local updates,
  `metropolis_step`, HMC proposal/warmup/reverse-probe, `rattle_step_core`, QN
  reverse-gate replay, QN solve attempts, and trace readers.
- Extended `test_retained_core_qn_route_contract` with
  `qn_context_trace_isolation`, proving two QN contexts keep independent traces
  while the official DFO-LS callback uses the selected context.

## Behavior Boundary

This is a state-ownership/productization slice only.

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

## Remaining Open Boundary

This slice intentionally does not migrate shared diagnostic/file ownership:

- QN attempt-capture file units, file-ready/write-error flags, sample counters,
  stride/limit policy, and capture directory;
- QN eval-flow status counters and global-filter counters;
- QN backend policy cache, preset values, notice/warning flags.

Those are diagnostics/product ownership decisions, not just scratch buffers.
The next stop is `CV011_QN_CAPTURE_DIAGNOSTICS_CONTEXT_DECISION_POINT_20260513.md`.
