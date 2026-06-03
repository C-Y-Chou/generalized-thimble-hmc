# WV-HMC n=6 Epsilon Scan Summary

Date: 2026-05-31

Fixed settings:

```text
constraint_tol = 1e-10
constraint_max_iter = 24
adaptive_newton_stop_enabled = 0
nstep = 5
T0 = 1e-4
T1 = 1e-3
d0 = 1e-4
d1 = 2.5e-4
initial_flow_time = 5.5e-4
W(t) = paper_wall
gamma = 0.2
init = n=6 safe t0p0001 bank
```

| epsilon | seeds | acceptance mean | acceptance range | effective x jump sq | effective z jump sq | effective flow jump | boundary/cycle | transition failures | RG failures | solver failures | ODEX failures |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.001 | 10 | 0.968 | 0.933-0.983 | 2.42332e-05 | 2.20758e-05 | 3.68406e-04 | 0.288 | 0 | 0 | 0 | 0 |
| 0.002 | 8 | 0.915625 | 0.860-0.955 | 7.44014e-05 | 7.30242e-05 | 3.64333e-04 | 0.673125 | 0 | 0 | 0 | 0 |
| 0.004 | 8 | 0.875 | 0.850-0.890 | 2.05865e-04 | 2.06905e-04 | 2.98624e-04 | 1.4875 | 3 | 1 | 0 | 0 |
| 0.006 | 8 | 0.8925 | 0.850-0.920 | 3.29817e-04 | 3.32857e-04 | 2.22074e-04 | 2.28812 | 13 | 4 | 2 | 2 |
| 0.008 | 8 | 0.869375 | 0.765-0.910 | 4.60004e-04 | 4.64838e-04 | 1.88420e-04 | 2.71437 | 28 | 13 | 4 | 4 |
| 0.010 | 8 | 0.816875 | 0.705-0.880 | 5.37769e-04 | 5.43651e-04 | 1.35102e-04 | 3.04 | 60 | 32 | 22 | 29 |
| 0.012 | 8 | 0.8425 | 0.785-0.880 | 6.10218e-04 | 6.17035e-04 | 9.28233e-05 | 3.39 | 37 | 29 | 16 | 24 |
| 0.016 | 8 | 0.841875 | 0.725-0.915 | 8.38613e-04 | 8.48344e-04 | 7.14165e-05 | 3.63875 | 64 | 49 | 20 | 32 |

## Decision

Use `epsilon=0.010` for the next nstep/L movement scan.

Reason: it is the first scan point that brings the mean acceptance close to the
target region while still retaining more flow-time motion than `0.012` and
`0.016`.  The higher-epsilon points are useful stress tests but show increasing
boundary pressure and shrinking flow-time motion.

Failure and RG counts are retained as diagnostics and cost predictors only; the
selection is based on acceptance and movement behavior.
