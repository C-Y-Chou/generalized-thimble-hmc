# Configuration

## Parameter Files

The Fortran runtime reads key-value parameter files. The active file can be set
with:

```bash
TLTM_PARAMETERS_FILE=data/parameters_stephanov_n6_mu06_t0.dat
```

The product wrapper passes this variable automatically when `--parameters` is
provided.

Important fields:

- `physical_state_size`: number of real physical coordinates.
- `x_size`: compatibility packed size, equal to `physical_state_size + 1`.
- `trajectory_length`: TLTM trajectory length.
- `integration_steps`: TLTM integration step count.
- `initial_flow_time`: TLTM flow-time label for fixed-flow runs.
- `constraint_tol`: projection tolerance.
- `stephanov_n`, `stephanov_mass`, `stephanov_mu`, `stephanov_tau`: Stephanov
  model parameters.
- `derivative_mode`: must be `manual`.

## WV-HMC Wrapper Options

Common options:

- `--cycles`
- `--seed`
- `--step-size`
- `--num-steps`
- `--t0`, `--t1`
- `--d0`, `--d1`
- `--w-profile`
- `--w-gamma`
- `--boundary-policy`
- `--init-mode`
- `--init-bank-file`
- `--measurement-start-cycle`
- `--history`
- `--snapshot-interval`

Use:

```bash
python3 scripts/run_tltm_product.py wv-hmc --help
```

`--boundary-policy` defaults to `normal_reflect`.  Use `full_bounce` or
`paper_full_flip` only when running the optional bounce-policy benchmark.

## Flow Backend

The default flow backend is DOP853. The public wrapper pins this default for
WV-HMC runs.

## Output Location

Wrapper outputs default to `output/product/`. Use `--output-dir` to select a
different directory.
