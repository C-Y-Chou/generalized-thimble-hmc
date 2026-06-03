# WV-HMC Pilot Readback

This readback preserves the complex ratio estimator across seed outputs.

## Summary

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 128 | 384000 | 353362 | 0.873408 | 0.0157266 | 299411 |

Transition diagnostics:
- Metropolis rejections: `69`
- Reverse-gate rejections: `37`
- Reverse-gate checked/passed/failed: `84668` / `84631` / `37`
- Reverse-gate finite error samples: `84631`
- Reverse-gate state error mean/max: `1.14206e-09` / `2.24681e-07`
- Reverse-gate momentum error mean/max: `1.89308e-09` / `1.69802e-06`
- Forward construction failures: `299332`
- ODE failures: `79`
- Effective x jump sq / cycle: `0.000772692`
- Effective z jump sq / cycle: `0.000778293`
- Accepted x jump sq / accepted proposal: `0.00350883`
- Accepted z jump sq / accepted proposal: `0.00353426`

Flow-time histogram diagnostics:
- Chain histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00165028` / `1.23756`
- Chain tail low/high counts: `0` / `30647`
- Measurement histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00164559` / `1.23741`

## Observables

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.37296705 | 0.0147 | -0.482 | -0.00860890566 | 0.00725 | -1.19 |
| logdet_dirac | 0.966992669 | 0.0848 |  | 0.681838746 | 0.229 |  |
| min_singular_ba_m2 | 0.628746904 | 0.0324 |  | 0.00733362713 | 0.00893 |  |
| number_density | 0.040782418 | 0.02 | 0.103 | 0.0380496853 | 0.024 | 1.59 |
| phase_factor | 0.673621461 | 0.0197 |  | 0.0280829914 | 0.0217 |  |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_bankinit_g0_e003n20_128x3000_20260602/readback_clean_n2_t001_bankinit_20260602/pilot/wv_hmc_pilot_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_bankinit_g0_e003n20_128x3000_20260602/readback_clean_n2_t001_bankinit_20260602/pilot/wv_hmc_pilot_observable_z.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_bankinit_g0_e003n20_128x3000_20260602/readback_clean_n2_t001_bankinit_20260602/pilot/wv_hmc_pilot_readback_metadata.json`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_bankinit_g0_e003n20_128x3000_20260602/readback_clean_n2_t001_bankinit_20260602/pilot/wv_hmc_flow_time_histogram.csv`
