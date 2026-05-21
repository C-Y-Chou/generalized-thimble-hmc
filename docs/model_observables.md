# Model Actions And Observables

This project keeps model-specific physics behind the `src/physics/` model
surface. Samplers and analysis code must not encode a particular action or
observable formula, and canonical sampler/config code must not branch on a
runtime model selector. To change models, replace the active source provider
behind the same model API.

## Action Surface

The active canonical provider is:

- `src/physics/model_stephanov.f90`

`src/physics/model.f90` exposes the stable interface used by flow and sampler
code:

- `calculate_action`
- `ds`
- `hessian`
- `hessian_vec`

For Stephanov, all four are hand-written analytic dense routines. Generic AD
or generated derivatives are validation oracles only and are not part of the
active sampler/flow path.

## Observable Surface

Model observables are defined by the active provider:

- `src/physics/model_stephanov.f90`
- `src/physics/model_observables.f90`

`model_observables.f90` is the public lookup/evaluation facade. It does not
contain sampler formulas; it delegates to the active provider.

Current Stephanov observables are:

- `chiral_condensate`
- `number_density`
- `logdet_dirac`
- `phase_factor`
- `min_singular_ba_m2`

The public API is `src/physics/model_observables.f90`:

- `model_observable_count()`
- `get_model_observable_name(index, name)`
- `find_model_observable(name)`
- `evaluate_model_observables(z, observables)`
- `evaluate_model_observable_by_index(z, index, observable)`

Stage2 and evaluator code call this API only. To move to a different model,
replace the active provider implementation and keep the same public model API;
do not add a runtime `model_name` branch to sampler/config code.

Draft future models first under:

- `model_specs/high_dimensional/`

That staging folder is not compiled. Promote a reviewed model by replacing the
active provider under `src/physics/` and the associated config fields under
`src/config/`.

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
EVAL_OBSERVABLE_NAME=chiral_condensate \
../bin/evaluate_expectations
```

If `EVAL_OBSERVABLE_NAME` is omitted, the evaluator uses the first observable
reported by the active provider.
