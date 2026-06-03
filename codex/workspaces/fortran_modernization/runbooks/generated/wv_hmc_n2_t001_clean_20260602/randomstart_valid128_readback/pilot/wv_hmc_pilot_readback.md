# WV-HMC Pilot Readback

This readback preserves the complex ratio estimator across seed outputs.

## Summary

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 128 | 640000 | 473484 | 0.897005 | 0.0177848 | 508485 |

Transition diagnostics:
- Metropolis rejections: `117`
- Reverse-gate rejections: `68`
- Reverse-gate checked/passed/failed: `131637` / `131569` / `68`
- Reverse-gate finite error samples: `131569`
- Reverse-gate state error mean/max: `1.2073e-09` / `1.75098e-06`
- Reverse-gate momentum error mean/max: `2.03715e-09` / `1.96869e-06`
- Forward construction failures: `508363`
- ODE failures: `122`
- Effective x jump sq / cycle: `0.000725472`
- Effective z jump sq / cycle: `0.000728273`
- Accepted x jump sq / accepted proposal: `0.00353211`
- Accepted z jump sq / accepted proposal: `0.00354574`

Flow-time histogram diagnostics:
- Chain histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00170617` / `1.20163`
- Chain tail low/high counts: `0` / `46982`
- Measurement histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00178297` / `1.19212`

## Observables

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.331907605 | 0.0202 | -2.39 | 0.00614073892 | 0.00643 | 0.955 |
| logdet_dirac | 1.16515561 | 0.183 |  | 1.35171486 | 0.258 |  |
| min_singular_ba_m2 | 0.81534427 | 0.101 |  | -0.0273779907 | 0.0177 |  |
| number_density | 0.0861639556 | 0.0176 | 2.7 | -0.0213881936 | 0.0225 | -0.949 |
| phase_factor | 0.735473751 | 0.0174 |  | -0.0261507448 | 0.0235 |  |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_g0_e003n20_128x5000_r2_20260602/readback_clean_n2_t001_20260602/valid128/pilot/wv_hmc_pilot_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_g0_e003n20_128x5000_r2_20260602/readback_clean_n2_t001_20260602/valid128/pilot/wv_hmc_pilot_observable_z.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_g0_e003n20_128x5000_r2_20260602/readback_clean_n2_t001_20260602/valid128/pilot/wv_hmc_pilot_readback_metadata.json`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_g0_e003n20_128x5000_r2_20260602/readback_clean_n2_t001_20260602/valid128/pilot/wv_hmc_flow_time_histogram.csv`
