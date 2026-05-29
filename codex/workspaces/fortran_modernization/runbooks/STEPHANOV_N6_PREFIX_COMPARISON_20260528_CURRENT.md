# Stephanov N6 Pooled Observable Data - 2026-05-28

Scope: compare selected current-data cuts for Stephanov `n=6`, `mu=0.6`, `m=0.004`, TLTM ladder endpoint `t_high=0.03`.

Exact values used:

- chiral condensate: `0.0244771982754 + 0 i`
- number density: `0.56611556665 + 0 i`

Data roots:

- withfb current: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_tltm_production/stephanov_n6_5000_complete_512_optimal_20260526e`
- nofb current: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_tltm_production/stephanov_n6_nofb15k_512_equalcost_20260526f`

Pooled estimator method:

- Pooled estimator: `O_pool = sum_s sum_i phi_{s,i} O_{s,i} / sum_s sum_i phi_{s,i}`.
- Errors are leave-one-seed jackknife errors on `O_pool`.
- `z = (O_pool - exact) / jackknife_error`, real and imaginary parts separately.
- `withfb_prefix2500` and `nofb_prefix2500` use the first 2500 observable rows per seed.
- `nofb_s01_to_s03` uses all observable rows in complete `nofb15_s01_*`, `nofb15_s02_*`, and `nofb15_s03_*` stage directories.

Sample and phase summary:

| group | seeds | total samples | min samples/seed | median samples/seed | max samples/seed | phase | phase JK err | eff frac | effN |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `withfb_prefix2500` | 512 | 1,280,000 | 2,500 | 2,500 | 2,500 | 0.118349 | 0.001724 | 0.014007 | 17928 |
| `nofb_s01_to_s03` | 512 | 3,840,512 | 7,501 | 7,501 | 7,501 | 0.117185 | 0.001184 | 0.013732 | 52739 |
| `nofb_prefix2500` | 512 | 1,280,000 | 2,500 | 2,500 | 2,500 | 0.118415 | 0.001986 | 0.014022 | 17948 |

Pooled values:

| group | chiral Re | chiral Im | density Re | density Im |
|---|---:|---:|---:|---:|
| `withfb_prefix2500` | `0.024293 +/- 0.000531` | `0.000753 +/- 0.000521` | `0.550467 +/- 0.019438` | `-0.038246 +/- 0.026554` |
| `nofb_s01_to_s03` | `0.024712 +/- 0.000425` | `-0.000384 +/- 0.000408` | `0.561956 +/- 0.015850` | `0.006467 +/- 0.016911` |
| `nofb_prefix2500` | `0.025501 +/- 0.000806` | `-0.000311 +/- 0.000762` | `0.544354 +/- 0.024644` | `-0.028188 +/- 0.030441` |

Pooled z values:

| group | chiral Re z | chiral Im z | density Re z | density Im z |
|---|---:|---:|---:|---:|
| `withfb_prefix2500` | -0.348 | +1.445 | -0.805 | -1.440 |
| `nofb_s01_to_s03` | +0.552 | -0.942 | -0.262 | +0.382 |
| `nofb_prefix2500` | +1.270 | -0.409 | -0.883 | -0.926 |
