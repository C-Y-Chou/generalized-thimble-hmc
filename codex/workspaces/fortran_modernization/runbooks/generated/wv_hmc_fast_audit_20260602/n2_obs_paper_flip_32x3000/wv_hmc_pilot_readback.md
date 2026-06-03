# WV-HMC Pilot Readback

This readback preserves the complex ratio estimator across seed outputs.

## Summary

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 31 | 93000 | 50849 | 0.921095 | 0.0390263 | 2920 |

Transition diagnostics:
- Metropolis rejections: `1280`
- Reverse-gate rejections: `1195`
- Reverse-gate checked/passed/failed: `90574` / `89379` / `1185`
- Reverse-gate finite error samples: `89389`
- Reverse-gate state error mean/max: `5.91669e-05` / `1.20993`
- Reverse-gate momentum error mean/max: `0.000226546` / `2.19894`
- Forward construction failures: `2426`
- ODE failures: `494`
- Effective x jump sq / cycle: `0.00358364`
- Effective z jump sq / cycle: `0.00193693`
- Accepted x jump sq / accepted proposal: `0.003783`
- Accepted z jump sq / accepted proposal: `0.00204469`

Flow-time histogram diagnostics:
- Chain histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00135667` / `1.64982`
- Chain tail low/high counts: `2405` / `14117`
- Measurement histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00204747` / `1.64625`

## Observables

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.376578959 | 0.0156 | -0.222 | 0.013305832 | 0.0155 | 0.856 |
| logdet_dirac | 0.741203347 | 0.144 |  | 1.17641704 | 0.363 |  |
| min_singular_ba_m2 | 0.560602611 | 0.0198 |  | -0.00618878349 | 0.00734 |  |
| number_density | 0.0308435074 | 0.0384 | -0.205 | -0.0282700574 | 0.0435 | -0.65 |
| phase_factor | 0.724177004 | 0.0365 |  | -0.0308645994 | 0.0354 |  |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n2_obs_paper_flip_32x3000_20260602/readback/wv_hmc_pilot_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n2_obs_paper_flip_32x3000_20260602/readback/wv_hmc_pilot_observable_z.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n2_obs_paper_flip_32x3000_20260602/readback/wv_hmc_pilot_readback_metadata.json`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n2_obs_paper_flip_32x3000_20260602/readback/wv_hmc_flow_time_histogram.csv`
