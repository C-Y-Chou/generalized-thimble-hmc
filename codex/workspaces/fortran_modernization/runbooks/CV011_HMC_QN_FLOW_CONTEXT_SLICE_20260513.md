# CV-011 HMC/QN Flow Context Slice

Updated: 2026-05-13 JST

## Implementation

- Threaded optional `flow_workspace_t` through `metropolis_step`.
- Threaded flow workspace through HMC proposal, warmup, reverse-probe, and
  `rattle_step_core`.
- Threaded flow workspace through Newton constraint residual flow calls.
- Threaded flow workspace through QN residual evaluation, finite-difference
  residual probes, rescue/recovery, and final RATTLE flow.
- Stage1 and Stage2 local updates now pass `run_context%flow%workspace`, so
  active proposal paths use per-replica/per-slot flow workspace ownership.

## Behavior Boundary

State ownership only. No intended change to physics equations, ODEX policy, QN
route, reverse-gate policy, Metropolis acceptance, route-B RNG streams, or
output schema.

## Verification

Passed:

```bash
PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor ../bin/run_tltm_stage1 ../bin/run_tltm_stage2
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Full M4 result: all guardrails passed; artifacts in `output/tests/m4_guardrails`.

## Next Stop

Official DFO-LS backend callback state is the next productization decision. The
C bridge accepts a `ctx` pointer, but the Fortran callback currently still uses
module-level `qn_official_*` context state. Full OpenMP/thread-safe
productization needs a decision before this callback state is redesigned or
explicitly deferred.
