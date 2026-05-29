# Stephanov N6 Pooled Observable Data - 2026-05-26

Scope: compare `nofb` and `withfb` using pooled estimators for
Stephanov `n=6`, `mu=0.6`, `m=0.004`, TLTM ladder endpoint `t_high=0.03`.

Exact values used:

- chiral condensate: `0.0244771982754 + 0 i`
- number density: `0.56611556665 + 0 i`

Data roots:

- nofb old 128: `output/stephanov_tltm_production/stephanov_n6_nofb_equalcost_128x4300_20260524a`
- nofb topup 384: `output/stephanov_tltm_production/stephanov_n6_nofb_topup384x4300_to512_20260525a`
- withfb 512: `output/stephanov_tltm_production/stephanov_n6_withfb_mf500_512x1100_after_nofb_20260525a`

Pooled estimator method:

- 512 seeds in each comparison.
- Use complete observable records only; trailing incomplete records from
  timeout-interrupted streams are ignored.
- Pooled estimator:
  `O_pool = sum_s sum_i phi_{s,i} O_{s,i} / sum_s sum_i phi_{s,i}`.
- Errors are leave-one-seed jackknife errors on `O_pool`.
- `z = (O_pool - exact) / jackknife_error`, real and imaginary parts separately.
- `nofb_same_config_size_as_withfb` uses the same record IDs as
  `withfb_all_available`; each nofb seed is truncated to the corresponding
  withfb seed's complete-sample count.

Sample and phase summary:

| group | seeds | total samples | min samples/seed | median samples/seed | max samples/seed | phase | phase JK err | eff frac | effN |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `nofb_all_available` | 512 | 2,005,535 | 3123 | 4081 | 4301 | 0.118306 | 0.001698 | 0.013996 | 28070 |
| `withfb_all_available` | 512 | 548,085 | 920 | 1101 | 1101 | 0.117640 | 0.002710 | 0.013839 | 7585 |
| `nofb_same_config_size_as_withfb` | 512 | 548,085 | 920 | 1101 | 1101 | 0.119897 | 0.003070 | 0.014375 | 7879 |

Pooled values:

| group | chiral Re | chiral Im | density Re | density Im |
|---|---:|---:|---:|---:|
| `nofb_all_available` | `0.024593 ± 0.000598` | `0.000268 ± 0.000497` | `0.559880 ± 0.024923` | `-0.039242 ± 0.027313` |
| `withfb_all_available` | `0.025611 ± 0.000949` | `-0.000419 ± 0.000889` | `0.594291 ± 0.042430` | `-0.007586 ± 0.036758` |
| `nofb_same_config_size_as_withfb` | `0.023018 ± 0.000905` | `0.000371 ± 0.000958` | `0.626331 ± 0.048556` | `-0.100126 ± 0.055140` |

Pooled z values:

| group | chiral Re z | chiral Im z | density Re z | density Im z |
|---|---:|---:|---:|---:|
| `nofb_all_available` | +0.194 | +0.540 | -0.250 | -1.437 |
| `withfb_all_available` | +1.195 | -0.471 | +0.664 | -0.206 |
| `nofb_same_config_size_as_withfb` | -1.612 | +0.387 | +1.240 | -1.816 |
