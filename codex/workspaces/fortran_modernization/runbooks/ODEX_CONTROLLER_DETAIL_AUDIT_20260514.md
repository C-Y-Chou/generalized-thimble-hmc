# ODEX Controller Detail Audit

Date: 2026-05-14 JST
Scope: `src/physics/odex_backend.f90` and the `solve_flow:intode*` endpoint
wrapper path
Status: first-pass detail audit complete; source unchanged; CV-012 remains active

## Executive Conclusion

The active ODEX backend is a TLTM endpoint-flow extrapolation integrator with a
Hairer-compatible midpoint/extrapolation core and the Hairer `IWORK(3)=3`
step-number sequence.  It should not be described as a complete line-by-line
implementation of Hairer's ODEX controller.

The source is strongest on:

- explicit midpoint rows and smoothing endpoint formula;
- even-power extrapolation tableau;
- shared `IWORK(3)=3` step-number sequence and matching work estimate;
- endpoint-only product boundary;
- signed interval handling for forward/backward integration direction;
- strict final-flow use through the surrounding TLTM proposal boundary.

The source is not yet detail-signed on:

- first-step selection;
- h-min floor policy;
- step-size growth/shrink bounds;
- rejected-step controller behavior;
- order promotion/demotion thresholds;
- conservative stability-control equivalence to Hairer's stability check.

Therefore the correct claim is:

```text
The modernization tree contains a Hairer-ODEX-family endpoint extrapolation
backend with the canonical IWORK(3)=3 sequence.  Several controller details are
TLTM-specific or still open-needs-proof and must not be advertised as an exact
full Hairer ODEX implementation.
```

## Reference Contract Used

Reference files inspected locally:

- `references/Hairer_SODE_I_Appendix_Subroutine_ODEX_pdfpages_494_496.pdf`
- `references/Hairer_SODE_I_II9_Extrapolation_Methods_pdfpages_237_270.pdf`

Relevant reference obligations, paraphrased:

- ODEX is a Gragg-Bulirsch-Stoer / explicit-midpoint extrapolation code with
  variable order and variable step size.
- The method computes midpoint approximations with step-number sequences,
  then extrapolates in even powers of the substep size.
- The user-supplied `H` is an initial step-size guess.  Hairer's appendix
  treats a derivative-scale-informed `H` as useful, and if `H=0` the code uses
  a small default guess.
- Step-size proposals use safety factors corresponding to Hairer `WORK(8)` and
  `WORK(9)`, with defaults around `0.65` and `0.94` when convergence is hoped
  for.
- Hairer also documents growth/shrink restrictions using `WORK(4)` and
  `WORK(5)`, plus order-selection thresholds `WORK(6)` and `WORK(7)` with
  default values around `0.8` and `0.9`.
- Hairer ODEX has stability-check and dense-output surfaces that are part of
  the general-purpose routine but are not automatically required by TLTM's
  endpoint-only product boundary.

## Source Contract Observed

Primary source:

- `src/physics/odex_backend.f90`
- `src/physics/solve_flow.f90`

Observed source mechanics:

- `odex_options` defaults to `k_min=4`, `k_max=10`,
  `step_sequence=odex_step_sequence_iwork3`, `endpoint_only=.true.`,
  `initial_step_fraction=0.01`, and conservative stability control disabled.
- `odex_integrate_endpoint*` initializes `h = t*initial_step_fraction`, computes
  a TLTM-specific `h_min`, then repeatedly calls `odex_step`.
- `odex_step` builds explicit midpoint rows, smooths each row with
  `0.5*(yprev + ycurr + dt*f(ycurr))`, and constructs the extrapolation tableau.
- `build_nsteps` uses Hairer `IWORK(3)=3`:
  `2,4,6,8,12,16,24,32,...`.
- `calculate_ak` uses the same step-number helper as `build_nsteps`.
- `calculate_wk` uses `abs(h)` in the denominator, so work estimates are
  positive for signed intervals.
- `calculate_hk` keeps the sign of `h`, so reverse integration keeps the
  correct direction.
- `solve_flow:flowzr_with_workspace` implements inverse flow by integrating the
  same nonnegative flow time with RHS scale `-1`.
- Solver assist is not an ODEX controller branch.  It is an `intode` wrapper
  policy restricted by context, stage, role, and h-min failure status.

## Detail Mapping

| Surface | Source | Reference expectation | Status | Audit finding |
| --- | --- | --- | --- | --- |
| Method family | `odex_step` midpoint rows and extrapolation tableau | Explicit midpoint / GBS extrapolation | `matched` | The row construction, smoothing endpoint, and extrapolation structure match the ODEX family. |
| Step sequence | `odex_iwork3_nstep`, `build_nsteps`, `calculate_ak` | Hairer `IWORK(3)=3` sequence | `matched` | The source now uses `2,4,6,8,12,16,24,32,...` consistently for rows and work estimate. |
| Endpoint-only scope | `endpoint_only=.true.`, no dense-output API used | Hairer full ODEX supports dense output | `intentional-deviation` | TLTM needs endpoint flow, not a general dense-output solver.  This is a product-scope decision, not a bug. |
| First step `h0` | `h = t*opts%initial_step_fraction`, default `0.01` | Hairer treats `H` as user initial guess; derivative-scale guesses are suggested; `H=0` has a small fallback | `intentional-deviation/open-needs-proof` | Current code does not expose or compute Hairer's user/derivative-informed initial guess.  It uses 1 percent of the requested interval.  This may be acceptable for endpoint TLTM but is not yet justified as Hairer-equivalent. |
| h-min floor | `max(h_min_fp, min(h_min_tol, h_min_span))` | Hairer has roundoff/min-step handling, but not this exact three-term TLTM policy in the inspected snippets | `open-needs-proof` | This is a project failure-classification boundary.  It needs branch tests and wording as TLTM-specific unless a line reference is found. |
| Error norm | scaled RMS difference of neighboring extrapolation columns | ODEX uses tolerance-scaled extrapolation error | `partial` | The general idea matches.  Exact denominator/index choices need branch-level tests against analytic ODE cases. |
| Step-size proposal | `h*0.94*(0.65/max(err,1e-14))**invexp(k)` | Hairer documents `WORK(8)`, `WORK(9)`, and an error/order exponent | `partial` | Constants `0.65` and `0.94` are recognizable, and normalized error explains the missing explicit `TOL`.  Exact index/exponent mapping and the `1e-14` floor remain open. |
| Step-size bounds | no explicit Hairer `WORK(4)` / `WORK(5)` candidate bound | Hairer restricts candidate `HNEW/HOLD` growth/shrink | `open-needs-proof` | The active controller can generate unbounded growth/shrink candidates except for loop truncation to final `t`.  This is the highest-priority ODEX controller gap. |
| Work estimate | `wk = ak/abs(h_new_candidate)` | Hairer uses positive work-per-unit-step measures | `matched/partial` | Sign robustness is fixed.  Exact `AK` indexing and use in every branch still need branch tests. |
| Order demotion threshold | branch comparisons use `0.9` in multiple places | Hairer separates decrease/increase thresholds, defaults around `0.8` and `0.9` | `open-needs-proof` | The source does not obviously encode the documented `0.8` decrease threshold.  Treat as controller deviation until proved otherwise. |
| Order promotion threshold | branch comparisons use `0.9` | Hairer increase threshold around `0.9` | `partial` | The constant is recognizable, but branch predicates and candidate-order indexing need dedicated tests. |
| Rejection behavior | `err >= 1` rejects at wrapper level; invalid/stability branches halve `h`; large intermediate error demotes via `(k*k+1)**2` | Hairer has structured reject/retry and order/step logic | `partial/open-needs-proof` | The mechanics are plausible but not paper-signed.  The `(k*k+1)**2` threshold needs a reference or project rationale. |
| Stability control | default none; conservative optional check on invalid/growth | Hairer ODEX has stability-check controls | `intentional-deviation/partial` | Default TLTM route does not use full Hairer stability controls.  The optional conservative check is a reduced project surface. |
| Signed interval | `calculate_hk` signed, `calculate_wk` positive, `flowzr` RHS scale `-1` | Backward integration direction must be preserved | `matched` | Direction and work-sign responsibilities are separated correctly. |
| Wrapper solver assist | `intode_solver_assist_policy_allows` | Not part of Hairer ODEX | `out-of-scope/project-policy` | This belongs to TLTM proposal navigation policy, not ODEX controller correctness. |

## Current Bug-Candidate Assessment

No source bug is proven by this audit alone.

However, the following ODEX controller surfaces are strong open-needs-proof
items and should be treated as possible controller deviations before any
publication-grade claim:

1. `h0 = 0.01*t` instead of a user/derivative-informed initial step.
2. Missing explicit Hairer `WORK(4)` / `WORK(5)` step-size bounds.
3. Order demotion using `0.9` rather than the documented decrease threshold
   near `0.8`.
4. The large-error demotion threshold `(k*k+1)**2`.
5. The `1.0e-14` error floor in `calculate_hk` / `calculate_wk`.
6. Optional conservative stability control being much narrower than full
   Hairer stability logic.

These are not automatically physics bugs because TLTM uses this solver as an
endpoint integrator behind strict proposal/failure boundaries.  They are,
nevertheless, blockers for saying "the handwritten ODEX controller is fully
paper-correct."

## Required Deterministic Evidence

Before closing the ODEX controller detail surface, add tests or evidence
packets for:

1. First-step contract:
   - fixed analytic ODE;
   - record initial `h`;
   - exercise short and long `t`;
   - decide whether `0.01*t` is accepted TLTM policy or should be replaced by
     a Hairer-style initial guess surface.

2. Step-size update branch table:
   - controlled error values around `err < 1`, `err = 1`,
     `err > (k*k+1)**2`;
   - expected `h` sign;
   - expected order `k` update.

3. Step-size bound decision:
   - either implement Hairer-like bounds and test them, or explicitly document
     why endpoint TLTM does not use them.

4. Order threshold tests:
   - synthetic `wk1/wk2` branch cases for demotion, retention, and promotion;
   - include the documented `0.8` vs source `0.9` decision.

5. Signed interval tests:
   - forward/backward analytic ODE consistency;
   - `calculate_wk` positive under negative `h`;
   - `calculate_hk` preserves integration direction.

6. h-min classification tests:
   - force h-min failure without invalid values;
   - verify returned endpoint, status, counters, and wrapper assist boundaries.

7. Stability branch tests:
   - invalid RHS rejection;
   - conservative growth rejection;
   - default no-stability-control behavior.

8. Endpoint product claim:
   - confirm dense output is not exposed or required by TLTM callers;
   - keep any report wording scoped to endpoint-flow production.

## Publication Claim Boundary

Allowed wording:

```text
We use a TLTM endpoint extrapolation integrator based on Hairer ODEX/GBS,
with explicit-midpoint extrapolation and the Hairer IWORK(3)=3 step sequence.
The implementation is guarded by endpoint-flow, proposal-failure, and
deterministic regression tests; controller-specific deviations are documented
as project policy.
```

Blocked wording until the required evidence exists:

```text
Our handwritten ODEX backend is a complete, line-by-line implementation of
Hairer's ODEX controller.
```

## Reopen Triggers

Reopen this audit if any of the following change:

- `initial_step_fraction`, `h_min_*`, `calculate_hk`, `calculate_wk`,
  `calculate_ak`, `build_nsteps`, or order branch predicates;
- ODEX failure status mapping;
- `intode` assist policy around h-min failures;
- `flowz`, `flowzr`, or final `flow(...)` strictness;
- public claims about dense output, full Hairer ODEX, or publication-grade
  paper correctness.

## Bottom Line

The ODEX core is not a mystery and not obviously broken.  But the important
controller details are not all paper-signed.  The next source-affecting ODEX
work must either align those details with Hairer or explicitly label and test
them as TLTM endpoint-controller policy.
