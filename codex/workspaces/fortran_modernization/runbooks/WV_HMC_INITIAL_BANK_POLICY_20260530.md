# WV-HMC Initial Bank Policy 2026-05-30

This records the initialization policy change after the dense WV-HMC `n=2`
observable pilots.

## Decision

Production-shaped WV-HMC pilots should not tune the initial ensemble by changing
the Gaussian width.  Gaussian starts remain acceptable only for tiny smoke tests
that exercise fail-closed behavior.

The default production-shaped initialization route is:

1. Build a `t=0` physical `x` checkpoint bank with the model parameters used by
   the target run.
2. Prevalidate bank records to the WV-HMC sampler start flow time, for example
   `T0=0.005`, using the dense flow-bank diagnostics.
3. Filter the `x_bank.dat` to records that are available at the target start
   flow time.
4. Run WV-HMC with `WV_HMC_INIT_MODE=bank` and
   `WV_HMC_INIT_BANK_FILE=<safe_x_bank.dat>`.

This keeps initialization tied to the physical `t=0` ensemble and separates
initial-state coverage from trajectory tuning.

## Rationale

The 2026-05-30 random-Gaussian WV-HMC runs showed seed-dependent failures before
cycle 1:

- `sigma=0.8`: 60/64 seeds completed; four seeds failed in the initial
  `flow_at(T0, x_initial)`.
- `sigma=0.5`: 55/64 seeds completed; nine seeds failed in the initial
  `flow_at(T0, x_initial)`.

Those failures are initial-state safety failures, not mid-chain transition
failures.  Retuning Gaussian width therefore does not address the right problem.

## Implemented Hooks

WV-HMC app initialization accepts:

- `WV_HMC_INIT_MODE=bank`
- `WV_HMC_INIT_BANK_FILE=<path>`
- `WV_HMC_INIT_BANK_RECORD=<record>` for a fixed record
- omitted or negative `WV_HMC_INIT_BANK_RECORD` for deterministic seed-based
  record selection from the bank

The bank file is a raw unformatted stream of `real(dp)` records with width
`config%state%physical_size`.

Cluster runner/PBS wrappers pass the corresponding `--init-bank-file` and
`--init-bank-record` options.

## Bank Preparation Tools

- `build_stephanov_t0_checkpoint_bank.py`
  builds a model-size-aware `t=0` checkpoint bank from Stage2 chains.
- `build_flow_bank_dense`
  prevalidates bank records to one or more target flow times and writes
  `diagnostics.csv`.
- `filter_x_bank_by_flow_diagnostics_20260530.py`
  copies only prevalidated source records into a safe WV-HMC initial bank.

## Validation Policy

For formal WV-HMC observable validation, do not count a Gaussian-initialized
run as the production-shaped gate.  The gate must use a prevalidated bank and
must report:

- selected bank path and record policy;
- state size and record count;
- prevalidation target flow time;
- initial-flow failure count;
- observable z-scores against the `n=2` exact references.
