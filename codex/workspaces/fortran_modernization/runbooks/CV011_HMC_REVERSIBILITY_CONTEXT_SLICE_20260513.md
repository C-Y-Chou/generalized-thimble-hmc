# CV-011 HMC Reversibility Context Slice

Updated: 2026-05-13 JST

## Scope

This slice handles the HMC reversibility/progress diagnostic boundary in
CV-011.  These diagnostics do not choose accepted physics states, but their
environment-loaded policy flags and counters were still module-owned state.

## Implemented Slice

- Added `hmc_reversibility_context_t` in `hmc_reversibility_checks`.
- Moved the reversibility-probe loaded/enabled/fallback-only/limit/count state
  behind the context.
- Moved the state-progress diagnostic loaded/enabled/limit/count state behind
  the context.
- Preserved legacy direct-call compatibility through a module fallback context.
- Added optional context arguments to the probe and progress diagnostic APIs.
- Added `release_hmc_reversibility_context`.
- Replaced the placeholder diagnostics field with
  `tltm_run_context_t%diagnostics%hmc_reversibility`.
- Threaded the context through Stage1/Stage2 local updates, `metropolis_step`,
  HMC proposal/warmup, RATTLE, and reverse-probe reporting.
- Added `test_hmc_reversibility_context_contract` and included it in the build
  and M4 guardrail target list.

## Behavior Boundary

This is a state ownership/productization slice only.

No intended change to:

- TLTM physics equations;
- flow, Newton, QN, RATTLE, reverse-gate, or Metropolis decisions;
- route-B RNG stream contract;
- public output schema;
- default reversibility/progress diagnostic policy.

With `HMC_REVERSIBILITY_PROBE_LIMIT` and
`HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT` unset, both diagnostics remain disabled by
default.  Existing direct callers retain module-fallback behavior, while
Stage1/Stage2 local updates now use the run-owned diagnostics context.

## Verification

Passed:

```sh
git diff --check
```

Passed:

```sh
make -C build test_hmc_reversibility_context_contract
```

Passed:

```sh
make -C build ../bin/run_tltm_stage2
```

Passed:

```sh
make -C build test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity
```

Passed:

```sh
PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

## Remaining Open Boundary

This removes HMC reversibility/progress probe config and counters from the
remaining CV-011 hidden-state list as a source-level ownership problem.
CV-011 remains open for:

- solver and reverse-gate diagnostics counters outside the prior HMC/QN slices;
- flow/ODEX counters, runtime traces, and last-failure snapshots;
- model tape/cache ownership;
- `param_mod` config mirror replacement or scoped product boundary;
- deterministic serial/reentrant checks across the migrated contexts.

Production redo remains external to modernization and belongs to
`tltm_production_comparison`.  Do not fast-forward that tree while formalized
assist bridge jobs are pinned to production-comparison commit `6f98b5b`.
