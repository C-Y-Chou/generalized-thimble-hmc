# Integrated Algorithm Modernization Plan - 2026-05-15

## Purpose

This plan integrates the post-audit decisions after the handwritten-algorithm
paper-correctness and numerical-soundness audit.

It replaces the older instinct to prove every handwritten controller as
paper-exact with a cleaner modernization direction:

1. use mature external packages where we do not want to own solver internals;
2. keep TLTM-specific physical/kernel certification gates explicit;
3. delete or quarantine in-house solver leftovers that are no longer part of
   the selected official route;
4. preserve behavior until each change passes F8/M4 and affected-baseline
   gates.

## Accepted Decisions

### RATTLE Failure Policy

Decision:

```text
Projection, final-flow, and reverse-gate failure use proposal reject/stay-put
as the selected TLTM MCMC policy.  We do not need to implement the paper's
momentum-flip failure continuation as the canonical route.
```

Implication:

- this is not a source bug;
- keep deterministic tests proving failure/reverse-gate reject keeps the live
  state unchanged;
- documentation should say the RATTLE core is paper-mapped while the failure
  policy is a project-selected rejection kernel.

### ODE Integration

Decision:

```text
Close handwritten ODEX-controller risk by evaluating a mature external ODE
package backend, not by proving the current endpoint-only handwritten ODEX
controller as full Hairer ODEX.
```

Implication:

- current handwritten endpoint-only ODEX remains the baseline backend;
- SUNDIALS CVODE is the primary candidate;
- ODEPACK is the fallback candidate;
- backend switch is behavior-relevant and requires endpoint, retained-core,
  Stage2, M4, and F8 affected-baseline gates.

Primary source of truth:

- `MATURE_ODE_BACKEND_DECISION_20260515.md`

### Official DFO-LS

Decision:

```text
DFO-LS itself is a good solver choice for the projection-residual rescue, but
the canonical route should be a thin official-package bridge plus TLTM
certification gates.  It should not retain in-house solver rescue/classification
logic as active control flow.
```

Keep in the official route:

- TLTM residual callback/definition;
- official DFO-LS package parameters such as `npt`, `rhobeg`, `rhoend`,
  `maxfun`, and objective-noise flag;
- strict TLTM residual `<= tol` acceptance gate;
- candidate certification;
- strict final-flow and reverse-gate checks;
- proposal reject/stay-put if any required gate fails.

Remove, disable, or quarantine away from the official route:

- best-candidate rescue when the package did not produce a candidate already
  within tolerance;
- `force-best` acceptance or relaxed tolerance in the official route;
- near/far failure classification as control flow;
- probe -> classify -> near/far rescue routing as active official control flow;
- outer in-house watchdog/budget controls beyond official DFO-LS `maxfun`;
- internal DFO-like fallback from active source.

## Work Order

### Step 1: Official DFO-LS Thin Bridge Cleanup

First implementation slice:

```text
Make the official DFO-LS route a thin bridge:
Newton strict attempt -> one official DFO-LS attempt -> strict TLTM residual
gate -> certification/final-flow/reverse-gate -> success or proposal reject.
```

Concrete tasks:

1. Done: `OFFICIAL_DFOLS_THIN_BRIDGE_BRANCH_MAP_20260515.md` identifies the
   exact source branches to keep, delete, disable, or move to legacy/internal
   mode.
2. Done: `F19_OFFICIAL_DFOLS_CERTIFICATION_RENAME_20260515.md` renamed
   `rescue_attempt_from_best` to `certify_candidate_if_within_tol` without
   intended numerical behavior change.
3. Done: `F19_OFFICIAL_DFOLS_POLICY_ISOLATION_20260515.md` ensures the official
   route never accepts `force-best` or relaxed
   tolerance.
4. Done: package failure returns proposal failure/reject unless a candidate
   already passes strict TLTM residual and certification.
5. Done for active source: near/far classification is diagnostics-only and
   near/far retry behavior is deleted from the QN/HMC route.
6. Done: `F19_INTERNAL_DFO_BACKEND_DELETION_20260515.md` deletes
   `QN_SOLVER_BACKEND=internal`, internal DFO-like solver helpers, near/far
   retry controls, force-best acceptance, and watchdog/budget controls from
   active source.
7. Done for F19.2/F19 deletion: retained-core QN route, RG reject identity, ODEX assist
   policy, policy-perturbation checks, and M4 passed locally.

Why this is first:

- it touches the active official DFO-LS route directly;
- it removes the largest source of conceptual ambiguity around "official"
  versus "in-house";
- it was completed before solver-assist deletion and mature ODE backend work,
  because both rely on a clean proposal-kernel boundary.

### Step 2: Solver-Assist Deletion Against The Protected Baseline

Status: implemented in `F15_SOLVER_ASSIST_DELETION_20260515.md`.

After the thin bridge route was made explicit, the existing assist-deletion
track was completed for active source:

- the `npt5_r0055` assist-off baseline is preserved as the production-sync
  rerun target;
- active solver assist is deleted under focused tests and M4;
- legacy assist enable envs are inert and compatibility counters report zero;
- keep feedback-kernel measure correctness as a separate audit.

Primary source of truth:

- `F15_SOLVER_ASSIST_DELETION_20260515.md`
- `ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md`

### Step 3: Mature ODE Backend Evaluation

Do not switch ODE backend until the QN route is clean.

Start with package discovery and a disabled-by-default endpoint spike:

- local/remote SUNDIALS availability;
- local/remote ODEPACK availability;
- endpoint-only comparison harness;
- retained-core and Stage2 gates;
- F8 affected-baseline statement.

Primary source of truth:

- `MATURE_ODE_BACKEND_DECISION_20260515.md`

### Step 4: Remaining Audit Closure Packets

After the above:

- Metropolis output API semantics;
- Stage2 RNG/swap replay invariance and swap isolation;
- model/action derivation note;
- diagnostics/counter schema packet;
- broader CV-011 state ownership/productization.

## Claim Boundary

Allowed:

```text
The current modernization plan keeps official DFO-LS as the selected projection
residual solver, but will thin the TLTM bridge so official-package evidence is
not mixed with in-house rescue/classification leftovers.  RATTLE failure uses
the selected reject/stay-put MCMC policy.  ODE controller risk will be handled
through mature ODE backend evaluation rather than full handwritten ODEX proof.
```

Blocked:

```text
DFO-LS success alone proves TLTM proposal correctness.
```

```text
Switching ODE backend is behavior-preserving by default.
```

## Next Action

F19 official DFO-LS thin bridge cleanup and F15b solver-assist deletion are
implemented. Continue with Step 3: mature ODE backend evaluation. First verify
local/remote SUNDIALS CVODE and ODEPACK availability, then design a
disabled-by-default endpoint backend spike with endpoint, retained-core,
Stage2, M4, and F8 affected-baseline gates.
