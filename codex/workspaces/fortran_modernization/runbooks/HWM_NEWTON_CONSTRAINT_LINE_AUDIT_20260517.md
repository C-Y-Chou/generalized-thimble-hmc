# HWA-NT Simplified Newton Constraint Line Audit

Date: 2026-05-17 JST

Status: implemented and focused-test passed. M4 pending in the current combined
HWA batch.

## Purpose

This packet gives the simplified Newton constraint solver the same treatment as
the ODEX/RATTLE handwritten audit path:

- line-level readback of `src/sampler/hmc_constraints.f90`;
- reference mapping to GT-HMC simplified Newton equations;
- separation of paper-matched target/update from TLTM controller policy;
- source hardening for direct API guard surfaces;
- focused proof tests for replay, projection split, and failed-output
  contracts.

## Source Scope

Main file:

- `src/sampler/hmc_constraints.f90`

Focused test:

- `tests/test_retained_core_newton_contract.f90`

Main caller boundary:

- `src/sampler/hmc_integrator_core.f90` calls
  `solve_constraint_newton(cttol, 100, ...)` as the first projection attempt
  before the official DFO-LS/QN boundary.

## Reference Mapping

The active simplified Newton target is the GT-HMC/TLTM residual already mapped
in `M2_REFERENCE_BACKED_CORE_AUDIT.md`:

```text
B = z + Delta z - lambda - z_t(x + u)
E Delta u + Delta lambda = B
Delta u = real_vec(E^{-1} B)
Delta lambda = B - E Delta u
```

Source readback:

- `solve_constraint_newton_seeded` forms
  `B = real(z - flowz(xt+u) - lambda) + del_z`, matching
  `z + Delta z - lambda - z_t(x+u)`.
- `solve_projected_step` solves `E^{-1}B`, zeroes imaginary/base-forbidden
  components with `real_vec`, computes `E Delta u`, and sets
  `Delta lambda = B - E Delta u`.
- The update `u += Delta u`, `lambda += Delta lambda` matches the fixed-base
  simplified Newton update.
- On success the returned `x_new` is `xt+u` and `Jl` is the real-packed
  lambda/correction vector.

The matched claim is about the residual and projection update. The paper does
not specify the exact TLTM controller constants used for near-tolerance
extension, divergence, stagnation, or tiny-step failure.

## Line-Level Map

| Area | Source lines | Classification |
| --- | --- | --- |
| Eval-flow status context | `hmc_constraints.f90:13-115` | diagnostics/context state, not math proof |
| Public wrapper and workspace dispatch | `122-150` | API boundary; now caller-owned workspace or local workspace |
| Output initialization and shape guards | `152-245` | stay-put failure contract; hardened in this packet |
| Fixed-base Jacobian factorization | `206-213` | matched simplified Newton setup |
| Seed handling | `219-235`, `274-305` | matched optional retry seed semantics; invalid seed shapes ignored |
| Residual construction | `288-305`, `338-349` | matched GT-HMC residual sign |
| Convergence test | `307-312`, `350-355` | project tolerance contract using `cttol` |
| Controller policy | `314-390` | TLTM numerical policy, not paper constants |
| Projected step | `396-441` | matched fixed-base tangent/normal split |
| Workspace allocation/release | `443-512` | implementation hygiene |

## Source Hardening

Implemented in `src/sampler/hmc_constraints.f90`:

- direct API rejects invalid `jac` dimensions before `map_to_real_mat`;
- direct API rejects nonfinite or nonpositive `tol`;
- all these failure paths keep the existing stay-put output contract:
  `x_new = xt`, `Jl = 0`, and `ierr = .true.` after valid output-shape checks.

This does not change the successful RATTLE/Newton route. The production caller
already passes a correctly shaped base Jacobian and positive `cttol`.

## Proof-Test Evidence

Focused test passed:

```text
make -C build test_retained_core_newton_contract
```

Readback:

```text
newton_replay case=1/2/3 ok=T
newton_projected_step_identity ok=T dxi_err=0 tangent_err=0 normal_err=0
newton_failure_output_reset label=nan_step ok=T dx=0 djl=0
newton_invalid_tol_reset ok=T dx=0 djl=0
newton_jac_shape_guard ok=T dx=0 djl=0
newton_iteration_exhaustion_reset ok=T dx=0 djl=0
```

The replay checks verify accepted Newton solves by reflowing `x_new` and
checking the residual

```text
real(z - flowz(x_new) - lambda) + Delta z
```

against the retained-core tolerance, with lambda scaling bounded by
`norm(lambda)/(h**2*force_scale) <= 20`.

The projection-split check uses an identity real Jacobian and verifies
`dxi=B`, tangent projection `[Re,0,Re,0]`, and normal component
`[0,Im,0,Im]`.

## Findings

| ID | Finding | Classification | Handling |
| --- | --- | --- | --- |
| HWA-NT-CORE-001 | Residual sign, lambda sign, fixed-base Jacobian use, and projected update match the GT-HMC simplified Newton equations under the current packing convention. | matched core | Closed with replay/projection tests. |
| HWA-NT-API-001 | Direct API did not explicitly guard invalid `jac` shape or invalid tolerance before deeper work. | API hardening | Patched and focused-tested; no live successful-route behavior change intended. |
| HWA-NT-CTRL-001 | `near_tol`, `stagnation_floor`, `diverge_floor`, `near_extend_chunk`, `iter_cap_hard`, divergence counts, stagnation counts, and tiny-step counts are TLTM controller policy rather than paper constants. | project policy | Keep unchanged. Reopen only with evidence that a predicate is harmful or if a future paper-alignment decision intentionally changes proposal/fallback frequency. |
| HWA-NT-STATUS-001 | Newton flow-eval status counters are diagnostics, not proof of the mathematical residual. | diagnostics boundary | Keep as HWA-DIAG/CV-011 boundary; do not cite counters as paper proof. |
| HWA-NT-LEGACY-001 | `step_size` is not used in the simplified Newton equations once `del_z` is passed; it currently serves only as a finite-input guard/API relic. | legacy API caveat | Defer to HWA-LEGACY/F9 cleanup if signature cleanup becomes product scope. |

## F8 Statement

This is behavior/API relevant only for invalid direct Newton API inputs:
incorrect `jac` dimensions and invalid tolerance now fail before deeper
workspace/Jacobian work and return explicit stay-put outputs. The production
RATTLE caller passes valid dimensions and positive `cttol`, so the accepted
Newton residual/update route is intended to be unchanged.

No local Stage2/Stage3 screen was run. If this patch is used for
production-comparison sync/regeneration, freeze a clean commit and rerun the
direct `npt5_r0055` PBS wrapper or record a narrower affected-baseline decision.

## Closure

HWA-NT is closed for the current simplified-Newton scope:

- matched residual/update core;
- controller-policy boundary documented;
- direct API hardening implemented;
- replay/projection/failure-output proof tests pass.

Reopen HWA-NT only if Newton controller behavior, tolerance policy, failure
classification, status schema, flow status handling, or public API semantics
change.
