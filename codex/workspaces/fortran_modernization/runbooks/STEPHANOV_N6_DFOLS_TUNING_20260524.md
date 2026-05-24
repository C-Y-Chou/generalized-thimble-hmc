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
