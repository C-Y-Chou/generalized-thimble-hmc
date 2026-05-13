# CV-011 Newton Eval-Flow Status Context Slice

Updated: 2026-05-13 JST

## Scope

This slice handles the Newton eval-flow status counters in `hmc_constraints`.
These counters feed Stage1/Stage2 summaries, so they are behavior-adjacent
diagnostics rather than physics decision logic.

## Implemented Slice

- Added `newton_eval_flow_status_context_t` in `hmc_constraints`.
- Moved Newton eval-flow status counters behind the context:
  success, zero-time success, stiff-rescue success, solver-assist success,
  max-step failure, invalid failure, h-min failure, and unknown status.
- Preserved legacy direct-call compatibility through a module fallback context.
- Added optional context arguments to reset/get/record APIs and to
  `solve_constraint_newton`.
- Threaded a Stage/run-owned Newton flow-status context through Stage1/Stage2
  local updates, `metropolis_step`, HMC proposal/warmup, RATTLE, reverse-gate
  replay, and Newton constraint solve.
- Stage1/Stage2 summary writers now read Newton eval-flow status from the
  Stage/run-owned context instead of module state.
- Added `test_newton_eval_flow_status_context_contract` and included it in the
  build and M4 guardrail target list.

## Behavior Boundary

This is a diagnostics ownership/productization slice only.

No intended change to:

- TLTM physics equations;
- flow, Newton, QN, RATTLE, reverse-gate, or Metropolis decisions;
- route-B RNG stream contract;
- public output schema or counter names.

The Stage1/Stage2 summary fields keep the same names and meanings. Only the
storage owner changed from module global counters to the active Stage/run
diagnostics context.

## Verification

Passed:

```sh
git diff --check
```

Passed:

```sh
make -C build test_newton_eval_flow_status_context_contract
```

Passed:

```sh
make -C build ../bin/run_tltm_stage2
```

Passed:

```sh
make -C build test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity
```

Passed:

```sh
python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags '' --output-root output/tests/post_b_rng_reference_anchor_newton_flow_context_check
```

Passed:

```sh
PYTHON="$PWD/.venv-dfols/bin/python" TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

## Anchor Note

The first full-M4 attempt caught a Stage2 post-B summary-hash mismatch. The
only normalized summary difference was `newton_eval_flow_status success`; the
Stage1 summary and Stage2 label trace were unchanged. The cause was incomplete
context threading through Stage2 adaptive preflow. After threading the same
Stage/run-owned context through `adaptive_preflow_to_target` and
`relax_with_zero_momentum`, the post-B RNG reference anchor returned to pass
without changing the frozen reference hash.

## Remaining Open Boundary

This removes Newton eval-flow status counters from the remaining CV-011
hidden-state list as a source-level ownership problem. CV-011 remains open for:

- constraint-solver aggregate counters, reverse-gate path counters, and
  failure-capture file/counter state in `constraint_solver_stats`;
- `solve_flow` fallback counters, runtime traces, and last-failure snapshots;
- model tape/cache ownership;
- `param_mod` config mirror replacement or scoped product boundary;
- deterministic serial/reentrant checks across the migrated contexts.

Production redo remains external to modernization and belongs to
`tltm_production_comparison`. Do not fast-forward that tree while formalized
assist bridge jobs are pinned to production-comparison commit `6f98b5b`.
