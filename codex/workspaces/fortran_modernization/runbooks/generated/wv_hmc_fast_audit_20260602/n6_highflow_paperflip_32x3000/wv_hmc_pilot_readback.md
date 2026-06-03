# WV-HMC Pilot Readback

This readback preserves the complex ratio estimator across seed outputs.

## Summary

| seeds | cycles | measurements | phase coherence | bounced/step | failures |
|---:|---:|---:|---:|---:|---:|
| 32 | 96000 | 5628 | 0.104309 | 0.0174326 | 22472 |

Transition diagnostics:
- Metropolis rejections: `320`
- Reverse-gate rejections: `837`
- Reverse-gate checked/passed/failed: `78364` / `77527` / `835`
- Reverse-gate finite error samples: `77529`
- Reverse-gate state error mean/max: `7.84417e-06` / `0.374296`
- Reverse-gate momentum error mean/max: `5.12964e-05` / `2.00426`
- Forward construction failures: `17636`
- ODE failures: `4836`
- Effective x jump sq / cycle: `0.0042984`
- Effective z jump sq / cycle: `0.00564686`
- Accepted x jump sq / accepted proposal: `0.00534468`
- Accepted z jump sq / accepted proposal: `0.00702137`

Flow-time histogram diagnostics:
- Chain histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00199823` / `1.4772`
- Chain tail low/high counts: `0` / `15344`
- Measurement histogram zero bins / adjacent flatness / max-min ratio: `0` / `0.00856326` / `1.39216`

## Observables

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.0220087207 | 0.00315 | -0.784 | -0.00358972816 | 0.00343 | -1.05 |
| logdet_dirac | -0.972692689 | 0.811 |  | 0.741608868 | 0.833 |  |
| min_singular_ba_m2 | 0.100448943 | 0.00696 |  | -0.00850900044 | 0.00784 |  |
| number_density | 0.645918714 | 0.133 | 0.599 | -0.0147266292 | 0.154 | -0.0955 |
| phase_factor | 0.14765203 | 0.168 |  | -0.182658341 | 0.131 |  |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602/readback/wv_hmc_pilot_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602/readback/wv_hmc_pilot_observable_z.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602/readback/wv_hmc_pilot_readback_metadata.json`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602/readback/wv_hmc_flow_time_histogram.csv`
