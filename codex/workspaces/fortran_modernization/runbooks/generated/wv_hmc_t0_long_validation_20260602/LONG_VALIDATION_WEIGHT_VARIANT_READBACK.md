# Long Validation Weight-Variant Readback

Recorded: 2026-06-02

Dataset:

```text
n6_t0_long_old_boundary_sourcepin_8ec6dc0d9b87_86f750bba994
```

Remote root:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601
```

This is an offline measurement-factor scan on the same observable histories.
The transition history is unchanged.  The dataset uses the old source pin
before the simplified-paper full-flip boundary fix.

## Full Measurement Window

Rows use the existing measurement-history window `[0.025,0.03]`.

| variant | samples | C | chiral z Re | chiral z Im | density z Re | density z Im | max abs z |
|---|---:|---:|---:|---:|---:|---:|---:|
| `phase_only` | 148397 | 0.09013 | 1.747 | -0.788 | -1.046 | 1.347 | 1.747 |
| `current_times_alpha` | 148397 | 0.08972 | 1.753 | -0.953 | -1.004 | 1.472 | 1.753 |
| `phase_over_alpha` | 148397 | 0.11083 | -3.176 | -0.781 | 1.294 | 1.348 | 3.176 |
| `current_wv_factor` | 148397 | 0.11038 | -3.198 | -0.954 | 1.370 | 1.475 | 3.198 |
| `phase_times_alpha` | 148397 | 0.07036 | 4.568 | -0.801 | -2.869 | 1.345 | 4.568 |
| `current_times_alpha2` | 148397 | 0.06999 | 4.578 | -0.955 | -2.863 | 1.465 | 4.578 |
| `current_over_alpha` | 148397 | 0.13190 | -10.455 | -0.955 | 4.242 | 1.479 | 10.455 |

Readback:

- The same-history full-window scan still shows a clear improvement if the
  weight is changed from `current_wv_factor` to `phase_only` or
  `current_times_alpha`.
- The improvement is not the same as the earlier 32x1500 scan: here
  `phase_times_alpha` and `current_times_alpha2` are worse, not better.
- Therefore this dataset does not support a simple "multiply by alpha" or
  "multiply by alpha squared" replacement.

## Flow-Cut Sensitivity

Rows report max absolute z over Re/Im chiral condensate and number density.

| flow cut | best variant | best max abs z | current max abs z | note |
|---|---|---:|---:|---|
| `t>=0.025` | `phase_only` | 1.747 | 3.198 | full measurement window improves under `phase_only` / `current_times_alpha` |
| `t>=0.028` | `phase_over_alpha` | 1.978 | 1.980 | essentially tied with current |
| `t>=0.029` | `current_wv_factor` | 0.939 | 0.939 | diagnostic tail cut only; not a reasonable production rescue |

Readback:

- The weight-variant improvement is strongest for the broad measurement window.
- The `t>=0.029` cut uses only `31157 / 148397` measurement samples, about
  `21%` of the already high-flow measurement window.  It is too close to the
  endpoint to be a reasonable production criterion for this ensemble.
- Therefore the fact that `t>=0.029` passes should only be used to localize the
  problem.  It does not rescue the current broad-window estimator.
- The actionable problem remains: the intended measurement window
  `[0.025,0.03]` fails under the current factor, while alternative factors
  improve that broad-window result.

## Artifact Paths

Local:

```text
runbooks/generated/wv_hmc_t0_long_validation_20260602/long_validation_weight_variants.csv
runbooks/generated/wv_hmc_t0_long_validation_20260602/long_validation_weight_variants_flowcuts.csv
```

Remote:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601/readback/long_validation_weight_variants.csv
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601/readback/long_validation_weight_variants_flowcuts.csv
```

## Next Audit Implication

This does not close the code audit.  It narrows the next check:

1. derive the WV-HMC measurement factor convention independently;
2. add an n=6 pointwise/oracle test for the phase, `alpha`, and `W(t)` factors;
3. compare that oracle to `src/sampler/wv_hmc_measurement.f90`.

Do not choose a production measurement factor from offline z-score ranking
alone.
