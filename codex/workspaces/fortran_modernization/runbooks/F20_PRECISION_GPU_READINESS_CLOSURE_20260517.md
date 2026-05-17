# F20 Precision/GPU Readiness Closure

Date: 2026-05-17 JST

Status: implemented for modernization closeout governance. This does not enable
single or mixed precision. It preserves strict double as the only certified
source/product mode and makes weaker modes explicit future work.

## Decision

The active modernization tree supports only:

```text
TLTM_PRECISION=double
TLTM_TOLERANCE_PROFILE=strict_double
```

The reserved future product interface is:

```text
TLTM_PRECISION=double|single|mixed
TLTM_TOLERANCE_PROFILE=strict_double|loose_double|experimental_single
```

Only the first combination is certified today. `single` and `mixed` are
rejected at build time until a separate certification packet passes.

## Implemented Source/Build Contract

- `build/Makefile` defines `TLTM_PRECISION ?= double` and
  `TLTM_TOLERANCE_PROFILE ?= strict_double`.
- The build fails if a user requests unsupported `single`, `mixed`, or weaker
  tolerance profiles.
- `src/sampler/tltm_stage2_driver.f90` now records a `precision` object in the
  Stage2 v1alpha manifest:
  - `precision_mode = double`
  - `tolerance_profile = strict_double`
  - `fortran_real_kind = real64`
  - `ode_backend_precision = double_real64`
  - `residual_certification_precision = double_real64`
  - `output_binary_precision = double_real64`
  - `single_mixed_status = experimental_until_certified`
- `codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py`
  is an M4-gated boundary audit for F20.

## Boundary Inventory

The F20 audit checks these hard double boundaries:

| Boundary | Current Source |
| --- | --- |
| Canonical real/complex kind | `src/core/utils.f90`: `dp = real64` |
| MT95 real kind | `src/core/mtdefs.f90`: `rk = real64` |
| Stage2 RNG v2 variates | `src/core/tltm_rng.f90`: `real(real64)` |
| LAPACK ABI | `dgetrf`, `dgetrs`, `dgemv`, `zgetrf` double/complex-double calls |
| Official DFO-LS bridge | C/Python `double` / `PyFloat_AsDouble` boundary |
| SUNDIALS CVODE bridge | `double` / `sunrealtype` comparison-only boundary |
| ODEX/C bridge | Fortran `real(c_double)` casts |
| Default tolerances | `abs_tol=3.0d-14`, `rel_tol=3.0d-14`, `constraint_tol=1.0d-13` |
| Stage2 sidecar metadata | Manifest precision/tolerance/output precision fields |

## Certification Gate For Future Single/Mixed Modes

Single/mixed precision remains experimental until all of the following pass as
a separate affected-baseline packet:

1. explicit build mode and manifest/schema fields for the new precision mode;
2. paired-seed certification against the strict-double baseline;
3. endpoint `x/z/J` differences and flow residual distributions;
4. Newton/QN residual and final-flow certification distributions;
5. proposal failure, reverse-gate rejection, ordinary rejection, and swap
   acceptance-rate comparisons;
6. observable drift and uncertainty comparisons for the selected production
   scale;
7. binary I/O compatibility or versioned output schema for changed precision;
8. clear product labeling that the weaker mode is not the strict-double
   publication baseline unless the gate passes.

## Verification

Focused gate:

```bash
make -C build precision_readiness_audit
```

M4 gate:

```bash
make -C build modernization_guardrails
```

The expected manifest is:

```text
output/tests/precision_readiness/F20_precision_readiness_manifest.json
```

## Closure

F20 is closed for modernization readiness: the strict-double product baseline is
explicit, the future precision/tolerance interface is reserved, unsupported
weaker modes fail closed, Stage2 sidecars record precision metadata, and M4
guards the boundary.

Reopen F20 if any of these change:

- `dp`, RNG, LAPACK, C/Python bridge, SUNDIALS, or binary I/O precision;
- default tolerances or residual certification thresholds;
- Stage2/Stage3 manifest/schema precision fields;
- single/mixed precision or weaker tolerance mode moves from design to
  implementation;
- GPU/OpenMP productization changes the precision or reduction semantics.
