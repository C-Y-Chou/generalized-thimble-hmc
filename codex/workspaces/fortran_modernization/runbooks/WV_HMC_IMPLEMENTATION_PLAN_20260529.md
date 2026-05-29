# WV-HMC Implementation Plan

Date: 2026-05-29

Purpose: add WV-HMC as a sibling sampler after TLTM closure, using the
simplified-algorithm readback and the math/physics review as implementation
contracts.  This plan is deliberately staged so formula and convention mistakes
are caught in small deterministic tests before any production driver exists.

## Source Boundary

WV-HMC must not be implemented as a hidden mode in TLTM Stage2 and must not
reuse the removed legacy `wv` flag.  TLTM keeps its canonical `nofb` production
behavior.  Shared code may include model providers, manual derivatives, ODE
backends, dense fixed-surface projection helpers, RNG utilities, IO helpers, and
readback infrastructure.  WV-HMC-specific code owns worldvolume state,
projection, force, simplified RATTLE, boundary handling, and trajectory
diagnostics.

Formula recovery is governed by
`WV_HMC_MATH_PHYSICS_REVIEW_20260529.md`: any newly recovered or corrected
formula is not implementation-ready until its source location, repo-convention
translation, independent derivation, invariant consequences, and validation test
are recorded.

## Phase 1. Math Kernel Slice

Goal: create deterministic source-level contracts for WV-HMC formulas without
calling flow solvers or production drivers.

Deliverables:

- `src/sampler/wv_hmc_kernels.f90`;
- `tests/test_wv_hmc_math_kernels.f90`;
- build target `make -C build test_wv_hmc_math_kernels`;
- inclusion in `modernization_guardrails`.

Contracts:

- target-space real inner product is `dot_product` on interleaved real arrays,
  equivalent to `Re(u^dagger v)`;
- `alpha2 = <xi_n, xi_n>` must be positive and finite;
- WV projection wraps fixed-surface decomposition:
  `c=<xi_n,w_n>/<xi_n,xi_n>`,
  `w_parallel=w_v+c xi_n`,
  `w_perp=w_n-c xi_n`;
- WV force:
  `force=1/2 [xi + W'(t) xi_n / <xi_n,xi_n>]`;
- simplified Newton algebra:
  `Delta h=c_B`,
  `Delta u=B0_v-c_B xi0_v`,
  `Delta lambda=B_n-c_B xi_n`,
  with `c_B=<B_n,xi_n>/<xi_n,xi_n>`.

Exit criteria:

- deterministic reconstruction and orthogonality checks pass;
- force and simplified update match hand-computed values;
- invalid `alpha2` and shape mismatches fail closed;
- existing TLTM numerical-helper tests still pass.

## Phase 2. Dense WV Projection Oracle

Goal: connect the WV wrapper to the existing dense fixed-surface projection
helper and model/flow conventions.

Deliverables:

- a WV projection API that consumes a fixed-surface decomposition result rather
  than duplicating `decompose2`;
- small-N tests that compare explicit complex-space formulas against the real
  interleaved implementation;
- checks for reconstruction, `<parallel,perp>=0`, and consistency under random
  complex tangent/normal seeds.

Exit criteria:

- dense backend passes for Stephanov `n=2`;
- the projection wrapper is backend-agnostic enough for a later BiCG backend;
- no TLTM proposal semantics change.

## Phase 3. WV Force And Flow Convention Validation

Goal: verify `xi=conj(partial S)`, tangent/normal flow conventions, and force
normalization against finite-difference oracles.

Deliverables:

- tests using random complex Stephanov seeds at nonzero complexified flow;
- finite-difference validation of the WV force direction and `W'(t)` term;
- failure classification for invalid or near-zero `alpha2`.

Exit criteria:

- manual derivative path is used for production formulas;
- AD/FD remains validation-only;
- complexified random-seed tests pass for multiple `n`.

## Phase 4. Dense WV RATTLE Oracle

Goal: implement the first WV simplified RATTLE step using explicit dense
linear algebra and small-N validation only.

Deliverables:

- WV state type carrying `(t, x, z, pi)`;
- nonlinear solve for `(h,u,lambda)` using the simplified update;
- one-step residual and reversibility diagnostics;
- boundary rule support recorded separately from ordinary projection failure.

Exit criteria:

- residual decreases for deterministic small cases;
- reverse one-step test passes within configured tolerance;
- energy-error scaling is monotone as step size decreases;
- boundary bounce behavior is separately tested.

## Phase 5. Matrix-Free Projection Backend

Goal: add the scalable backend needed for high-dimensional WV-HMC.

Deliverables:

- explicit-Jacobian backend remains the oracle;
- matrix-free BiCG/BiCGStab backend with only `E`, `E^T`, and Hessian-vector
  operations;
- backend comparison tests on small-N cases.

Exit criteria:

- matrix-free backend agrees with dense oracle on small-N cases;
- convergence/failure diagnostics distinguish linear solve failure from
  physical boundary or ODE failure;
- high-dimensional use is blocked until oracle comparison passes.

## Phase 6. WV-HMC Driver And Readback

Goal: add an independent WV-HMC sampler driver after the kernels are validated.

Deliverables:

- standalone WV-HMC app and config namespace;
- no reuse of TLTM `withfb` fallback as a production default;
- WV measurement weights and subinterval policy;
- shared observable/readback output where definitions match.

Exit criteria:

- Stephanov `n=2` exact-reference smoke passes;
- flow-time visitation and boundary diagnostics are available;
- TLTM guardrails pass unchanged.

## Experiment SOP Draft

This SOP is an initial implementation contract.  It should be updated after the
first real WV-HMC pilot runs, using observed flow-time histograms, bounce rates,
acceptance, RATTLE/ODE failures, and estimator stability.  The sampler
parameters are not model observables; they are experiment settings.

1. Choose the model and reference checks.
   - Start with a small exact-reference target such as Stephanov `n=2`.
   - Use manual action derivatives for production formulas.
   - Keep AD/FD only as validation oracles on random complexified seeds.

2. Choose the sampler/worldvolume interval `[T0,T1]`.
   - `T0` should be small enough that the surface near `Sigma_T0` is still
     ergodic.  If the original surface is already nonergodic, the literature
     allows additional algorithms or negative `T0`.  This repo currently
     supports exact lower hard-wall startup at nonnegative `T0-d0` through the
     simplified bounce convention.  Negative-flow startup remains unsupported
     until the flow backend has an explicit negative-time contract.
   - `T1` should be large enough that oscillatory integrals are sufficiently
     tamed.  A useful preliminary criterion is a fixed-flow or GT-HMC phase
     check at `T1`, e.g. the average phase is not compatible with zero at about
     the two-standard-error level.

3. Choose the measurement subinterval `[\tilde T0,\tilde T1]`.
   - Default to the whole sampler interval: `[\tilde T0,\tilde T1]=[T0,T1]`.
   - Production readback may restrict the subinterval only after global
     worldvolume equilibrium is established.
   - The chosen subinterval must satisfy
     `T0 <= \tilde T0 < \tilde T1 <= T1`.
   - The final choice should pass a plateau/stability check: small changes of
     `\tilde T0` and `\tilde T1` change the estimator only within statistical
     errors.

4. Choose the initial `W(t)` profile.
   - Start with the paper-style tilted wall profile:
     `W(t)=-gamma(t-T0)` inside `[T0,T1]`, plus exponential lower and upper
     walls controlled by `(c0,d0)` and `(c1,d1)`.
   - `gamma` gives an upward driving tilt and prevents configurations from
     accumulating near small flow time.  Later application papers sometimes use
     `gamma=0` for small systems and positive `gamma` for larger systems.
   - `d0,d1` set wall penetration depths; `c0,c1` set wall strength.
   - If the simple tilted wall does not give adequate flow-time coverage, the
     next step is multicanonical tuning of `W(t)`, not changing the estimator.

5. Choose HMC trajectory parameters.
   - Pick the integrator step size `epsilon` first, because it controls local
     numerical stability and acceptance.
   - Then scan `nstep` and `L=epsilon*nstep` for flow-time transport, bounce
     rate, round trips, and acceptance.
   - Do not choose `L/nstep` by trying to suppress diagnostic failures alone.
     Failures are diagnostics; the primary criteria are correct transition
     behavior, stable Hamiltonian errors, adequate flow-time transport, and
     estimator quality.

6. Run a short pilot.
   - Record flow-time histogram, high/low boundary bounce counts, acceptance,
     `Delta H`, RATTLE residuals, ODE failures, projection/alpha failures,
     flow-time round trips, and measurement inclusion/skips.
   - If samples accumulate at low `t`, increase `gamma` or use a tuned
     multicanonical profile.
   - If wall bounces or solver failures dominate, adjust `epsilon`, `d0/d1`,
     and wall strength before increasing production length.

7. Promote to production only after readback passes.
   - Small exact-reference observables must be correct.
   - `F_WV` denominator/phase diagnostics must be stable.
   - Measurement-subinterval plateau checks must pass.
   - Restart, snapshot, and output manifests must record all sampler interval,
     measurement interval, `W(t)`, and HMC trajectory parameters.

## Current Slice

Phase 1 is implemented as a math-kernel contract slice.  The first Phase 2
increment is the dense projection wrapper that composes the existing
fixed-surface `decompose_tangent_projection` helper with the WV projection
formula.

Additional completed kernel-level validation:

- `xi=conj(partial S)` is exposed as an explicit convention helper and tested
  against a five-point finite-difference directional derivative of `Re S` on a
  random complex Stephanov `n=2` seed;
- tangent flow RHS `conj(Hv)` is tested against a five-point finite-difference
  derivative of `xi(z)`;
- normal flow RHS is fixed as the sign-reversed convention `-conj(Hv)`;
- dense WV force uses the fixed-surface normal component `xi_n` directly through
  `wv_force_dense_with_jacobian`; do not obtain the force normal by calling
  `wv_project_dense_with_jacobian(w=xi)`, because that returns the WV
  projection of `xi`, whose perpendicular component is zero by construction;
- dense simplified-Newton update and linear residual kernels now provide the
  local oracle for the future nonlinear WV-RATTLE solve.
- `wv_hmc_constraints.f90` exposes the first-constraint residual evaluator
  `R = z + Delta z - lambda - z_{t+h}(x+u)` for the dense path.  The current
  contract tests zero residual at `Delta z=h=u=lambda=0` and verifies that one
  linearized simplified-Newton update reduces a normalized small-step residual.
- `wv_solve_first_constraint_dense` now performs the dense simplified-Newton
  iteration for the first WV-RATTLE constraint.  The current small-N contract
  reaches `1e-10` residual tolerance in the normalized Stephanov `n=2`
  small-step case.
- The first final-momentum projection contract is present: after a dense
  first-constraint solve, the test constructs `pi_tilde'`, projects it with the
  WV projection at `(z', J')`, and checks reconstruction, orthogonality, and
  that re-projecting the accepted momentum leaves no measurable WV-normal
  residue.
- `wv_rattle_step_dense_no_boundary` now composes the dense first-constraint
  solve and final momentum projection into a single no-boundary WV-RATTLE step.
  The current smoke test performs a small forward step followed by a momentum
  flipped reverse step and checks return errors at the `1e-7` state scale.  The
  step now accepts explicit constraint tolerance and max-iteration controls,
  with the original `1e-8` / `16` defaults preserved.
- `wv_calculate_hamiltonian` records the sampler Hamiltonian contract
  `H=0.5||pi||^2+Re S(z)+W(t)`.  The dense RATTLE smoke now checks fixed-total-
  MD-time energy-error reduction for `W=0`, `W'=0` when the substep size is
  halved and the constraint solve tolerance is tightened.
- `wv_apply_simplified_boundary_rule` implements the simplified-paper
  deterministic boundary rule as a separate kernel: trial states inside
  `[T0-d0,T1+d1]` are accepted, while trial states outside that extended
  interval return to the current `(t,x,z,J)` and flip `pi -> -pi`.  This slice
  intentionally does not guess a partial boundary-crossing or penetration-depth
  integration algorithm beyond the explicit deep-outside bounce rule.
- `wv_rattle_step_dense_with_boundary` wraps the no-boundary dense step with
  the explicit boundary rule and returns a separate `bounced` diagnostic.  The
  contract test verifies both the inside-interval path, which must match the
  no-boundary trial, and the outside-interval path, which must restore the
  current state and flip the incoming momentum.
- The first iterative backend slice is present as an explicit-J BiCGStab
  projection oracle: `wv_decompose_iterative_with_jacobian` and
  `wv_project_iterative_with_jacobian` solve the same real Jacobian system as
  the dense LU path and are tested against the dense projection output.
  `wv_force_iterative_with_jacobian` and
  `wv_simplified_newton_update_iterative_with_jacobian` extend the same
  explicit-J BiCGStab oracle to the WV force and simplified-Newton update.  This
  is an iterative version of the explicit fixed-surface dense oracle, not the
  canonical high-dimensional WV backend.
- The first true matrix-free WV operator slice is present:
  `flow_apply_worldvolume_operator_at` integrates the base flow, one tangent
  vector with `dot v = conj(Hv)`, and one normal vector with
  `dot n = -conj(Hn)` on the same ODE path.  `wv_decompose_matrix_free_at` then
  uses BiCGStab to solve `A w0 = w` through that operator without building the
  dense Jacobian.  Matrix-free projection, force, and simplified-Newton wrappers
  are exposed as `wv_project_matrix_free_at`, `wv_force_matrix_free_at`, and
  `wv_simplified_newton_update_matrix_free_at`.
- Current matrix-free validation covers the zero-flow limit against the dense
  wrappers and a nonzero-flow reconstruction test where a target generated as
  `A w0` is decomposed back to the original `w0` within the configured
  projection tolerance.  This is the certification base for high-dimensional
  backend work; it is not yet wired into the trajectory driver.
- `wv_hmc_potential.f90` provides configurable `W(t)` providers with exact `W`
  and `W'` evaluation.  The original polynomial/zero profile remains available
  for controlled oracles.  The paper-style tilted wall profile is implemented as
  a separate provider and is validated by finite-difference derivative checks;
  production use still requires pilot tuning of `(T0,T1,d0,d1,gamma,c0,c1)`.
- `wv_hmc_trajectory.f90` provides the first deterministic dense trajectory
  proposal kernel.  It composes `W/W'`, dense WV-RATTLE steps, explicit boundary
  handling, trajectory diagnostics, and initial/final Hamiltonian accounting.
  The current contract test verifies that a one-step trajectory with zero
  potential matches the underlying one-step boundary wrapper exactly.
- The trajectory layer also exposes `wv_metropolis_accept_probability`, a
  deterministic fail-closed implementation of `min(1, exp(-Delta H))`.  Random
  accept/reject draws and production IO remain outside this kernel-level slice.
- `wv_transition_dense` adds the first deterministic transition kernel: given an
  externally supplied raw momentum and uniform random variate, it projects the
  momentum to `T_z R`, runs the dense trajectory proposal, performs a production
  reverse-gate replay from `(z', -pi')`, computes the Metropolis probability
  only after the reverse gate passes, and returns either the proposed or
  original state.  Reverse-gate rejection is diagnosed separately from
  Metropolis rejection and forward construction failure.  RNG ownership and
  output streams remain outside this kernel.
- `run_wv_hmc_smoke` is a diagnostic app for the same deterministic transition
  path.  It reads the active model parameters, forces the manual derivative
  provider, constructs a small deterministic real seed state and raw momentum,
  then prints transition, constraint, and ODEX diagnostics.  This is a command
  line smoke test only; it is not a production WV-HMC driver or IO format.
- `wv_hmc_app_common.f90` centralizes the first WV-HMC app namespace, output,
  and potential-profile parsing.  `run_wv_hmc_smoke` remains a three-cycle
  `WV_HMC_SMOKE_*` diagnostic entry point, while `run_wv_hmc` is the standalone
  dense pilot entry point using the `WV_HMC_*` namespace and writing summary and
  observable CSV files by default.  Both apps still use the dense oracle backend
  and deterministic initial seed state; production bank/snapshot initialization
  is a later explicit feature.
- `wv_hmc_driver.f90` adds the first dense chain-level driver kernel.  It uses
  WV-specific counter-based RNG domains for Gaussian momentum and Metropolis
  accept draws, repeatedly calls `wv_transition_dense`, and reports
  cycle-level diagnostics without entering TLTM Stage2.  The summary includes
  reverse-gate rejection counts and last reverse-gate state/momentum errors, as
  well as flow-time coverage diagnostics (`min`, `max`, `mean`, observation
  count) so `W(t)` and HMC parameter pilots can check transport instead of only
  final flow time.  The smoke app now exercises this driver and writes a one-row
  CSV summary through
  `WV_HMC_SMOKE_SUMMARY_FILE` (default:
  `output/tests/wv_hmc_smoke_summary.csv` via the Makefile target).
- `wv_hmc_measurement.f90` adds the first dense measurement oracle for
  `F_WV = alpha^{-1} det(E)/|det(E)| exp(-i Im S)`.  It computes `alpha^2`
  from the fixed-surface split of `xi`, keeps the existing dense
  `log_determinant` phase convention, and returns both the unit phase factor
  and the full `alpha^{-1}`-weighted WV factor.  The current contract test
  checks the `t=0` real-plane case against an explicit hand calculation where
  `det(E)=1` and `alpha^2` is the squared imaginary component of `xi`.
- The measurement module also exposes a ratio-preserving weighted-observable
  accumulator.  It stores `sum F_WV O`, `sum F_WV`, `sum |F_WV|`, sample count,
  phase coherence, and final estimates as a single numerator/denominator
  structure so future WV readbacks cannot accidentally bootstrap or average
  numerator and denominator independently.
- `wv_hmc_driver.f90` can optionally receive that accumulator.  When present it
  evaluates the WV measurement factor and current model observables after each
  completed cycle inside the configured measurement flow-time subinterval
  `[\tilde T0,\tilde T1]` and accumulates the ratio estimator without feeding
  any measurement information back into the transition decision.  The driver
  defaults the measurement subinterval to the sampler/worldvolume interval
  `[T0,T1]` and fails closed unless
  `T0 <= \tilde T0 < \tilde T1 <= T1`.
- `run_wv_hmc_smoke` now reports final-state `alpha`, `alpha2`, phase, WV factor
  components, accumulated WV denominator diagnostics, measurement counts, and
  phase coherence in stdout and in `wv_hmc_smoke_summary.csv`; the summary also
  records the sampler interval `(sampler_t0,sampler_t1,d0,d1)` separately from
  the measurement interval `(measurement_t0,measurement_t1)`.  It also writes
  generic model-observable ratio estimates through `WV_HMC_SMOKE_OBSERVABLE_FILE`
  (default: `output/tests/wv_hmc_smoke_observables.csv` via the Makefile target).
  The smoke measurement window defaults to the sampler interval `[T0,T1]` and
  can be overridden with `WV_HMC_SMOKE_MEASUREMENT_T0` and
  `WV_HMC_SMOKE_MEASUREMENT_T1`.  The smoke `W(t)` profile defaults to `zero`;
  `WV_HMC_SMOKE_W_PROFILE=paper_wall` enables the paper-style tilted wall using
  `WV_HMC_SMOKE_W_GAMMA`, `WV_HMC_SMOKE_W_C0`, and `WV_HMC_SMOKE_W_C1` together
  with the existing sampler interval and wall-depth settings.  Reverse-gate
  tolerances default to `1e-6` for normalized state error and `1e-4` for
  normalized momentum error, and can be overridden with
  `WV_HMC_SMOKE_REVERSE_GATE_STATE_TOL`,
  `WV_HMC_SMOKE_REVERSE_GATE_MOMENTUM_TOL`, `WV_HMC_REVERSE_GATE_STATE_TOL`,
  and `WV_HMC_REVERSE_GATE_MOMENTUM_TOL`.
- `wv_rattle_step_dense_with_boundary` now also handles lower hard-wall
  crossings for the current nonnegative-flow backend.  If the first
  simplified-Newton flow-time displacement would require a negative flow-time
  evaluation, the wrapper applies the simplified-paper bounce directly: keep
  current `(t,x,z,J)` and flip `pi -> -pi`.  This is a domain guard for the
  explicit hard wall, not a partial boundary-crossing integrator.  General
  outside-interval trials that remain in the nonnegative flow domain still go
  through the no-boundary trial and the explicit boundary rule.  Negative
  `T0-d0` remains unsupported until the flow backend defines negative-time
  behavior.
- Cluster-only dense pilots were run on cluster02 after the local-execution
  policy change; no local simulation evidence is used for the pilot decision.
  See
  `runbooks/generated/wv_hmc_dense_pilot_cluster_20260529/README.md`.
  Both PBS jobs passed the WV math and constraint kernel tests before running
  the scans.  The initial grid confirmed that flat `W(t)` concentrates near
  small flow time, while the focused tilted-wall grid identified the current
  conservative dense-oracle working point:
  `paper_wall gamma=1`, `T0=0.005`, `T1=0.2`, `d0=0.005`, `d1=0.05`,
  `epsilon=0.002`, `nstep=2`.  This is a pre-matrix-free wiring point, not a
  production physics setting.

Do not proceed to the production driver, production IO, or production runs until the
dense projection oracle, force/flow convention tests, first-constraint residual
tests, first-constraint nonlinear solve tests, final momentum projection tests,
boundary rule tests, reversibility/energy tests, and smoke transition diagnostics
pass.  Exact lower hard-wall startup and near-lower-wall negative crossing now
have source-level contract tests; negative-flow startup and any future partial
boundary-crossing integrator remain separate source-supported features, not
implicit behavior.
