# WV-HMC Newton Trace Analysis

Run root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_large_residual_trace_off_statebank_8x100_20260531/chunks/chunk_00_18421.anode01`

This is a calibration aid only.  Newton fail-fast thresholds must be recalibrated per model, parameter set, `W(t)`, HMC trajectory setting, DOP853 policy, and initial-bank distribution.

| label | cycles | solves | conv | boundary | max_iter | conv rate | resolved rate | conv iter q50/q90/max | init res q50 | final res q50 | best/init q50 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| seed_8971101 | 100 | 1559 | 1497 | 58 | 1 | 0.96023091725465037 | 0.99743425272610653 | 7/12/76 | 0.084798211011720054 | 3.5365331079433743e-11 | 4.1932368331739865e-10 |
| seed_8971102 | 100 | 1522 | 1464 | 49 | 1 | 0.96189224704336396 | 0.9940867279894875 | 9/17/146 | 0.084888825601537737 | 4.2192190961861141e-11 | 4.9296985929516561e-10 |
| seed_8971103 | 100 | 1542 | 1483 | 52 | 1 | 0.96173800259403375 | 0.99546044098573283 | 9/13/85 | 0.083832785754378344 | 3.9924276911607308e-11 | 4.7618661559684111e-10 |
| seed_8971104 | 100 | 1553 | 1501 | 48 | 1 | 0.96651641983258207 | 0.99742433998712166 | 8/13/120 | 0.085687278331992023 | 3.5090902428585807e-11 | 4.2064367494264323e-10 |
| seed_8971105 | 100 | 1564 | 1491 | 69 | 1 | 0.95332480818414322 | 0.99744245524296671 | 8/12/52 | 0.085217949724258918 | 3.5308079426481207e-11 | 4.1801141538468333e-10 |
| seed_8971106 | 100 | 1552 | 1486 | 62 | 1 | 0.95747422680412375 | 0.99742268041237114 | 8/12/176 | 0.085683866919508161 | 3.380443816578311e-11 | 3.963353931729288e-10 |
| seed_8971107 | 100 | 1536 | 1470 | 60 | 1 | 0.95703125 | 0.99609375 | 8/13/110 | 0.085990468403863263 | 3.3624378173851215e-11 | 3.899735022519735e-10 |
| seed_8971108 | 100 | 1519 | 1462 | 47 | 0 | 0.9624753127057275 | 0.99341672152732063 | 8/14/180 | 0.084841042187491597 | 3.6285848842539682e-11 | 4.2166138437399394e-10 |

Artifacts:
- `wv_newton_trace_candidate_summary.csv`
- `wv_newton_trace_solve_summary.csv`
- `wv_newton_trace_iteration_summary.csv`
- `wv_newton_trace_availability.json`

Calibration rule: do not enable adaptive Newton stop from this table alone.  First check that eventually convergent solves would not be rejected by the proposed cutoff, then rerun the same candidate with the candidate cutoff enabled and verify transition/observable diagnostics are unchanged except for intended fail-fast cost reduction.
