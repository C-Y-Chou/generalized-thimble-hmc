# DOP853 backend notes

Date: 2026-05-23

Scope: endpoint integration backend for TLTM flow ODE tests, especially ODEX-failing
configs used to measure failure cost. This is not a physics-equivalence signoff.

Reference basis:
- Hairer, Norsett, Wanner, Solving Ordinary Differential Equations I, 2nd ed.
- Section II.4 gives the scaled RMS error norm and adaptive step-size idea.
- Section II.5 identifies the Dormand-Prince order-8 method used by DOP853.
- Section II.10 describes the stretched DOP853 estimator using order-5 and
  order-3 embedded estimators.
- Appendix DOP853 notes the production code as order 8(5,3), dense output
  order 7, and default step ratio clamp WORK(3)=0.333, WORK(4)=6.

Implemented controller contract:
- Backend selector: `TLTM_ODE_BACKEND=dop853`.
- Step result is the order-8 Dormand-Prince update.
- Error estimator:
  `err = abs(h) * sum(err5_i**2) / sqrt(n * (sum(err5_i**2) + 0.01*sum(err3_i**2)))`,
  where each component is scaled by
  `abs_tol + rel_tol * max(abs(y_old_i), abs(y_new_i))`.
- Accept if `err <= 1`; reject otherwise.
- Accepted-step update uses the Hairer-style stabilized controller with
  `expo = 1/8 - 0.2*beta`, `safety=0.9`, `fac1=0.333`, `fac2=6`.
- After a rejected step, the next accepted-step proposal is clamped not to grow
  beyond the rejected step.
- Initial step uses the Hairer-style HINIT probe by default:
  evaluate `f(y0)`, take a small Euler probe, estimate the local second
  derivative scale, and choose the first DOP853 step from the scaled norms.
  `TLTM_DOP853_HINIT_ENABLED=0` falls back to the old
  `t * initial_step_fraction` endpoint guess.
- Default `h_min` is the Hairer tiny-step gate from the existing Hairer ODEX
  route, re-evaluated at the current integration time. `TLTM_DOP853_MIN_STEP`
  is an explicit stricter fail-fast override.
- `TLTM_DOP853_MAX_STEP` clamps every proposed step before endpoint clipping.
- `TLTM_DOP853_MAX_RHS_EVALS`, `TLTM_DOP853_MAX_REJECT`, and the optional
  stiffness-suspicion gate now have distinct failure reasons/status codes
  instead of collapsing into `max_steps`.
- Stiffness suspicion follows the DOP853 production-code style of checking
  accepted steps occasionally via `hlamb = |h|*||df||/||dy||`. It is a fail-fast
  diagnostic gate for non-stiff regions, not a rescue sampler.

Dense output:
- Not implemented yet.
- Hairer DOP853 supports order-7 dense output. That is the next possible layer
  if we want to reuse a high-flow endpoint for high-to-low replica swap reflow.

Local verification:
- `make -C build FC=gfortran LDFLAGS=-fopenmp OMP=1 test_odex_backend_package_contract`
  passed with DOP853 accuracy, context, RHS-budget, h_min, max-step,
  max-reject, and stiffness-status checks after the non-dense controller
  completion.
- `make -C build FC=gfortran LDFLAGS=-fopenmp OMP=1 ../bin/run_tltm_stage2`
  passed.
- Local Stephanov n=6 smoke with `TLTM_ODE_BACKEND=dop853`, HINIT enabled, and
  cycles=2 at `t=1e-7` completed:
  `output/tests/dop853_hinit_smoke_20260523/flowtime_summary.csv`.
- 3-slot Stephanov n=6 fail-heavy setup, ladder `0,0.02,0.03`, cycles=20,
  direct t=0 bank record 0:
  - ODEX production elapsed: 130.528816 s
  - DOP853 production elapsed: 30.262344 s
  - ODEX swap reflow subtiming: 204.681110 s
  - DOP853 swap reflow subtiming: 46.273190 s
  - Both runs had swap `flow_calls=31`, `flow_failures=28`.
  - Both runs had local `proposal_failure=40`.
  - DOP853 used 236676 RHS evaluations versus ODEX 802165.

Conclusion for current purpose:
- DOP853 is a useful backend for testing fail-heavy flow configs because it
  preserves the same high-level failure classification in this smoke setup while
  cutting the dominant swap-reflow cost by about 4.4x.
- This is not yet a dense-output implementation and not a physics-output
  equivalence claim.
