# WV-HMC n=6 Gamma55 Bank Refresh 2026-06-01

Purpose: replace the old warm state bank with a target-matched WV-HMC
equilibrium bank for the fixed target:

```text
model = Stephanov n=6, mu=0.6, tau=0
[T0,T1] = [0.0001, 0.03]
W(t) = paper_wall, gamma = 55
epsilon = 0.010
nstep = 8
constraint_tol = 1e-10
constraint_max_iter = 192
ODE backend = dop853
```

## Cut Decision From Canceled 15k Validation Prefix

The canceled long validation wrote observable histories but not state histories.
Those histories cannot be converted into a bank, but they are sufficient to
choose the burn-in cut for the next state-history bank-builder run.

Key seed-jackknife results from the partial 552-seed run:

| cut | samples | chiral z | density z | high-flow chiral z |
|---:|---:|---:|---:|---:|
| 3001+ | 2662646 | -0.777 | -1.000 | -2.865 |
| 4001+ | 2189825 | -0.015 | -1.013 | -2.228 |
| 5001+ | 1716082 | -0.151 | -1.008 | -1.894 |
| 6001+ | 1242159 | 0.114 | -1.177 | -1.246 |
| 7001+ | 768793 | -0.065 | -0.671 | -0.943 |
| 8001+ | 468327 | -0.006 | -0.401 | -0.797 |

Window checks show that all-flow estimates are already compatible after about
4000 cycles, but the high-flow bin remains the sensitive diagnostic.  The
practical bank-builder policy is therefore:

```text
minimum discard for old warm bank refresh = 6000 cycles
preferred retained state-history window = cycles 6001-8000
optional conservative subset = cycles 7001-8000
```

The unweighted flow-time histogram is stable under these cuts.  Five equal-bin
fractions remain near:

```text
0.216, 0.190, 0.187, 0.195, 0.212
```

The max/min bin ratio is about `1.16`, acceptable for the current bank-refresh
purpose.

## Bank Refresh Shape

Run `512` seeds for `8000` cycles from the old warm state bank, with:

```text
measurement_start_cycle = 1
state_history = on
observable_history = on
history_stride = 20
final_state = on
```

After completion, build the new state bank from `state_history` with:

```text
min_cycle = 6001
flow_bins = 10
flow-stratified sampling
```

Expected candidate state records from `6001-8000`:

```text
512 seeds * 2000 cycles / stride 20 = about 51200 records
```

This is enough to build a flat flow-bin restart bank without relying on final
states alone.

## Validation After Bank Build

Use the new bank for a short validation, not another 15k run:

```text
512 seeds x 3000-4000 cycles
measurement_start_cycle = 501
state_history = off
observable_history = on
```

Pass condition:

- early windows are compatible with late windows;
- all-flow chiral and density z are within the expected statistical range;
- high-flow bin no longer shows the old early negative chiral drift;
- unweighted flow-time histogram remains flat enough.

If the new-bank short validation still needs a multi-thousand-cycle burn-in,
the problem is no longer only the old warm bank; retune kernel or inspect WV-HMC
transition correctness again.
