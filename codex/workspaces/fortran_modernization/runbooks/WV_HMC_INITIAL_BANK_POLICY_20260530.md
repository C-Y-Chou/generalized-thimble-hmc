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

## Cluster Validation

The bank route was validated on cluster02 after the Python 3.6 compatibility
fix in commit `066e2d9`.

- Initial-bank build job `17926.anode01` completed on C8 in 48 s wall time.
  It built a Stephanov `n=2`, `t=0` physical bank with `state_size=8`,
  prevalidated the first 1024 records to `T0=0.005`, and selected 1000 safe
  records.
- Bank-init smoke job `17927.anode01` completed on C8 in 33 s wall time.
  The WV math and constraint kernel checks passed, `run_wv_hmc` compiled, and
  8 bank-initialized candidates ran for 10 cycles without bank read or
  initial-flow aborts.
- Bank-init observable validation job `17928.anode01` completed on C16 in
  15m52s wall time.  It produced 64/64 summaries and 64/64 observable files
  with `manifest bad=0`.

The safe bank used by the observable validation is:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260530/stephanov_n2_wv_hmc_t0_initial_bank_8x2000_t0005_20260530_repair1_17926.anode01/safe_bank_t0p005/x_bank.dat
```

The formal validation output is:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260529/wv_hmc_dense_observable_validation_n2_64x4000_eps020_bankinit_20260530_17928.anode01
```

Key readback numbers from `17928.anode01`:

| seeds | cycles | measurements | phase coherence | accepted fraction | flow-time mean | flow-time max |
|---:|---:|---:|---:|---:|---:|---:|
| 64 | 256000 | 191999 | 0.929079 | 0.7264 | 0.09598 | 0.2000 |

| observable | z Re | z Im |
|---|---:|---:|
| chiral_condensate | -2.28 | 1.58 |
| number_density | 0.562 | -1.14 |

This validates the bank-initialization mechanism and removes the Gaussian
initial-flow failure mode.  It does not by itself freeze the final WV-HMC HMC
parameters; subsequent tuning should use bank initialization and judge
movement, observable stability, and acceptance diagnostics under that policy.

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
