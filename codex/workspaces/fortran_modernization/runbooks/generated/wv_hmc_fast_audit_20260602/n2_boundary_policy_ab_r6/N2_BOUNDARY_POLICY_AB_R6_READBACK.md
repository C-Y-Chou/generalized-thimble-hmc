# N=2 Boundary Policy A/B R6

Same-seed A/B: `paper_full_flip` vs legacy `normal_reflect`. Seeds `9820001..9820032`; 3000 cycles per seed; `step_size=0.015`, `num_steps=3`; `T0=0.005`, `T1=0.2`; `W_PROFILE=paper_wall`, `gamma=1.0`; random Gaussian init. Exact chiral/density targets are the Stephanov n=2 values used by the WV-HMC readback script.

Build gate: WV-HMC math kernels PASS; constraint kernels PASS; deterministic boundary gates confirmed `paper_full_flip` and `normal_reflect` produce different boundary momentum rules.

## Policy Summary
| policy | seeds | cycles | measurements | phase C | transitions failed | reverse-gate rejected | runtime sum s |
|---|---:|---:|---:|---:|---:|---:|---:|
| paper_full_flip | 32 | 96000 | 78661 | 0.932105 | 2760 | 1442 | 1414.1 |
| normal_reflect | 32 | 96000 | 79340 | 0.931495 | 2842 | 1798 | 1362.4 |

## Observable Z
| policy | observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---|---:|---:|---:|---:|---:|---:|
| paper_full_flip | chiral_condensate | 0.358138992 | 0.0114 | -1.91427 | -0.0133566935 | 0.0143 | -0.93656 |
| paper_full_flip | logdet_dirac | 0.686400324 | 0.104 |  | 0.686292215 | 0.289 |  |
| paper_full_flip | min_singular_ba_m2 | 0.621125317 | 0.0243 |  | 0.0149757463 | 0.00867 |  |
| paper_full_flip | number_density | 0.0813453734 | 0.0253 | 1.68425 | 0.0583240363 | 0.0348 | 1.67815 |
| paper_full_flip | phase_factor | 0.765848108 | 0.024 |  | 0.0433418139 | 0.0265 |  |
| normal_reflect | chiral_condensate | 0.364736013 | 0.01 | -1.5291 | 0.0136355686 | 0.015 | 0.908781 |
| normal_reflect | logdet_dirac | 0.603098889 | 0.0933 |  | 0.811435043 | 0.252 |  |
| normal_reflect | min_singular_ba_m2 | 0.598068941 | 0.0224 |  | 0.00616456843 | 0.00477 |  |
| normal_reflect | number_density | 0.0777914799 | 0.0264 | 1.4812 | -0.0160754181 | 0.036 | -0.447013 |
| normal_reflect | phase_factor | 0.757646193 | 0.0253 |  | -0.000197242404 | 0.0272 |  |

## Paired Delta
Delta is `paper_full_flip - normal_reflect`, using matched-seed leave-one-seed jackknife.

| observable | delta Re | SE Re | z Re | delta Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | -0.00659702017 | 0.0112 | -0.588 | -0.0269922621 | 0.0164 | -1.65 |
| logdet_dirac | 0.0833014348 | 0.0788 | 1.06 | -0.125142828 | 0.228 | -0.548 |
| min_singular_ba_m2 | 0.0230563758 | 0.0242 | 0.954 | 0.00881117786 | 0.00997 | 0.883 |
| number_density | 0.00355389349 | 0.0197 | 0.18 | 0.0743994544 | 0.0378 | 1.97 |
| phase_factor | 0.00820191517 | 0.0174 | 0.472 | 0.0435390563 | 0.0272 | 1.6 |

Artifacts:
- `/Users/ccy/Documents/TLTM_fortran_modernization/codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_fast_audit_20260602/n2_boundary_policy_ab_r6/n2_boundary_policy_ab_r6_policy_summary.csv`
- `/Users/ccy/Documents/TLTM_fortran_modernization/codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_fast_audit_20260602/n2_boundary_policy_ab_r6/n2_boundary_policy_ab_r6_observable_z.csv`
- `/Users/ccy/Documents/TLTM_fortran_modernization/codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_fast_audit_20260602/n2_boundary_policy_ab_r6/n2_boundary_policy_ab_r6_paired_delta.csv`
- `/Users/ccy/Documents/TLTM_fortran_modernization/codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_fast_audit_20260602/n2_boundary_policy_ab_r6/n2_boundary_policy_ab_r6_seed_paired.csv`
