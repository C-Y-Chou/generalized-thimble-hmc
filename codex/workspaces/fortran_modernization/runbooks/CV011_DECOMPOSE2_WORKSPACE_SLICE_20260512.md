# CV-011 Decompose2 Workspace Slice

Updated: 2026-05-12 JST

Scope: first non-RNG hidden-workspace migration after the route-B RNG contract
and post-B reference anchor.

## Change

`hmc_kernels:decompose2` no longer owns subroutine-local `save` scratch arrays.
It now accepts an optional explicit `decompose2_workspace_t`; callers that do
not pass a workspace use an automatic local workspace rather than shared hidden
state.

The active RATTLE core path stores `decompose2_workspace_t` inside
`rattle_step_workspace_t` and passes it through the final momentum projection.

## Files

- `src/sampler/hmc_kernels.f90`
- `src/sampler/hmc_state_buffers.f90`
- `src/sampler/hmc_integrator_core.f90`

## Behavior Boundary

This is intended as behavior-preserving workspace ownership work:

- no RNG stream changes;
- no solver policy changes;
- no Metropolis/reverse-gate acceptance changes;
- no output schema changes.

The fallback no-workspace call path remains for legacy/test callers, but it no
longer uses shared `save` scratch storage.

## Verification

Passed locally on 2026-05-12 JST:

```bash
make -C build FC=gfortran LDFLAGS= test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

The post-B RNG reference anchor stayed stable after the workspace migration.

## Remaining CV-011 Work

This only removes one hidden scratch-workspace class. CV-011 remains open for:

- ODEX/flow module workspaces and diagnostic state;
- Newton/QN solver workspaces, counters, traces, and policy state;
- Stage2 audit/logging state;
- model tape/generated cache state;
- param/config legacy global mirror;
- deterministic serial/reentrant checks for the selected product contract.
