# Stephanov `n=6` Example

This example exercises the dense explicit-J WV-HMC public wrapper on the
Stephanov `n=6`, `mu=0.6` benchmark parameter file.

## Smoke

```bash
make wv-hmc-smoke
```

## Validation-Style Run

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
  --output-dir output/product/wv_hmc_stephanov_n6_example
```

The output directory should contain a `product_run_manifest.json` plus the
CSV files written by the WV-HMC executable.  Treat this as a reproducibility
and wrapper check, not as a standalone production physics estimate.

## Optional Boundary-Policy Benchmark

To compare against the optional full-bounce policy, rerun with the same
parameters, seed, cycle count, burn rule, and measurement window, changing only:

```bash
--boundary-policy full_bounce
```
