# WV-HMC n=2 T1=0.01 Clean Validation

Date: 2026-06-02

Scope: Stephanov n=2, WV-HMC dense explicit-J kernel, `paper_full_flip`,
`T0=0`, `T1=0.01`, `gamma=0`, `epsilon=0.003`, `nstep=20`.

Source pin:

- `4597ced50bd8-dee0602a51c0`
- runtime snapshot:
  `/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n2_t001_fullflip_clean_20260602`

## Build Gate

Build/test job:

- `18744.anode01`
- queue/node: `C17 / cnode37`
- result: exit `0`

Deterministic gates passed, including:

- `wv_boundary_paper_full_flip ok=T`
- `wv_boundary_normal_reflect_policy ok=T`
- trajectory reversibility / energy-order checks
- dense chain driver check
- nonzero-W transition and measurement-factor checks

## Random-Start Diagnostic

Run:

- remote root:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_g0_e003n20_128x5000_r2_20260602`
- jobs: `18745.anode01` through `18752.anode01`, top-up `18753.anode01`
- valid estimator input: 128 valid seeds
- startup failures excluded from estimator: seeds `9900011`, `9900029`

All-cycle random-start estimator did not pass cleanly:

| cut | chiral z Re | chiral z Im | density z Re | density z Im |
|---|---:|---:|---:|---:|
| all | -2.389 | 0.955 | 2.699 | -0.949 |
| first half | -3.388 | 1.942 | 3.743 | -2.401 |
| second half | -0.431 | -0.388 | 0.488 | 0.718 |

Interpretation for this run: the failure is consistent with random-Gaussian
initial transient, not flow-bin-specific bias. The second half is already
consistent with exact values, and all flow bins show the same early bias
direction.

## Bank-Init Clean Validation

State bank:

- built from 128 valid final states of the random-start run
- path:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/state_bank_from_t001_late_final_20260602/state_bank_t001_final128.bin`

Run:

- remote root:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/wv_hmc_n2_t001_fullflip_bankinit_g0_e003n20_128x3000_20260602`
- jobs: `18754.anode01` through `18761.anode01`
- all jobs exit `0`
- 128 summary/observable/history files present

Run diagnostics:

| item | value |
|---|---:|
| cycles | 384000 |
| measurements | 353362 |
| acceptance including rejects | 0.220214 |
| phase coherence | 0.873408 |
| chain flow histogram max/min | 1.23756 |
| measurement flow histogram max/min | 1.23741 |
| effective x jump sq / cycle | 7.7269e-4 |
| effective z jump sq / cycle | 7.7829e-4 |

All-cut seed-jackknife observable gate:

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.372967 | 0.01468 | -0.482 | -0.008609 | 0.00725 | -1.188 |
| number_density | 0.040782 | 0.02000 | 0.103 | 0.038050 | 0.02399 | 1.586 |

Prefix stability:

| prefix | chiral z Re | chiral z Im | density z Re | density z Im |
|---:|---:|---:|---:|---:|
| 500 | -0.490 | -0.652 | -0.423 | 1.287 |
| 1000 | -0.311 | -1.247 | -0.723 | 1.829 |
| 1500 | -0.605 | -0.842 | -0.338 | 1.391 |
| 2000 | -0.609 | -0.679 | -0.145 | 1.218 |
| 3000 | -0.482 | -1.188 | 0.103 | 1.586 |

Flow-bin check:

| flow bin | chiral z Re | chiral z Im | density z Re | density z Im |
|---|---:|---:|---:|---:|
| [0, 0.0025) | -0.474 | -0.924 | 0.257 | 1.397 |
| [0.0025, 0.005) | -0.591 | -1.249 | -0.048 | 1.574 |
| [0.005, 0.0075) | -0.559 | -1.269 | 0.266 | 1.657 |
| [0.0075, 0.01] | -0.233 | -1.136 | -0.063 | 1.522 |

## Conclusion

For Stephanov n=2 at `T1=0.01`, the current dense WV-HMC full-flip kernel
passes the clean observable gate when initialized from a valid WV state bank.

The random-Gaussian run is not a clean correctness failure of the kernel; it
shows an initial-transient/startup-quality problem. For future WV-HMC
validation and production, use a staged bank-building workflow rather than
judging the kernel from random-Gaussian starts.

Artifacts:

- `bankinit_readback/`
- `randomstart_valid128_readback/`
- `bankinit_submitted_jobs.tsv`
- `randomstart_submitted_jobs.tsv`
