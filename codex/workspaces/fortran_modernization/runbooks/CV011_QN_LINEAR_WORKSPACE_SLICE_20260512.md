# CV-011 QN Linear Workspace Slice

Updated: 2026-05-12 JST

Scope: second non-RNG hidden-workspace migration after the route-B RNG contract.

## Change

`quasi_newton_linear_solver_mod` no longer owns module-level `save` scratch
arrays for linear solves and QN initial-guess construction. It now exposes
`qn_linear_workspace_t`; each public solver helper accepts an optional explicit
workspace, and callers that do not pass one use automatic local workspace rather
than shared hidden state.

Public helper APIs keep backward-compatible positional arguments:

- `solve_linear_direction(..., workspace)`
- `initial_guess_from_jacobian(..., workspace)`
- `initial_guess_from_projection_target(..., workspace)`

The new `workspace` arguments are optional.

## Files

- `src/sampler/quasi_newton_linear_solver.f90`

## Behavior Boundary

This is intended as behavior-preserving workspace ownership work:

- no official DFO-LS preset or acceptance-gate change;
- no QN residual definition change;
- no RNG stream change;
- no output schema change.

## Verification

Passed locally on 2026-05-12 JST with official DFO-LS Python env loaded:

```bash
PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$(.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract post_b_rng_reference_anchor
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

## Remaining CV-011 Work

This removes one QN scratch-workspace class, but CV-011 remains open for:

- QN residual/trace/policy/capture module state;
- Newton solver scratch and status counters;
- ODEX/flow workspaces and diagnostics state;
- Stage2 audit/logging state;
- model tape/generated cache state;
- param/config legacy global mirror;
- deterministic serial/reentrant checks.
