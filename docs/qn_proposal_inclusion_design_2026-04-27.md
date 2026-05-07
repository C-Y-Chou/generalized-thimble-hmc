# QN Proposal Inclusion Design

Date: 2026-04-27

## Decision

All rescue design stays inside the QN framework.

The problem is not "new Newton method vs QN". The problem is how to include more QN-generated proposals while keeping the transition kernel consistent.

Current safe baseline:

```text
Newton fail -> QN p28 -> success proposal / fail reject
```

Target:

```text
Newton fail -> QN proposal policy that includes more QN candidates correctly
```

## What Was Wrong With Previous Rescue

The unsafe pattern is sequential conditional fallback:

```text
QN route A fails -> try route B
route B passes gate -> try route C
route C succeeds -> accept proposal
```

This can change the effective proposal support between forward and reverse directions. The issue is not branch switching. Branch switching is allowed if the proposal is reversible and correctly Metropolized.

The issue is that the route itself was chosen after observing solver failure/gate information, but that route-selection probability was not included in the proposal accounting.

## Correct Ways To Include More QN Proposals

Do not treat reverse certification or geometry filters as the main rescue
design. They are diagnostics unless they remove the same proposal class that
causes the ensemble shift. If fullpath passes those filters but still shifts
Re-virial, then the defect is not understood and the policy is not promotable.

### Option A: Fixed QN Route

Pick exactly one QN route before solving. Run only that route.

Examples:

```text
QN_ROUTE_ID=p28
QN_ROUTE_ID=p40
QN_ROUTE_ID=full_s1
QN_ROUTE_ID=seed_bank_p28
```

If the chosen route fails, reject the proposal. Do not switch routes.

This is the cleanest diagnostic. It answers whether a route itself is consistent, independent of fallback chaining.

### Option B: Fixed Route Mixture

Sample a route from fixed weights before the proposal:

```text
P(route=p28)       = w28
P(route=p40)       = w40
P(route=full_s1)   = wfull
P(route=seed_bank) = wseed
```

Then run only the selected route. If weights are fixed and state-independent, the route probability cancels in the Metropolis ratio.

This includes more QN proposals over the ensemble without conditional fallback bias.

### Option C: Delayed Rejection

Sequential fallback is possible, but only if implemented as proper delayed rejection:

```text
try q1
if q1 fails/rejects, try q2 with corrected acceptance probability
```

This requires proposal-density / reverse-path correction terms. We should not implement this first.

## First Practical Candidate: Fixed QN Seed Bank

The first new route should still call:

```text
solve_constraint_quasi_newton(...)
```

but with a fixed candidate set inside one route:

```text
QN_ROUTE_ID=seed_bank_p28
```

Candidate seeds can be:

- standard Jacobian seed;
- scaled Jacobian seed: `0.5`, `0.25`, `0.75`, `1.25`;
- continuation-scaled target attempts;
- bounded restart seeds already available inside QN.

Important constraints:

- the candidate set is fixed before solving;
- all candidates are attempted under one route definition;
- no candidate is attempted only because another route failed unless that is part of the fixed route definition;
- selection is deterministic.

## Candidate Selection

If several QN candidates converge, do not use branch identity.

Use a deterministic numerical rule:

1. residual `< cttol`;
2. finite flow/Jacobian;
3. fixed route/candidate priority defined before the solve;
4. fixed deterministic tie-break, such as smallest residual within the same
   priority class.

Branch switching is allowed. The internal route used on reverse does not need to match the forward route. The actual priority policy must map the proposal back.

Do not choose the candidate by reverse round-trip error or by a post-hoc
geometry filter as a production rule unless the resulting proposal probability
is explicitly accounted for.

## Reverse Certification

During validation, rescued QN proposals should be audited with actual-policy
reverse certification:

```text
forward: x, p --production QN policy--> y, p'
reverse: y, -p' --same production QN policy--> x_check, p_check

pass if:
  ||x_check - x||_inf < tol_x
  ||z_check - z||_inf < tol_z
  ||p_check + p||_inf < tol_p
  |DeltaH_forward + DeltaH_reverse| < tol_H
```

If certification fails, the event is diagnostically invalid under the current
proposal rule. This may justify a temporary validation reject, but it is not by
itself a complete production design.

This is not a same-branch check. It only checks that the route gives a reversible proposal.
It is also not a same-internal-route check. If reverse p28 returns to the original state after forward extension, that is acceptable.

Passing reverse certification is also not sufficient. Standard `exp(-Delta H)`
Metropolis additionally requires the deterministic proposal map to preserve
phase-space volume, or else the acceptance ratio needs the missing Jacobian /
proposal-density factor.

## Minimum Implementation Plan

### Phase 1: Proposal-Measure Audit

Before adding another production rescue path, explain what fullpath adds.

For the same local states/momenta, compare `p28` and `full_s1` and record:

- whether the event is `p28_success`, `fullpath_added_success`, or common fail;
- selected QN route/candidate;
- endpoint and Re/Im observable contribution;
- `Delta H`;
- actual-policy reverse return error;
- local finite-difference log-volume estimate on sampled added proposals;
- number of converged candidates in the route.

If fullpath-added proposals pass reverse checks but have nonzero log-volume or
asymmetric candidate multiplicity, then the correct fix is proposal-density
accounting, not another filter.

### Phase 2: QN Route Mode

Add:

```text
QN_ROUTE_ID=p28 | p40 | full_s1 | seed_bank_p28
```

Default remains:

```text
p28
```

Route definitions:

- `p28`: current bounded QN probe max_iter=28.
- `p40`: same QN solver with max_iter=40, no global/near/nonnear fallback.
- `full_s1`: one fixed full-stage QN route, no conditional fallback.
- `seed_bank_p28`: fixed seed bank around the p28 QN solve.

### Phase 3: Compare Fixed Routes

Run small route comparison:

```text
20 seeds x 50k cycles
no_fb
p28
p40
full_s1
seed_bank_p28
```

Key question:

- If fixed `p40`/`full_s1` still shifts Re mean, the route itself is problematic.
- If fixed route is stable but conditional fallback was not, the issue was route inclusion/accounting.

### Phase 4: Route Mixture

Only after fixed routes are individually stable, add fixed route mixture:

```text
QN_ROUTE_WEIGHTS=p28:0.5,seed_bank_p28:0.5
```

No state-dependent weights until proposal-ratio correction exists.

## Promotion Criteria

Promote a QN inclusion policy only if:

- unresolved failures decrease or remain acceptable;
- Re/Im mean moves toward exact zero or at least does not move away;
- P68/P95 remain compatible with exact normal coverage;
- reverse certification rejection rate is low;
- runtime overhead is acceptable.

Reject if:

- Re mean shifts monotonically as more QN candidates are included;
- many candidates fail actual-policy reverse certification;
- correctness only appears after mixing routes in a way not individually understood.

## Immediate Next Step

Implement `QN_ROUTE_ID` and test fixed-route `p28`, `p40`, `full_s1`, and `seed_bank_p28` at small scale before any large seed run.

## Added-Proposal Audit Update

The minimal replay audit found that the first 16 `global36`-added proposals
pass actual-policy local reverse checks at roundoff level. A reverse-only filter
would therefore not remove them.

The same audit found a separate baseline issue: 5 of 70 p28/common successes
reverse to a different state, with endpoints clustered near `Re z ~= +/-0.265`.

Design consequence:

- reverse certification remains required as a diagnostic, but it is not the
  production inclusion rule;
- if an added proposal passes reverse, it can still be invalid under the current
  Metropolis rule if the full local phase-space map is not volume preserving or
  if route/candidate selection changes proposal density;
- future rescue design should focus on fixed route definitions and measurable
  proposal accounting, not post-hoc geometry gates.

Revised first implementation target:

1. add an audit mode for full one-step phase-space finite-difference `log|det dT|`;
2. add route-specific capture for `p34/p36/p40` added cases, because that region
   is known from seed-level tests to shift Re coverage;
3. keep production default at `p28` until a route passes reverse, phase-volume,
   and seed-level consistency checks.

Implementation note: the phase-space determinant must be computed in a reduced
tangent coordinate chart. A raw determinant over the stored `(x, p)` arrays is
not valid here because `x` carries a fixed flow-time coordinate and `p` is stored
as a redundant projected 2-real vector for one physical tangent degree of
freedom.

Post-QN simplified-Newton refinement was tested as an audit option:

```text
QN_POST_NEWTON_REFINE_ENABLED=1
```

The sign conversion is:

```text
ld_seed = -Jl_qn
u_seed  = inverse_flow(z + del_z + Jl_qn) - x0
```

because QN and simplified Newton use opposite signs for the normal correction in
their residual definitions, and because Newton's `u` coordinate is the manifold
coordinate displacement, not QN's internal `xi`. This refinement did not recover
the p28 reverse-bad cases in the minimal replay, so it should remain
diagnostic-only and should not be treated as a production rescue design.
