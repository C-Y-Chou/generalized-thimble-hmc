# Model Provider

The sampler code calls a model provider through a generic Fortran API.  A model
is responsible for the physics.  The sampler is responsible for transitions,
flow-time bookkeeping, ratio estimators, histories, snapshots, and restart
metadata.

This is the onboarding contract for adding a new physics model.  Freeze the
contract in `model_specs/` before changing active Fortran source.

## Boundary Rule

Do not put model choice into canonical sampler kernels.  TLTM, GT-HMC, and
WV-HMC code should call the generic facades:

- `src/physics/model.f90`
- `src/physics/model_observables.f90`

Model-specific formulas belong in a provider module such as
`src/physics/model_<name>.f90`.  The facades may dispatch to the active
provider, but sampler kernels should not contain model-specific branches.

## Required Model Contract

A model specification must define:

- model name and target integral;
- real state layout and complexified state layout;
- scalar holomorphic action `S(z)`;
- manually provided gradient `dS/dz`;
- manually provided Hessian-vector product `H(z) v`;
- dense Hessian construction if dense validation or dense WV-HMC requires it;
- model parameters and their configuration-file names;
- observable names and analytic formulas;
- exact, semianalytic, or independent small-reference values when available;
- expected singularities, branch cuts, determinant conventions, and phase
  conventions;
- valid flow-time range for initial validation.

The active production rule is manual derivatives.  Automatic differentiation
or finite differences may be used as validation or development oracles, but the
runtime provider should expose analytic routines directly.

## Fortran Provider API

The public facades currently require these routines:

- `calculate_action(z, s)`: return the complex scalar action.
- `ds(z, grad)`: return the complex gradient with the same state ordering as
  `z`.
- `hessian_vec(z, v, hv)`: return `H(z) v`.
- `hessian(z, h)`: return a dense Hessian when the dense route needs it.
- `batched_ds_hessian_vec_available()`: state whether the provider has a
  fused gradient / multi-vector Hessian-vector implementation.
- `ds_hessian_vec_batch(z, vectors, grad, hvectors)`: optional fused path.
- `model_observable_count()`: return the observable count.
- `get_model_observable_name(index, name)`: return stable observable names.
- `evaluate_model_observables(z, observables)`: evaluate all observables.
- `evaluate_model_observable_by_index(z, index, observable)`: optional fast
  path for one observable.

All provider routines must be deterministic for fixed inputs and must not hide
sampler state, random-number generation, or measurement-window decisions.

## Observable Contract

Observables are model-owned analytic functions of the current complexified
configuration.  They should not include sampler weights, burn cuts,
measurement-window cuts, or ratio-estimator postprocessing.

For WV-HMC and TLTM reweighting, analysis must preserve:

```text
O_hat = sum_i w_i O_i / sum_i w_i
```

If a quantity is derived from multiple observables or from the final ensemble
ratio, document it as a post-analysis diagnostic rather than a primary provider
observable.

## Complexified Validation Gates

Derivative validation must use genuinely complex seeds.  The minimum provider
gate is:

- random complex state;
- random complex perturbation direction;
- action finite-difference check against manual gradient;
- Hessian-vector finite-difference check against manual `hessian_vec`;
- dense Hessian times vector checked against `hessian_vec` when dense Hessian
  is provided;
- batched gradient / Hessian-vector output checked against scalar calls when
  a batched path is provided;
- observable count, names, finite values, and single-observable fast path
  checked against all-observable evaluation.

The public validation command includes the current Stephanov provider
derivative gate:

```bash
make test
```

## Small-Reference Gate

Before using a new provider for production-style sampling, add at least one
small reference check.  Acceptable references include:

- exact value for a small matrix size;
- direct quadrature or enumeration for a toy limit;
- independent implementation in a notebook or script;
- published benchmark value with matching conventions;
- a controlled limiting case with known symmetry, zero imaginary part, or
  known derivative identity.

Record the normalization, parameter values, observable convention, and expected
tolerance.  A small-reference pass is separate from an HMC tuning pass: do not
use sampler agreement alone as proof that the model formulas are correct.

## Promotion Checklist

1. Draft the model specification from `model_specs/TEMPLATE.md`.
2. Review the action, state layout, observables, and reference values.
3. Implement `src/physics/model_<name>.f90`.
4. Update only the provider facades needed to select the model.
5. Add or update parameter-file keys under `src/config` only when required.
6. Add derivative, Hessian-vector, observable, and small-reference tests.
7. Run `make test`.
8. Run a short TLTM or WV-HMC smoke with observable histories enabled.
9. Record the source commit, parameter file, run options, and output path.

## Active Stephanov Provider

The current provider is implemented in:

- `src/physics/model_stephanov.f90`
- `src/physics/model.f90`
- `src/physics/model_observables.f90`

The selected benchmark parameters are in:

- `data/parameters_stephanov_n6_mu06_t0.dat`
