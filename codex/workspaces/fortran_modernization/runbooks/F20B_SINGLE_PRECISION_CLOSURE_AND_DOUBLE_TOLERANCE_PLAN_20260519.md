# F20b Single-Precision Closure And Double-Tolerance Plan

Date: 2026-05-19 JST

## Decision

Single precision is closed as the active optimization direction. Do not propose
or schedule single-precision production tests unless F20b is explicitly
reopened with new evidence.

The active path is double precision only: find suitable ODE and Newton/QN
tolerances separately, then verify a combined double-precision candidate against
strict physics output.

## Evidence Closing Single Precision

1. Current-head strict vs loose double, 10 seeds x 10000 cycles:
   - no_fb mean runtime increased from 460.984 s to 598.496 s.
   - fb_norefine mean runtime increased from 779.617 s to 800.123 s.
   - Loose ODEX calls decreased, but RHS work increased sharply:
     no_fb RHS evals +5.457B and fb_norefine RHS evals +8.175B.
   - CVODE counters were zero, so the cost is in ODEX path, not CVODE.

2. Component attribution at the full 1e-6 ODE/constraint scale did not provide a
   valid speedup path:
   - odex_only and constraint_only chunks exited in Stage2 initialization.
   - Stage2 logs show initialization failure at flow_time=0.3500 after repeated
     reverse-gate reject diagnostics and shrinking preflow steps.
   - dfols_only, rg_only, and all_loose rows were generated, but the attribution
     campaign failed acceptance because strict merge/reference comparison was
     incomplete after the failed chunks.

3. Fixed-input flowz replay ruled out a wrapper/PBS/parser-only explanation:
   - Repair3 completed with valid replay rows.
   - Loose behavior was input/method dependent, not uniformly slower.
   - Some strict-sourced inputs were faster under loose tolerance, while other
     state classes showed loose-controller explosions.

4. High-cost flowz replay repair2 completed on valid cost-captured states:
   - Jobs: build 16056.anode01 on C16, replay 16057.anode01 on C12.
   - Both jobs exited 0; replay walltime was 00:00:18.
   - All eight replay CSVs had 500 rows; `flowz_replay_summary.json` and
     `flowz_replay_top_cases.csv` were generated.
   - For high-cost states captured from all_loose trajectories, loose replay was
     much more expensive on identical inputs:
     - all_loose/no_fb: RHS ratio 73.186, rejected-step ratio 515.055, runtime
       ratio 77.460.
     - all_loose/fb_norefine: RHS ratio 51.820, rejected-step ratio 375.608,
       runtime ratio 55.251.
   - For high-cost states captured from strict trajectories, loose replay was
     cheaper on identical inputs:
     - strict/no_fb: RHS ratio 0.159, runtime ratio 0.210.
     - strict/fb_norefine: RHS ratio 0.159, runtime ratio 0.206.

Interpretation: the problematic cost is state-distribution dependent. The loose
profile can move the simulation into ODEX states where the lower-order/looser
controller path creates many more rejected steps and RHS evaluations. Reducing
floating-point precision would not address that mechanism and would increase
correctness risk.

## Double-Only Calibration Plan

Stage A: ODE tolerance scan with Newton/QN/constraint/reverse-gate settings kept
strict.

Recommended first candidates:
- strict baseline: abs/rel = 3e-14
- ode_tol_1e12: abs/rel = 1e-12
- ode_tol_1e10: abs/rel = 1e-10
- ode_tol_1e8: abs/rel = 1e-8

Do not start with 1e-6 again. It is already a failed or non-speedup boundary for
the current 10seed x 10k evidence.

Stage B: Newton/QN tolerance scan at the best accepted ODE tolerance.

Recommended first candidates:
- newton_tol_1e12: constraint/QN quasi = 1e-12
- newton_tol_1e10: constraint/QN quasi = 1e-10
- newton_tol_1e8: constraint/QN quasi = 1e-8

Keep reverse-gate tolerance strict during Stage A and B. Treat reverse-gate
tolerance as a later physics-facing acceptance knob, not the first runtime knob.

Stage C: Combined double candidate.

Run the selected ODE and Newton/QN tolerances together at 10seed x 10k. Accept
only if per-seed rows, aggregate tables, protocol audit, strict comparison, and
physics metrics pass.

## Required Readback

For each candidate and method, report:
- mean Ohat real/imag, seed standard deviation, cycle/jackknife error
- Z_mean
- P68/P95
- unresolved and projection failures
- total ODEX calls, accepted/rejected steps, RHS evaluations, midpoint rows
- runtime
- comparison against strict-current-head or accepted handoff reference

