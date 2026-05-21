# Stephanov Working-n Decision - 2026-05-22

## Decision

Use `n=4` as the primary working dimension for the next TLTM/GTM development
cycle.

Use `n=6` as the first stress dimension after the `n=4` workflow is stable.

Do not use `n=8` or higher as the immediate working dimension.  At
`m=0.004, mu=0.6, tau=0, t=0`, direct phase reweighting already estimates a
phase effective fraction below `1e-4` by `n=8`, which is too expensive for
the current local/cluster-maintenance phase and would mostly measure resource
limits before the algorithmic workflow is settled.

## Fixed Scan Conditions

```text
N_f = 1
m   = 0.004
mu  = 0.6
tau = 0
t   = 0
method = nofb
```

The goal is to choose a development dimension, not to make final production
physics claims.

## Direct t=0 Phase Scan

Independent Gaussian reweighting readback:

| n | samples | phase coherence | phase eff frac | nominal samples for 1% phase-effective target |
|---:|---:|---:|---:|---:|
| `2` | `300000` | `0.39344627` | `0.15479997` | `6.46e4` |
| `4` | `300000` | `0.12013882` | `0.01443334` | `6.93e5` |
| `6` | `250000` | `0.03361424` | `0.00112992` | `8.85e6` |
| `8` | `200000` | `0.00814738` | `6.637985e-5` | `1.51e8` |
| `10` | `150000` | `0.00355053` | `1.260626e-5` | `7.93e8` |

Interpretation:

- `n=2` is too mild for the intended sign-problem work.
- `n=4` is the first nontrivial sign-problem point while still tractable.
- `n=6` is already a serious stress point.
- `n>=8` is beyond the immediate working range for nofb `t=0` development.

## Canonical Stage2 nofb Readback

### n=4

Previous Stage2 confirmation:

```text
root=/tmp/tltm_stephanov_t0_n_scan_20260522/stage2_nofb_mu06/n04
chains=4
cycles_per_chain=20000
samples_written=80004
used_after_burn=76000
phase_coherence=0.11850805
phase_eff_frac=0.01404416
proposal_failure=0
accept_rate=0.72715
```

Observable readback:

| observable | estimate | error Re | relative Re error |
|---|---:|---:|---:|
| `chiral_condensate` | `0.017808141 - 0.000079110 i` | not persisted in this packet | n/a |
| `number_density` | `0.36890828 + 0.00864963 i` | not persisted in this packet | n/a |

This point is useful because phase reweighting is visibly degraded while
canonical nofb still runs cleanly with no proposal-construction failures.

### n=6

Short Stage2 confirmation:

```text
root=/tmp/tltm_stephanov_choose_working_n_20260522/stage2_nofb_mu06_n6
chains=4
cycles_per_chain=10000
samples_written=40004
used_after_burn=36000
phase_coherence=0.03587102
phase_eff_frac=0.00128673
proposal_failure=0
accept_rate=0.438125
walltime_local=250.3 s
```

Observable readback:

| observable | estimate | error Re | error Im | relative Re error |
|---|---:|---:|---:|---:|
| `chiral_condensate` | `0.02396508 + 0.00268265 i` | `0.00444851` | `0.00562523` | `18.6%` |
| `number_density` | `0.62398207 - 0.00390076 i` | `0.13038817` | `0.14015350` | `20.9%` |

This is the first dimension where the observable error bars are already large
in a short canonical nofb run.  It is therefore a good stress target, but too
costly and noisy as the first working dimension.

## Working Plan

1. Stabilize all nonzero-flow, observable-stream, and validation workflows at
   `n=4, m=0.004, mu=0.6, tau=0`.
2. Use `n=4` to tune flow-time ladders and distinguish phase improvement from
   solver/mobility failures.
3. Promote to `n=6` only after the `n=4` run protocol has a clear pass/fail
   table and known local/PBS runtime.
4. Treat `n>=8` as later production/stress scope, not the immediate
   development target.
