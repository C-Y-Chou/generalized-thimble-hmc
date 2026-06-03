# WV-HMC Small-T1 Gamma Check After Epsilon Retune

Date: 2026-05-30

Scope: Stephanov n=2 WV-HMC, small flow-time window.

Fixed settings:

- `T0 = 1.0e-4`
- `T1 = 1.0e-3`
- `d0 = 1.0e-4`
- `d1 = 2.5e-4`
- initial flow time `5.5e-4`
- `epsilon = 5.0e-4`
- `nstep = 20`
- `W(t) = -gamma * (t - T0)` with paper-wall tails
- random Gaussian initialization
- cluster-only runs through `cluster02_qsub_gate.sh`

The preceding invalid scan that increased `epsilon` while every step was wall-dominated was cancelled and should not be used.

## Focused Confirmation

Run root:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_small_t1_gamma_confirm_e0005_*_n2_64x3000_20260530`

| gamma | seeds | acc | bounce | eff_x_jump_sq | eff_t_jump_abs | flow_adj | flow_max_min | flow_low | flow_high | meas_adj | meas_max_min | C | chiral_z_re | density_z_re |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 63 | 0.9442 | 0.4237 | 1.566e-05 | 1.984e-04 | 0.00189 | 1.150 | 10527 | 33329 | 0.00255 | 1.168 | 0.9417 | -11.84 | 7.19 |
| 50 | 63 | 0.9459 | 0.3781 | 2.103e-05 | 2.145e-04 | 0.00204 | 1.139 | 10422 | 33491 | 0.00340 | 1.218 | 0.9478 | -6.83 | 6.34 |
| 100 | 63 | 0.9470 | 0.3214 | 2.622e-05 | 2.339e-04 | 0.00249 | 1.164 | 10967 | 33687 | 0.00501 | 1.226 | 0.9293 | -3.34 | 4.55 |
| 250 | 63 | 0.9449 | 0.3878 | 1.662e-05 | 1.859e-04 | 0.00148 | 1.266 | 9260 | 40032 | 0.00216 | 1.298 | 0.9237 | -8.70 | 4.60 |
| 500 | 64 | 0.9458 | 0.3924 | 1.571e-05 | 1.729e-04 | 0.02242 | 2.012 | 7961 | 40695 | 0.02249 | 2.084 | 0.9472 | -8.34 | 6.47 |

## Result

At the retuned step scale, `gamma = 0` is not strictly best by every flatness metric:

- `gamma = 250` has the smallest adjacent-bin roughness.
- `gamma = 0` has the best max/min histogram ratio and less high-flow tail pileup.
- `gamma = 500` is clearly too tilted.

Current conservative default:

- keep `gamma = 0` as the robust paper-wall default;
- keep `gamma = 250` as a nearby comparison candidate if a later criterion prioritizes adjacent-bin roughness over tail balance.

Observable z-scores are not yet acceptable in this short random-start scan, so this run is not a WV-HMC correctness validation.
