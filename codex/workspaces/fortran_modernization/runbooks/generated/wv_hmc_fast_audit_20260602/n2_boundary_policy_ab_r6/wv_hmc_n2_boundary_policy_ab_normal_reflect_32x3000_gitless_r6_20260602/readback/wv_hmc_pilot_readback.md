# WV-HMC Pilot Readback

This readback preserves the complex ratio estimator across seed outputs.

## Summary

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 32 | 96000 | 79340 | 0.931495 | 0.0411715 | 3436 |

Transition diagnostics:
- Metropolis rejections: `1379`
- Reverse-gate rejections: `1798`
- Reverse-gate checked/passed/failed: `93158` / `91360` / `1520`
- Reverse-gate finite error samples: `91638`
- Reverse-gate state error mean/max: `0.000818004` / `1.69833`
- Reverse-gate momentum error mean/max: `0.001013` / `2.08334`
- Forward construction failures: `2842`
- ODE failures: `594`
- Effective x jump sq / cycle: `0.00399462`
- Effective z jump sq / cycle: `0.00194627`
- Accepted x jump sq / accepted proposal: `0.00426183`
- Accepted z jump sq / accepted proposal: `0.00207646`

Flow-time histogram diagnostics:
- Chain histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00163717` / `1.8028`
- Chain tail low/high counts: `2631` / `14029`
- Measurement histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00159564` / `1.78679`

## Observables

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.364736013 | 0.01 | -1.53 | 0.0136355686 | 0.015 | 0.909 |
| logdet_dirac | 0.603098889 | 0.0933 |  | 0.811435043 | 0.252 |  |
| min_singular_ba_m2 | 0.598068941 | 0.0224 |  | 0.00616456843 | 0.00477 |  |
| number_density | 0.0777914799 | 0.0264 | 1.48 | -0.0160754181 | 0.036 | -0.447 |
| phase_factor | 0.757646193 | 0.0253 |  | -0.000197242404 | 0.0272 |  |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_normal_reflect_32x3000_gitless_r6_20260602/readback/wv_hmc_pilot_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_normal_reflect_32x3000_gitless_r6_20260602/readback/wv_hmc_pilot_observable_z.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_normal_reflect_32x3000_gitless_r6_20260602/readback/wv_hmc_pilot_readback_metadata.json`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_boundary_policy_ab_20260602/wv_hmc_n2_boundary_policy_ab_normal_reflect_32x3000_gitless_r6_20260602/readback/wv_hmc_flow_time_histogram.csv`
