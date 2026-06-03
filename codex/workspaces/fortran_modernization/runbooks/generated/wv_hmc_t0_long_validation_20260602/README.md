# WV-HMC T0 Long Validation Readback

Current status packet:

- `FACT_DECISION_AND_WORKSPACE_STATUS_20260602.md`: settled fact, dataset
  routing, worktree state, and current progress.
- `current_status_20260602.json`: compact machine-readable version of the same
  status.
- `MEASUREMENT_FACTOR_CONVENTION_AUDIT.md`: phase / alpha / W(t) convention
  audit.
- `LONG_VALIDATION_WEIGHT_VARIANT_READBACK.md`: same-history offline
  measurement-factor variants on this old-boundary dataset.

Key settled fact:

- For this pinned old-boundary n=6 dataset and the broad measurement window
  `[0.025,0.03]`, replacing the current online weight
  `exp(W) * phase / alpha` with the paper-correct no-W offline weight
  `phase / alpha` still fails the observable gate:
  `max |z| = 3.176`, from chiral condensate Re.
- This does not validate or invalidate a future current-source production run
  after fixing the source/test convention.  This dataset predates the
  simplified-paper full-flip boundary-policy fix.

Run:

- Remote output: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601`
- Remote logs: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601`
- Jobs: `18680.anode01` to `18683.anode01`
- Queues/nodes: `C17`; `cnode37` for chunks 00-02 and `cnode38` for chunk 03
- Runtime: `25903.99` to `29419.10` seconds per chunk

Protocol:

- `gamma=65`, `epsilon=0.009`, `nstep=10`, `L=0.09`
- Sampler interval `[T0,T1]=[0,0.03]`
- Measurement interval `[0.025,0.03]`
- Measurement starts at cycle `1001`
- Requested cycles: `15000`
- Initial condition: current `t=0` state bank

Completion:

| item | value |
|---|---:|
| submitted seeds | 64 |
| completed summaries | 63 |
| observable histories | 64 |
| usable measurement histories | 63 |
| failed/no-measurement seed | `9630023` |
| seed `9630023` status | `return_code=4`, `measurement_included=0`, `measurement_skipped=15000` |
| snapshot files | 0 |

Note: cyclic snapshots were requested at submission time, but this runtime snapshot's PBS/runner did not expose snapshot fields in the boot log or manifest, and no snapshot files were produced. This run is usable for observable validation, not for rebuilding a cyclic snapshot bank.

Kernel Summary

| metric | value |
|---|---:|
| completed cycles | 945000 |
| accepted/cycle | 0.8057566 |
| transition failures/cycle | 0.1805397 |
| reverse-gate rejects/cycle | 0.0104317 |
| Metropolis rejects/cycle | 0.0032720 |
| ODE failures/cycle | 0.0501683 |
| measurement samples | 148397 |
| measurement samples/cycle | 0.1570339 |
| measurement histogram max/min ratio | 1.1718567 |
| full flow-time mean | 0.0184082 |
| full flow-time max | 0.03499998 |
| effective `x` jump squared mean | 0.0046575 |
| effective flow-time jump absolute mean | 0.0067993 |
| measurement samples/seed min/median/max | 2231 / 2359 / 2494 |

Observable Prefix Sweep

Seed-jackknife ratio estimates over the completed 63 seeds.

| prefix | samples | C | chiral Re z | chiral Im z | density Re z | density Im z |
|---:|---:|---:|---:|---:|---:|---:|
| 5000 | 42414 | 0.10942 | -1.461 | 1.016 | 0.963 | 0.305 |
| 7500 | 69132 | 0.10937 | -1.799 | -0.221 | 0.708 | 0.838 |
| 10000 | 95602 | 0.11234 | -3.040 | -0.876 | 1.053 | 1.252 |
| 12500 | 122445 | 0.11107 | -2.920 | -0.657 | 1.230 | 1.032 |
| 15000 | 148397 | 0.11038 | -3.198 | -0.954 | 1.370 | 1.475 |

Flow-Cut Results

All rows use the same completed 63 seeds and all available 15000-cycle histories.

| measurement cut | samples | C | chiral Re z | chiral Im z | density Re z | density Im z |
|---|---:|---:|---:|---:|---:|---:|
| `t >= 0.025` | 148397 | 0.11038 | -3.198 | -0.954 | 1.370 | 1.475 |
| `t >= 0.026` | 120396 | 0.11295 | -3.151 | -0.422 | 1.162 | 1.038 |
| `t >= 0.027` | 91389 | 0.11488 | -3.098 | 0.252 | 1.063 | 0.617 |
| `t >= 0.028` | 61745 | 0.11304 | -1.980 | 1.227 | 0.022 | -0.627 |
| `t >= 0.029` | 31157 | 0.11085 | -0.939 | 0.874 | -0.247 | 0.008 |

Readback

- The full requested measurement window `[0.025,0.03]` does not pass the observable gate: chiral Re remains about `-3.20 sigma`.
- Tightening the measurement window to the high-flow tail substantially improves the observable result. At `t >= 0.028`, density is essentially centered and chiral Re is borderline at about `-1.98 sigma`. At `t >= 0.029`, both chiral and density Re/Im are within `1 sigma`.
- The measurement histogram inside `[0.025,0.03]` is flat enough for this diagnostic (`max/min ~= 1.17`), so the remaining chiral issue is not simply a histogram flatness failure inside that interval.
- One seed never enters the measurement window. This is a high-flow visitation warning and should be treated separately from the 63-seed observable estimator.
- This run supports using a stricter high-flow measurement interval for the next validation, but it does not validate `[0.025,0.03]` as a production measurement window.

Artifacts:

- `wv_hmc_t0_retune_scan_summary.csv`
- `wv_hmc_t0_retune_scan_summary.md`
- `long_validation_prefix_sweep.csv`
- `long_validation_flow_cuts.csv`
- `long_validation_prefix_flow_cut_grid.csv`
