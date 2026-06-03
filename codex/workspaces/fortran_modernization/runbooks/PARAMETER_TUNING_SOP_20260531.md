# Parameter Tuning SOP

Date: 2026-05-31

Purpose: freeze the repository-wide order for tuning simulation parameters.
This SOP applies to TLTM and WV-HMC.  Algorithm-specific SOPs may add details,
but they may not invert this dependency order.

## Core Rule

Tune parameters in dependency order.  A downstream parameter must not be tuned
to hide an upstream numerical, initialization, or model-definition problem.

The canonical order is:

1. model and observable correctness;
2. initialization and bank coverage;
3. numerical backend accuracy and solver exit policy;
4. HMC step size `epsilon`;
5. trajectory length through `nstep` and `L=epsilon*nstep`;
6. tempering/worldvolume sampling-shape parameters;
7. production scale: cycles, seeds, snapshots, wall-clock allocation;
8. final observable, robustness, and efficiency validation.

Any upstream change invalidates the downstream tuning unless a targeted
equivalence check shows the downstream behavior is unchanged.

## 1. Model And Observable Gate

Fix before tuning sampler parameters:

- model id and physical parameters;
- physical state layout;
- scalar action;
- manual gradient;
- manual Hessian or Hessian-vector product when required;
- observable analytic definitions;
- exact references when available;
- complexification convention.

Required validation:

- random complex-seed gradient checks by AD or finite differences;
- random complex-seed Hessian/Hv checks by AD or finite differences;
- observable registry checks;
- small-size exact-reference smoke if available.

Do not tune HMC, ladder, `W(t)`, fallback, or solver caps to compensate for an
unvalidated model provider.

## 2. Initialization And Bank Gate

Detailed policy is governed by `INIT_BANK_TUNING_SOP_20260531.md`.

Fix the initial distribution before interpreting sampler tuning:

- t=0 bank or other physical-bank source;
- burn-in and bank construction HMC protocol;
- bank record count and seed coverage;
- restart/snapshot semantics;
- preflow/adaptive initialization policy for nonzero flow time;
- lower fixed-tau bank-builder protocol when used as an initialization source;
- record-selection policy: random bank draw, matched draw, or single-record
  diagnostic.

Checks:

- seed-to-seed scatter;
- action and observable distributions;
- split-bank consistency;
- exact-reference consistency when available;
- coverage of relevant tails or sectors;
- safe-flow prevalidation and filtering diagnostics when the target starts at
  nonzero flow time.

Gaussian starts are allowed only for explicit initialization tests.  For
production-style high-dimensional tests, prefer a validated physical bank.
Single-record starts are diagnostic controls for mixing from one point, not
production evidence.  A safe-init bank that only avoids initial-flow failures is
not a physical-quality bank until it passes the coverage checks above.

For WV-HMC/high-flow starts, a practical bank route is to run a fixed-tau
builder simulation at a lower flow time and then pack those states into the
downstream state-bank format.  The builder sampler has its own HMC tuning and
may use larger `epsilon` and larger `L` than the target production kernel
because the lower-flow geometry is easier.  This is an upstream initialization
workflow: changing the lower `tau`, builder `epsilon`, builder `nstep/L`,
burn-in, or harvested snapshot set invalidates downstream solver/HMC/`W(t)`
tuning unless equivalence is checked.

## 3. Numerical Backend And Solver Gate

Fix numerical accuracy before tuning Markov parameters.

Backend choices include:

- ODE backend and tolerances;
- DOP853 controller, first-step policy, min/max step, RHS budget, and fail-fast
  exits;
- dense vs iterative vs matrix-free projection backend;
- Newton/RATTLE/projection tolerances and stop policy;
- reverse-gate tolerance in production kernels.

Required order for solver stop/fail-fast:

1. Fix tolerance as an accuracy target.
2. Run with adaptive stop disabled and a generous iteration/evaluation cap.
3. Observe convergence traces at that fixed tolerance.
4. Choose fail-fast or cap policy only from the observed residual/evaluation
   behavior.
5. Prove it does not reject eventually convergent solves.
6. A/B verify that enabling it does not change transition, observable, or ratio
   diagnostics except through intended cost reduction.

Do not lower tolerance, max iteration, ODE budgets, or reverse-gate strictness
as the first runtime optimization.  These are numerical policies and require
equivalence evidence.

## 4. HMC Step-Size Gate

Tune `epsilon` before `L`.

`epsilon` controls the local proposal scale and attempt acceptance.  The scan
should use bounded, short, parallel runs and reject only settings that are not
operational:

- no samples or catastrophic timeout;
- invalid Hamiltonian or invalid delta-H behavior;
- attempt acceptance too low for useful HMC;
- runtime per proposal too large for the development stage.

Acceptance must count all attempts, including construction failures that become
stay-put proposals.  Conditional Metropolis acceptance may be reported as a
diagnostic, but it is not the primary step-size acceptance.

Do not choose `epsilon` by minimizing failure count.  Failure/reverse-gate
counts are diagnostics and cost predictors unless they are shown to cause
downstream observable, mixing, or wall-clock damage.

## 5. Trajectory-Length And Movement Gate

After choosing `epsilon`, tune `nstep`; then `L=epsilon*nstep`.

The primary target is useful movement per cost, not acceptance alone.  Required
movement diagnostics:

- accepted and effective `||delta x||^2/n`;
- accepted and effective `||delta z||^2/n` when complexified state exists;
- autocorrelation or block stability for key observables;
- seed-to-seed scatter;
- flow-time movement only as an extended-variable diagnostic;
- wall-clock cost per accepted and per attempted proposal.

For early development, scan small `nstep` values first.  Do not use a larger
`nstep` only because it hides a solver or initialization issue.

## 6. Tempering, Flow-Time, And Worldvolume Sampling-Shape Gate

This layer is algorithm-specific and comes after the local HMC scale is sane.

For TLTM:

- select `t_high` from phase improvement, numerical stability, and feasibility;
- build the ladder sparsely first;
- add intermediate replicas only where edge transport requires them;
- keep `nofb` canonical and treat `withfb` as legacy diagnostic unless frozen
  criteria prove a correctness or efficiency need;
- do not tune ladder density to minimize failure counts alone.

For WV-HMC:

- `[T0,T1]` and the measurement interval are upstream domain choices, not
  sampler-tuning outputs.  They must be fixed from the algorithm/physics target
  before solver, epsilon, and movement scans are interpreted.
- Default `T0 = 0`, the physical-manifold lower endpoint.  A positive `T0` is
  an explicit domain choice, not a numerical safety knob for solver/reflow
  failures.
- Flow-time histograms, boundary counts, movement, and acceptance may reject an
  interval as operationally unusable or trigger an upstream redesign, but they
  are not criteria for selecting `[T0,T1]`.
- With `[T0,T1]` fixed, start with the paper-style wall profile for `W(t)`.
- Use flow-time histograms only to decide whether `W(t)` needs tilt or
  multicanonical tuning within the fixed interval.
- changing `W(t)` or wall parameters requires a solver-health recheck because
  it can change Newton/RATTLE residual behavior.  Changing `[T0,T1]` is an
  upstream domain change and invalidates the full downstream tuning path.

Required diagnostics:

- flow-time histogram;
- boundary bounce/reflection counts;
- high-flow residence and return;
- label or flow-time transport where applicable;
- round trips or equivalent transport proxy;
- phase coherence and phase ESS when weights are complex.

## 7. Production Scale Gate

Only after the algorithmic parameters are fixed:

- choose cycles from expected autocorrelation and target error;
- choose seeds from available resources and seed-level robustness needs;
- choose chunking from scheduler walltime and throughput benchmarks;
- enable snapshots and restart paths;
- define archive/data-retention scope;
- define excluded-runtime manifest before using timing data.

Do not use all-available longer runs as algorithm-intrinsic comparisons unless
the cut is explicitly labeled.  Prefer:

1. matched-seed equal-prefix;
2. equal-cycle;
3. equal-wall-clock;
4. all-available operational summaries.

For wall-clock comparisons, exclude known repair/outlier jobs only by an
explicit manifest and state that the exclusion blocks claims if it prevents a
clean equal-wall-clock cut.

## 8. Final Validation Gate

A production setting is not accepted until it passes:

- exact-reference observable z-scores when references exist;
- real/imaginary components reported separately;
- ratio-preserving uncertainty for complex weights;
- seed-jackknife or seed/bootstrap;
- large-block stability;
- first-half vs second-half stability;
- cumulative prefix stability;
- seed-level outlier and leave-one-seed-out checks;
- acceptance and movement tables;
- solver stop/reverse-gate/failure summaries;
- runtime and throughput table;
- reproducible paths to data and generated summaries.

Observable correctness and wall-clock efficiency are hard gates.  Transport,
failure, and solver diagnostics explain or warn; they are not substitutes for
physical estimator quality.

## Invalidation Matrix

| Change | Must Recheck |
|---|---|
| model/action/derivatives/observable definitions | all gates |
| initial bank or burn-in policy | solver trace, HMC tuning, production validation |
| lower fixed-tau bank-builder `tau`, `epsilon`, `nstep/L`, or harvest window | bank coverage, solver trace, HMC tuning, production validation |
| ODE backend or tolerances | solver trace, HMC tuning, observables |
| Newton/projection tolerance | solver trace, fail-fast A/B, observables |
| solver cap/adaptive stop | fail-fast false-reject audit, A/B, observables |
| reverse-gate tolerance | reversibility/RG A/B, observables |
| `epsilon` | acceptance, movement, solver health |
| `nstep` or `L` | movement, runtime, solver health |
| TLTM `t_high` | ladder, local HMC health, phase/transport |
| TLTM ladder | swap/transport, production validation |
| WV `[T0,T1]` or measurement interval, including any nonzero `T0` choice | solver trace, HMC tuning, `W(t)`, observables |
| WV walls or `W(t)` | flow histogram, solver trace, HMC tuning, observables |
| cycle/seed/chunking | error analysis, robustness, runtime only |

## Anti-Patterns

These are disallowed:

- choosing `L` before `epsilon`;
- lowering solver caps before observing fixed-tolerance convergence;
- loosening tolerance as the first fail-fast tool;
- accepting a setting because failure counts are lower;
- rejecting a setting because failure counts are higher without downstream
  damage evidence;
- using flow-time movement as the only movement metric;
- choosing WV `[T0,T1]` from histogram flatness, acceptance, boundary count, or
  HMC movement diagnostics;
- using equal-sample comparisons as equal-wall-clock comparisons;
- retuning criteria after seeing final data.

## Required Runbook Record

Every production-style tuning sequence must leave a short runbook with:

- fixed upstream inputs;
- exact parameter scan values;
- scheduler job ids and output roots;
- selected parameter and reason;
- rejected alternatives and reason;
- diagnostics used;
- what downstream gates were invalidated or preserved;
- whether the run is development, diagnostic, or production evidence.

## SOP Self-Update Mechanism

If executing the SOP exposes a missing gate, wrong dependency order, ambiguous
criterion, or tooling assumption that can change scientific interpretation:

1. Stop using the affected output for decisions until the gap is classified.
2. Add an amendment entry to the active run ledger with:
   - issue;
   - affected gate;
   - why the existing SOP was insufficient;
   - corrective SOP text or tooling change;
   - whether earlier outputs must be rerun, reanalyzed, or only relabeled.
3. Patch the canonical SOP or child SOP before continuing if the flaw affects
   future choices.
4. Record the patch path, commit/worktree state, and any revalidation command.
5. Resume from the earliest invalidated gate, not from the point where the flaw
   was discovered.

Self-updates must tighten or clarify the SOP.  They must not retune decision
thresholds after seeing final physics data.

Existing algorithm-specific runbooks that implement this SOP:

- `TLTM_CANONICAL_SOP_20260528.md`;
- `STEPHANOV_HMC_PROTOCOL_TUNING_POLICY_20260522.md`;
- `INIT_BANK_TUNING_SOP_20260531.md`;
- `WV_HMC_PARAMETER_TUNING_SOP_20260531.md`.
