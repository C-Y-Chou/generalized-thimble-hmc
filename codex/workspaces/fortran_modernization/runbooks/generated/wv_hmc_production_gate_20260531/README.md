# WV-HMC Production Gate 20260531

This runbook freezes the first production-readiness gate for the dense
explicit-J WV-HMC kernel before matrix-free/BiCGStab wiring.

## Scope

Model and parameters:

- model: Stephanov, `n=2`, `nf=1`, `m=0.2`, `mu=0.3`, `tau=0.1`
- exact references:
  - `chiral_condensate = 0.380047505938398`
  - `number_density = 0.0387173396674602`
- ODE backend: DOP853
- WV-HMC kernel: dense explicit-J
- initialization: repaired safe `t0p005` x-bank
- sampler interval: `T0=1e-4`, `T1=1e-3`
- measurement interval: `[T0,T1]`
- wall parameters: `d0=1e-4`, `d1=2.5e-4`, `c0=c1=1`
- HMC parameters: `epsilon=0.003`, `nstep=20`, `L=0.06`
- reverse gate: on

This gate does not validate the future matrix-free/BiCGStab trajectory path and
does not by itself define the high-dimensional `W(t)` tuning SOP.

## Deterministic Gates

Nonzero-`W` measurement/reweighting identity:

- request:
  `FMOD-WV-HMC-NONZERO-W-REWEIGHT-IDENTITY-GH3T3-RERUN2-20260531`
- job:
  `18309.anode01`
- result:
  PASS for `gamma = 0, 0.02, 0.2, 20`
- strongest direct WV identity error:
  `2.794e-20`

Nonzero-`W` transition gate:

- request:
  `FMOD-WV-HMC-NONZERO-W-TRANSITION-GATE-20260531`
- job:
  `18310.anode01`
- result:
  PASS for paper-wall `gamma=0.2` force finite difference, reverse gate, and
  Hamiltonian scaling.

These gates rule out the local bugs that were most likely after the earlier
`gamma=0.2` z-score failure: wrong `exp(W)` sign in measurement, wrong `W'`
force sign, and immediately non-reversible nonzero-`W` RATTLE motion.

## Production-Validation Runs

Two paired runs were submitted through the cluster02 scheduler gate:

| run | request | jobs | seeds x cycles | gamma | history |
|---|---|---:|---:|---:|---|
| `wv_hmc_prodgate_gamma0p2_history_n2_128x30000_20260531` | `FMOD-WV-HMC-PRODGATE-HISTORY-GAMMA0P2-128X30000-N2-20260531` | `18311-18318` | `128 x 30000` | `0.2` | observable + state, stride 10 |
| `wv_hmc_prodgate_gamma0_history_n2_128x30000_20260531` | `FMOD-WV-HMC-PRODGATE-HISTORY-GAMMA0-128X30000-N2-20260531` | `18319-18326` | `128 x 30000` | `0` | observable + state, stride 10 |

Primary artifacts:

- gamma `0.2` all-measurement readback:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_prodgate_gamma0p2_history_n2_128x30000_20260531/combined_128seed/readback`
- gamma `0.2` history readback:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_prodgate_gamma0p2_history_n2_128x30000_20260531/history_readback`
- gamma `0` all-measurement readback:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_prodgate_gamma0_history_n2_128x30000_20260531/combined_128seed/readback`
- gamma `0` history readback:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_prodgate_gamma0_history_n2_128x30000_20260531/history_readback`

## All-Measurement Exact-Reference Gate

The all-measurement readback uses all accepted measurement rows accumulated
inside each seed summary, with seed jackknife over 128 seed-level ratio sums.

| gamma | observable component | estimate | SE | z |
|---:|---|---:|---:|---:|
| `0.2` | `Re chiral_condensate` | `0.379072841` | `0.00639723` | `-0.152` |
| `0.2` | `Im chiral_condensate` | `0.00233683` | `0.00322934` | `0.724` |
| `0.2` | `Re number_density` | `0.0514664` | `0.00968024` | `1.317` |
| `0.2` | `Im number_density` | `-0.0120155` | `0.00998620` | `-1.203` |
| `0` | `Re chiral_condensate` | `0.376573610` | `0.00704711` | `-0.493` |
| `0` | `Im chiral_condensate` | `0.000889212` | `0.00302965` | `0.294` |
| `0` | `Re number_density` | `0.0482998` | `0.0102670` | `0.933` |
| `0` | `Im number_density` | `-0.00571640` | `0.00991771` | `-0.576` |

Result:

- gamma `0.2` passes the exact-reference production gate.
- gamma `0` control also passes.
- The earlier `gamma=0.2` two-sigma z-score did not reproduce at
  `128 x 30000` with the same kernel and history-enabled run.

## History-Aware Hidden-Risk Gate

The history readback uses the stride-10 observable history and preserves the
complex ratio estimator while jackknifing seed or cycle blocks.

Gamma `0.2`, all-cut selected results:

| error method | max exact-reference z over four components | note |
|---|---:|---|
| seed jackknife | `1.293` | passes |
| `500`-cycle block jackknife | `2.511` | too-small blocks underestimate SE |
| `1000`-cycle block jackknife | `1.990` | borderline but below 2 for max component |
| `2500`-cycle block jackknife | `1.577` | passes |
| `5000`-cycle block jackknife | `1.419` | passes |

Gamma `0`, all-cut selected results:

| error method | max exact-reference z over four components | note |
|---|---:|---|
| seed jackknife | `0.927` | passes |
| `500`-cycle block jackknife | `1.862` | passes |
| `1000`-cycle block jackknife | `1.464` | passes |
| `2500`-cycle block jackknife | `1.157` | passes |
| `5000`-cycle block jackknife | `1.014` | passes |

Result:

- The 500-cycle block estimate is not a safe production SE for gamma `0.2`;
  it is shorter than the observed autocorrelation scale and makes density look
  artificially significant.
- Seed jackknife and larger block sizes agree that the gamma `0.2` hidden-risk
  z signal is not present in this run.
- Production readbacks should report seed jackknife and at least one large
  block size, preferably `2500` and `5000` cycles for this setup.

## Stability Checks

Gamma `0.2` seed-jackknife cumulative and half-run checks:

| cut | max exact-reference z over four components |
|---|---:|
| prefix `10000` | `1.993` |
| prefix `15000` | `1.606` |
| prefix `20000` | `1.618` |
| prefix `30000` | `1.293` |
| first half | `1.768` |
| second half | `1.197` |

Gamma `0` seed-jackknife cumulative and half-run checks:

| cut | max exact-reference z over four components |
|---|---:|
| prefix `10000` | `0.839` |
| prefix `15000` | `0.997` |
| prefix `20000` | `0.693` |
| prefix `30000` | `0.927` |
| first half | `0.604` |
| second half | `0.745` |

Result:

- No monotone drift away from the exact value is visible.
- The gamma `0.2` density Re component is the slowest component, but it moves
  toward the exact reference as the prefix grows.

## Mixing And Runtime Diagnostics

| gamma | acceptance | phase coherence | failures | RG rejected | max seed runtime | seed-hours | state jump sq median | state span sq median |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `0.2` | `0.900683` | `0.870285` | `5418` | `168909` | `2442.87 s` | `78.43` | `0.05516` | `59.28` |
| `0` | `0.900734` | `0.867984` | `5323` | `167733` | `2405.15 s` | `78.33` | `0.05657` | `59.39` |

Flow-time coverage from state history:

- gamma `0.2`:
  - per-seed flow minima range: `0.000100001` to `0.000101924`
  - per-seed flow maxima range: `0.000997503` to `0.000999998`
  - per-seed flow means range: `0.000532059` to `0.000563475`
- gamma `0`:
  - per-seed flow minima range: `0.000100009` to `0.000103297`
  - per-seed flow maxima range: `0.000996640` to `0.000999996`
  - per-seed flow means range: `0.000524810` to `0.000569376`

Result:

- Gamma `0.2` does not show a runtime or movement penalty relative to gamma `0`
  in this small-`T1` production gate.
- Both runs cover the full flow-time interval.
- Acceptance is high but not frozen: state-history movement and span are
  comparable across gamma `0.2` and gamma `0`, and exact observables pass.

## Production Decision

For dense explicit-J WV-HMC on Stephanov `n=2`, the production gate passes.

Use this as the current production validation setup:

- DOP853 backend
- dense explicit-J WV-HMC
- repaired bank initialization
- `T0=1e-4`, `T1=1e-3`
- paper-wall `W(t)` with `gamma=0.2`, `c0=c1=1`
- `epsilon=0.003`, `nstep=20`
- reverse gate on
- production readback with all-measurement seed jackknife plus history
  seed/large-block jackknife

Do not promote the following yet:

- matrix-free/BiCGStab trajectory path
- high-dimensional production
- larger `T1`
- larger or adaptively tuned `W(t)` slopes

The earlier z-score warning was real enough to require this gate, but it is not
confirmed as a persistent bias after deterministic nonzero-`W` gates and the
paired `128 x 30000` history run.
