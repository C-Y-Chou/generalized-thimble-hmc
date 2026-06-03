# WV-HMC History Readback

Input root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_bankinit_g0_e003n20_128x3000_20260602`

## Run Metadata

| item | value |
|---|---:|
| summary_seed_rows | 128 |
| manifest_seed_rows | 128 |
| cycles_completed | 384000 |
| accepted | 84562 |
| rejected | 299438 |
| acceptance_rate_including_rejects | 0.22021354166666668 |
| transitions_failed | 299332 |
| metropolis_rejected | 69 |
| reverse_gate_rejected | 37 |
| reverse_gate_checked | 84668 |
| reverse_gate_failed | 37 |
| runtime_sec_sum_over_seeds | 3348.556703567505 |

## Production Gate Signal

- strongest all-cut seed-jackknife exact-reference z: `number_density z_im` = `1.59`
- block rows available: `15`
- state-history rows available: `128`

## All-Cut Seed Jackknife

| observable | Re | SE Re | z Re | Im | SE Im | z Im | phase coherence | samples |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.37296705 | 0.0147 | -0.482 | -0.00860890566 | 0.00725 | -1.19 | 0.873408 | 353362 |
| number_density | 0.040782418 | 0.02 | 0.103 | 0.0380496853 | 0.024 | 1.59 | 0.873408 | 353362 |
| logdet_dirac | 0.966992669 | 0.0848 |  | 0.681838746 | 0.229 |  | 0.873408 | 353362 |
| phase_factor | 0.673621461 | 0.0197 |  | 0.0280829914 | 0.0217 |  | 0.873408 | 353362 |
| min_singular_ba_m2 | 0.628746904 | 0.0324 |  | 0.00733362713 | 0.00893 |  | 0.873408 | 353362 |

Artifacts are written next to this Markdown file.
