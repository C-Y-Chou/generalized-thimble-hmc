# WV-HMC Positive-Target Invariant Gate

Status: `fail`

This gate compares Markov samples against the deterministic positive worldvolume target, not only against final physical observables.

## Setup

- run root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_positive_target_invariant_20260602/wv_hmc_positive_target_invariant_n2_t001_current_4597ced50bd8_20260602/sample`
- seeds: `64`
- samples: `116485`
- oracle GH/t orders: `3` / `5`
- target interval: `[0.0, 0.01]`
- W profile: `paper_wall`, gamma `0.0`
- oracle available slots: `30668`
- oracle unavailable slots: `2137`
- oracle missing slots allowed: `1`
- max pointwise ratio-direct relative error: `1.212e-19`

## Primary Gates

| metric | exact Re | estimate Re | SE Re | z Re | exact Im | estimate Im | SE Im | z Im | status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| positive.alpha2_mean | 5.9247928 | 6.3856927 | 0.443 | 1.04 | 0 | 0 | 0 | nan | pass |
| positive.alpha_mean | 1.6564815 | 1.8018272 | 0.0727 | 2 | 0 | 0 | 0 | nan | pass |
| positive.chiral_condensate.mean | 0.16891945 | 0.39916732 | 0.0183 | 12.6 | 4.0347663e-16 | 0.0082147527 | 0.0185 | 0.444 | fail |
| positive.flow_time_mean | 0.0047934261 | 0.004924276 | 3.71e-05 | 3.53 | 0 | 0 | 0 | nan | warn |
| positive.flow_time_second | 3.1363914e-05 | 3.2579022e-05 | 3.69e-07 | 3.29 | 0 | 0 | 0 | nan | warn |
| positive.number_density.mean | 0.45730564 | 0.25013822 | 0.0155 | -13.4 | -7.2493675e-16 | 0.013432292 | 0.0432 | 0.311 | fail |
| positive.x2_per_coord_mean | 0.33253928 | 0.3186816 | 0.0138 | -1 | 0 | 0 | 0 | nan | pass |
| ratio.chiral_condensate | 0.38619746 | 0.34432902 | 0.0282 | -1.48 | -1.3749505e-16 | -0.02533729 | 0.0124 | -2.05 | pass |
| ratio.number_density | 0.02603302 | 0.0248434 | 0.0324 | -0.0368 | -2.761366e-16 | 0.088347736 | 0.0463 | 1.91 | pass |

Artifacts:

- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_positive_target_invariant_20260602/wv_hmc_positive_target_invariant_n2_t001_current_4597ced50bd8_20260602/readback/positive_target_invariant_comparison.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_positive_target_invariant_20260602/wv_hmc_positive_target_invariant_n2_t001_current_4597ced50bd8_20260602/readback/positive_target_seed_aggregates.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_positive_target_invariant_20260602/wv_hmc_positive_target_invariant_n2_t001_current_4597ced50bd8_20260602/readback/positive_target_invariant_metadata.json`
