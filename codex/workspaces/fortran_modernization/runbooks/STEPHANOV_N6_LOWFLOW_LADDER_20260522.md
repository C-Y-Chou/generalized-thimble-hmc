# Stephanov n=6 Low-Flow Ladder - 2026-05-22

## Scope

This is a local-only nofb exploratory ladder while the cluster is under
maintenance.  It is not production evidence.  The purpose is to test whether
very small nonzero flow time is immediately useful at the selected Stephanov
working point:

```text
n = 6
N_f = 1
m = 0.004
mu = 0.6
tau = 0
derivative_mode = manual
enable_quasi_fallback = false
```

The baseline runtime preset is:

```text
data/parameters_stephanov_n6_mu06_t0.dat
```

Artifacts:

```text
/tmp/tltm_stephanov_n6_lowflow_ladder_20260522/
/tmp/tltm_stephanov_n6_lowflow_ladder_20260522/summary_analysis.csv
```

The flow-zero comparison row reuses the earlier longer local run:

```text
/tmp/tltm_stephanov_choose_working_n_20260522/stage2_nofb_mu06_n6
```

## Run Shape

The three new nonzero-flow probes used:

```text
method=nofb
TLTM_STAGE2_NUM_REPLICAS=1
TLTM_STAGE2_SWAP_ENABLED=0
TLTM_STAGE2_LOCAL_UPDATES=1
TLTM_STAGE2_INIT_SIGMA=0.8
chains=4
cycles_per_chain=1000
burn_per_chain=100
used_after_burn=3604
```

The earlier `t=0` comparison used:

```text
chains=4
cycles_per_chain=10000
burn_per_chain=1000
used_after_burn=36004
```

## Readback

Errors below are chain-jackknife errors over four chains and are noisy for the
short nonzero-flow rows.

| flow time | used samples | phase coherence | phase JK err | phase eff frac | proposal failures | proposal failure rate | accept rate | max runtime / chain |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `0` | `36004` | `0.03586298` | `0.00729468` | `0.00128615` | `0` | `0` | `0.438125` | `246.2 s` |
| `1e-7` | `3604` | `0.03048586` | `0.01309967` | `0.00092939` | `0` | `0` | `0.442000` | `132.8 s` |
| `1e-6` | `3604` | `0.05678707` | `0.03950545` | `0.00322477` | `9` | `0.00225` | `0.438250` | `156.8 s` |
| `1e-5` | `3604` | `0.03313373` | `0.02574926` | `0.00109784` | `38` | `0.00950` | `0.434750` | `224.5 s` |

Primary observable readback:

| flow time | `chiral_condensate` | error Re | error Im | `number_density` | error Re | error Im |
|---:|---:|---:|---:|---:|---:|---:|
| `0` | `0.02396421 + 0.00266300 i` | `0.004564` | `0.004848` | `0.62413997 - 0.00355258 i` | `0.1701` | `0.1716` |
| `1e-7` | `0.02481148 + 0.02266139 i` | `0.01392` | `0.01743` | `0.64276322 - 0.87240848 i` | `0.5214` | `0.8966` |
| `1e-6` | `0.01743096 - 0.00324638 i` | `0.02673` | `0.01904` | `0.53814585 - 0.09645736 i` | `1.048` | `0.8114` |
| `1e-5` | `0.01994750 + 0.00915763 i` | `0.02046` | `0.03286` | `0.67270972 - 0.48000880 i` | `0.5500` | `1.481` |

## Preliminary Conclusion

The sign problem remains severe throughout this very-low-flow ladder.  The
phase effective fraction stays at `O(1e-3)`.

`t=1e-6` is the only row with an apparent phase-coherence increase, but the
chain-jackknife phase error is large (`0.0395`), so this is not yet a
statistically supported improvement.  Treat it as a candidate for the next
longer local/PBS confirmation, not as a conclusion.

`t=1e-5` is not a good immediate target for longer nofb runs: it gives no clear
phase improvement over `t=0`, has nonzero proposal-construction failures
(`0.95%`), and is about `9x` slower per `1000` cycles than the `t=0` local
baseline.

The next focused step should be a longer `t=1e-6` nofb confirmation at `n=6`
before testing higher flow times.  If `t=1e-6` does not show a statistically
meaningful phase or observable-error improvement, the nofb flow ladder should
not be pushed upward without changing the run protocol or using feedback.
