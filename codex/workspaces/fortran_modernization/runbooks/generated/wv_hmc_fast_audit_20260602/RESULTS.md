# WV-HMC Fast Detection Results 2026-06-02

Purpose: localize WV-HMC observable bias risk with fast kernel gates before
running more long-chain tuning.

Plan: `FAST_DETECTION_PLAN.md`

## Execution Summary

All execution was cluster-only through the cluster02 scheduler gate.  No local
Fortran simulation was used.

| stage | job | result | conclusion |
|---|---:|---|---|
| Pre-fix kernel audit | `18694.anode01` | one failure | The only failed gate was simplified-paper boundary full flip. |
| Paper full-flip fix | local patch, synced to cluster | applied | Boundary exits now restore current state and apply `pi -> -pi`. |
| Post-fix kernel audit | `18695.anode01` | pass | Math kernels and constraint kernels passed. |
| n=2 observable sanity | `18696.anode01` | 31/32 usable seeds | Exact-reference z scores for chiral/density Re/Im were all below 1 sigma. |

## Pre-Fix Localization

Before the boundary patch, the deterministic audit passed the force,
projection, Newton/RATTLE, fixed-length energy-order, and forward/reverse
energy-antisymmetry gates.  The only failing gate was the simplified-paper
boundary policy.

Key lines:

```text
wv_dense_trajectory_energy_order ok=T dH_large=1.5445E-09 dH_mid=3.8612E-10 dH_small=8.4961E-11 slope_lm=2.0000 slope_ms=2.1842
wv_dense_trajectory_reverse_energy ok=T dt=8.2264E-18 dx=1.5027E-16 dpi=1.0875E-15 dH_pair=1.7764E-15 dH_fwd=6.0027E-11
wv_boundary_paper_full_flip ok=F full_flip_error=3.2097E-01 normal_reflect_error=0.0000E+00 bounced=T
[ERROR] WV-HMC constraint kernel failures=1
```

This localized a real implementation mismatch: the previous implementation was
self-consistent for normal/component reflection, but did not implement the
simplified-paper full momentum flip.

## Fix

The default simplified-WV production boundary exit now follows the paper rule:

```text
state_out = state_current
pi_out = -pi_current
```

This is applied both for ordinary outside-extended-interval exits and for the
nonnegative-flow lower hard-wall guard.  Numerical construction failures that
cannot be classified as boundary exits remain rejected-proposal diagnostics.

Touched source/tests:

- `src/sampler/wv_hmc_constraints.f90`
- `tests/test_wv_hmc_constraint_kernels.f90`

Updated runbooks:

- `WV_HMC_IMPLEMENTATION_PLAN_20260529.md`
- `WV_HMC_MATH_PHYSICS_REVIEW_20260529.md`
- `WV_HMC_PARAMETER_TUNING_SOP_20260531.md`

## Post-Fix Kernel Gate

After the patch, the same deterministic audit passed.

Key lines:

```text
wv_dense_trajectory_energy_order ok=T dH_large=1.5445E-09 dH_mid=3.8612E-10 dH_small=8.4961E-11 slope_lm=2.0000E+00 slope_ms=2.1842E+00
wv_dense_trajectory_reverse_energy ok=T dt=8.2264E-18 dx=1.5027E-16 dpi=1.0875E-15 dH_pair=1.7764E-15 dH_fwd=6.0027E-11
wv_boundary_paper_full_flip ok=T full_flip_error=0.0000E+00 normal_reflect_error=3.2097E-01 bounced=T
[PASS] WV-HMC math kernels
[PASS] WV-HMC constraint kernels
WV_HMC_DEBUG_TESTS_COMPLETE
```

## n=2 Observable Sanity

Run name:
`wv_hmc_fast_audit_n2_obs_paper_flip_32x3000_20260602`

Remote readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n2_obs_paper_flip_32x3000_20260602/readback`

Local readback copy:
`n2_obs_paper_flip_32x3000/`

Configuration:

- Stephanov `n=2`
- 32 seeds x 3000 cycles
- measurement start cycle 1001
- random Gaussian initial state, sigma `0.8`
- `T0=0.005`, `T1=0.2`, `D0=0.005`, `D1=0.05`
- measurement interval `[0.005,0.2]`
- paper-wall `gamma=1`
- `epsilon=0.015`, `nstep=3`
- constraint tolerance `1e-10`, max Newton iterations `48`
- 16 parallel workers

One seed failed before producing samples due to an initial ODE flow failure:

```text
seed=6202009 status=103 cycles_attempted=0 cycles_completed=0 odex_calls=1 odex_failure=1
```

The other 31 seeds were used in the readback.

Summary:

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 31 | 93000 | 50849 | 0.921095 | 0.0390263 | 2920 |

Observable exact-reference check:

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.376578959 | 0.0156 | -0.222 | 0.013305832 | 0.0155 | 0.856 |
| number_density | 0.0308435074 | 0.0384 | -0.205 | -0.0282700574 | 0.0435 | -0.650 |

Flow-time histogram:

| histogram | zero bins | adjacent flatness | max/min ratio |
|---|---:|---:|---:|
| chain | 0 | 0.00135667 | 1.64982 |
| measurement | 0 | 0.00204747 | 1.64625 |

## Current Conclusion

The fast audit found and fixed a concrete simplified-paper boundary-policy
deviation.  After the fix, deterministic WV-HMC kernel identities pass, and a
cheap `n=2` observable sanity run does not show gross exact-reference bias.

This does not yet prove that the previous `n=6` WV-HMC observable drift is fully
resolved.  The next discriminator should be a short post-fix `n=6` run using
the already tuned parameter path, with the same observable/z and flow-time-bin
checks used before.

## n=6 High-Flow Diagnostic

Run name:
`wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602`

Remote readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602/readback`

Local readback copy:
`n6_highflow_paperflip_32x3000/`

Configuration:

- Stephanov `n=6`, `mu=0.6`, `tau=0`
- 32 seeds x 3000 cycles
- measurement start cycle 501
- initial state bank:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat`
- sampler interval `[T0,T1]=[0,0.03]`
- diagnostic measurement interval `[0.028,0.03]`
- `D0=0.0001`, `D1=0.005`
- paper-wall `gamma=65`
- `epsilon=0.009`, `nstep=10`
- constraint tolerance `1e-10`, max Newton iterations `192`

This is a high-flow diagnostic only.  It is not the primary WV-HMC correctness
gate because the full mathematical estimator should also pass on the full
measurement interval `[0,0.03]`.

Summary:

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 32 | 96000 | 5628 | 0.104309 | 0.0174326 | 22472 |

Transition diagnostics:

| metric | value |
|---|---:|
| Metropolis rejections | 320 |
| Reverse-gate rejections | 837 |
| Forward construction failures | 17636 |
| ODE failures | 4836 |
| Effective x jump sq / cycle | 0.0042984 |
| Effective z jump sq / cycle | 0.00564686 |

Flow-time histogram:

| histogram | zero bins | adjacent flatness | max/min ratio |
|---|---:|---:|---:|
| chain | 0 | 0.00199823 | 1.47720 |
| measurement | 0 | 0.00856326 | 1.39216 |

Observable exact-reference check:

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.0220087207 | 0.00315 | -0.784 | -0.00358972816 | 0.00343 | -1.046 |
| number_density | 0.645918714 | 0.133 | 0.599 | -0.0147266292 | 0.154 | -0.0955 |

Diagnostic status:

- The high-flow cut does not show the earlier gross observable drift after the
  paper full-flip boundary fix.
- This supports the boundary-policy fix as a useful diagnostic improvement.
- The production correctness decision must wait for the matched full-window
  `[0,0.03]` readback.
