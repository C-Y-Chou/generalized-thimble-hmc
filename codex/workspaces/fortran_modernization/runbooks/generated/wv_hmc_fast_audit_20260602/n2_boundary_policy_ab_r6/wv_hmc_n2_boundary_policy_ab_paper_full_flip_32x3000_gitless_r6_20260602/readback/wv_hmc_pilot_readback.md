# WV-HMC Pilot Readback

This readback preserves the complex ratio estimator across seed outputs.

## Summary

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 32 | 96000 | 78661 | 0.932105 | 0.0416814 | 3246 |

Transition diagnostics:
- Metropolis rejections: `1386`
- Reverse-gate rejections: `1442`
- Reverse-gate checked/passed/failed: `93240` / `91798` / `1418`
- Reverse-gate finite error samples: `91822`
- Reverse-gate state error mean/max: `8.83436e-05` / `0.863253`
- Reverse-gate momentum error mean/max: `0.00048066` / `2.49434`
- Forward construction failures: `2760`
- ODE failures: `486`
- Effective x jump sq / cycle: `0.00383874`
- Effective z jump sq / cycle: `0.0019197`
- Accepted x jump sq / accepted proposal: `0.00407599`
- Accepted z jump sq / accepted proposal: `0.00203835`

Flow-time histogram diagnostics:
- Chain histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00211352` / `1.65632`
- Chain tail low/high counts: `2607` / `14732`
- Measurement histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00206926` / `1.64105`

## Observables

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.358138992 | 0.0114 | -1.91 | -0.0133566935 | 0.0143 | -0.937 |
| logdet_dirac | 0.686400324 | 0.104 |  | 0.686292215 | 0.289 |  |
| min_singular_ba_m2 | 0.621125317 | 0.0243 |  | 0.0149757463 | 0.00867 |  |
| number_density | 0.0813453734 | 0.0253 | 1.68 | 0.0583240363 | 0.0348 | 1.68 |
| phase_factor | 0.765848108 | 0.024 |  | 0.0433418139 | 0.0265 |  |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_paper_full_flip_32x3000_gitless_r6_20260602/readback/wv_hmc_pilot_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_paper_full_flip_32x3000_gitless_r6_20260602/readback/wv_hmc_pilot_observable_z.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_paper_full_flip_32x3000_gitless_r6_20260602/readback/wv_hmc_pilot_readback_metadata.json`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_paper_full_flip_32x3000_gitless_r6_20260602/readback/wv_hmc_flow_time_histogram.csv`
