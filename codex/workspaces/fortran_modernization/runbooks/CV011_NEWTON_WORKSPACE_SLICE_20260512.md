# CV-011 Newton Workspace Slice

Updated: 2026-05-12 JST

Scope: third non-RNG hidden-workspace migration after the route-B RNG contract.

## Change

`hmc_constraints:solve_constraint_newton` no longer owns subroutine-local
`save` scratch arrays for Newton projection solves. It now exposes
`newton_constraint_workspace_t`; callers may pass an explicit workspace, and
legacy callers use automatic local workspace rather than shared hidden state.

The active RATTLE core path stores `newton_constraint_workspace_t` inside
`rattle_step_workspace_t` and passes it to `solve_constraint_newton`.

## Files

- `src/sampler/hmc_constraints.f90`
- `src/sampler/hmc_state_buffers.f90`
- `src/sampler/hmc_integrator_core.f90`

## Behavior Boundary

This is intended as behavior-preserving workspace ownership work:

- no Newton residual/update formula change;
- no ODEX/flow policy change;
- no QN fallback policy change;
- no RNG stream change;
- no output schema change.

## Verification

Passed locally on 2026-05-12 JST:

```bash
make -C build FC=gfortran LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract post_b_rng_reference_anchor
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

## Remaining CV-011 Work

CV-011 remains open for:

- Newton/QN status counters and policy state;
- QN residual/trace/capture module state;
- ODEX/flow workspaces and diagnostics state;
- Stage2 audit/logging state;
- model tape/generated cache state;
- param/config legacy global mirror;
- deterministic serial/reentrant checks.
