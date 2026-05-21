# Model Observable Stream I/O Slice - 2026-05-22

Scope: move observable formulas out of Stage2/evaluator orchestration and into
the model layer, then add a generic measurement stream suitable for large
datasets.

## Source Changes

- Added `src/physics/model_observables.f90`.
- Added model-owned observable definition files:
  - `src/physics/model_observable_registry.inc`
  - `src/physics/model_observable_body.inc`
- Added `physics/model_observables` to `build/makefile`.
- Updated `src/sampler/tltm_stage2_driver.f90` so observable streams write:
  - `complex(dp) phi`
  - `complex(dp) observable_values(model_observable_count())`
- Updated Stage2 v1 sidecars to record the observable provider, names, record
  layout, stream paths, stride/cap controls, and `observables/observable_schema.json`.
- Updated `src/apps/evaluate_expectations.f90` so observable formulas are taken
  from `model_observables`; the app can also read
  `EVAL_OBSERVABLE_HISTORY_FILE` directly.

## Contract

Sampler/evaluator code must not encode model-specific observable formulas. For
a new model, update:

- `src/physics/model_action_body.inc`
- `src/physics/model_observable_registry.inc`
- `src/physics/model_observable_body.inc`

The current compatibility observable names are `virial` and `z_sum`; `tra2`
and `z` are aliases for `z_sum` at lookup time.

## Verification

Build:

```bash
make -C build fast ../bin/run_tltm_stage2 ../bin/evaluate_expectations
```

Local smoke:

```bash
TLTM_STAGE2_NUM_REPLICAS=1 \
TLTM_STAGE2_CYCLES=2 \
TLTM_STAGE2_LOCAL_UPDATES=1 \
TLTM_STAGE2_MAX_FLOW_TIME=0.05 \
TLTM_STAGE2_SWAP_ENABLED=0 \
TLTM_STAGE2_SUMMARY_FILE=/tmp/tltm_observable_stream_smoke/stage2_summary.dat \
TLTM_STAGE2_LABEL_TRACE_FILE=/tmp/tltm_observable_stream_smoke/label_trace.dat \
TLTM_STAGE2_COLD_OBSERVABLE_FILE=/tmp/tltm_observable_stream_smoke/observable_history.dat \
TLTM_STAGE2_COLD_Z_HISTORY_FILE=/tmp/tltm_observable_stream_smoke/z_history.dat \
TLTM_STAGE2_COLD_PHI_HISTORY_FILE=/tmp/tltm_observable_stream_smoke/phi_history.dat \
TLTM_STAGE2_V1_OUTPUT_DIR=/tmp/tltm_observable_stream_smoke/v1 \
../bin/run_tltm_stage2
```

Readback:

- `observable_history.dat` was 144 bytes for 3 records with 2 observables:
  `3 * (1 + 2) * 16`.
- `manifest.json`, `protocol.json`, and `observables/observable_schema.json`
  parsed as JSON.
- `scripts/audit_tltm_tempering_protocol.py` passed with zero errors; one
  expected warning remained because the smoke command did not pass a label trace.
- `EVAL_OBSERVABLE_HISTORY_FILE=/tmp/tltm_observable_stream_smoke/observable_history.dat`
  `EVAL_OBSERVABLE_NAME=virial ../bin/evaluate_expectations` completed. The
  tiny 3-sample gnuplot render warned about logscale range, which is expected
  for the smoke size and not an observable-stream failure.
