# Model Specification Template

Copy this file into a model-specific directory under `model_specs/` and fill it
before editing active provider source.

## Identity

- Model name:
- Target integral:
- Reference papers or notes:
- Intended sampler path: TLTM / GT-HMC / WV-HMC

## State Layout

- Real state dimension:
- Complexified state dimension:
- Index ordering:
- Matrix, lattice, or field convention:
- Reality, Hermiticity, gauge, or constraint convention:

## Parameters

| name | meaning | default | valid range | config key |
|---|---|---:|---:|---|
| | | | | |

## Action

Write the scalar holomorphic action `S(z)` and define every normalization
factor.

```text
S(z) =
```

State branch, determinant, logarithm, and phase conventions here.

## Manual Gradient

Write the analytic gradient in the same state ordering as the provider.

```text
dS/dz =
```

## Hessian / Hessian-Vector

Write the analytic Hessian-vector product `H(z) v`.  If a dense Hessian is
also needed, define how its columns correspond to the vector ordering.

```text
H(z) v =
```

## Observables

Provider observables are analytic functions of the complexified configuration.
Do not include sampler weights or ratio-estimator postprocessing.

| name | analytic form | exact/reference value | notes |
|---|---|---:|---|
| | | | |

## Small Reference

- Reference parameter point:
- Exact, semianalytic, or independent value:
- Expected tolerance:
- Independent source of the reference:

## Validation Gates

- [ ] random complex gradient finite-difference check
- [ ] random complex Hessian-vector finite-difference check
- [ ] dense Hessian times vector equals Hessian-vector routine
- [ ] batched derivative path equals scalar derivative path, if provided
- [ ] observable count and names are stable
- [ ] all observables are finite on random complex seeds
- [ ] single-observable fast path equals all-observable evaluation
- [ ] small-reference check passes
- [ ] short sampler smoke writes histories and manifest

## Promotion Notes

- Provider source file:
- Facade changes:
- Parameter-file changes:
- Tests added:
- Known caveats:
