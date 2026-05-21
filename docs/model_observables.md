# Model Actions And Observables

This project keeps model-specific physics behind the `src/physics/` model
surface. Samplers and analysis code must not encode a particular action or a
particular observable formula.

## Action Surface

The model action is defined in:

- `src/physics/model_action_body.inc`

Run after editing:

```bash
cd build
make regen_model_derivatives
```

The generated model module provides `calculate_action`, `ds`, `hessian`, and
`hessian_vec` through `src/physics/model.f90`.

## Observable Surface

Model observables are defined by two files:

- `src/physics/model_observable_registry.inc`
- `src/physics/model_observable_body.inc`

`model_observable_registry.inc` declares the number and names of available
observables. `model_observable_body.inc` fills `observables(:)` from the
current flowed state `z(:)` and model parameters.

Current compatibility observables are:

- `virial`
- `z_sum` (legacy `tra2` / `z` alias)

The public API is `src/physics/model_observables.f90`:

- `model_observable_count()`
- `get_model_observable_name(index, name)`
- `find_model_observable(name)`
- `evaluate_model_observables(z, observables)`
- `evaluate_model_observable_by_index(z, index, observable)`

Stage2 and evaluator code call this API only. To move to a different model,
update the action body plus the observable registry/body; do not edit sampler
or evaluator formula code.

If the new model needs additional couplings or lattice-shape parameters beyond
the current compatibility `alpha`/`beta` controls, add those parameters to
`src/config/param_mod.f90` and consume them from the model layer. The sampler
and evaluator should still see only the generic model APIs.

Draft new models first under:

- `model_specs/high_dimensional/`

That staging folder is not compiled. Promote its action/observable drafts into
`src/physics/` only after the model plan and validation plan are reviewed.

## Stage2 Observable Stream

For large datasets, prefer measurement streams over full `z_history` unless a
configuration snapshot is explicitly needed.

Enable cold-slot observable stream:

```bash
TLTM_STAGE2_COLD_OBSERVABLE_FILE=/path/to/observable_history.dat
```

Enable all-replica observable streams:

```bash
TLTM_STAGE2_ALL_REPLICA_OBSERVABLE_DIR=/path/to/replica_outputs
```

Record layout is unformatted stream binary:

```text
complex(dp) phi
complex(dp) observable_values(model_observable_count)
```

Use stride/cap controls to bound output size:

- `TLTM_STAGE2_OBSERVABLE_STRIDE`
- `TLTM_STAGE2_OBSERVABLE_MAX_SAMPLES`
- `TLTM_STAGE2_COLD_OBSERVABLE_STRIDE`
- `TLTM_STAGE2_COLD_OBSERVABLE_MAX_SAMPLES`
- `TLTM_STAGE2_ALL_REPLICA_OBSERVABLE_STRIDE`
- `TLTM_STAGE2_ALL_REPLICA_OBSERVABLE_MAX_SAMPLES`

The v1 sidecar package writes:

- `observables/observable_schema.json`
- observable schema fields in `manifest.json`, `protocol.json`, and
  `config.resolved.json`

## Evaluator Input

The evaluator can still read `z_history.dat` + `phi_history.dat` and compute
observables through `model_observables`.

For large datasets, read the Stage2 observable stream directly:

```bash
EVAL_OBSERVABLE_HISTORY_FILE=/path/to/observable_history.dat \
EVAL_OBSERVABLE_NAME=virial \
../bin/evaluate_expectations
```

If `EVAL_OBSERVABLE_NAME` is omitted, the legacy `tra2` flag selects `z_sum`;
otherwise the default is `virial`.
