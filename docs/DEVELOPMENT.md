# Development

## Guardrails

Public validation:

```bash
make test
```

Direct targets:

```bash
make -C build test_wv_hmc_math_kernels
make -C build test_wv_hmc_constraint_kernels
make -C build test2
```

General source hygiene:

```bash
git diff --check
```

## Change Discipline

- Keep sampler logic model-general.
- Keep model formulas inside the provider.
- Preserve ratio-estimator structure when analyzing observables.
- Keep burn-in decisions explicit in run manifests and readbacks.
- Record source commit, parameters, run options, and output paths for validation
  runs.
- Re-run public tests after wrapper, build, or model-provider edits.

## Source Layout

- `src/core`: numerical helpers, RNG, profiling utilities.
- `src/config`: runtime configuration.
- `src/physics`: model provider, observables, flow backend.
- `src/sampler`: TLTM, HMC, WV-HMC kernels, constraints, drivers.
- `src/apps`: executable entry points.
- `scripts`: product runner and automation scripts.
- `tests`: Fortran validation programs.
