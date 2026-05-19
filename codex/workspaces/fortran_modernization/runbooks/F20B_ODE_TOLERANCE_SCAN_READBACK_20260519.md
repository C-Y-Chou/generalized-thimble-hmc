# F20b ODE Tolerance Scan Readback

Date: 2026-05-19 JST

Canonical workspace: `/Users/ccy/Documents/TLTM_qn_error_handling`

Remote workspace:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`

Scheduler request: `FMOD-F20B-R2-ODETOL-SCAN-20260519`

Source commit: `bc3add0fe8e73d71270c4751954279a6d518251e`

## Scope

This is Stage A of the F20b double-only tolerance calibration:

- scale: 10 seeds x 10000 cycles
- methods: `no_fb`, `fb_norefine`
- ODE abs/rel profiles: strict `3e-14`, `1e-12`, `1e-10`, `1e-8`
- Newton/QN/constraint/reverse-gate tolerances: strict
- parent did not submit or cancel PBS jobs directly

## Readback Summary

Completed profiles:

| profile | method | rows | protocol | mean runtime s | ODEX calls | accepted | rejected | RHS evals | RG candidates | RG rejects | projection mean | unresolved |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| strict | no_fb | 10 | pass | 501.669 | 60,524,445 | 349,770,488 | 13,056,353 | 11,648,502,219 | 3,925,264 | 1,038 | 932.5 | 8,287 |
| strict | fb_norefine | 10 | pass | 865.060 | 64,485,350 | 384,774,123 | 16,987,785 | 13,756,621,316 | 4,001,410 | 994 | 255.4 | 1,560 |
| ode_1e12 | no_fb | 10 | pass | 397.594 | 60,491,404 | 310,069,564 | 10,395,180 | 8,747,505,581 | 3,925,757 | 1,022 | 927.1 | 8,249 |
| ode_1e12 | fb_norefine | 10 | pass | 708.810 | 64,112,868 | 341,127,250 | 13,530,393 | 10,192,729,211 | 3,991,829 | 1,896 | 345.7 | 1,561 |
| ode_1e10 | no_fb | 10 | pass | 287.950 | 68,023,102 | 349,873,249 | 15,661,473 | 7,958,209,404 | 5,271,449 | 12,747 | 1,331.1 | 8,005 |
| ode_1e10 | fb_norefine | 10 | pass | 501.581 | 69,798,691 | 364,929,589 | 17,652,482 | 8,582,287,473 | 5,284,350 | 18,621 | 1,266.1 | 1,479 |

Physics/output summaries:

| profile | method | mean Re | seed std Re | mean err Re | Zmean Re | mean Im | seed std Im | mean err Im | Zmean Im | P68 | P95 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| strict | no_fb | 0.007879 | 0.179614 | 0.160949 | 0.138720 | -0.029744 | 0.140321 | 0.102720 | -0.670301 | 0.1 | 1.0 |
| strict | fb_norefine | 0.010875 | 0.159385 | 0.135406 | 0.215769 | -0.013375 | 0.104298 | 0.093491 | -0.405523 | 0.5 | 0.8 |
| ode_1e12 | no_fb | 0.004555 | 0.182918 | 0.160944 | 0.078740 | -0.031122 | 0.138346 | 0.102751 | -0.711370 | 0.1 | 1.0 |
| ode_1e12 | fb_norefine | 0.000371 | 0.174898 | 0.137178 | 0.006713 | -0.021584 | 0.108298 | 0.094504 | -0.630253 | 0.4 | 0.6 |
| ode_1e10 | no_fb | -0.002394 | 0.210740 | 0.166992 | -0.035929 | 0.003695 | 0.133049 | 0.109390 | 0.087825 | 0.3 | 0.9 |
| ode_1e10 | fb_norefine | 0.070170 | 0.271606 | 0.169491 | 0.816987 | 0.006039 | 0.111428 | 0.108039 | 0.171375 | 0.2 | 0.6 |

`mean err` is the mean of the per-seed cycle/jackknife `err_Ohat_*` fields; all
completed rows had `err_Ohat_valid=1`.

Failed upper screen:

- `ode_1e8` had no per-seed or aggregate summary at readback time.
- Stage2 logs showed repeated `[RG_REJECT_CASE]` lines followed by
  `[ERROR][TLTM-S2] Slot 1 initialization failed at flow_time=  0.3500`.
- The parent asked the scheduler agent to inspect/cancel only the `1e-8` tail
  jobs if still active, preserving artifacts. No parent-side `qdel` was run.

Preflight:

- latest preflight log:
  `output/logs/fortran_modernization/reference_datasets/preflight/m6_reference_preflight_build.20260519T190720.log`
- M4 guardrails passed.
- No `Python.h`, `pyconfig`, traceback, or libpython failure was found. The
  `libpython` strings in the log are successful link lines.

## Interpretation

`ode_1e12` is the first clean ODE-relaxation candidate:

- both methods produced 10 rows and protocol audit pass;
- runtime and RHS evaluations decreased for both methods;
- reverse-gate and projection counters remain close to strict, except for a
  modest `fb_norefine` reverse-gate reject increase;
- physics summaries stay within the current 10seed noise band.

`ode_1e10` is a speed candidate but not clean enough for default promotion:

- runtime and RHS evaluations improve substantially;
- reverse-gate rejects jump by about one order of magnitude in both methods;
- projection failures increase sharply;
- `fb_norefine` mean Re shifts to `0.070170` with `Zmean Re=0.816987`, not a
  decisive 10seed physics failure, but no longer a clean numerical-only change.

`ode_1e8` is rejected for this flow:

- it can fail Stage2 initialization at `flow_time=0.3500`;
- it is beyond the observed safe ODE tolerance boundary.

## Decision

For Stage B, fix ODE abs/rel at `1e-12` and scan Newton/QN/constraint tolerance
there. Keep reverse-gate tolerance strict.

Do not use `1e-10` as a production default without an additional targeted
boundary scan and a larger physics comparison. Treat it as the aggressive speed
edge, not the clean candidate.

Do not use `1e-8` or `1e-6` as ODE tolerance candidates for the current F20b
route.
