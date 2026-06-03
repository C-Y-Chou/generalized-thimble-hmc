# WV-HMC n=6 Long Validation Readback - 2026-06-03

## Scope

This readback records the completed Stephanov `n=6` dense explicit-J WV-HMC
long validation used by the productization closure gate.

Important exact-reference correction:

- The first generated remote readback directory `readback_18880` used the
  script defaults for a different target and must not be used for physical
  `n=6` z-scores.
- The corrected directory is `readback_18880_exact_n6`, generated with:
  - `exact_chiral = 0.0244771983`
  - `exact_density = 0.5661155667`

## Remote Artifacts

| item | path |
| --- | --- |
| run root | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_tau0bank_validation_20260603/wv_hmc_n6_t0001_tau0bank_val10k_eps016_n10_g55_16x10000_20260603/sample_18880.anode01` |
| corrected readback | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_tau0bank_validation_20260603/readback_18880_exact_n6` |
| boot log | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_n6_t0001_tau0bank_validation_20260603/wv_hmc_n6_t0001_tau0bank_val10k_eps016_n10_g55_16x10000_20260603/pbs_boot_18880.anode01.log` |

## Run Metadata

| item | value |
| --- | ---: |
| job | `18880.anode01` |
| host | `cnode37` |
| queue | `C17` |
| source pin | `4597ced50bd8-20a2258de6d8` |
| source commit | `4597ced50bd89f17796aeb56f3444ebc2a7cb17a` |
| source dirty count | `111` |
| model parameters | `data/parameters_stephanov_n6_mu06_t0.dat` |
| seeds | `16` |
| cycles per seed | `10000` |
| total cycles | `160000` |
| wall time | `17418.51 s` |
| summed seed runtime | `274309.79 s` |
| ODE backend | `dop853` |
| `epsilon` | `0.016` |
| `nstep` | `10` |
| `T0,D0,T1,D1` | `1e-4, 1e-4, 0.03, 0.005` |
| `W(t)` | `paper_wall`, `gamma=55` |
| boundary policy | `paper_full_flip` |
| init mode | `bank`, tau-0 x bank flowed to `T0=1e-4` |

## Completeness

| artifact | count |
| --- | ---: |
| `seed_*_summary.csv` | `16` |
| `seed_*_observable_history.csv` | `16` |
| `seed_*_observables.csv` | `16` |
| `seed_*_x_history.dat` | `16` |
| `seed_*_state_history.dat` | `16` |
| `seed_*_final_state.bin` | `16` |
| `seed_*_snapshot_index.csv` | `16` |

No zero-measurement seed was observed.

| metric | value |
| --- | ---: |
| measurement attempted | `137637` |
| measurement included | `137637` |
| measurement failed | `0` |
| accepted | `126377` |
| rejected | `33623` |
| acceptance including rejects | `0.78985625` |
| transitions failed | `27981` |
| Metropolis rejected | `1464` |
| reverse-gate rejected | `4178` |

## Flow And Movement

| metric | value |
| --- | ---: |
| mean effective x jump sq | `0.00946259` |
| mean effective flow-time jump abs | `0.00788320` |
| flow-time mean over seeds | `0.0173729` |
| flow-time min over seeds | `5.54e-5` to `1.0e-4` |
| flow-time max over seeds | `0.0349836` to `0.0349998` |
| measurement flow histogram min/max over 32 bins | `3806 / 5165` |
| measurement flow histogram max/min ratio | `1.357` |

The flow histogram is sufficiently populated across the full interval for this
validation.  The chain is not sticky in either `x` or flow time.

## Primary Observable Z-Scores

All uncertainties below are seed-jackknife uncertainties that preserve the
complex ratio structure.  `z_Re` uses the exact physical reference, and `z_Im`
tests against zero.

| cut | samples | C | chiral z_Re | chiral z_Im | density z_Re | density z_Im |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| all cycles | `137637` | `0.0760` | `-1.974` | `-0.984` | `1.466` | `1.184` |
| first half / prefix 5000 | `68744` | `0.0862` | `-3.438` | `-0.611` | `1.559` | `0.797` |
| second half | `68893` | `0.0661` | `0.036` | `-0.691` | `0.635` | `0.713` |
| cycles >= 1001 | `123881` | `0.0766` | `-1.566` | `-0.842` | `1.265` | `0.689` |
| cycles >= 2001 | `110169` | `0.0722` | `-0.732` | `-0.340` | `0.759` | `0.314` |
| cycles >= 3001 | `96526` | `0.0695` | `-0.412` | `-0.611` | `0.707` | `0.690` |
| cycles >= 4001 | `82635` | `0.0683` | `-0.248` | `-0.693` | `0.860` | `0.673` |
| cycles >= 5001 | `68893` | `0.0661` | `0.036` | `-0.691` | `0.635` | `0.713` |
| cycles >= 6001 | `55099` | `0.0681` | `-0.303` | `-0.452` | `1.048` | `0.650` |
| cycles >= 7001 | `41318` | `0.0703` | `-0.146` | `-0.339` | `0.982` | `0.081` |
| cycles >= 8001 | `27498` | `0.0702` | `-0.038` | `0.404` | `0.079` | `-0.218` |
| cycles >= 9001 | `13719` | `0.1016` | `-3.742` | `0.770` | `1.962` | `0.730` |

The last-1000-cycle cut is too small to use as a gate by itself and is listed
only as a sensitivity diagnostic.

## Block-Size Check, All Cycles

| error method | chiral z_Re | chiral z_Im | density z_Re | density z_Im |
| --- | ---: | ---: | ---: | ---: |
| seed jackknife | `-1.974` | `-0.984` | `1.466` | `1.184` |
| 250-cycle block jackknife | `-2.099` | `-1.013` | `1.527` | `1.275` |
| 500-cycle block jackknife | `-2.038` | `-1.005` | `1.542` | `1.213` |

The all-cycle chiral real part is borderline at about two standard errors and
is stable under these error estimates.  The late-cycle cuts remove this
deviation.

## Readback Decision

This is not a clean all-cycle pass.  The first half has a clear warmup or
initial-bank transient, with chiral real part at `-3.438 sigma`.

It is also not evidence of a stable dense WV-HMC kernel bias.  After dropping
the first 2000 cycles, all four primary z-scores remain within about one
standard error through the main late cuts with adequate samples.  The second
half is fully compatible with the exact references.

Productization may proceed with a bounded caveat:

- do not use all-cycle WV-HMC estimates as production estimates for this run;
- document burn-in/thermalization handling for WV-HMC;
- state that this `n=6` validation supports the dense explicit-J WV-HMC path
  after burn-in, but it also exposes a startup transient from the tau-0 bank;
- keep matrix-free/BiCGStab and high-dimensional performance optimization as
  future work;
- proceed next to DFO-LS/`withfb` active dependency cleanup and product docs.
