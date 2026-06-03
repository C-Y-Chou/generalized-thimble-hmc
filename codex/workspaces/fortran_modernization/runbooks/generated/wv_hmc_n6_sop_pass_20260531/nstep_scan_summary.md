# WV-HMC n=6 Nstep Movement Scan Summary

Date: 2026-05-31

Fixed settings:

```text
epsilon = 0.010
constraint_tol = 1e-10
constraint_max_iter = 24
adaptive_newton_stop_enabled = 0
T0 = 1e-4
T1 = 1e-3
d0 = 1e-4
d1 = 2.5e-4
initial_flow_time = 5.5e-4
W(t) = paper_wall
gamma = 0.2
init = n=6 safe t0p0001 bank
```

SOP amendment during this gate: the movement scan must include the current
baseline `nstep` using the same seed set and bank draw policy.  Supplemental
same-seed `nstep=5` and `nstep=7` scans were added before selecting.

| nstep | L | seeds | acceptance mean | acceptance range | effective x jump sq | effective z jump sq | effective flow jump | boundary/cycle | transition failures | RG failures | solver failures | ODEX failures | ODEX calls/cycle |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2 | 0.020 | 8 | 0.841875 | 0.675-0.930 | 8.63002e-05 | 8.63885e-05 | 1.77818e-04 | 1.25687 | 45 | 35 | 16 | 20 | 28.7125 |
| 4 | 0.040 | 8 | 0.76625 | 0.050-0.945 | 2.83445e-04 | 2.86653e-04 | 8.57058e-05 | 2.2625 | 220 | 38 | 45 | 46 | 52.0875 |
| 5 | 0.050 | 8 | 0.780625 | 0.050-0.935 | 4.59380e-04 | 4.64454e-04 | 1.10145e-04 | 2.9125 | 193 | 25 | 33 | 36 | 64.6587 |
| 6 | 0.060 | 8 | 0.770625 | 0.050-0.945 | 5.85465e-04 | 5.92701e-04 | 1.12659e-04 | 3.5775 | 208 | 23 | 36 | 38 | 76.06 |
| 7 | 0.070 | 8 | 0.68125 | 0.050-0.910 | 8.21952e-04 | 8.31477e-04 | 8.52376e-05 | 3.69937 | 281 | 69 | 67 | 76 | 89.8063 |
| 8 | 0.080 | 8 | 0.735 | 0.050-0.925 | 1.16929e-03 | 1.18252e-03 | 8.16480e-05 | 4.4225 | 215 | 36 | 38 | 41 | 103.119 |

## Decision

Use `nstep=8` (`L=0.08`) for the first n=6 validation smoke.  It gives the
largest effective configuration-space movement while keeping mean acceptance in
a usable HMC range.

Keep `nstep=5` as the conservative fallback if validation shows unacceptable
wall-clock cost, excessive seed-level instability, or observable/history
diagnostics that point to over-aggressive trajectories.

Failure and RG counts are retained as diagnostics and cost predictors only.
