# WV-HMC History Readback

Input root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_retuned_g0_eps010_n8_max192_32x1000_20260531`

## Run Metadata

| item | value |
|---|---:|
| summary_seed_rows | 32 |
| manifest_seed_rows | 32 |
| cycles_completed | 32000 |
| accepted | 28998 |
| rejected | 3002 |
| acceptance_rate_including_rejects | 0.9061875 |
| transitions_failed | 1977 |
| metropolis_rejected | 353 |
| reverse_gate_rejected | 672 |
| reverse_gate_checked | 30023 |
| reverse_gate_failed | 513 |
| runtime_sec_sum_over_seeds | 55049.07842516899 |

## Production Gate Signal

- strongest all-cut seed-jackknife exact-reference z: `chiral_condensate z_im` = `0.883`
- block rows available: `15`
- state-history rows available: `0`

## All-Cut Seed Jackknife

| observable | Re | SE Re | z Re | Im | SE Im | z Im | phase coherence | samples |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.0268379661 | 0.00836 | 0.283 | -0.00961445176 | 0.0109 | -0.883 | 0.0507131 | 24147 |
| number_density | 0.478038071 | 0.271 | -0.325 | 0.150257375 | 0.35 | 0.429 | 0.0507131 | 24147 |
| logdet_dirac | -0.852240026 | 1.31 |  | 0.584752937 | 1.39 |  | 0.0507131 | 24147 |
| phase_factor | -0.0285055728 | 0.196 |  | -0.313265927 | 0.294 |  | 0.0507131 | 24147 |
| min_singular_ba_m2 | 0.134501339 | 0.0179 |  | -0.0314400205 | 0.0161 |  | 0.0507131 | 24147 |

Artifacts are written next to this Markdown file.
