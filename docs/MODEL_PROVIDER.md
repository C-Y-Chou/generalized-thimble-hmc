# Model Provider

The sampler code calls a model provider through a generic Fortran API. A model
is responsible for the physics; the sampler is responsible for transitions,
flow, bookkeeping, and observable accumulation.

## Required Contract

A provider supplies:

- scalar action `S(x)`;
- manual gradient `dS/dx`;
- Hessian-vector product or equivalent dense Hessian action;
- flow RHS derived from the action;
- observable names and observable values;
- exact or reference values when available for validation.

The active production rule is manual derivatives. Automatic or finite-difference
tools can be used as validation or development oracles, but the runtime provider
should expose the analytic routines directly.

## Complexified Validation

Derivative validation should use genuinely complex seeds. The minimum useful
gate is:

- random complex state;
- random complex perturbation direction;
- gradient finite-difference check;
- Hessian-vector finite-difference check;
- observable shape and finite-value check.

The public validation command includes the Stephanov provider derivative gate:

```bash
make test
```

## Active Stephanov Provider

The current provider is implemented in:

- `src/physics/model_stephanov.f90`
- `src/physics/model.f90`
- `src/physics/model_observables.f90`

The selected benchmark parameters are in:

- `data/parameters_stephanov_n6_mu06_t0.dat`

## Adding A Model

1. Create a model specification under `model_specs/`.
2. Implement the provider routines in `src/physics/`.
3. Add a parameter file under `data/`.
4. Add derivative and observable validation tests.
5. Run `make test`.
6. Run a short WV-HMC or TLTM smoke with observable histories enabled.

Do not put model choice into the canonical sampler kernels. The sampler should
continue to call the generic provider interface.
