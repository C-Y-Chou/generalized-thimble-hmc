# Generalized Thimble HMC

Fortran tools for generalized thimble simulations with model-owned actions,
manual derivatives, and observable streams.

Author: CHOU CHIEN YU

## What Is Included

- TLTM: the current canonical tempered-ladder generalized-thimble workflow.
- WV-HMC: a dense explicit-J sibling sampler with validation on the Stephanov
  `n=6` benchmark after burn-in.
- Model provider interface: scalar action, manual gradient, Hessian-vector
  product, complexified validation, and model-owned observables.
- Product runner: `scripts/run_tltm_product.py` exposes build, test, TLTM, and
  WV-HMC commands from one entry point.

The dense WV-HMC path is suitable for validation and development of the
algorithmic workflow. Matrix-free trajectories and high-dimensional performance
engineering are future work.

## Quick Start

Build the public executables:

```bash
make build
```

Run the public validation checks:

```bash
make test
```

Run a short WV-HMC smoke:

```bash
make wv-hmc-smoke
```

Run a longer dense WV-HMC example:

```bash
python3 scripts/run_tltm_product.py wv-hmc \
  --parameters data/parameters_stephanov_n6_mu06_t0.dat \
  --cycles 1000 \
  --output-dir output/product/wv_hmc_example \
  --history \
  --snapshot-interval 250
```

Run canonical TLTM through a Stage3 protocol file:

```bash
python3 scripts/run_tltm_product.py tltm \
  --config path/to/stage3_protocol.json \
  --jobs 8 \
  --output-dir output/product/tltm_example
```

Production-scale runs should use the scheduler environment documented for the
target cluster. Local runs are intended for build checks, smoke tests, and small
development examples.

## Documentation

- [Install](docs/INSTALL.md)
- [User Guide](docs/USER_GUIDE.md)
- [Model Provider](docs/MODEL_PROVIDER.md)
- [Samplers](docs/SAMPLERS.md)
- [Configuration](docs/CONFIGURATION.md)
- [Outputs and Restart](docs/OUTPUTS_AND_RESTART.md)
- [Development](docs/DEVELOPMENT.md)
- [References](docs/REFERENCES.md)
- [Reproducibility Records](docs/REPRODUCIBILITY_RECORDS.md)

## License

This repository is distributed under GPL-3.0-or-later. See
[LICENSE](LICENSE), [LICENSE_POLICY.md](LICENSE_POLICY.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
