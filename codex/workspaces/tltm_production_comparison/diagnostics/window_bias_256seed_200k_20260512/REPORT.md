# Window Bias Diagnostic Report

## Integrity Check

- Recomputed per-seed full-run ratios from `virial.dat` and binary `phi_history.dat`.
- Max absolute recompute difference: Re `3.30291e-15`, Im `2.17881e-15`.

## Existing Dataset Scale Readback

| dataset | method | n_seeds | mean_re | std_re | Zmean_re |
| --- | --- | --- | --- | --- | --- |
| official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb | no_fb | 10 | 0.0265223 | 0.188677 | 0.44452 |
| official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb | fb_norefine | 10 | -0.029074 | 0.103918 | -0.88474 |
| official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb | no_fb | 32 | 0.0201888 | 0.0856452 | 1.33347 |
| official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb | fb_norefine | 32 | -0.00199377 | 0.0559636 | -0.201532 |
| official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb | no_fb | 256 | 0.00251288 | 0.0384177 | 1.04655 |
| official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb | fb_norefine | 256 | 0.00402056 | 0.0326054 | 1.97295 |

## 200k Split Into Four Windows

| method | window | mean_re | Zmean_re | mean_im | Zmean_im |
| --- | --- | --- | --- | --- | --- |
| fb_norefine | 0 | 0.00137891 | 0.34327 | 0.000891453 | 0.303027 |
| fb_norefine | 1 | 0.00736861 | 1.76167 | -0.000385239 | -0.139789 |
| fb_norefine | 2 | 0.00559802 | 1.37464 | -0.00155994 | -0.577698 |
| fb_norefine | 3 | -0.000142914 | -0.0353124 | -0.00236484 | -0.885691 |
| no_fb | 0 | 0.00290375 | 0.575669 | -0.00333222 | -1.18168 |
| no_fb | 1 | 0.00190483 | 0.371351 | 0.00124817 | 0.411938 |
| no_fb | 2 | -0.000457481 | -0.0907287 | -0.00427269 | -1.45167 |
| no_fb | 3 | 0.00387284 | 0.797027 | 0.0029318 | 1.05698 |

## Paired Difference: fb_norefine - no_fb

| window | mean_diff_re | t_diff_re | pos/neg |
| --- | --- | --- | --- |
| 0 | -0.00152483 | -0.248018 | 128/128 |
| 1 | 0.00546378 | 0.978189 | 136/120 |
| 2 | 0.0060555 | 0.998639 | 134/122 |
| 3 | -0.00401575 | -0.686853 | 126/130 |

## 20 Window Sign Summary

- `fb_norefine` split20 windows with positive mean Re: `12/20`.
- `no_fb` split20 windows with positive mean Re: `9/20`.
- paired split20 mean differences positive/negative: `10/10`.

## fb_norefine Counter Correlations For Full 200k

| target | counter | pearson_r |
| --- | --- | --- |
| Ohat_re | fallback_trigger_count | 0.660007 |
| Ohat_re | accepted_local_quasi_count | 0.3647 |
| Ohat_re | unresolved_failure_count | 0.539758 |
| Ohat_re | reverse_gate_total_reject_count | 0.396734 |
| Ohat_re | local_metropolis_reject_count | 0.450908 |

## Outputs

- `per_seed_window_observables.csv`
- `window_summary.csv`
- `paired_window_summary.csv`
- `per_seed_paired_window_diff.csv`
- `counter_correlation_summary.csv`
- `total_recompute_check.csv`
- `dataset_scale_summary.csv`
