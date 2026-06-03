# WV-HMC History Readback

Input root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_g0_e003n20_128x5000_r2_20260602_valid_input`

## Run Metadata

| item | value |
|---|---:|
| summary_seed_rows | 128 |
| manifest_seed_rows | 128 |
| cycles_completed | 640000 |
| accepted | 131452 |
| rejected | 508548 |
| acceptance_rate_including_rejects | 0.20539375 |
| transitions_failed | 508363 |
| metropolis_rejected | 117 |
| reverse_gate_rejected | 68 |
| reverse_gate_checked | 131637 |
| reverse_gate_failed | 68 |
| runtime_sec_sum_over_seeds | 5157.7321536540985 |

## Production Gate Signal

- strongest all-cut seed-jackknife exact-reference z: `number_density z_re` = `2.7`
- block rows available: `15`
- state-history rows available: `128`

## All-Cut Seed Jackknife

| observable | Re | SE Re | z Re | Im | SE Im | z Im | phase coherence | samples |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.331907605 | 0.0202 | -2.39 | 0.00614073892 | 0.00643 | 0.955 | 0.897005 | 473484 |
| number_density | 0.0861639556 | 0.0176 | 2.7 | -0.0213881936 | 0.0225 | -0.949 | 0.897005 | 473484 |
| logdet_dirac | 1.16515561 | 0.183 |  | 1.35171486 | 0.258 |  | 0.897005 | 473484 |
| phase_factor | 0.735473751 | 0.0174 |  | -0.0261507448 | 0.0235 |  | 0.897005 | 473484 |
| min_singular_ba_m2 | 0.81534427 | 0.101 |  | -0.0273779907 | 0.0177 |  | 0.897005 | 473484 |

Artifacts are written next to this Markdown file.
