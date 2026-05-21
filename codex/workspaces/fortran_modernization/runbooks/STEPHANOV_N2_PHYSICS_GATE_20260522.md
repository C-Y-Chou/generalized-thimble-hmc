# Stephanov n=2 Physics Gate - 2026-05-22

## Scope

This is a local-only validation gate run while the cluster was unavailable.
It is not production evidence.  The purpose is to check that the canonical
Stephanov provider and observable stream reproduce n=2 physics at flow time
zero, and that an infinitesimal-flow nofb run has no gross model/observable
mismatch.

All TLTM runs below used:

- `TLTM_PARAMETERS_FILE=data/parameters.dat`
- `stephanov_n=2`, `stephanov_nf=1`, `m=0.2`, `mu=0.3`, `tau=0.1`
- `derivative_mode=manual`
- `enable_quasi_fallback=false`
- `TLTM_STAGE2_NUM_REPLICAS=1`
- `TLTM_STAGE2_SWAP_ENABLED=0`
- `TLTM_STAGE2_LOCAL_UPDATES=1`
- `TLTM_STAGE2_INIT_SIGMA=0.8`
- no withfb/fallback comparison

The run outputs were written under:

```text
/tmp/tltm_stephanov_n2_physics_gate_20260522/
```

## Independent Reference

At flow time zero, the physical ratio is

```text
<O> = int O(Z) det(D[Z]) exp(-n ||Z||^2) dZ
      / int det(D[Z]) exp(-n ||Z||^2) dZ
```

For n=2 and `N_f=1`, `det(D)=det(B A + m^2 I)`.  The primary observables
`chiral_condensate` and `number_density` multiplied by `det(D)` are low-degree
polynomials, so Gauss-Hermite quadrature is an independent exact-reference
check for those observables.  The phase-coherence reference is numerical
because it contains `abs(det(D))`.

Reference values:

| reference | chiral_condensate | number_density | phase coherence |
|---|---:|---:|---:|
| GH k=3 | `0.380047505938226` | `0.0387173396674579` | `0.862837350234350` |
| GH k=5 | `0.380047505938398` | `0.0387173396674602` | `0.863821090007014` |

The k=3 and k=5 agreement for the two primary observables is the exactness
check.  The k=5 phase value is used only as a sanity scale.

## Flow Time 0 Result

Run shape:

```text
root=/tmp/tltm_stephanov_n2_physics_gate_20260522/flow0_nofb_8x100k
flow_time=0
chains=8
cycles_per_chain=100000
samples_written=800008
burn_per_chain=1000
analysis_batches=400
batch_size=1980
```

Counters:

| accepted | metropolis_reject | proposal_failure |
|---:|---:|---:|
| `770921` | `29079` | `0` |

Batch-jackknife readback:

| quantity | estimate | err Re | err Im | comparison |
|---|---:|---:|---:|---|
| `chiral_condensate` | `0.379306596130751 + 0.000042946070802 i` | `9.933e-4` | `2.789e-4` | Re `-0.75 sigma`, Im `+0.15 sigma` vs GH k=5 |
| `number_density` | `0.039038721624842 + 0.000251305043447 i` | `9.689e-4` | `7.428e-4` | Re `+0.33 sigma`, Im `+0.34 sigma` vs GH k=5 |
| phase coherence | `0.864560515543992` | `3.664e-4` | n/a | `+2.02 sigma` vs GH k=5 numerical phase scale |

Conclusion: flow time 0 passes the n=2 physics gate.  The two primary
observables agree with the independent Gauss-Hermite reference within one
jackknife sigma, imaginary parts are consistent with zero, and there were no
proposal-construction failures.

## Infinitesimal-Flow Sanity

The first low-flow probes showed that nofb failures grow quickly with flow
time under the current local settings:

| flow time | run shape | proposal failures | note |
|---:|---:|---:|---|
| `0.01` | `1 x 1000` | `96` | too many failures for a clean model gate |
| `0.001` | `1 x 1000` | `25` | still solver-contaminated |
| `0.0001` | `8 x 10000` | `230` | no gross mismatch, but not a signoff gate |

The cleanest low-flow probe was therefore lowered to `t=1e-5`.

Run shape:

```text
root=/tmp/tltm_stephanov_n2_physics_gate_20260522/flow000001_nofb_8x50k
flow_time=0.00001
chains=8
cycles_per_chain=50000
samples_written=400008
burn_per_chain=1000
analysis_batches=400
batch_size=980
```

Counters:

| accepted | metropolis_reject | proposal_failure |
|---:|---:|---:|
| `385306` | `14561` | `133` |

Batch-jackknife readback:

| quantity | estimate | err Re | err Im | comparison |
|---|---:|---:|---:|---|
| `chiral_condensate` | `0.377524846349544 - 0.000157225382778 i` | `1.379e-3` | `3.947e-4` | Re `-1.83 sigma`, Im `-0.40 sigma` vs GH k=5 |
| `number_density` | `0.041582335665903 + 0.000641728970950 i` | `1.331e-3` | `1.086e-3` | Re `+2.15 sigma`, Im `+0.59 sigma` vs GH k=5 |
| phase coherence | `0.865460087374458` | `5.280e-4` | n/a | `+3.10 sigma` vs GH k=5 numerical phase scale |

The same low-flow estimates are consistent with the flow-zero TLTM estimates
within combined Monte Carlo errors:

| quantity | low-flow minus flow-zero TLTM | combined Re sigma |
|---|---:|---:|
| `chiral_condensate` | `-0.001782` | `1.05` |
| `number_density` | `+0.002544` | `1.54` |
| phase coherence | `+0.000900` | `1.38` |

Conclusion: `t=1e-5` is a useful nofb smoke/sanity gate and shows no gross
model or observable-stream mismatch.  It is not as clean as the flow-zero
physics signoff because it still has a small nonzero proposal-failure count
and slightly larger apparent tension against the exact reference.  The model
correctness conclusion should therefore rest on the flow-zero exact-reference
gate; low-flow evidence only checks that the flowed/Jacobian/observable stream
is plausibly connected.

## Current Conclusion

No Stephanov model-formula or observable-registration error was found at n=2.

The primary conclusion is:

```text
n=2, flow_time=0, nofb: PASS against independent exact reference.
```

The secondary conclusion is:

```text
n=2, flow_time=1e-5, nofb: PASS as a low-flow sanity check, not a production
or exact-reference signoff.
```

For the next validation layer, use flow time zero as the model-physics
reference gate for n=4 if an exact or high-precision independent reference can
be built.  Treat larger low-flow nofb deviations first as solver/mobility
questions, not as model-formula failures, unless the flow-zero reference gate
also fails.
