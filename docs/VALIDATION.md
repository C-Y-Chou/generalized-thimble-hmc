# Validation

This page defines the public validation path for the current repository state.
It is intentionally small: it verifies the shipped wrappers and dense
explicit-J WV-HMC path without depending on private job-control state or large
generated datasets.

## Claim Boundary

- TLTM is the mature production-style sampler path in this repository.
- Dense explicit-J WV-HMC is available for algorithm validation and Stephanov
  benchmark development.
- Dense WV-HMC defaults to `normal_reflect` boundary handling.
- `full_bounce` / `paper_full_flip` is an optional benchmark policy.
- Matrix-free trajectories, iterative linear solves, and high-dimensional
  WV-HMC performance validation remain future work.
- DOP853 is the public flow-backend path for wrapper-launched WV-HMC runs.

Do not treat a single run, seed, burn cut, or measurement window as a final
physics claim.  Production claims should use ratio-preserving uncertainty
estimates and record the full run protocol.

## Public Smoke Checks

Build:

```bash
make build
```

Run public tests:

```bash
make test
```

Run a short dense WV-HMC smoke:

```bash
make wv-hmc-smoke
```

The smoke target writes a manifest and short output under
`output/product/wv_hmc_smoke`.

## Stephanov `n=6` Dense WV-HMC Example

Use this command for a small local validation-style run:

```bash
python3 scripts/run_tltm_product.py wv-hmc \
  --parameters data/parameters_stephanov_n6_mu06_t0.dat \
  --cycles 1000 \
  --seed 20260529 \
  --step-size 0.016 \
  --num-steps 10 \
  --t0 1e-4 \
  --d0 1e-4 \
  --t1 0.03 \
  --d1 0.005 \
  --w-profile paper_wall \
  --w-gamma 55 \
  --boundary-policy normal_reflect \
  --history \
  --snapshot-interval 250 \
  --output-dir output/product/wv_hmc_validation
```

For an optional bounce-policy benchmark, change only:

```bash
--boundary-policy full_bounce
```

Compare policies only after matching the model parameters, seeds, cycle
budget, burn rule, measurement window, and ratio-estimator analysis.

## Required Run Metadata

Record these items for any result used beyond a smoke test:

- git commit;
- parameter file;
- model name and physical size;
- sampler and boundary policy;
- flow backend;
- `T0`, `D0`, `T1`, `D1`;
- `W(t)` profile and parameters;
- step size and number of integration steps;
- seed list and cycle count;
- burn rule and measurement window;
- output directory and manifest path.

## Observable Analysis Rule

For complex reweighted observables, preserve the ratio structure:

```text
O_hat = sum_i w_i O_i / sum_i w_i
```

Uncertainty estimates should resample seeds or blocks while recomputing the
ratio, rather than bootstrapping numerator and denominator independently.
