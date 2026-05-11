# Official DFO-LS Preset Tuning Policy

Updated: 2026-05-11 JST

## Scope

This policy governs the embedded official DFO-LS backend for the canonical p28
BTN/QN projection route.

The backend boundary is intentionally narrow:

- TLTM owns the BTN residual, initial seed construction, flow/backflow callback,
  residual gate, reverse gate, Metropolis decision, diagnostics, and failure as
  rejection.
- Official `DFO-LS==1.6.5` owns only the derivative-free least-squares solve
  between `x0` and the returned candidate `x`.
- TLTM acceptance is always `residual_norm <= cttol` or the active quasi
  tolerance. DFO-LS package `flag` is recorded/diagnostic only.

## Production Preset

The production default preset is `stable_gate77`, also accepted as `stable`,
`gate77`, `production`, or `official_alone`.

```text
QN_SOLVER_BACKEND=official_dfols
QN_OFFICIAL_DFOLS_PRESET=stable_gate77
QN_OFFICIAL_DFOLS_NPT=4
QN_OFFICIAL_DFOLS_MAXFUN=250
QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE=1
QN_OFFICIAL_DFOLS_RHOBEG=0.018
QN_OFFICIAL_DFOLS_RHOEND=1e-16
QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-30
QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0
```

Rationale from the 77-attempt PBS replacement gate:

- The old `rhobeg=0.05`, default-`npt` preset regressed one in-house-converged
  attempt.
- `npt=4`, `rhobeg=0.018` preserved all 63 in-house-converged attempts.
- The six remaining residual failures were all in-house-nonconverged hard
  attempts.

## Allowed Tuning Surface

Tuning may only use official DFO-LS controls exposed by the package:

- `npt`
- `rhobeg`
- `rhoend`
- `maxfun`
- `objfun_has_noise`
- `user_params["model.abs_tol"]`
- `user_params["model.rel_tol"]`

Do not add external multistart, escape steps, line search, backtracking,
best-rescue selection, or post-package polishing around official DFO-LS. Those
would create a new TLTM-side optimizer rather than evaluating the official
solver alone.

## Acceptance Hierarchy

When comparing official-only presets, choose by this order:

1. Preserve every attempt that converged under the current in-house QN solver
   when checked by the TLTM residual gate.
2. Preserve the float64 contract for objective input, residual output, and
   returned solution.
3. Minimize failures among in-house-nonconverged hard attempts.
4. Minimize residual-call cost, especially p90/max tails, after the first three
   criteria pass.
5. Only then consider chain-level aggregate metrics.

A preset that improves total success count but regresses any in-house-converged
attempt is not production-safe.

## Runtime Policy

The embedded backend is now the default code path in
`solve_constraint_quasi_newton`. The in-house solver remains available only for
controlled legacy comparison:

```bash
QN_SOLVER_BACKEND=internal
```

Production builds must use:

```bash
make -C build ENABLE_OFFICIAL_DFOLS=1 ../bin/run_tltm_stage2 ../bin/evaluate_expectations
```

On remote Rocky 8 nodes where `python3.11-devel` is not installed system-wide,
run the production preflight PBS first. It extracts rebuildable Python headers
under `.deps/python-devel-3.11` when needed and passes `PYTHON_EMBED_CFLAGS`
to `make`. If the cluster changes, override with `TLTM_PYTHON_INCLUDE_DIR`.

Production jobs must expose the official package to the embedded interpreter:

```bash
export TLTM_OFFICIAL_DFOLS_PYTHONPATH="/path/to/.venv-dfols/lib/python3.11/site-packages"
```

If the bridge or import fails, TLTM rejects that QN attempt without falling back
to the internal solver. This keeps the official-alone policy honest.

## Verification Gates

Required before production redo:

1. Build `run_tltm_stage2` and `evaluate_expectations` with
   `ENABLE_OFFICIAL_DFOLS=1`.
2. Run a live Stage2 smoke with `QN_SOLVER_BACKEND=official_dfols`,
   `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`, and `TLTM_OFFICIAL_DFOLS_PYTHONPATH`
   pointing at the venv.
3. Confirm the Stage2 summary has nonzero `quasi_stage_stats probe_success` or
   nonzero `qn_eval_flow_status success`.
4. Confirm logs contain no `Official DFO-LS bridge failed`, Python import
   traceback, or module-not-found error.
5. Keep reverse gate and Metropolis settings unchanged from the selected
   production protocol.
