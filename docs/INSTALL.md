# Install

## Requirements

- GNU make.
- A Fortran compiler: `gfortran`, Intel `ifx`, or an MPI Fortran wrapper.
- A C compiler: `clang`, `gcc`, `icx`, or `cc`.
- Python 3.8 or newer for wrapper and validation scripts.
- Optional BLAS/LAPACK linkage. The repository also has a bundled linear
  algebra path for the public validation targets.

On macOS, Accelerate can be used through:

```bash
make USE_EXTERNAL_LINALG=1
```

On Linux with OpenBLAS:

```bash
make USE_EXTERNAL_LINALG=1 EXTERNAL_LINALG_LIBS='-lopenblas'
```

## Build

From the repository root:

```bash
make build
```

Equivalent direct build command:

```bash
python3 scripts/run_tltm_product.py build
```

To override compilers:

```bash
make build FC=gfortran CC=gcc PYTHON=python3
```

Executables are written to `bin/`.

## Validate

Run the public validation set:

```bash
make test
```

This builds and runs the WV-HMC math-kernel test, WV-HMC constraint-kernel test,
and model derivative test.

## Smoke Run

```bash
make wv-hmc-smoke
```

The smoke writes under `output/product/wv_hmc_smoke/`. It is a short
wrapper/output check, not a physics validation run.
