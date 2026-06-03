# User Guide

## Workflow

1. Choose or implement a model provider.
2. Prepare a `parameters.dat`-style key-value file.
3. Build and validate the public targets.
4. Run a smoke test.
5. Run TLTM or WV-HMC through `scripts/run_tltm_product.py`.
6. Read observables from the generated CSV files.
7. For larger studies, record the source commit, parameter file, run options,
   and output directory.

## WV-HMC Example

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
  --history \
  --snapshot-interval 250 \
  --output-dir output/product/wv_hmc_example
```

The wrapper writes a `product_run_manifest.json` into the output directory.

## TLTM Example

TLTM uses a run-protocol JSON for multiseed runs:

```bash
python3 scripts/run_tltm_product.py tltm \
  --config path/to/tltm_protocol.json \
  --jobs 8 \
  --max-seeds 32 \
  --output-dir output/product/tltm_example
```

Use `--dry-run` to print the delegated command before launching.

## Burn-In

WV-HMC validation on the Stephanov `n=6` benchmark showed a startup transient
from the initial bank. Treat burn-in as part of the production protocol:

- keep observable histories for validation runs;
- inspect prefix stability before using estimates;
- record the chosen measurement window in the run manifest;
- do not use all-cycle estimates when the startup transient is visible.

## Production Runs

Local examples are for development.  Larger studies should use an appropriate
batch or HPC environment when needed, and should keep enough metadata to
reproduce the run.
