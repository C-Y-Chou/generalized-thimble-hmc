# F18b Handwritten ODEX Endpoint Hardening

Date: 2026-05-16 JST
Scope: `src/physics/odex_backend.f90`, the `solve_flow:intode*` endpoint
wrapper path, and deterministic endpoint-flow tests.
Status: active plan; source unchanged in this decision packet.

## Decision

Return the ODE-controller modernization route to the handwritten endpoint ODEX
backend, after the F18 SUNDIALS CVODE evaluation failed to produce a better
canonical production route.

This is not a decision to claim full Hairer ODEX paper correctness.

The target claim is:

```text
TLTM uses a paper-aware endpoint extrapolation backend in the Hairer ODEX/GBS
family, with the Hairer IWORK(3)=3 sequence, explicit TLTM endpoint-only
product scope, documented controller policy, deterministic branch tests, and
affected-baseline gates for any behavior-changing controller patch.
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

- first-step `h0` policy: current default is `t * initial_step_fraction`;
- h-min floor and failure classification;
- missing explicit Hairer-style `WORK(4)` / `WORK(5)` step-size bounds;
- order promotion/demotion thresholds and branch predicates;
- rejected-step controller behavior;
- large-error demotion threshold;
- `1.0e-14` error floor in controller estimates;
- optional conservative stability branch and default no-stability policy;
- ODEX/flow counters, traces, and last-failure snapshots still mixed with
  broader hidden state/productization work.

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

### F18b.1 - Behavior-Free Deterministic Controller Tests

Goal: freeze the current controller behavior before debating patches.

Deliverables:

- `test_odex_controller_policy_contract` or equivalent focused tests covering:
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

### F18b.2 - Explicit TLTM Policy Wording

Goal: decide which controller details are accepted project policy rather than
paper-equivalent implementation.

Decision points:

- keep `h0 = 0.01 * t` as TLTM endpoint policy, or introduce a Hairer-inspired
  initial-step estimate as a behavior-changing candidate;
- keep current h-min floor policy, or replace with a more paper-aligned
  min-step policy;
- accept current order thresholds, or align decrease/increase thresholds with
  Hairer-style defaults;
- add explicit growth/shrink bounds, or document why endpoint TLTM truncation
  and failure-as-rejection are the chosen policy;
- keep conservative stability control disabled by default, or add a stricter
  default only after affected-baseline evidence.

Gate:

- decision packet before source behavior changes.

### F18b.3 - ODEX/Flow State Productization

Goal: continue modernization without altering the solver kernel.

Deliverables:

- migrate ODEX/flow counters, traces, and last-failure snapshots out of active
  module state into explicit run/workspace context, or document a product
  boundary for legacy direct callers;
- preserve current status/counter output unless a schema change is explicitly
  approved.

Gate:

- focused context-isolation tests;
- exact-output or affected-baseline comparison for any counter/status surface.

### F18b.4 - Optional Controller Alignment Patch

Goal: only after F18b.1/F18b.2, decide whether to patch controller behavior.

Candidate behavior-changing patches:

- Hairer-style initial-step estimator;
- explicit step-size growth/shrink bounds;
- corrected decrease/increase order thresholds;
- broader stability check.

Gate:

- one patch family per commit;
- F8 behavior statement;
- focused deterministic branch tests;
- M4;
- affected-baseline comparison at the smallest useful scale before any 10k
  production-like rerun.

## Immediate Next Step

Start with F18b.0/F18b.1, not a behavior-changing source patch.

The first source-facing patch should add a focused deterministic ODEX controller
policy contract that observes and freezes current behavior.  If the test needs
small helper accessors for pure controller helpers, add them without changing
the production integration path.

After that test exists, decide whether `h0`, h-min, step-size bounds, order
thresholds, and stability policy are accepted TLTM endpoint policy or candidates
for a separate behavior-changing patch.

## Relationship To Other Workstreams

- F18 SUNDIALS CVODE: parked as disabled-by-default comparison-only evidence.
- F17/CV-012: this is the ODEX-controller closure path for handwritten
  algorithm claim boundaries.
- F13/W9: ODEX/flow hidden-state cleanup remains part of explicit
  context/productization.
- F20: precision/tolerance profile design must remain separate from this
  strict double-precision ODEX hardening baseline.
