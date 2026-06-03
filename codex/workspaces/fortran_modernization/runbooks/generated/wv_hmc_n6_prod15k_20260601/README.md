# WV-HMC N6 t=0.03 15k Streaming Readback

Root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_production_20260601/wv_hmc_n6_t003_prod768x15000_gitless_r3_20260601`

## Diagnostics

| item | value |
|---|---:|
| history_files | 768 |
| summary_rows | 768 |
| manifest_rows | 768 |
| cycles_completed | 11520000 |
| measurement_included | 10473014 |
| acceptance_rate | 0.9079403645833334 |
| transitions_failed_per_cycle | 0.06146623263888889 |
| reverse_gate_failed_per_checked | 0.014924006482111531 |
| odex_failure_per_call | 0.0003454880875849557 |
| runtime_sec_median_seed | 19587.768317461014 |
| runtime_sec_max_seed | 30249.91617655754 |
| seed_node_hours_sum | 4183.724500122733 |

## All Seed Jackknife

| observable | Re | SE Re | z Re | Im | SE Im | z Im | phase C | samples |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.0225948 | 0.000378487 | -4.97345 | -8.46883e-05 | 0.00032938 | -0.257114 | 0.0683277 | 10473014 |
| number_density | 0.579107 | 0.0132486 | 0.980593 | 0.0108503 | 0.01518 | 0.714779 | 0.0683277 | 10473014 |
| logdet_dirac | -1.1093 | 0.0521489 |  | 1.53487 | 0.0535023 |  | 0.0683277 | 10473014 |
| phase_factor | 0.144381 | 0.00785234 |  | -0.0158401 | 0.00738104 |  | 0.0683277 | 10473014 |
| min_singular_ba_m2 | 0.131693 | 0.000656568 |  | 0.000477697 | 0.000647127 |  | 0.0683277 | 10473014 |

## Exact-Reference Prefix Z

| cut | chiral Re z | chiral Im z | density Re z | density Im z | phase C | samples |
|---|---:|---:|---:|---:|---:|---:|
| prefix_5000 | -2.04148 | 0.171549 | -0.33987 | 0.397964 | 0.0679762 | 3249184 |
| prefix_10000 | -4.33614 | -0.9316 | 1.39408 | 1.66468 | 0.068817 | 6859557 |
| prefix_15000 | -4.97345 | -0.257114 | 0.980593 | 0.714779 | 0.0683277 | 10473014 |
| first_half | -2.79646 | -0.461349 | 0.011438 | 1.02032 | 0.0679076 | 5052063 |
| second_half | -4.33324 | 0.0916268 | 1.33921 | -0.0316205 | 0.0687201 | 5420951 |
| all | -4.97345 | -0.257114 | 0.980593 | 0.714779 | 0.0683277 | 10473014 |

Artifacts:
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_production_20260601/wv_hmc_n6_t003_prod768x15000_gitless_r3_20260601/readback_streaming_n6_15k_20260601/estimator_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_production_20260601/wv_hmc_n6_t003_prod768x15000_gitless_r3_20260601/readback_streaming_n6_15k_20260601/seed_summary.csv`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_production_20260601/wv_hmc_n6_t003_prod768x15000_gitless_r3_20260601/readback_streaming_n6_15k_20260601/run_diagnostics.json`
