# F20c NT/QN/DFO-LS Tolerance Scan Readback

Date: 2026-05-19 JST

Canonical workspace: `/Users/ccy/Documents/TLTM_qn_error_handling`

Remote workspace:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`

Scheduler request: `FMOD-F20C-R2-NTQN-DFOLS-SCAN-20260519`

Source commit: `748bffa75afff491fadabf3e6fd3a39cb5054921`

Scheduler submission commit:
`112173a3d063f4d7f3b6b3f790d722603a004d3d`

Scheduler cancellation-state commit:
`e8427dd6874a8255cdddd283820a427bc8aa6b62`

## Scope

This is Stage B of the F20 double-only tolerance calibration:

- scale: 10 seeds x 10000 cycles
- methods: `no_fb`, `fb_norefine`
- ODE abs/rel fixed at `1e-12`
- reverse gate fixed at `1e-8`
- shared residual profiles for NT, QN, and official DFO-LS:
  - `tau_1e12`: constraint/QN `1e-12`, DFO-LS `rhoend=1e-15`,
    `model_abs=1e-24`, `model_rel=0`
  - `tau_1e10`: constraint/QN `1e-10`, DFO-LS `rhoend=1e-13`,
    `model_abs=1e-20`, `model_rel=0`
  - `tau_1e8`: constraint/QN `1e-8`, DFO-LS `rhoend=1e-11`,
    `model_abs=1e-16`, `model_rel=0`
- comparison baseline:
  `output/tests/f20_double_tolerance_calibration/f20b_ode_absrel1e12_strict_newton_r2_10seed_10k_bc3add0fe8e7`
- parent did readiness, dry-run, request-row, and readback only; scheduler did
  the real PBS submission and the later `tau_1e8` cancellation.

## Submission

Dry-run artifacts:

- manifest:
  `output/logs/f20_double_tolerance_calibration/f20c_ode1e12_ntqn_dfols_tau1e8_r2_10seed_10k_748bffa75aff/submit/submit_manifest_20260519T201604.env`
- queue plan:
  `output/logs/f20_double_tolerance_calibration/f20c_ode1e12_ntqn_dfols_tau1e8_r2_10seed_10k_748bffa75aff/submit/submit_queue_plan_20260519T201604.json`

Real scheduler artifacts:

- manifest:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20_double_tolerance_calibration/f20c_ode1e12_ntqn_dfols_tau1e8_r2_10seed_10k_748bffa75aff/submit/submit_manifest_20260519T201950.env`
- queue plan:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20_double_tolerance_calibration/f20c_ode1e12_ntqn_dfols_tau1e8_r2_10seed_10k_748bffa75aff/submit/submit_queue_plan_20260519T201950.json`

Job layout:

| job | id | queue | result |
|---|---:|---|---|
| build | 16107 | C16 | exit 0, walltime 00:01:59 |
| tau_1e12 no_fb | 16108 | F | exit 0, walltime 00:06:42 |
| tau_1e12 fb_norefine | 16109 | F | exit 0, walltime 00:11:07 |
| tau_1e10 no_fb | 16110 | F | exit 0, walltime 00:06:07 |
| tau_1e10 fb_norefine | 16111 | F | exit 0, walltime 00:08:45 |
| tau_1e8 no_fb | 16112 | F | exit 0, walltime 00:01:49 |
| tau_1e8 fb_norefine | 16113 | F | cancelled after tau_1e8 no_fb invalid readback |
| tau_1e12 merge | 16114 | C12 | exit 0, walltime 00:00:01 |
| tau_1e10 merge | 16115 | C12 | exit 0, walltime 00:00:01 |
| tau_1e8 merge | 16116 | C12 | cancelled by dependency/cancel cascade |

Preflight:

- latest preflight log:
  `output/logs/fortran_modernization/reference_datasets/preflight/m6_reference_preflight_build.20260519T201952.log`
- M4 guardrails passed.
- No `Python.h`, `pyconfig`, traceback, `ModuleNotFoundError`, fatal
  libpython, or `[ERROR]` pattern was found in the preflight/build logs.

## Baseline

The baseline is F20b ODE `1e-12` with strict Newton/QN/DFO-LS settings.

| profile | method | rows | audit | mean Re | seed std Re | err Re | Zmean Re | mean Im | seed std Im | err Im | Zmean Im | P68 | P95 | runtime s |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | no_fb | 10 | pass | 0.0045545985 | 0.1829179465 | 0.1609437410 | 0.0787397049 | -0.0311215937 | 0.1383458633 | 0.1027511011 | -0.7113701712 | 0.1 | 1.0 | 397.593826 |
| baseline | fb_norefine | 10 | pass | 0.0003712651 | 0.1748975144 | 0.1371778260 | 0.0067127509 | -0.0215840963 | 0.1082975525 | 0.0945038807 | -0.6302534436 | 0.4 | 0.6 | 708.810178 |

| profile | method | ODEX calls | accepted | rejected | RHS evals | RG candidates | RG rejects | unresolved | projection mean | NT successes | QN successes |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | no_fb | 60,491,404 | 310,069,564 | 10,395,180 | 8,747,505,581 | 3,925,757 | 1,022 | 8,249 | 927.1 | 52,532,072 | 0 |
| baseline | fb_norefine | 64,112,868 | 341,127,250 | 13,530,393 | 10,192,729,211 | 3,991,829 | 1,896 | 1,561 | 345.7 | 54,537,860 | 1,476,921 |

## Candidate Readback

| profile | method | rows | audit | mean Re | seed std Re | err Re | Zmean Re | mean Im | seed std Im | err Im | Zmean Im | P68 | P95 | runtime s |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| tau_1e12 | no_fb | 10 | pass | 0.0043603383 | 0.1829213859 | 0.1609014905 | 0.0753799259 | -0.0309411289 | 0.1387434820 | 0.1026891785 | -0.7052182862 | 0.1 | 1.0 | 372.723410 |
| tau_1e12 | fb_norefine | 10 | pass | 0.0027836690 | 0.1724271573 | 0.1368127370 | 0.0510519010 | -0.0224644518 | 0.1107830477 | 0.0943972609 | -0.6412428220 | 0.4 | 0.6 | 623.046945 |
| tau_1e10 | no_fb | 10 | pass | -0.0127872670 | 0.2068340274 | 0.1576799344 | -0.1955040435 | -0.0272033387 | 0.1435571160 | 0.1017558054 | -0.5992354312 | 0.1 | 0.9 | 326.537780 |
| tau_1e10 | fb_norefine | 10 | pass | 0.0193803163 | 0.1748564673 | 0.1425211997 | 0.3504928493 | -0.0072799037 | 0.1119486035 | 0.0981098486 | -0.2056396956 | 0.3 | 0.8 | 488.395315 |
| tau_1e8 | no_fb | 10 | pass | 0.2300834636 | 0.5660501368 | 0.2900093552 | 1.2853769473 | 0.1972655770 | 0.3858882469 | 0.2762759172 | 1.6165522849 | 0.3 | 0.8 | 69.893340 |

| profile | method | ODEX calls | accepted | rejected | RHS evals | RG candidates | RG rejects | unresolved | projection mean | NT successes | QN successes |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| tau_1e12 | no_fb | 56,369,299 | 288,878,619 | 9,676,403 | 8,151,530,474 | 3,925,775 | 1,020 | 8,250 | 927.0 | 48,409,927 | 0 |
| tau_1e12 | fb_norefine | 59,660,785 | 316,730,073 | 12,493,770 | 9,422,056,112 | 3,992,119 | 1,848 | 1,578 | 342.6 | 50,305,776 | 1,256,296 |
| tau_1e10 | no_fb | 48,930,883 | 251,628,695 | 8,826,392 | 7,141,605,768 | 4,062,175 | 3,125 | 7,818 | 891.5 | 40,694,088 | 0 |
| tau_1e10 | fb_norefine | 51,482,800 | 274,151,424 | 11,361,259 | 8,194,164,048 | 4,114,344 | 5,002 | 1,513 | 448.7 | 42,137,492 | 997,799 |
| tau_1e8 | no_fb | 13,495,561 | 63,890,672 | 1,588,002 | 1,539,182,578 | 1,640,755 | 175,887 | 587 | 17,350.8 | 10,106,006 | 0 |

`tau_1e8/fb_norefine` was cancelled after the completed `tau_1e8/no_fb`
readback showed the profile was already invalid.

## Paired Comparison Against Baseline

| profile | method | paired seeds | d mean Re | SE dRe | z dRe | max abs dRe | d mean Im | SE dIm | z dIm | max abs dIm | d failures | d RG rejects/seed |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| tau_1e12 | no_fb | 10 | -0.0001942602 | 0.0001386328 | -1.4012569152 | 0.0013031403 | 0.0001804648 | 0.0002692219 | 0.6703200957 | 0.0025179564 | 0.1 | -0.4 |
| tau_1e12 | fb_norefine | 10 | 0.0024124038 | 0.0040074636 | 0.6019777181 | 0.0229639686 | -0.0008803556 | 0.0018660451 | -0.4717761456 | 0.0136799943 | 1.7 | -9.6 |
| tau_1e10 | no_fb | 10 | -0.0173418655 | 0.0239574634 | -0.7238606702 | 0.1720364258 | 0.0039182550 | 0.0050512860 | 0.7756945449 | 0.0275494328 | -43.1 | 420.6 |
| tau_1e10 | fb_norefine | 10 | 0.0190090512 | 0.0197478051 | 0.9625905833 | 0.1008585005 | 0.0143041926 | 0.0164239995 | 0.8709323552 | 0.1464280172 | -4.8 | 621.2 |

Runtime deltas against baseline:

| profile | method | baseline runtime s | candidate runtime s | delta s | speedup |
|---|---|---:|---:|---:|---:|
| tau_1e12 | no_fb | 397.593826 | 372.723410 | -24.870416 | 6.3% |
| tau_1e12 | fb_norefine | 708.810178 | 623.046945 | -85.763233 | 12.1% |
| tau_1e10 | no_fb | 397.593826 | 326.537780 | -71.056046 | 17.9% |
| tau_1e10 | fb_norefine | 708.810178 | 488.395315 | -220.414863 | 31.1% |

## Interpretation

`tau_1e8` is rejected:

- it is fast only because it is no longer solving the same reliable numerical
  problem;
- `no_fb` projection failures jump to a mean of `17350.8`;
- reverse-gate rejects jump to `175887`;
- observable means visibly drift to `Re=0.2300834636` and `Im=0.1972655770`;
- the `fb_norefine` tail was not worth spending queue time on after this
  readback.

`tau_1e12` is the conservative clean candidate:

- both methods passed 10-row readback and protocol audit;
- runtime improves modestly relative to the F20b ODE `1e-12` strict-NT/QN
  baseline;
- paired observable drift is tiny;
- reverse-gate and projection diagnostics remain essentially unchanged.

`tau_1e10` is the selected performance candidate for the next scale-up:

- both methods passed 10-row readback and protocol audit;
- runtime improves by about 18% for `no_fb` and 31% for `fb_norefine`;
- paired observable drift stays below 1 sigma in both methods and both real and
  imaginary parts at 10seed x 10k;
- reverse-gate rejects increase from `1022` to `3125` in `no_fb`, and from
  `1896` to `5002` in `fb_norefine`;
- `fb_norefine` projection mean increases from `345.7` to `448.7`.

The diagnostic increase means `tau_1e10` is not yet a final production default,
but it is the strongest current double-precision tolerance candidate. It should
be verified at a larger scale before promotion.

## Decision

Close single precision for this route. Use double precision only.

Recommended next candidate:

- `TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-12`
- `TLTM_STAGE2_REL_TOL_OVERRIDE=1e-12`
- `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-10`
- `QN_QUASI_TOL_OVERRIDE=1e-10`
- `QN_REVERSE_GATE_TOL=1e-8`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-13`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-20`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`

Fallback conservative candidate:

- same ODE and reverse-gate settings, but constraint/QN `1e-12`,
  DFO-LS `rhoend=1e-15`, `model_abs=1e-24`, `model_rel=0`.

Rejected:

- single precision as an active optimization direction;
- `single_feasible1e6_rg1e4`;
- ODE or NT/QN shared tolerance `1e-8` for the current route;
- reverse gate `1e-4` as part of this tolerance search.

Next scale recommendation: run the `tau_1e10` double candidate at larger scale
against the strict double/current accepted reference, preserving method-by-method
readback of observables, protocol audit, ODEX counters, RG rejects, projection
failures, and runtime.
