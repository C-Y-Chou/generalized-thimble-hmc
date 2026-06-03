# WV-HMC Parameter Tuning SOP

Date: 2026-05-31

Purpose: define the WV-HMC-specific tuning order before matrix-free/BiCGStab
trajectory wiring and before larger Stephanov runs.  This is a child SOP of
`PARAMETER_TUNING_SOP_20260531.md`; it adds WV-HMC Newton/RATTLE details but
does not replace the repository-wide parameter dependency order.

For the currently tuned Stephanov `n=6`, `T1=0.03` dense explicit-J production
preset, use `WV_HMC_N6_T003_PRODUCTION_SOP_20260531.md`.  This file remains
the retuning SOP for when an upstream input changes.

## Scope

This SOP applies whenever the WV-HMC transition parameters are changed:

- model, `n`, `m`, `mu`, `nf`, or action derivatives;
- sampler interval `[T0,T1]` or measurement interval;
- `W(t)` profile or wall parameters;
- DOP853 tolerances/controller settings;
- initial bank distribution;
- HMC `epsilon`, `nstep`, or `L`;
- Newton constraint tolerance, iteration cap, or adaptive fail-fast policy.

All Fortran build, simulation, validation, and timing evidence for production
decisions must come from the scheduler-gated cluster path, not from local runs.

## Non-Negotiable Ordering

1. Fix the physics target and reference checks.
   - Record model parameters, exact references if available, initial-bank
     source, sampler `[T0,T1]`, measurement interval, `W(t)`, and DOP853 policy.
   - Default `T0 = 0`, the physical-manifold lower endpoint.  A positive lower
     endpoint is an explicit domain choice, not a numerical safety knob.
   - `[T0,T1]` and the measurement interval are domain inputs.  They are not
     selected from acceptance, movement, boundary, or histogram diagnostics.
   - Do not use observable agreement from a bad tuning sequence as validation.

2. Fix the Newton constraint tolerance before designing fail-fast.
   - The tolerance is an accuracy target, not the first runtime knob.
   - Start from the validated dense WV-HMC value for comparable small runs
     (`1.0e-10`) unless a separate tolerance-equivalence gate justifies another
     value.
   - If a looser tolerance is later desired for cost, run it as an A/B
     accuracy-equivalence study after the stable tuning path exists.

3. Observe raw Newton convergence at fixed tolerance.
   - Run with adaptive Newton stop disabled.
   - Use a generous `constraint_max_iter` so that eventual convergence can be
     seen rather than truncated.  For new settings, use at least the current app
     default (`48`); use `96` or `128` when the trace shows late convergence or
     when moving to larger `n`.
   - Enable Newton trace output and aggregate it with
     `codex/workspaces/fortran_modernization/tasks/scripts/analyze_wv_hmc_newton_traces_20260530.py`.
   - Record per-solve final stop reason, iteration count, residual curve,
     initial/final/min residual, first residual growth, and forward/reverse
     direction.
   - The trace gate may be intentionally truncated when it already contains
     enough solves to classify the convergence distribution and the remaining
     work is dominated by a long runtime tail.  If this is done, record the
     truncation reason, number of solves, completed seed/cycle coverage, and
     whether the missing tail can affect the proposed cap or predicate.

4. Choose any fail-fast rule from the residual trace, not by blind max-iter
   cuts.
   - A fail-fast rule must target solves that are already clearly divergent,
     stagnant, nonfinite, or residual-error cases under the generous trace.
   - It must not reject solves that would converge under the fixed tolerance
     within the generous cap.
   - Boundary exits are handled by the simplified-paper full momentum flip
     `pi -> -pi` in the default WV-HMC production kernel.  Only true numerical
     construction failures that cannot be classified as boundary exits are
     proposal-rejection diagnostics.
   - Trace summaries must report boundary exits separately from failed solves.
     A boundary exit contributes to the resolved transition accounting, not to
     the Newton failure count.
   - The calibration record must state the trace data, fixed tolerance, chosen
     predicate/cap, and false-reject audit on eventual convergences.

5. A/B verify the candidate fail-fast gate.
   - Compare the same model, bank, `W(t)`, `[T0,T1]`, `epsilon`, `nstep`, seeds,
     and cycle prefix with fail-fast off vs on.
   - Required invariant checks: transition attempts, acceptance, reverse-gate
     accounting, flow-time distribution, configuration-space movement,
     observable estimates, and ratio diagnostics must agree within statistical
     noise.
   - The only intended change is cost or earlier classification of solves that
     would not converge anyway.

6. Tune `epsilon` for acceptance using the accepted solver gate.
   - `epsilon` controls proposal scale and acceptance.
   - Target acceptance should be chosen for productive motion, not for low
     failure counts.
   - Failure/RG counts are diagnostics and cost predictors; they are not the
     primary tuning target.

7. Tune `nstep` and `L=epsilon*nstep` for movement.
   - Movement must be measured in configuration space, not only in flow time.
   - Required movement diagnostics include accepted and effective
     `||delta x||^2/n`, `||delta z||^2/n`, flow-time span, flow-time histogram,
     boundary bounces, and round trips when applicable.
   - The scan must include the current baseline `nstep` using the same seed
     set and initial-bank draw policy as the other scan points.  Reusing an
     epsilon-scan result with different seeds is allowed only as context, not
     as the paired baseline for selecting `nstep`.
   - A setting that only changes flow time but leaves configuration-space motion
     poor is not validated.

8. Tune `W(t)` on the fixed `[T0,T1]`.
   - Start with the paper-style wall profile after `[T0,T1]` has already been
     fixed from the algorithm/physics target.
   - Use the flow-time histogram to decide whether `W(t)` needs tilt or
     multicanonical tuning within that fixed interval.
   - For the implemented `paper_wall` profile inside the interval,
     `W(t) = -gamma * (t - T0)`.  Therefore the unweighted sampling tilt across
     the interval is controlled by `exp(gamma * (T1 - T0))`, not by `gamma`
     alone.  On short intervals such as `T1 - T0 ~= 0.03`, values like
     `gamma = 0.2` or `1` are effectively near-flat; an order-one histogram
     change can require `gamma = O(10-100)`.
   - Select candidate `gamma` first from sampler flow-time coverage on the
     fixed interval.  The default target is a sufficiently flat unweighted
     flow-time histogram, because over-suppressing low flow can make phase
     coherence look better while hiding an ergodicity or transport problem.
   - The WV measurement factor is `phase / alpha`; `W(t)` is already present in
     the positive sampling density and the W-weighted target integral, so it
     must not be multiplied into `wv_factor`.  Every gamma scan must still
     report ratio diagnostics: `sum_abs_weight`, denominator magnitude/phase,
     phase coherence, phase ESS or an equivalent ratio stability proxy,
     observable SE, acceptance, movement, and runtime.  These are secondary
     health gates; they do not replace the histogram coverage criterion.
   - Histogram flatness, boundary counts, flow-time movement, and acceptance are
     diagnostics of the sampler on the chosen interval.  They are not criteria
     for selecting `[T0,T1]`.
   - Changing `W(t)` or wall parameters invalidates previous solver convergence
     calibration unless a fresh trace or health check shows the Newton residual
     behavior is unchanged.
   - Changing `[T0,T1]` is an upstream domain change.  Restart from the domain
     record and then redo solver, epsilon, movement, `W(t)`, and validation
     gates as needed.

9. Run production validation.
   - Required outputs: observable z-scores, ratio-preserving uncertainty,
     seed-jackknife or seed/bootstrap, large-block checks, first/second-half
     comparison, cumulative estimates, flow-time histogram, state movement,
     acceptance, reverse-gate summaries, Newton stop summaries, and runtime.
   - Exact-reference correctness is the final gate for small Stephanov tests.

## Solver Fail-Fast Calibration Details

The current code exposes these production controls through the WV-HMC app
namespace:

- `WV_HMC_CONSTRAINT_TOL`
- `WV_HMC_CONSTRAINT_MAX_ITER`
- `WV_HMC_ADAPTIVE_NEWTON_STOP_ENABLED`
- `WV_HMC_NEWTON_TRACE_FILE`

The current source has additional adaptive-stop constants inside
`src/sampler/wv_hmc_constraints.f90`:

- `near_tol = max(2.0e2*tol, 1.0e-10)`;
- `stagnation_floor = max(1.0e4*tol, 1.0e-8)`;
- `diverge_floor = max(1.0e5*tol, 1.0e-6)`;
- divergence stop after repeated growth;
- stagnation stop after repeated flat residual and tiny updates;
- boundary-exit stop when repeated boundary clamping cannot approach tolerance.

Those constants are not a universal WV-HMC theorem.  If a new trace shows that
they need to be varied, expose explicit knobs or patch the policy deliberately
before production.  Do not silently rely on hard-coded constants after changing
model, `W(t)`, interval, DOP853 policy, bank, `epsilon`, or `nstep`.

## Stephanov n=6 Initial Workflow

For the first dense explicit-J WV-HMC Stephanov `n=6` step, use this sequence:

1. Model and references:
   - `n=6`, `nf=1`, `m=0.004`, `mu=0.6`, `tau=0`;
   - exact `chiral_condensate = 0.0244771983`;
   - exact `number_density = 0.5661155667`;
   - start from an established t=0 bank, not a fresh Gaussian, unless the run
     explicitly tests initialization.
   - record `[T0,T1]` and the measurement interval as upstream domain choices,
     with source/rationale; do not derive them from sampler histograms.
   - If the available warm bank is too small or visibly target-mismatched,
     rebuild initialization through a lower fixed-tau flow-state bank before
     interpreting the WV-HMC validation.

1b. Preferred initial-flow-bank construction for difficult intervals:
   - default to `tau_bank = 0`;
   - if a positive `tau_bank < T1` is intentionally used, require zero
     proposal/reflow solver failures at the selected fixed-tau builder
     `epsilon/L`; otherwise lower `tau_bank`, not `epsilon`;
   - run a fixed-tau builder at `tau_bank`;
   - tune the builder with larger candidate `epsilon` and `L` than the target
     WV-HMC production kernel when acceptance and configuration-space movement
     allow it;
   - harvest post-burn-in cyclic snapshots or x-history;
   - pack records as WV-HMC `state_bank` records with layout `tau_bank + x`;
   - record builder `tau_bank`, `epsilon`, `nstep/L`, burn-in, seeds, snapshot
     interval, and harvest window.

2. Solver trace:
   - fixed `WV_HMC_CONSTRAINT_TOL=1.0e-10`;
   - `WV_HMC_ADAPTIVE_NEWTON_STOP_ENABLED=0`;
   - generous `WV_HMC_CONSTRAINT_MAX_ITER=96` initially;
   - Newton trace enabled;
   - conservative short transition setting first, then repeat after the
     selected `epsilon/nstep` changes if the residual distribution changes.

3. Fail-fast decision:
   - analyze residual curves and iteration distribution;
   - choose cap/predicate only after proving it does not cut eventual
     convergences;
   - A/B verify with the same seeds and prefix.

4. HMC tuning:
   - scan `epsilon` for acceptance after the solver gate is fixed;
   - scan `nstep` at fixed `epsilon` for configuration-space movement and
     flow-time coverage;
   - do not select by minimizing RG/failure counts.

5. `W(t)` tuning:
   - tune only `W(t)`/wall shape within the fixed `[T0,T1]`;
   - if `[T0,T1]` changes, restart the downstream gates instead of treating it
     as an efficiency retune.

6. Validation:
   - require exact-reference z-score checks, seed/block stability, flow-time
     histogram, movement, Newton stop table, acceptance, and runtime.

## Anti-Patterns

These are explicitly disallowed as SOP:

- lowering `constraint_max_iter` first and calling the resulting timeout pattern
  a fail-fast policy;
- scanning `constraint_tol` for runtime before fixing the accuracy target;
- choosing `L` before `epsilon`;
- using flow-time movement alone as the movement criterion;
- selecting `[T0,T1]` from histogram flatness, acceptance, or movement
  diagnostics;
- treating low failure count or low reverse-gate rejection as the tuning goal;
- enabling adaptive Newton stop because it is available in code;
- carrying a solver cap from `n=2` to `n=6` without a fresh trace.

## Required Calibration Artifacts

Each new WV-HMC production setting must leave:

- raw run metadata with model, `W(t)`, interval, DOP853 policy, bank, `epsilon`,
  `nstep`, `tol`, `max_iter`, and adaptive-stop flag;
- `wv_newton_trace_candidate_summary.csv`;
- `wv_newton_trace_solve_summary.csv`;
- `wv_newton_trace_iteration_summary.csv`;
- fail-fast false-reject audit;
- fail-fast off/on A/B summary if adaptive stop or a lower cap is used;
- HMC epsilon scan summary;
- HMC nstep/movement scan summary;
- final observable/readback summary.

The trace analyzer already writes the first three trace summaries.  The missing
part before this SOP was the mandatory ordering and the requirement that the
solver gate be calibrated before HMC production tuning.
