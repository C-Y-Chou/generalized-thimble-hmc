# F20 Precision And GPU Readiness - 2026-05-15

## Decision

Modernization must finish with an explicit precision/GPU readiness packet.

The current canonical correctness and publication baseline remains the strict
double-precision line:

```text
double precision
ODE abs/rel tolerance: current strict baseline, e.g. 3e-14 unless superseded by
  an explicitly gated package-backend decision
constraint/QN residual tolerance: 1e-13
reverse gate enabled
strict final residual certification
failure as proposal rejection
```

Future larger GPU projects may need single or mixed precision, but that must be
introduced as a separate certified mode.  It must not silently weaken the
current canonical baseline.

## Why This Is Required

Large GPU targets may make full double precision too expensive, especially for
larger state spaces, many chains, or future accelerator-oriented kernels.

The strict double baseline is still valuable: it is the reference oracle used
to calibrate and certify any weaker-precision mode.  Without a preserved double
baseline, a faster GPU mode could produce biased results without a clean way to
measure the drift.

## Product Boundary

Allowed before modernization closeout:

- keep strict double precision as the canonical reference mode;
- add build/config/product design for future precision profiles;
- identify every hard double boundary that blocks single or mixed precision;
- define certification gates for any weaker-precision mode;
- record that weaker precision is experimental until those gates pass.

Blocked:

- calling single precision or weaker tolerance a drop-in replacement for the
  current publication baseline;
- weakening `cttol`, reverse-gate policy, final certification, or output
  schema without an explicit affected-baseline decision;
- mixing precision-mode work into F18 SUNDIALS/CVODE correctness comparison.

## Known Hard Double Boundaries

The current tree is not just a `dp` typedef switch.

- `src/core/utils.f90` defines `dp = real64`.
- LAPACK calls use double/complex-double routines such as `dgetrf`, `dgetrs`,
  `dgemv`, and `zgetrf`.
- The official DFO-LS C/Python bridge uses `double *` and Fortran
  `real(c_double)`.
- The RNG utility currently emits `real64` values.
- Binary history and evaluation files implicitly encode double-precision
  layout.
- The current SUNDIALS dependency spike is the default double-precision CVODE
  build, not a single-precision CVODE build.
- Existing deterministic guardrails and tolerances assume double precision.

## Required Closeout Deliverables

Before modernization is called complete, produce a precision readiness packet
with:

1. an inventory of all precision-boundary code paths, including Fortran kinds,
   LAPACK calls, C bridges, Python bridges, SUNDIALS builds, RNG conversion,
   binary IO, sidecars, tests, and scripts;
2. a proposed build-time precision interface, e.g.
   `TLTM_PRECISION=double|single|mixed`, with `double` as default;
3. a separate tolerance-profile interface, e.g.
   `TLTM_TOLERANCE_PROFILE=strict_double|loose_double|experimental_single`;
4. manifest/schema fields recording precision mode, tolerance profile, ODE
   backend precision, residual certification precision, and output binary
   precision;
5. a certification plan comparing any single/mixed mode against the strict
   double baseline using paired seeds, endpoint differences, residual
   distributions, failure/reject rates, reverse-gate statistics, and observable
   drift;
6. an explicit statement that single/mixed precision remains experimental
   unless those gates pass.

## Preferred Future Shape

The likely larger-GPU route is mixed precision rather than pure single
precision everywhere:

- compute expensive proposal/flow pieces in GPU-friendly precision where
  possible;
- recompute or certify critical residual/action/reverse-gate quantities in
  double precision when available;
- use compensated reductions or periodic double audits when full double is too
  expensive;
- preserve strict reject/stay-put behavior when certification fails.

## Interaction With F18

F18 SUNDIALS/CVODE work should stay double precision while proving package
backend correctness against the current baseline.

Precision/GPU readiness starts after the double package-backend route is
understood.  It may reuse F18 endpoint and affected-baseline harnesses, but it
is not allowed to change F18 acceptance criteria.
