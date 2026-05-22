# Stephanov n=6 t=0 Checkpoint Bank - 2026-05-22

## Scope

This records the first local development checkpoint bank for the selected
Stephanov working point:

```text
n = 6
N_f = 1
m = 0.004
mu = 0.6
tau = 0
flow_time = 0
```

The bank is meant to replace high-dimensional Gaussian preflow initialization
for low-flow protocol tests.  It is a local development bank, not a production
coverage claim.

## Source Support

Stage2 now supports optional physical-state checkpoint output:

```text
TLTM_STAGE2_COLD_X_HISTORY_FILE=/path/to/x_history.dat
```

Each record is the physical `slot%x` vector only:

```text
real(dp) x(physical_state_size)
```

For the current `n=6` Stephanov model, `physical_state_size=72`, so each record
is `72 * 8 = 576` bytes.  The flow-time label is not packed into this stream;
it remains fixed slot metadata.

The reproducible local builder is:

```text
codex/workspaces/fortran_modernization/tasks/scripts/build_stephanov_t0_checkpoint_bank.py
```

## Build Command

The current local development bank was built with:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/build_stephanov_t0_checkpoint_bank.py \
  --skip-build \
  --chains 4 \
  --cycles 1000 \
  --history-stride 10 \
  --burn-records 20 \
  --run-name stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522 \
  --force
```

Output root:

```text
output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/
```

Key files:

```text
bank/x_bank.dat
bank/x_bank_index.csv
bank/bank_summary.csv
bank/coverage_summary.json
chains/chain_XX/{x,z,phi,observable}_history.dat
chains/chain_XX/summary.dat
```

## Bank Shape

Run shape:

| field | value |
|---|---:|
| chains | `4` |
| seeds | `8606000..8606003` |
| cycles per chain | `1000` |
| history stride | `10` |
| raw records per chain | `101` |
| burn records removed | `20` |
| used records per chain | `81` |
| total checkpoints | `324` |

Size checks:

| file | observed bytes | expected bytes | status |
|---|---:|---:|---|
| `bank/x_bank.dat` | `186624` | `324 * 72 * 8 = 186624` | pass |
| `chains/chain_00/x_history.dat` | `58176` | `101 * 72 * 8 = 58176` | pass |
| `chains/chain_00/observable_history.dat` | `9696` | `101 * 6 * 16 = 9696` | pass |

## Chain Summary

| chain | seed | accept | proposal failures | runtime sec | phase coherence | mean `||x||^2` |
|---:|---:|---:|---:|---:|---:|---:|
| `0` | `8606000` | `0.444` | `0` | `21.987` | `0.0597` | `6.6728` |
| `1` | `8606001` | `0.452` | `0` | `22.026` | `0.0145` | `6.7349` |
| `2` | `8606002` | `0.423` | `0` | `22.058` | `0.1118` | `6.7714` |
| `3` | `8606003` | `0.436` | `0` | `21.976` | `0.1177` | `6.9599` |

Pooled phase coherence from the selected bank records:

```text
0.061606335374384334
```

## Coverage Diagnostics

Current split-chain Rhat checks from `coverage_summary.json`:

| scalar | Rhat |
|---|---:|
| `x_norm2` | `1.000003277748154` |
| `chiral_re` | `1.0006462219315235` |
| `chiral_im` | `1.0034741936326004` |
| `density_re` | `1.0029867303813065` |
| `density_im` | `1.0139780520303179` |
| `logdet_re` | `1.003154935242851` |
| `logdet_im` | `1.007800641252488` |
| `min_singular_re` | `0.9963048161493702` |

The largest reported 5%-tail occupancy deviation among these tracked scalars is
`0.05` for `density_im`; the other tracked deviations are below `0.049`.

## Interpretation

This bank is sufficient for the next local development step: remove Gaussian
starts from `t=1e-6` protocol scans by starting from fixed, thermalized `t=0`
physical states, then applying adaptive preflow with staged flow and
zero-momentum relaxation to reach the nonzero target flow time.

It is not sufficient for a final physics coverage claim.  Before using it for a
claim about sign-problem improvement or absence of initialization bias, rerun
with disjoint checkpoint subsets and verify that phase coherence, primary
observables, proposal failures, and error bars are stable under bank expansion.

## Next Step

Use the restart/read path for `x_bank.dat` or per-chain `x_history.dat`, then
run `n=6, t=1e-6, nofb` confirmation from disjoint checkpoint subsets using the
selected bank-adaptive HMC protocol:

```text
epsilon = 0.10
nstep   = 6
L       = 0.60
initialization preflow L/nstep = 0.16/2
```
