# Generalized Thimble HMC

Fortran tools for Monte Carlo simulations on deformed integration surfaces for
systems with a numerical sign problem.  The terminology follows the Fukuma
program around the tempered Lefschetz thimble method (TLTM), generalized
thimble HMC (GT-HMC), and worldvolume HMC (WV-HMC).

Author: CHOU CHIEN YU

## Physics Scope

The central object is a complexified path integral whose original real
integration surface is continuously deformed by the antiholomorphic gradient
flow.  TLTM uses the flow time as a tempering parameter between flowed surfaces
to control both residual phase fluctuations and multimodal barriers.  WV-HMC
instead samples the worldvolume swept out by those flowed surfaces.

This repository is intended to make that workflow model-general: a physics
provider supplies the action, derivatives, and observables; the sampler code
handles constrained HMC transitions, flow-time bookkeeping, ratio estimators,
histories, and restart metadata.

## What Is Included

- TLTM: the current canonical tempered Lefschetz thimble workflow.
- GT-HMC/WV-HMC kernels: dense explicit-J generalized-thimble and worldvolume
  HMC components, with WV-HMC validation on the Stephanov `n=6` benchmark after
  burn-in.  Dense WV-HMC defaults to normal-reflection boundary handling; full
  bounce is retained as an optional benchmark policy.
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
  --boundary-policy normal_reflect \
  --output-dir output/product/wv_hmc_example \
  --history \
  --snapshot-interval 250
```

Run canonical TLTM through a run-protocol file:

```bash
python3 scripts/run_tltm_product.py tltm \
  --config path/to/tltm_protocol.json \
  --jobs 8 \
  --output-dir output/product/tltm_example
```

Local runs are intended for build checks, smoke tests, and small development
examples.  Larger studies should record the source commit, parameter files,
run options, and output directory so the analysis can be reproduced.

## Documentation

- [Install](docs/INSTALL.md)
- [User Guide](docs/USER_GUIDE.md)
- [Model Provider](docs/MODEL_PROVIDER.md)
- [Model Specification Template](model_specs/TEMPLATE.md)
- [Samplers](docs/SAMPLERS.md)
- [Validation](docs/VALIDATION.md)
- [WV-HMC Validation Packet 2026-06-16](docs/WV_HMC_VALIDATION_PACKET_20260616.md)
- [Configuration](docs/CONFIGURATION.md)
- [Flow Backend](docs/FLOW_BACKEND.md)
- [Outputs and Restart](docs/OUTPUTS_AND_RESTART.md)
- [Development](docs/DEVELOPMENT.md)
- [References](docs/REFERENCES.md)
- [Reproducibility Records](docs/REPRODUCIBILITY_RECORDS.md)
- [Changelog](CHANGELOG.md)

For the physics background and citation guidance, start from
[References](docs/REFERENCES.md).

## Citation

Repository citation metadata is provided in [CITATION.cff](CITATION.cff).  A
scientific paper should also cite the relevant TLTM, GT-HMC, or WV-HMC algorithm
references listed in [References](docs/REFERENCES.md).

## License

This repository is distributed under GPL-3.0-or-later. See
[LICENSE](LICENSE), [LICENSE_POLICY.md](LICENSE_POLICY.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
