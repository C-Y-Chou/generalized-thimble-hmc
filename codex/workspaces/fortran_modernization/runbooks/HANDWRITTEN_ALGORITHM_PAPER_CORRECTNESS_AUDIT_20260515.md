# Handwritten Algorithm Paper-Correctness And Numerical-Soundness Audit - 2026-05-15

## Scope

Audit target:

- canonical local tree: `/Users/ccy/Documents/TLTM_qn_error_handling`
- branch: `codex/fortran-modernization`
- committed source head inspected: `3d63d4c`
- current assist-off run-producing source SHA: `71af06f55c240a0c20fc7a38c1353219be805930`
- current-head claim-boundary input:
  `HANDWRITTEN_ALGORITHM_CURRENT_HEAD_AUDIT_20260515.md`
- earlier claim-boundary inputs:
  - `HANDWRITTEN_ALGORITHM_DETAIL_AUDIT_GAP_REPORT_20260514.md`
  - `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`
  - `HANDWRITTEN_ALGORITHM_CURRENT_ANALYSIS_REPORT_20260514.md`

Purpose: audit the stronger claim "all handwritten algorithms are
paper-correct."  Where the implementation is not an exact paper
implementation, this audit also checks whether the code is numerically and
physically defensible for the current TLTM route.

## Audit Standard

This report separates four levels of evidence:

1. `paper-matched`: implementation formula and relevant controller/status
   surface are directly mapped to the defining paper/reference.
2. `paper-family/partial`: core formula is mapped, but controller constants,
   branch decisions, failure policy, or product boundary are project-specific.
3. `project-policy numerically sound`: code is not literally the paper policy,
   but appears Markov-safe, stability-oriented, or otherwise defensible under a
   clearly scoped project contract.
4. `open-needs-proof`: the code may be reasonable, but this audit did not find
   enough paper mapping or deterministic branch evidence to sign it as
   publication-grade paper-correct.

Passing behavior baselines, M4/F8 guardrails, and production readbacks are
important, but they are not substitutes for paper-level implementation-detail
signoff.

## Executive Verdict

The audit is complete for the current source.  No immediate production source
bug requiring a physics-changing Fortran patch was established.

The stronger claim is blocked:

```text
All handwritten TLTM numerical algorithms are paper-correct.
```

The correct current claim is:

```text
The current TLTM modernization source is paper-mapped and
numerical-soundness-audited at the handwritten-algorithm boundary.  Several
core formulas match the defining references, but ODEX controller policy,
RATTLE/HMC failure handling, BTN/QN controller policy, Stage2 RNG/replay
evidence, Metropolis output API semantics, model-derivative provenance, and
diagnostics/counter surfaces remain explicitly scoped and cannot be represented
as universal paper-correctness.
```

## Algorithm Classification

| Area | Verdict | Audit result |
| --- | --- | --- |
| Action and derivatives | source-consistent, not independently paper-signed | `model_action_body.inc`, `model_generated.f90`, and the Tapenade-style derivative path are internally consistent with the implemented action.  The finite-difference derivative guardrail exists.  This audit did not independently derive the action from the physics paper, so claim it as source-consistent unless a separate model-derivation note is added. |
| Antiholomorphic flow RHS | paper-matched core, partial product surface | `flowz` initializes real `x` with zero imaginary part and integrates `dot z = conjg(dS/dz)`; `flowzr` uses the negative sign for inverse flow; `flow` propagates `dot J = conjg(H J)`.  This matches the TLTM flow equations at RHS level.  ODEX controller and model-cache state remain separate caveats. |
| ODEX endpoint backend | paper-family/partial | Explicit midpoint/extrapolation and the Hairer `IWORK(3)=3` sequence are mapped.  The current endpoint-only backend is not a full Hairer ODEX implementation: `h0`, `h_min`, step-size growth/shrink bounds, order thresholds, rejection, and stability policy are project-specific or still open-needs-proof. |
| RATTLE/HMC core step | mostly paper-matched core, project-policy failure surface | The step order maps to RATTLE-style half force, constrained position projection, final flow, half force, tangent projection, Hamiltonian, and Metropolis acceptance.  Failure handling is not literally the paper's momentum-flip continuation; TLTM treats failures/reverse-gate failures as proposal rejection/stay-put through callers and accounting.  That is Markov-safe under the current API usage, but not paper-exact. |
| Simplified Newton projection | paper-matched target, project-policy controller | The projection residual and fixed-Jacobian split match the simplified-Newton/fixed-point idea used for the flowed manifold constraint.  Iteration caps, near-case extension, divergence, stagnation, and tiny-step exits are project numerical policy, not external-paper detail. |
| BTN/QN and official DFO-LS bridge | matched residual target, partial controller | The active route uses the official DFO-LS package with TLTM-side residual certification.  The handwritten bridge, initial guesses, budget/watchdog policy, best-candidate recovery, and legacy internal DFO-like fallback code are project policies and must not be described as a paper-exact DFO-LS implementation. |
| Metropolis acceptance and live-state contract | acceptance paper-matched, API caveat | `Delta H = H_final - H_initial`, `min(1, exp(-Delta H))`, invalid proposal reset, and failure-as-rejection are correct.  On an ordinary finite Metropolis reject, `metropolis_step` leaves proposal buffers in `x_new/z_new/j_new`; inspected callers commit only when `accepted`, so the live Markov state is safe.  Future callers must not assume every rejection returns the current state in output buffers. |
| Stage2 replica exchange/swap | paper-matched acceptance, partial replay evidence | Swap acceptance uses effective energy `Re S - Re log det J` after reflowing labels at the other flow time, and rejected swaps keep slots unchanged.  One-parity-per-cycle scheduling and RNG keying are product policy; schedule/order invariance and swap-isolation evidence are still needed before stronger replica-exchange proof claims. |
| Stage2 RNG v2 | product-contract sound, not a paper-correctness claim | Philox-style counter-based domain-separated keys for init/local momentum/local accept/swap accept are a sound RNG ownership correction and are tested with known-answer/domain-separation checks.  RNG v2 intentionally changes finite same-seed trajectories and is not itself a paper-correctness proof. |
| Phase/reweighting/effective energy | paper-mapped formula | `compute_phase_factor` uses `exp(-i Im S + i Im log det J)`.  Stage2 effective energy uses `Re S - Re log det J`, matching the TLTM measure/swap acceptance surface.  Principal-branch log-determinant behavior should be kept as an explicit numerical convention. |
| Diagnostics and counters | useful evidence, not paper signoff | Typed local-transition accounting and sidecars are strong engineering evidence.  Broader solver/flow/constraint counters and failure-capture surfaces are not part of paper-correctness and should not be used as proof without schema/versioned audit. |

## Code Inspection Notes

### Action And Model Derivatives

Inspected surfaces:

- `src/physics/model_action_body.inc`
- `src/physics/model_generated.f90`
- `src/physics/model_autodiff.f90`
- `tests/test_action_derivatives.f90`

The action body is the single formula source for `calculate_action`, and the
generated derivative path uses the same structure.  This is the correct
software shape for source consistency.  The remaining limitation is provenance:
the audit checked consistency against the implemented action, not an
independent paper derivation of that action and branch conventions.

Status: no immediate source bug found; add a short model-derivation note before
claiming paper-level model correctness.

### Flow And Jacobian RHS

Inspected surfaces:

- `src/physics/solve_flow.f90:906`
- `src/physics/solve_flow.f90:945`
- `src/physics/solve_flow.f90:984`
- `src/physics/solve_flow.f90:1031`
- `src/physics/solve_flow.f90:1051`

`flowz_with_workspace` packs `x(2:)` as the real initial condition and zeroes
imaginary components.  `rhs_flow_vec_context` evaluates `ds(z)` and maps the
conjugate derivative into the real ODE vector.  `flowzr_with_workspace` uses
the same RHS with scale `-1`, giving inverse-flow sign handling.  The Jacobian
RHS computes Hessian-vector products `H J` and maps their conjugates into the
real ODE system.

Status: flow/Jacobian RHS is paper-matched at the differential-equation level.
Do not let that statement absorb ODEX controller details or model-cache state.

### ODEX Endpoint Backend

Inspected surfaces:

- `src/physics/odex_backend.f90:25`
- `src/physics/odex_backend.f90:94`
- `src/physics/odex_backend.f90:115`
- `src/physics/odex_backend.f90:763`
- `src/physics/odex_backend.f90:816`
- `src/physics/odex_backend.f90:996`

The implementation has an endpoint-only product boundary, `IWORK(3)=3` step
sequence, midpoint/extrapolation machinery, and a conservative stability
surface.  Hairer-style constants `0.65` and `0.94` appear in the step estimator.
The important mismatch is controller completeness: the current code does not
implement or prove the full Hairer ODEX control surface for initial `H`, `WORK`
bounds, order-selection thresholds, and stability branch behavior.

Status: no immediate bug found; the all-paper-correct claim remains blocked by
ODEX controller detail closure.  The current modernization decision is not to
prove the handwritten controller as full Hairer ODEX.  Use
`MATURE_ODE_BACKEND_DECISION_20260515.md` as the route for closing long-term
handwritten ODE-controller risk through a mature external package backend.

### RATTLE, HMC, And Failure Policy

Inspected surfaces:

- `src/sampler/hmc_integrator_core.f90:210`
- `src/sampler/hmc_integrator_core.f90:340`
- `src/sampler/hmc_integrator_core.f90:572`
- `src/sampler/hmc_integrator_core.f90:582`
- `src/sampler/hmc_integrator_core.f90:605`
- `src/sampler/hmc_kernels.f90:14`
- `src/sampler/hmc_kernels.f90:34`
- `src/sampler/hmc_kernels.f90:97`

The RATTLE core follows the expected sequence: compute force, form the
projected displacement target, solve the constraint, strictly reflow the final
base point, update momentum from the flowed displacement, apply final force,
project momentum to the tangent space, and optionally run reverse-gate replay.
Hamiltonian evaluation is `0.5*norm2(p)**2 + Re S(z)`.

Two boundary notes matter:

- `calculate_dV` uses the current real-packed convention `E0_real/2`.  This is
  guarded by existing retained-core tests but deserves an equation note before
  making a clean paper-signoff statement.
- Paper-level RATTLE failure discussion uses a momentum flip for projection
  failure.  Current TLTM turns failure/reverse-gate failure into proposal
  rejection/stay-put through the transition machinery.  This is defensible for
  the Markov kernel when callers keep the old state, but it is not the literal
  paper policy.

Status: no immediate production bug found; paper-correctness wording must be
scoped.

### Simplified Newton Projection

Inspected surfaces:

- `src/sampler/hmc_constraints.f90:121`
- `src/sampler/hmc_constraints.f90:244`
- `src/sampler/hmc_constraints.f90:392`

The implementation factors the current real Jacobian once, solves a fixed
linearized projection step, keeps the real/tangent part through `real_vec`, and
puts the complement into the normal/Lagrange component.  The residual is then
re-evaluated through `flowz`.

This is aligned with the simplified Newton/fixed-point projection formulation.
The hard caps, near-extension window, divergence counts, stagnation tests, and
tiny-step tests are numerical engineering policy.

Status: target equation is paper-mapped; controller policy remains project
specific.

### QN, BTN, And Official DFO-LS Bridge

Inspected surfaces:

- `src/sampler/quasi_newton_solver.f90:75`
- `src/sampler/quasi_newton_solver.f90:80`
- `src/sampler/quasi_newton_solver.f90:122`
- `src/sampler/quasi_newton_linear_solver.f90:74`
- `src/sampler/quasi_newton_linear_solver.f90:140`

The active production-facing backend is official DFO-LS with an independent
TLTM residual gate and reconstruction/certification path.  That is the right
claim boundary: official package core plus TLTM-specific acceptance gate.

The bridge remains handwritten: initial guesses, projection-target seeds,
budget/watchdog policy, force-best controls, trace/capture policy, and fallback
classification.  Internal DFO-like routines are legacy/comparison paths, not
the official package and not paper-exact.

Status: no source bug found; do not make paper-correctness claims for the
controller around the package without a dedicated packet.

### Metropolis API And Live-State Safety

Inspected surfaces:

- `src/sampler/markovchain_metropolis.f90:22`
- `src/sampler/markovchain_metropolis.f90:85`
- `src/sampler/markovchain_metropolis.f90:96`
- `src/sampler/markovchain_metropolis.f90:116`
- `src/sampler/markovchain_metropolis.f90:146`
- `src/sampler/tltm_stage2_driver.f90:634`

The acceptance rule is correct.  The proposal outputs are reset to current
state on proposal failure, invalid Hamiltonian, and invalid `Delta H`.  They are
not reset on an ordinary finite Metropolis reject.  Current inspected callers
commit state only if `accepted`, so the live chain is safe.

Status: no current-path bug found.  Add an API contract test or change the
routine to reset output buffers on all rejection before future callers rely on
stay-put outputs.

### Stage2 RNG And Swap Kernel

Inspected surfaces:

- `src/core/tltm_rng.f90:18`
- `src/core/tltm_rng.f90:44`
- `src/core/tltm_rng.f90:65`
- `src/core/tltm_rng.f90:98`
- `src/sampler/tltm_stage2_driver.f90:587`
- `src/sampler/tltm_stage2_driver.f90:1648`

Stage2 now defaults to `stage2_kernel_rng_v2`.  The local transition owns a
domain-separated momentum vector and acceptance uniform.  Swap acceptance uses
its own domain.  This fixes the previous implicit state/ordering ambiguity and
is numerically sound.

The remaining gap is not the RNG primitive; it is protocol evidence.  Before
publication-grade claims, add deterministic first-N-cycle signatures, schedule
or order invariance checks, and swap isolation tests showing local-update keys
do not depend on swap outcomes.

Status: product RNG contract is sound; paper-correctness is still scoped.

### Phase, Determinant, And Effective Energy

Inspected surfaces:

- `src/sampler/markovchain_phase.f90:8`
- `src/sampler/tltm_stage2_driver.f90`
- `src/utils.f90` `log_determinant`

The phase factor is `exp(-i Im S + i Im log det J)`, and Stage2 effective
energy uses `Re S - Re log det J`.  This matches the TLTM measure and swap
acceptance surface.  The determinant uses a principal complex-log convention;
that is acceptable but should be documented as the numerical convention.

Status: formula surface is paper-mapped.

### Legacy Test Trigger Footgun

Inspected surface:

- `src/sampler/hmc.f90:204`
- `src/sampler/hmc.f90:213`

Even when explicit `momentum_in` is passed, `if (istest) momentum = testmom`
overrides the momentum.  Production policy appears to keep `istest` false, so
this is not an active Stage2 RNG v2 production bug.  It is still a dangerous
legacy trigger because enabling `istest` would silently bypass explicit
momentum ownership.

Status: classify under behavior-preserving F9 cleanup or an API guardrail test;
do not change it in this audit without an affected-baseline gate.

## Findings

### Finding 1: Universal Paper-Correctness Is Blocked

The current source does not support the statement that all handwritten
algorithms are paper-correct.  Several components are paper-matched at the core
equation level, but controller details, failure policies, RNG replay evidence,
and API contracts are project-specific or still open.

Severity: claim-boundary blocker, not an immediate source patch.

### Finding 2: RATTLE Failure Policy Is Soundly Scoped, Not Literal Paper Policy

Current failure handling is proposal rejection/stay-put as used by the callers.
That is Markov-safe for the current route, but it differs from the paper's
momentum-flip discussion for projection failure.  This needs either an explicit
accepted limitation or a proof/test packet for the rejection-as-stay-put policy.

Severity: paper-correctness blocker.

### Finding 3: Metropolis Output Buffers Have A Narrow API Contract

An ordinary finite reject can leave proposal values in `x_new/z_new/j_new`.
Current callers only commit on `accepted`, so the live state is safe.  Future
callers need either a test/documented contract or a code patch that resets
outputs on all rejection.

Severity: API caveat, no current-path bug found.

### Finding 4: Legacy `istest/testmom` Can Override Explicit Momentum

The explicit Stage2 RNG v2 momentum path can be bypassed if `istest` is enabled.
This is not active under the current production contract but should be cleaned
or guarded before product hardening.

Severity: legacy-trigger footgun.

### Finding 5: ODEX Controller Remains The Largest Paper Detail Gap

Endpoint flow is sufficient for the TLTM product boundary, and the core
midpoint/extrapolation machinery is mapped.  Full Hairer ODEX paper-correctness
is still not established for h0, h-min, growth/shrink bounds, order control,
and stability/rejection branches.

Severity: paper-correctness blocker.

## Closure Queue

1. Mature ODE backend packet:
   - keep the current handwritten endpoint-only ODEX as the behavior baseline;
   - evaluate SUNDIALS CVODE as the primary external backend candidate;
   - use ODEPACK LSODA/LSODE as fallback if SUNDIALS packaging is too costly;
   - require endpoint, retained-core, Stage2, M4, and F8 affected-baseline
     gates before changing the canonical backend.
2. RATTLE/HMC failure-policy packet:
   - decide whether rejection-as-stay-put is the accepted TLTM product policy;
   - add deterministic tests around every proposal failure/reverse-gate status;
   - document why the policy preserves the Markov kernel.
3. Metropolis API packet:
   - either document/test "outputs only meaningful when accepted" or reset
     output buffers on all rejection under F8/M4.
4. Stage2 RNG/swap replay packet:
   - first-N-cycle draw signatures;
   - local-update order invariance;
   - swap isolation;
   - sidecar evidence that rejected swaps leave state unchanged.
5. QN/BTN controller packet:
   - budgets, watchdogs, near/far classification, force-best, official-bridge
     failure modes, and best-candidate certification.
6. Model/action derivation packet:
   - one short derivation/provenance note tying the implemented action and
     branch conventions to the physics definition.
7. Diagnostics/counter schema packet:
   - typed event ownership for broader flow/constraint/replay/capture counters;
   - keep diagnostics separate from paper-correctness claims.

## Allowed And Blocked Wording

Allowed:

```text
The current source has an all-handwritten-algorithm paper-correctness and
numerical-soundness audit.  It found no immediate current-route source bug, but
it explicitly scopes non-paper-exact controller, failure-policy, RNG replay,
API, model-provenance, and diagnostics surfaces.
```

Blocked:

```text
All handwritten algorithms are paper-correct.
```

```text
The current behavior baseline proves paper correctness.
```

```text
Failure reduction or deterministic guardrails prove feedback-kernel measure
correctness.
```

## Bottom Line

This audit satisfies the requested all-handwritten-algorithm audit for the
current modernization source.  The realistic state is not "paper-correct
complete"; it is "paper-mapped, numerically audited, and explicitly scoped."
No immediate source bug was established, but CV-012 remains active until the
closure queue above is resolved or accepted as published limitations.
