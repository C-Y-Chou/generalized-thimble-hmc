# Stephanov N6 Pooled Observable Data - 2026-05-29

Scope: compare `nofb` and `withfb` using pooled estimators for Stephanov `n=6`, `mu=0.6`, `m=0.004`, TLTM ladder endpoint `t_high=0.03`.

Exact values used:

- chiral condensate: `0.0244771982754 + 0 i`
- number density: `0.56611556665 + 0 i`

Data roots:

- nofb 15k/equal-cost: `output/stephanov_tltm_production/stephanov_n6_nofb15k_512_equalcost_20260526f`
- withfb 5k: `output/stephanov_tltm_production/stephanov_n6_5000_complete_512_optimal_20260526e`

Pooled estimator method:

- 512 seeds in each comparison.
- Pooled estimator: `O_pool = sum_s sum_i phi_{s,i} O_{s,i} / sum_s sum_i phi_{s,i}`.
- Errors are leave-one-seed jackknife errors on `O_pool`.
- `z = (O_pool - exact) / jackknife_error`, real and imaginary parts separately.
- `nofb_same_config_size_as_withfb` truncates each nofb seed to `5001` samples.

Sample and phase summary:

| group | seeds | total samples | min samples/seed | median samples/seed | max samples/seed | phase | phase JK err | eff frac | effN |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `nofb_all_available` | 512 | 7,680,512 | 15001 | 15001 | 15001 | 0.117377 | 0.000834 | 0.013777 | 105817 |
| `withfb_all_available` | 512 | 2,560,512 | 5001 | 5001 | 5001 | 0.120014 | 0.001219 | 0.014403 | 36880 |
| `nofb_same_config_size_as_withfb` | 512 | 2,560,512 | 5001 | 5001 | 5001 | 0.116900 | 0.001440 | 0.013666 | 34991 |

Pooled values:

| group | chiral Re | chiral Im | density Re | density Im |
|---|---:|---:|---:|---:|
| `nofb_all_available` | `0.024754 +/- 0.000287` | `-0.000279 +/- 0.000272` | `0.560016 +/- 0.011405` | `0.003129 +/- 0.011746` |
| `withfb_all_available` | `0.023727 +/- 0.000432` | `0.000705 +/- 0.000392` | `0.592795 +/- 0.017151` | `-0.036843 +/- 0.019729` |
| `nofb_same_config_size_as_withfb` | `0.025126 +/- 0.000543` | `-0.000275 +/- 0.000523` | `0.547976 +/- 0.018858` | `0.016299 +/- 0.022575` |

Pooled z values:

| group | chiral Re z | chiral Im z | density Re z | density Im z |
|---|---:|---:|---:|---:|
| `nofb_all_available` | +0.962 | -1.027 | -0.535 | +0.266 |
| `withfb_all_available` | -1.736 | +1.798 | +1.556 | -1.867 |
| `nofb_same_config_size_as_withfb` | +1.194 | -0.526 | -0.962 | +0.722 |

Visual artifacts:

- `z_convergence_curve.png`
- `cumulative_estimator_trace.png`
- `paired_method_delta_trace.png`
- `block500_estimator_trace.png`
- `combined_distance_trace.png`
