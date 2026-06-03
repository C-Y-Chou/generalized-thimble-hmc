# WV-HMC n=6 Low-Flow Validation Readback

Date: 2026-05-31

Run: `wv_hmc_n6_zonly_lowflow_validation_32x3000_20260531`

Output root:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_validation_20260531/wv_hmc_n6_zonly_lowflow_validation_32x3000_20260531`

Jobs: `18357.anode01`, `18358.anode01`, `18359.anode01`, `18360.anode01`

## Settings

| field | value |
|---|---:|
| seeds | 32 |
| cycles per seed | 3000 |
| measurement start | 501 |
| step size | 0.010 |
| nstep | 8 |
| sampler T0 | 0.0001 |
| sampler T1 | 0.001 |
| D0 | 0.0001 |
| D1 | 0.00025 |
| initial flow time | 0.00055 |
| W profile | paper_wall |
| gamma | 0.2 |
| constraint tol | 1e-10 |
| constraint max iter | 24 |
| init | t=0.0001 bank |

## Completion

| item | value |
|---|---:|
| manifests | 4/4 |
| seed summaries | 32/32 |
| return codes | all 0 |
| timed out | 0 |
| total included measurements | 61668 |
| total attempted measurements | 61668 |

## Runtime And Transition Diagnostics

| metric | min | median | max |
|---|---:|---:|---:|
| runtime sec / seed | 920.225 | 1052.976 | 1102.342 |
| sec / cycle / seed | 0.307 | 0.351 | 0.367 |
| accepted / cycle | 0.735 | 0.831 | 0.885 |
| transition failure / cycle | 0.0137 | 0.0267 | 0.1113 |
| reverse gate rejected / cycle | 0.0573 | 0.0873 | 0.1030 |
| Metropolis rejected / cycle | 0.0420 | 0.0553 | 0.0613 |
| ODE calls / cycle | 105.173 | 111.209 | 114.001 |
| solver iter / cycle | 14.992 | 19.507 | 21.629 |
| reverse solver iter / cycle | 15.245 | 19.850 | 22.134 |
| trajectory steps / cycle | 7.205 | 7.842 | 7.923 |
| reverse trajectory steps / cycle | 6.970 | 7.689 | 7.850 |
| bounced steps / cycle | 4.627 | 5.096 | 5.800 |

## Ratio Estimator Summary

| metric | value |
|---|---:|
| phase coherence | 0.0397618 |
| abs denominator | 296.660 |
| arg denominator | 0.293294 |
| sum abs weight | 7460.921 |

Seed jackknife preserves the complex ratio structure.

Exact references:

| observable | exact Re target | exact Im target |
|---|---:|---:|
| chiral_condensate | 0.0244771983 | 0 |
| number_density | 0.5661155667 | 0 |

| observable | Re estimate | Re SE | Re z | Im estimate | Im SE | Im z |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.0205506 | 0.0111107 | -0.353 | -0.00663785 | 0.0103059 | -0.644 |
| number_density | 0.655590 | 0.364024 | 0.246 | 0.235369 | 0.382905 | 0.615 |

## Other Observable Estimates

| observable | Re estimate | Re SE | Im estimate | Im SE |
|---|---:|---:|---:|---:|
| logdet_dirac | -1.17225 | 2.92153 | -2.04517 | 2.76478 |
| phase_factor | 0.339571 | 0.351565 | -0.400292 | 0.432657 |
| min_singular_ba_m2 | 0.172062 | 0.0375681 | 0.0147131 | 0.0221504 |

## Validation Status

The four primary exact-reference z scores are all below 1 in magnitude for this 32 seed x 3000 cycle validation run.

This validates the corrected low-flow dense WV-HMC kernel at the current smoke/provisional scale. It does not replace later production-scale validation or matrix-free trajectory validation.
