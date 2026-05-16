# F18b Handwritten ODEX Endpoint Hardening

Date: 2026-05-16 JST
Scope: `src/physics/odex_backend.f90`, the `solve_flow:intode*` endpoint
wrapper path, and deterministic endpoint-flow tests.
Status: F18b.0/F18b.1 source map and observation contract implemented;
F18b.2 controller decision packet added and later superseded; F18b.3/F18b.3a
state productization implemented; HWM-ODEX-001 selected F18b.4 controller
alignment; F18b.4a spec/probe target implemented.

## Decision

Return the ODE-controller modernization route to the handwritten endpoint ODEX
backend, after the F18 SUNDIALS CVODE evaluation failed to produce a better
canonical production route.

This is not a decision to claim the current backend is already full Hairer ODEX
paper-correctness.  The user has selected changing controller surfaces toward
Hairer/paper or stronger-reference behavior through F18b.4.

The target claim is:

```text
TLTM uses a paper-aware endpoint extrapolation backend in the Hairer ODEX/GBS
family, with the Hairer IWORK(3)=3 sequence, explicit TLTM endpoint-only
product scope, explicitly unresolved controller decision surfaces,
deterministic branch tests, and affected-baseline gates for any
behavior-changing controller patch.
```

Blocked claim:

```text
The handwritten endpoint ODEX backend is a complete line-by-line
implementation of Hairer's full ODEX controller.
```

## Why The Route Changed

F18 built and tested a disabled-by-default SUNDIALS CVODE backend.  Strict CVODE
is valuable as a comparison backend, but the current evidence does not promote
it to canonical production:

- strict CVODE completed the 10seed/10k comparison but was much slower than the
  handwritten ODEX baseline;
- fixed-point `m>0` tuning was rejected as slower without useful TLTM payoff;
- `TLTM_CVODE_MAX_STEPS=320` was faster but changed proposal/failure behavior
  and observables at 10seed/10k;
- non-max-step fail-fast tuning found `TLTM_CVODE_MAX_CONV_FAILS=1` exact vs
  strict CVODE at 10seed/10k, but it was slower.

Therefore the practical modernization path is to harden the current endpoint
ODEX backend as owned project code, while keeping SUNDIALS CVODE as a
disabled-by-default comparison and diagnostic backend.

## Current ODEX Claim Boundary

Use `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md` as the source map.

Currently matched or intentionally scoped:

- explicit midpoint / extrapolation family;
- Hairer `IWORK(3)=3` step-number sequence: `2,4,6,8,12,16,24,32,...`;
- endpoint-only TLTM product boundary;
- signed interval handling through signed `h` and positive work estimates;
- inverse flow through the negative RHS scale in `flowzr`.

Open-needs-proof or TLTM-specific:

- first-step `h0` behavior: current default is `t * initial_step_fraction`;
- h-min floor and failure classification;
- missing explicit Hairer-style `WORK(4)` / `WORK(5)` step-size bounds;
- order promotion/demotion thresholds and branch predicates;
- rejected-step controller behavior;
- large-error demotion threshold;
- `1.0e-14` error floor in controller estimates;
- optional conservative stability branch and default no-stability policy;
- broader hidden state/productization work is still active outside the F18b.3a
  ODEX/flow diagnostics and runtime-trace slice.

The list above was the decision surface.  The current confirmed decision is:
patch ODEX controller surfaces toward Hairer/paper or stronger-reference
behavior, but only after F18b.4 writes the spec, branch tests, F8 statement, and
affected-baseline plan.

## F18b.0 Source Map

This map records where controller behavior currently lives.  It is evidence
for later decisions, not a claim that the choices are already paper-correct.

| Surface | Source owner | Current behavior | F18b status |
| --- | --- | --- | --- |
| Runtime knobs | `odex_options` | Stores backend, tolerance, order limits, max steps, CVODE knobs, `h_min_*`, `initial_step_fraction`, and optional conservative stability knobs. | observe first |
| Result/status contract | `odex_result`, `odex_result_mark_*`, `odex_result_to_intode_status` | Reports endpoint success, zero-time success, max-step failure, invalid failure, h-min failure, counters, final order/step, and CVODE diagnostics. | observe first |
| Workspace tables | `odex_workspace`, `ensure_odex_workspace_object`, `ensure_odex_tables` | Owns extrapolation tableaux, midpoint state buffers, `nsteps`, `ak`, inverse exponents, and ratios. | observe first |
| Endpoint controller | `odex_integrate_endpoint*` | Normalizes options, handles zero time, selects ODEX vs CVODE, computes h-min, initializes `h = t * initial_step_fraction`, truncates the final step, accepts on `er1 < 1`, rejects otherwise, and classifies max-step/h-min/invalid failure. | observe first |
| Step controller | `odex_step*` | Builds midpoint/extrapolation rows, applies optional conservative stability rejection, evaluates order branches, and returns signed next `h`, order, result, and normalized error estimate. | observe first |
| Step sequence | `build_nsteps`, `odex_iwork3_nstep` | Hairer `IWORK(3)=3` sequence `2,4,6,8,12,16,24,32,...`. | freeze as TLTM endpoint policy |
| Work estimate | `calculate_ak`, `calculate_wk` | `ak` uses the same `IWORK(3)=3` helper; `wk` is positive through `abs(h)`. | observe first |
| Step estimate | `calculate_hk` | Candidate step keeps the sign of the current interval and uses the `1.0e-14` error floor. | observe first |
| Observation seam | `odex_observe_*` helpers | Public test/readback helpers expose current h-min, first step, controller estimate, large-error threshold, and stability predicate without changing the production integration path. | F18b.1 guardrail |

## F18b.0 Decision Table

| Controller surface | Classification now | Behavior-changing if patched? | Required gate before patch |
| --- | --- | --- | --- |
| Hairer `IWORK(3)=3` sequence | `freeze_as_TLTM_policy` | yes | F8 statement, focused ODEX tests, M4, affected baseline |
| `h0 = t * initial_step_fraction` | `test_current_behavior_first` | yes | F18b.2 decision, F8 statement, focused ODEX tests, M4, affected baseline |
| h-min floor and h-min failure status | `test_current_behavior_first` | yes | F18b.2 decision, F8 statement, focused ODEX tests, M4, affected baseline |
| explicit growth/shrink step-size bounds | `candidate_behavior_change` | yes | F18b.2 decision plus smallest useful affected-baseline screen |
| order promotion/demotion predicates | `test_current_behavior_first` | yes | F18b.2 decision, branch tests, M4, affected baseline |
| rejected-step controller behavior | `test_current_behavior_first` | yes | F18b.2 decision, failure/rejection tests, M4, affected baseline |
| large-error demotion threshold `(k*k + 1)**2` | `test_current_behavior_first` | yes | F18b.2 decision, branch tests, M4, affected baseline |
| controller error floor `1.0e-14` | `test_current_behavior_first` | yes | F18b.2 decision, tolerance/precision impact statement, M4, affected baseline |
| signed interval with positive work estimate | `test_current_behavior_first` | yes | F18b.2 decision, forward/backward endpoint tests, M4, affected baseline |
| default no-stability-control policy | `test_current_behavior_first` | yes | F18b.2 decision, stability tests, M4, affected baseline |
| optional conservative stability branch | `defer_to_product_scope` unless selected | yes | explicit product-policy decision and affected-baseline screen |

## F18b.1 Observation Contract

Implemented `test_odex_controller_observation_contract`, wired into
`build/makefile` and M4.  The focused test freezes the current behavior at the
controller-observation level:

- `h0` helper reports `0.01 * t` for short and long signed intervals;
- h-min observation matches the current `fp`, `tol`, and `span` component
  formula;
- `build_nsteps` reports `2,4,6,8,12,16` for the first six rows;
- signed `calculate_hk` and positive `calculate_wk` behavior is observable;
- the `1.0e-14` controller error floor and large-error threshold are frozen;
- negative endpoint integration preserves a negative final step;
- max-step failure classifies as `odex_status_failure_max_steps`;
- invalid RHS rejection classifies through h-min failure after repeated
  rejection;
- default stability control does not reject, while the conservative predicate
  rejects only when both size and growth conditions are met.

This test is a current-behavior freeze.  It does not decide whether the open
surfaces are accepted TLTM endpoint policy or candidates for a later
behavior-changing patch.

Focused readback:

```text
make -C build FC=gfortran LDFLAGS= test_odex_controller_observation_contract
```

Result:

- `h0_hmin_observation ok=T`, with `h_short=2.5000E-03`,
  `h_long=-5.0000E-02`, and `h_min=2.5000E-13`;
- `sequence_work_observation ok=T`, with signed `h_candidate=-1.3469E-01`
  and positive `work=1.5592E+02`;
- `signed_endpoint_observation ok=T`, status `0`, negative final step, and
  endpoint error `4.9960E-16`;
- `max_steps_failure_observation ok=T`, status `101`, accepted steps `1`,
  and `t_remaining=7.5000E-01`;
- `hmin_failure_observation ok=T`, status `103`, rejected steps `35`;
- `stability_observation ok=T`, default `none=F`, conservative `large=T`,
  and `small_dt=F`.

Full local guardrail:

```text
PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Result: `[M4][SUMMARY] all guardrails passed`, artifacts under
`output/tests/m4_guardrails`.

## F18b.2 Decision Packet

The controller decision packet is
`F18B_CONTROLLER_DECISION_PACKET_20260516.md`.

2026-05-16 update: this decision packet is now superseded by HWM-ODEX-001 in
`HANDWRITTEN_MISMATCH_RESOLUTION_TABLE_20260516.md`.  The historical summary
below records what was recommended, but it must not be treated as final
authorization to leave the non-paper-exact surfaces unchanged.

Summary:

- accept the narrow TLTM endpoint ODEX/GBS claim with Hairer `IWORK(3)=3`;
- keep signed intervals and positive work estimates as TLTM endpoint policy;
- preserve current `h0`, h-min, order predicates, rejection behavior, large
  error threshold, and `1.0e-14` floor for modernization closure;
- do not add explicit Hairer `WORK(4)` / `WORK(5)` growth-shrink bounds now;
- keep default stability control as `none`, with conservative stability as an
  explicit opt-in surface only;
- keep SUNDIALS CVODE disabled-by-default comparison-only;
- require F8, M4, focused branch/failure tests, and affected-baseline evidence
  before any future behavior-changing controller patch.

This historical packet no longer closes F18b controller policy by itself.  It
still documents the previous conservative recommendation and the required gates
for any behavior-changing controller patch.

The active follow-up is
`F18B4_ODEX_CONTROLLER_PAPER_ALIGNMENT_PLAN_20260516.md`.  Its first spec/probe
slice adds `test_odex_controller_alignment_spec` and exposes the current
order-transition branch for deterministic testing.

## F18b.3 State And Behavior-Correction Decision

The state/behavior-correction packet is
`F18B3_ODEX_FLOW_STATE_AND_BEHAVIOR_CORRECTION_DECISION_20260516.md`.

Summary:

- continue with ODEX/flow state productization, not a controller behavior
  patch;
- split per-call runtime trace/context state from run-level diagnostics;
- add a run-owned INTODE/ODEX diagnostics context for fallback counters,
  context bins, disabled-by-default CVODE comparison counters, and
  last-failure snapshots;
- keep legacy module fallback for direct callers and compatibility tests;
- preserve current public counter/status/output values unless an explicit
  behavior-correction packet says otherwise;
- if implementation reveals a wrong public diagnostic definition, stop and
  decide it under F4/F7/F8 before changing output/schema semantics;
- any endpoint solver, final-flow, reverse-gate, or Metropolis behavior change
  remains outside F18b.3 and needs explicit approval plus affected-baseline
  evidence.

## Hard Rules For This Slice

- Do not change physics/output in an ordinary cleanup commit.
- Any behavior-changing ODEX controller patch needs an F8 statement, M4, and an
  explicit affected-baseline comparison or a user-approved narrower baseline.
- Do not remove the handwritten ODEX backend while it is the canonical behavior
  baseline.
- Do not promote SUNDIALS CVODE to canonical without a new decision packet.
- Do not broaden the product claim to dense output or a general-purpose ODE
  solver unless the user explicitly reopens that scope.

## Work Packages

### F18b.0 - Source Map And Decision Table

Goal: make the ODEX hardening work executable without relying on chat context.

Deliverables:

- source map for `odex_options`, `odex_result`, `odex_workspace`,
  `odex_integrate_endpoint*`, `odex_step`, `build_nsteps`, `calculate_ak`,
  `calculate_hk`, and `calculate_wk`;
- decision table for every open controller surface:
  `freeze_as_TLTM_policy`, `test_current_behavior_first`,
  `candidate_behavior_change`, or `defer_to_product_scope`;
- F8 classification for each candidate source patch.

Gate:

- docs/control-plane validation only; no source behavior change.

### F18b.1 - Behavior-Free Deterministic Controller Observation Tests

Goal: observe and freeze the current controller behavior before accepting or
patching any undecided surface.

Deliverables:

- `test_odex_controller_observation_contract` or equivalent focused tests
  covering:
  - `IWORK(3)=3` step sequence and work-estimate positivity;
  - first-step initialization for short and long endpoint intervals;
  - signed `h` preservation and negative-interval work estimates;
  - synthetic step-size/order branch cases near accept/reject thresholds;
  - h-min failure classification and result/status mapping;
  - default no-stability-control behavior plus conservative stability rejection.

Gate:

- focused ODEX test target;
- `git diff --check`;
- M4 guardrails if public test/build manifests change.

### F18b.2 - Controller Decision Packet

Goal: decide which controller details are accepted as TLTM endpoint policy,
which should be patched toward Hairer-style behavior, and which remain deferred
behind product scope.

Decision points:

- decide whether to accept current `h0 = 0.01 * t` as TLTM endpoint policy, or
  introduce a Hairer-inspired initial-step estimate as a behavior-changing
  candidate;
- decide whether to accept current h-min floor policy, or replace it with a
  more paper-aligned
  min-step policy;
- decide whether to accept current order thresholds, or align
  decrease/increase thresholds with Hairer-style defaults;
- decide whether to add explicit growth/shrink bounds, or document why
  endpoint TLTM truncation and failure-as-rejection are the chosen policy;
- decide whether to keep conservative stability control disabled by default, or
  add a stricter default only after affected-baseline evidence.

Gate:

- complete in `F18B_CONTROLLER_DECISION_PACKET_20260516.md`; no source
  behavior changes authorized by this packet.

### F18b.3 - ODEX/Flow State Productization

Goal: continue modernization without altering the solver kernel.

Deliverables:

- migrate ODEX/flow counters and last-failure snapshots into a run-owned
  diagnostics context;
- move active runtime trace/context attribution off shared module state on the
  Stage1/Stage2 product path;
- preserve legacy direct-call compatibility through module fallback;
- preserve current status/counter output unless a schema or diagnostic behavior
  correction is explicitly approved.

Gate:

- focused context-isolation tests;
- exact-output or affected-baseline comparison for any counter/status surface.

### F18b.4 - Selected Controller Alignment Patch

Goal: implement the confirmed HWM-ODEX-001 direction by aligning controller
behavior toward Hairer/paper or stronger-reference behavior, without batching all
controller surfaces into one risky source patch.

Selected behavior-changing patch families:

- Hairer-style or stronger-reference initial-step estimator;
- explicit step-size growth/shrink bounds;
- paper-aligned or reference-backed order decrease/increase thresholds;
- h-min/min-step policy and failure classification;
- rejected-step/status branch behavior;
- stability policy.

Gate:

- one patch family per commit;
- F8 behavior statement;
- focused deterministic branch tests;
- M4;
- affected-baseline comparison at the smallest useful scale before any 10k
  production-like rerun.

## Immediate Next Step

F18b.3a has been implemented as a behavior-preserving state-productization
slice, and F18b.4a has added the first spec/probe test target without changing
endpoint integration behavior.

The next source-facing step is the first behavior-changing F18b.4 family:
growth/shrink bounds plus order-threshold alignment.  Patch one controller
family at a time.  Each family needs a row-specific F8 statement, focused tests,
M4 gate, and affected-baseline plan before changing production behavior.

## Relationship To Other Workstreams

- F18 SUNDIALS CVODE: parked as disabled-by-default comparison-only evidence.
- F17/CV-012: this is the ODEX-controller closure path for handwritten
  algorithm claim boundaries.
- F13/W9: ODEX/flow hidden-state cleanup remains part of explicit
  context/productization.
- F20: precision/tolerance profile design must remain separate from this
  strict double-precision ODEX hardening baseline.
