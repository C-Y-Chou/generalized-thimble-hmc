# Stephanov n=6 DFO-LS Tuning, 2026-05-24

## Scope

This note records the DOP853-pinned offline fixed-attempt replay used to tune
the official DFO-LS fallback for the Stephanov n=6 with-fallback path.  It does
not replace the older p28 `stable_gate77` policy.

Captured attempts:

```text
output/stephanov_dfols_tuning/stephanov_n6_dfols_policy_scan_noisefixed0_parallel_20260524a/base_auto_r025_rho16_abs26/qn_attempt_capture/record_0505
```

All replay jobs used:

```text
TLTM_ODE_BACKEND=dop853
TLTM_DOP853_HINIT_ENABLED=1
TLTM_DOP853_STIFFNESS_CHECK_ENABLED=1
TLTM_DOP853_STIFFNESS_CHECK_INTERVAL=1000
TLTM_DOP853_STIFFNESS_MAX_HITS=15
TLTM_DOP853_STIFFNESS_THRESHOLD=6.1
```

## Evidence Runs

```text
16755[].anode01  safety/growing scan
16756[].anode01  alpha1/alpha2 rho-schedule scan
16757[].anode01  alpha1/safety refinement scan
16758[].anode01  chosen preset validation at maxfun=700
```

Output roots:

```text
output/stephanov_dfols_tuning/stephanov_n6_dfols_safety_scan_rb020_sst4_grow16_all21_20260524a
output/stephanov_dfols_tuning/stephanov_n6_dfols_alpha_scan_rb020_a1x4_a2x3_all21_20260524a
output/stephanov_dfols_tuning/stephanov_n6_dfols_alpha_safety_refine_rb020_a1x5_sst3_all21_20260524a
output/stephanov_dfols_tuning/stephanov_n6_dfols_chosen_a105_sst035_mf700_all21_20260524a
```

## Findings

- `growing.safety.*` did not change the observed success set or NF profile at
  fixed `general.safety_step_thresh`.  The safety tail is therefore not a
  growing-phase knob problem for this captured set.
- `general.safety_step_thresh` alone did not improve the failure set.  It can
  change the success NF distribution, but high values may create a bad max tail.
- `tr_radius.alpha1` is the useful knob.  `alpha1=0.05` reduces rho levels and
  lowers the success NF tail without changing the success set.
- `tr_radius.alpha2` did not improve the profile in this scan; keep the package
  default.

## Selected Replay Preset

Use this for the next Stephanov n=6 with-fallback production smoke:

```text
rhobeg=0.20
rhoend=1e-13
model.abs_tol=1e-26
model.rel_tol=0
tr_radius.gamma_dec=default
tr_radius.alpha1=0.05
tr_radius.alpha2=default
general.safety_step_thresh=0.35
objfun_has_noise=0
maxfun=700
```

Validation at `maxfun=700`:

```text
success_count=17/21
failure_samples=8,16,19,21
success_nf_median=398
success_nf_p90=537.4
success_nf_max=615
wall_sec_median=79.839
wall_sec_p90=110.625
wall_sec_max=147.364
```

Comparable baseline in the refinement scan, with package-default alpha/safety
and `maxfun=1200`:

```text
success_count=17/21
failure_samples=8,16,19,21
success_nf_p90=597.8
success_nf_max=741
wall_sec_p90=194.907
wall_sec_max=249.365
```

## Decision

Promote the selected replay preset to the next short with-fallback production
smoke.  If production loses attempts that the replay succeeded on, raise the
cap to `maxfun=800` before changing any other package parameter.  Do not resume
blind scans of `growing.safety.*`; the diagnostic evidence says it is the wrong
control surface for this case.

## Production AB Check

The replay knobs were wired into the production C bridge in commit
`416e0ae2acbd9865484c0cc6656c432930103107`, then checked with a short
production-path AB test:

```text
PBS job: 16759[].anode01
output: output/stephanov_dfols_tuning/stephanov_n6_prod_ab_maxfun_8cand_8x5_20260524a
records: 0,101,202,303,404,505,606,707
cycles: 5
ladder: 0,1e-3,3e-3,7e-3,1e-2,1.3e-2,1.6e-2,1.8e-2,2e-2,2.25e-2,2.5e-2,2.75e-2,3e-2
flow bank: output/stephanov_flow_banks/stephanov_n6_tltm_t003_ladder13_dop853_highflow_bank_8x600_20260523_xhist_b100_s5/flow_bank_ladder13_dop853_dense_cache
summary: production_ab_summary.csv
attempts: production_ab_attempts.csv
```

Merged production summary:

```text
candidate      wall_s  wall/nofb  attempts  converged  conv_frac  maxfun_hits
nofb            53.1      1.00          0          0        n/a            0
default_mf800  341.0      6.42        350        268      0.766           82
tuned_mf400    147.8      2.78        219         65      0.297          154
tuned_mf500    226.8      4.27        282        173      0.613          109
tuned_mf600    240.7      4.53        300        198      0.660          102
tuned_mf650    268.5      5.05        332        233      0.702           99
tuned_mf700    269.2      5.07        329        236      0.717           93
tuned_mf800    297.5      5.60        343        259      0.755           84
```

Production conclusions:

- The useful with-fallback path is not merely 3x slower than nofb for this
  short-cycle test.  `maxfun=400` is 2.78x but clips too many attempts, while
  practical tuned settings are 4.3x-5.6x nofb.
- The default package `maxfun=800` path is worse than the tuned path:
  6.42x nofb versus 5.60x for tuned `maxfun=800`, with comparable convergence.
- The practical production elbow is around `maxfun=650-700`.  `maxfun=700`
  gains only three more converged attempts than `650` in this short run, but it
  has essentially the same walltime and fewer maxfun hits.  Keep `maxfun=700`
  as the default with-fallback smoke setting unless a longer run changes the
  success/cost curve.
