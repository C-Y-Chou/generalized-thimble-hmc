# F19 Internal DFO Backend Deletion - 2026-05-15

Status: implemented locally on `codex/fortran-modernization`.

## Decision

The official QN route now has one active solver backend:

```text
Newton strict attempt -> official DFO-LS package attempt -> TLTM residual
certification -> final flow / reverse gate -> success or proposal reject.
```

`QN_SOLVER_BACKEND=internal` is no longer a supported active backend.  If that
legacy value is supplied, the policy loader warns and uses `official_dfols`.

## Source Changes

- `src/sampler/quasi_newton_solver.f90`
  - Removed the internal DFO-like trust-region solver `run_dfo_ls_attempt`.
  - Removed the finite-difference DFO-GN helper `build_dfo_gn_jacobian`.
  - Removed force-best proposal acceptance and quasi watchdog/budget policy.
  - Kept the official DFO-LS C bridge, TLTM residual callback, strict candidate
    certification, attempt capture, and global-filter diagnostics.
- `src/sampler/quasi_newton_linear_solver.f90`
  - Removed `solve_linear_direction`, real-matrix workspaces, and the unused
    projection-target seed helper.
  - Kept only `initial_guess_from_jacobian`, which seeds the official package
    from the BTN/TLTM Jacobian variable map.
- `src/sampler/hmc_integrator_core.f90`
  - Removed near/non-near retry controls and retry attempts.
  - Removed `QN_S1_*` and `QN_QUASI_TOL_OVERRIDE` active source handling.
  - Kept failure classification as diagnostics only.
  - Kept proposal rejection/stay-put and reverse-gate certification as the
    project-selected RATTLE failure policy.

Historical PBS wrappers may still export legacy environment variables for
reproducibility, but active source no longer reads the removed knobs.

## Verification

Local commands run with the embedded official package:

```bash
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_official_dfols_preset_contract \
  test_retained_core_qn_route_contract \
  test_retained_core_rg_reject_identity \
  test_odex_assist_policy
```

Result: pass.

Compatibility check:

```bash
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
  QN_SOLVER_BACKEND=internal ./bin/test_official_dfols_preset_contract
```

Result: pass, with warning that `internal` is no longer supported and
`official_dfols` is used.

## Claim Boundary

Allowed after this slice:

```text
The active QN solver route uses the official DFO-LS package only.  TLTM
certification gates, final-flow strictness, reverse-gate rejection, and
diagnostics remain in-house project policy.
```

Still blocked:

```text
DFO-LS package success alone proves proposal correctness.
```

```text
All handwritten TLTM algorithms are paper-correct.
```

```text
Historical scripts or outputs that used in-house DFO-like code are official
DFO-LS evidence.
```

## Next Step

`F15b` solver-assist deletion is now implemented in
`F15_SOLVER_ASSIST_DELETION_20260515.md`. Continue with mature ODE backend
evaluation from `MATURE_ODE_BACKEND_DECISION_20260515.md`.
