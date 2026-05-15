# Mature ODE Backend Decision - 2026-05-15

## Decision

The modernization target for ODE integration is now a mature external ODE
package backend, not a proof that the handwritten endpoint-only ODEX controller
is a full Hairer ODEX implementation.

Current handwritten ODEX remains the canonical behavior baseline until an
external backend passes the required affected-baseline gates.  Do not replace
it in-place without F8/M4 and explicit output/readback comparison.

## Rationale

The current endpoint-only ODEX path is useful as a preserved TLTM behavior
baseline, but its controller is still handwritten.  Proving every controller
detail against Hairer ODEX would spend effort on maintaining a solver stack we
do not actually want to own long term.

The preferred scientific-software direction is:

```text
Retain the current endpoint-flow API and TLTM acceptance/failure contracts,
but move adaptive ODE integration behind a mature package backend.
```

This changes the CV-012 closure strategy:

- do not try to make the handwritten controller a publication-grade full ODEX;
- keep the existing handwritten backend as `legacy/current-baseline`;
- introduce an external backend as a candidate;
- accept it only after deterministic and statistical affected-baseline gates.

## Candidate Packages

### Primary Candidate: SUNDIALS CVODE

Use SUNDIALS CVODE as the first mature backend candidate.

Why:

- maintained scientific-computing package with official documentation;
- variable-step, variable-order methods;
- Adams method for nonstiff systems and BDF for stiff systems;
- C API is practical to call from the existing Fortran/C bridge style already
  used for official DFO-LS;
- richer status/query surface than a small handwritten endpoint solver.

Expected integration shape:

- add a build-time optional backend, e.g. `TLTM_ODE_BACKEND=sundials_cvode`;
- call CVODE through a small C shim or ISO C binding layer;
- keep the public TLTM flow API stable: `flowz`, `flowzr`, `flow`;
- preserve strict final-flow semantics and explicit failure statuses;
- keep current ODEX backend as default until the SUNDIALS route passes gates.

Reference basis:

- SUNDIALS CVODE documentation describes variable-order, variable-step
  multistep methods.
- CVODE exposes Adams and BDF method choices through `CV_ADAMS` and `CV_BDF`.

### Fallback Candidate: ODEPACK LSODA/LSODE

ODEPACK is a mature LLNL Fortran solver collection and is attractive because
it is Fortran-native.

Why it is second choice:

- very mature and public-domain;
- includes stiff and nonstiff solvers;
- Fortran 77 integration may be simpler than SUNDIALS on the remote cluster;
- status/config surface is older and less product-friendly than SUNDIALS.

Use ODEPACK if SUNDIALS is unavailable or too disruptive to package on the
cluster.

Reference basis:

- LLNL documents ODEPACK as a collection of Fortran solvers for ODE initial
  value problems, including both stiff and nonstiff systems.
- LLNL documents LSODE as using Adams methods for nonstiff systems and BDF
  methods for stiff systems.

### Non-Goal: Full Hairer ODEX Ownership

Using a mature ODE package is not the same as proving full Hairer ODEX
paper-correctness.  If exact Hairer ODEX behavior becomes a requirement, that
should be a separate backend/import decision.  It is not the preferred route
for reducing handwritten-controller risk.

## Required Gates Before Becoming Canonical

1. Build/discovery gate:
   - verify package availability locally and on the remote PBS target;
   - record version, license, link mode, and compiler flags in manifests.
2. Deterministic endpoint gate:
   - compare `flowz`, `flowzr`, and `flow` endpoint/Jacobian results against
     the current ODEX backend on a fixed representative input set;
   - include success, h-min/failure, inverse-flow, and Jacobian finite-
     difference cases.
3. HMC/RATTLE retained-core gate:
   - run retained-core RATTLE/RG tests with the candidate backend;
   - verify failure-as-rejection policy and strict final-flow status mapping.
4. Stage2 kernel gate:
   - run Stage2 RNG v2/swap contracts with the candidate backend;
   - ensure local-update RNG ownership is unchanged by ODE backend selection.
5. Affected-baseline comparison:
   - run M4 plus an explicit F8 affected-baseline comparison;
   - treat output drift as expected unless explicitly bounded and accepted.
6. Production-readiness decision:
   - only after the above gates decide whether SUNDIALS/ODEPACK becomes the
     canonical backend or remains an optional experimental backend.

## Claim Boundary

Allowed:

```text
The project has selected mature external ODE package adoption as the route for
closing handwritten ODE-controller risk.  The current handwritten endpoint-only
ODEX remains a baseline backend until the external backend passes affected-
baseline gates.
```

Blocked:

```text
The current handwritten ODEX controller is full Hairer ODEX paper-correct.
```

```text
Switching to SUNDIALS/ODEPACK preserves outputs automatically.
```

```text
Using a mature ODE package proves the full TLTM proposal kernel correct.
```

## Next Implementation Slice

Do not patch `solve_flow` directly first.  Start with an evaluation spike:

1. detect SUNDIALS availability locally and on cluster02;
2. identify the smallest CVODE endpoint integration shim;
3. add a disabled-by-default backend flag;
4. run endpoint-only comparison tests against current ODEX;
5. write the F8 behavior statement before any canonical route switch.
