# WV-HMC n=6 Gamma Scan Readback 2026-06-01

Remote root:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_gamma_scan_20260601/wv_hmc_n6_t003_gamma_scan_64x2500_gitless_20260601`

Purpose: test the diagnosis that the failed `gamma=0` validation was caused by
too much low-flow sampling from a flat `W(t)`.

## Scan

```text
model = Stephanov n=6, mu=0.6, tau=0
sampler interval = [0.0001, 0.03]
measurement interval = [0.0001, 0.03]
W profile = paper_wall
gamma = 30, 55, 80
gamma = 120 was submitted but canceled before running after gamma=80 already showed high-flow overshoot.
seeds = 16 per gamma
cycles = 2500 per seed
epsilon = 0.010
nstep = 8
constraint_tol = 1e-10
constraint_max_iter = 192
adaptive_newton_stop = off
large_residual_stop = off
```

All completed gamma values finished with no timeout and no nonzero return code.

## Result

The gamma diagnosis is confirmed.

For the implemented `paper_wall` profile, `W(t) = -gamma * (t - T0)`, so
`gamma=0` is effectively flat and over-samples low flow.  Nonzero gamma changes
the flow-time visitation at the expected scale.  Since `T1 - T0 ~= 0.03`, useful
gamma values are `O(50)`, not `O(1)`.

## Flow-Time Histogram

| gamma | sample low-bin fraction | sample high-bin fraction | abs-weight low-bin fraction | abs-weight high-bin fraction | pooled phase C |
|---:|---:|---:|---:|---:|---:|
| 30 | 0.1058 | 0.0460 | 0.1170 | 0.0353 | 0.0882 |
| 55 | 0.0720 | 0.0704 | 0.1117 | 0.0371 | 0.0451 |
| 80 | 0.0474 | 0.1021 | 0.1087 | 0.0389 | 0.0773 |

Interpretation:

- `gamma=30` is still too low-flow biased.
- `gamma=55` makes the unweighted sample count nearly flat and is the current
  histogram-flat baseline.
- `gamma=80` overshoots toward high flow.  Its better short-scan observable
  z-scores and pooled phase coherence are secondary health diagnostics, not a
  reason to prefer it over the histogram-flat point.

The primary `gamma` selection criterion is flow-time coverage on the fixed
measurement interval.  A low-flow deficit can make phase coherence look better
while hiding an ergodicity problem, so phase coherence cannot override the
histogram criterion.  Weighted-bin fractions are not expected to be flat
because the WV measurement factor includes `exp(W) / alpha`; they are reported
as ratio-estimator health diagnostics.

## Observable Z

Exact references:

```text
chiral_condensate = 0.0244771983
number_density = 0.5661155667
```

| gamma | chiral Re | SE | z | density Re | SE | z |
|---:|---:|---:|---:|---:|---:|---:|
| 30 | 0.0164397 | 0.0028395 | -2.831 | 0.789792 | 0.169719 | 1.318 |
| 55 | 0.0312310 | 0.0189916 | 0.356 | 0.405514 | 0.584174 | -0.275 |
| 80 | 0.0194553 | 0.0059791 | -0.840 | 0.697007 | 0.178302 | 0.734 |

These are short 16-seed diagnostics, not final observable validation.  They
show that `gamma=30` is not enough and that nonzero gamma removes the immediate
full-window chiral failure seen at `gamma=0`.  They do not justify choosing a
high-flow-biased gamma when the flow-time histogram is no longer flat.

## Runtime And Transition Health

| gamma | accept | transition fail/cycle | Metropolis reject/cycle | reverse-gate fail | median runtime sec | max runtime sec | solver iter/cycle |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 30 | 0.8925 | 0.0662 | 0.0237 | 0.0127 | 3660 | 3842 | 75.10 |
| 55 | 0.9114 | 0.0661 | 0.0077 | 0.0120 | 3937 | 4158 | 75.70 |
| 80 | 0.9071 | 0.0667 | 0.0082 | 0.0159 | 4256 | 4440 | 77.39 |

The current `epsilon=0.010`, `nstep=8` remains stable enough for this gamma
range.  Runtime rises with gamma but not catastrophically.

## Interim Decision

The concrete problem in the previous validation was flat `W(t)` / `gamma=0`.
Do not run further `gamma=0` WV-HMC validation for `n=6`, `T1=0.03`.

The next useful short test should be based on the histogram-flat point, not on
the largest short-run phase coherence.  Use `gamma=55` as the current baseline.
If further refinement is needed, scan a narrow bracket around the count-flat
point, for example `50, 55, 65`, and keep `gamma=80` only as a high-flow-biased
upper-bracket diagnostic.

Low pooled phase coherence or large short-run SE at `gamma=55` is not by itself
a reason to move to `gamma=80`; it means the histogram-flat candidate needs a
larger validation and movement/ergodicity checks.

Do not go back to long 15k validation before this short validation passes.

## Artifacts

- `gamma_scan_estimator_summary.csv`
- `gamma_scan_flow_histogram.csv`
- `gamma_scan_runtime_summary.csv`
