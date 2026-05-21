# Stephanov t=0 n-Scan Sign-Problem Gate - 2026-05-22

## Scope

This is a local-only exploratory gate run while the cluster was unavailable.
It is not production evidence.  The purpose is to fix flow time at `t=0`,
increase Stephanov matrix size `n`, and stop once the model sign problem is
severe.

The benchmark parameters are from `model_specs/high_dimensional/`:

```text
N_f = 1
m   = 0.004
tau = 0
mu  = 0.6  # main sign-problem diagnostic point
```

Severe sign-problem criterion for this gate:

```text
phase_coherence = |sum phi| / sum |phi| < 0.2
phase_eff_frac  = phase_coherence^2 < 0.04
```

At `t=0`, the Jacobian is identity and `phi = det(D) / |det(D)|`, so this
scan separates the model sign problem from flow/Jacobian solver effects.

## Direct t=0 Phase Scan

The first pass used independent Gaussian reweighting:

```text
Zx_ij, Zy_ij ~ exp(-n x^2)
phase_coherence = |E[det(D)]| / E[|det(D)|]
```

Direct scan readback:

| mu | n | samples | phase coherence | phase eff frac | status |
|---:|---:|---:|---:|---:|---|
| `0.4` | `2` | `200000` | `0.67196803` | `0.45154103` | not severe |
| `0.4` | `4` | `150000` | `0.40460721` | `0.16370699` | not severe |
| `0.4` | `6` | `100000` | `0.24243910` | `0.05877672` | near severe |
| `0.4` | `8` | `80000` | `0.13165995` | `0.01733434` | severe |
| `0.6` | `2` | `200000` | `0.39489563` | `0.15594256` | not severe |
| `0.6` | `4` | `150000` | `0.11659627` | `0.01359469` | severe |
| `0.8` | `2` | `200000` | `0.27310422` | `0.07458591` | near severe |
| `0.8` | `4` | `150000` | `0.11973459` | `0.01433637` | severe |

Conclusion from the direct scan: at the main benchmark diagnostic point
`mu=0.6`, increasing `n` from `2` to `4` is enough to enter severe sign-problem
territory at `t=0`.

## Canonical Stage2 nofb Confirmation

The direct scan was followed by canonical `bin/run_tltm_stage2` nofb readback
at `mu=0.6`.

Shared run shape:

```text
root=/tmp/tltm_stephanov_t0_n_scan_20260522/stage2_nofb_mu06
flow_time=0
TLTM_STAGE2_NUM_REPLICAS=1
TLTM_STAGE2_SWAP_ENABLED=0
TLTM_STAGE2_LOCAL_UPDATES=1
chains=4
cycles_per_chain=20000
burn_per_chain=1000
```

Readback:

| n | samples written | used after burn | phase coherence | phase eff frac | direct phase | accepted | metropolis reject | proposal failure | accept rate |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `2` | `80004` | `76000` | `0.39518294` | `0.15616955` | `0.39489563` | `75452` | `4548` | `0` | `0.94315` |
| `4` | `80004` | `76000` | `0.11850805` | `0.01404416` | `0.11659627` | `58172` | `21828` | `0` | `0.72715` |

Primary observable readback from the same Stage2 observable streams:

| n | chiral_condensate | number_density |
|---:|---:|---:|
| `2` | `0.0094567425 - 0.0000486991 i` | `0.29759133 + 0.00306026 i` |
| `4` | `0.017808141 - 0.0000791098 i` | `0.36890828 + 0.00864963 i` |

The Stage2 nofb phase coherence agrees with the independent direct scan:

```text
n=2: 0.39518 vs 0.39490
n=4: 0.11851 vs 0.11660
```

There were no proposal-construction failures in either Stage2 run, and
`t=0` has no flowed Jacobian.  Therefore the observed collapse of phase
coherence at `n=4` is a model sign problem, not a nofb solver failure.

## Derivative/Hessian Gate At n=4

After the n-scan, `tests/test_action_derivatives.f90` was extended to include
the benchmark severe-onset point:

```text
n=4, m=0.004, mu=0.6, tau=0
```

The test uses random genuinely complexified `Zx,Zy` and validates manual
derivatives with five-point finite differences.  Local readback:

| case | ds vs FD | HVP vs FD gradient | hessian*v vs HVP |
|---|---:|---:|---:|
| `n=2, m=0.2, mu=0.3, tau=0.1` | `1.0104e-10` | `7.3519e-11` | `6.4172e-15` |
| `n=4, m=0.004, mu=0.6, tau=0` | `1.6182e-10` | `3.1479e-10` | `1.2535e-14` |

This validates the action gradient and Hessian-vector product at the severe
n-scan baseline.  The explicit dense `hessian` wrapper is checked by comparing
`matmul(hessian, v)` against the hand-written HVP.

## Conclusion

For the benchmark Stephanov parameters:

```text
m=0.004, mu=0.6, tau=0, N_f=1, flow_time=0
```

the first severe sign-problem point along the even-`n` ladder is:

```text
n=4
phase_coherence ~= 0.1185
phase_eff_frac  ~= 0.0140
```

This means only about `1.4%` of nominal samples remain effective for phase
reweighting at `n=4`, before adding any flow/Jacobian complications.

Next validation should use `n=4, mu=0.6, t=0` as the first severe baseline
before testing whether nonzero flow improves phase coherence or creates
solver/mobility problems.
