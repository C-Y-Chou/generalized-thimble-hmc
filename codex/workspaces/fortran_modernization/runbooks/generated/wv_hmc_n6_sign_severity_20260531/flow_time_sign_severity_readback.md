# WV-HMC n=6 Flow-Time Sign-Severity Probe

Date: 2026-05-31

Run: `wv_hmc_n6_flowtime_sign_probe_t003_16x1000_20260531`

Remote output:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_sign_severity_20260531/wv_hmc_n6_flowtime_sign_probe_t003_16x1000_20260531`

Jobs: `18361.anode01`, `18362.anode01`

Purpose: estimate sign-problem severity as a function of WV-HMC flow time. This is an endpoint-selection diagnostic, not a production observable claim.

## Run Settings

| field | value |
|---|---:|
| seeds | 16 |
| cycles per seed | 1000 |
| measurement start | 201 |
| step size | 0.010 |
| nstep | 8 |
| sampler T0 | 0.0001 |
| sampler T1 | 0.03 |
| D0 | 0.0001 |
| D1 | 0.005 |
| initial flow time | 0.001 |
| W profile | paper_wall |
| gamma | 1.0 |
| observable history stride | 1 |

Completion:

| item | value |
|---|---:|
| manifests | 2/2 |
| seed summaries | 16/16 |
| return codes | all 0 |
| timed out | 0 |
| history rows | 11934 |

Transition diagnostics:

| metric | min | median | max |
|---|---:|---:|---:|
| runtime sec / seed | 1643.27 | 1773.94 | 1887.06 |
| accepted / cycle | 0.825 | 0.859 | 0.884 |
| transition failure / cycle | 0.080 | 0.103 | 0.128 |
| reverse gate rejected / cycle | 0.015 | 0.029 | 0.041 |
| Metropolis rejected / cycle | 0.003 | 0.0085 | 0.022 |
| flow-time mean / seed | 0.0109 | 0.0121 | 0.0132 |
| flow-time max / seed | 0.0343 | 0.0348 | 0.0350 |

## Flow-Time Binned Sign Severity

The bin diagnostic uses
`C_bin = |sum_{i in bin} w_i| / sum_{i in bin} |w_i|`.

| flow-time bin | samples | mean t | C_bin | phase ESS |
|---|---:|---:|---:|---:|
| [0.0001,0.001) | 935 | 0.000553 | 0.0327 | 0.898 |
| [0.001,0.003) | 1636 | 0.00195 | 0.00911 | 0.125 |
| [0.003,0.005) | 1310 | 0.00398 | 0.0861 | 9.03 |
| [0.005,0.0075) | 1401 | 0.00619 | 0.0416 | 2.30 |
| [0.0075,0.01) | 1144 | 0.00870 | 0.0774 | 6.56 |
| [0.01,0.0125) | 955 | 0.0112 | 0.0674 | 4.18 |
| [0.0125,0.015) | 902 | 0.0137 | 0.107 | 10.1 |
| [0.015,0.02) | 1488 | 0.0174 | 0.0751 | 8.16 |
| [0.02,0.025) | 1212 | 0.0224 | 0.113 | 15.1 |
| [0.025,0.03) | 951 | 0.0273 | 0.139 | 17.8 |
| all | 11934 | 0.0109 | 0.0724 | 58.8 |

CSV:
`runbooks/generated/wv_hmc_n6_sign_severity_20260531/flow_time_bin_sign_severity.csv`

## Readback

The low-flow validation window `[0.0001, 0.001]` is not a sensible endpoint for production T1 selection. It has low phase coherence, and the adjacent `[0.001, 0.003)` bin is even worse in this probe.

The higher-flow bins are visibly milder. The strongest endpoint evidence in this scan is near `t in [0.025, 0.03)`, where `C_bin = 0.139` with phase ESS `17.8`, compared with `C_bin = 0.0327` for `[0.0001,0.001)` and `0.00911` for `[0.001,0.003)`.

Interim endpoint implication: keep `T1 = 0.03` as the first WV-HMC high-flow endpoint candidate. The next production-level decision should not lower T1 based on low-flow observable correctness alone; it should require flow-time binned sign-severity and enough high-flow residence.

Remaining caveat: this is a 16 seed x 1000 cycle diagnostic with gamma 1.0, so it establishes the scale and direction of the sign-severity improvement, not a final precision estimate.
