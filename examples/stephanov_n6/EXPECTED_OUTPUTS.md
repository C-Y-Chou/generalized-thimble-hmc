# Expected Outputs

The Stephanov `n=6` example writes a product manifest and CSV outputs under
the selected output directory.

For the default smoke script:

```bash
examples/stephanov_n6/run_wv_hmc_smoke.sh
```

the output directory is:

```text
output/product/wv_hmc_stephanov_n6_smoke/
```

Expected files:

| path | purpose |
|---|---|
| `product_run_manifest.json` | reproducibility metadata from the product wrapper |
| `summary.csv` | one-row WV-HMC run summary and solver counters |
| `observables.csv` | final weighted observable estimates |
| `final_state.bin` | final chain state for restart-oriented workflows |

If `--history` is added, the wrapper also writes:

| path | purpose |
|---|---|
| `observable_history.csv` | per-cycle observable and weight history |
| `x_history.dat` | real-state history |
| `state_history.dat` | worldvolume state history |

The manifest should include:

- `sampler = wv_hmc_dense_explicit_j`;
- `ode_backend = dop853`;
- `boundary_policy = normal_reflect`;
- the parameter file path;
- cycle count, seed, step size, and trajectory step count;
- flow interval and soft-wall parameters.

The smoke run is a wrapper and output-shape check.  It is not a production
physics estimate.
