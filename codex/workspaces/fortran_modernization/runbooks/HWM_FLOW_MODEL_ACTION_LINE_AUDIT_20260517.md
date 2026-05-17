# HWA-FLOW/MODEL Flow, Action, Phase Line Audit

Date: 2026-05-17 JST

Status: implemented for the current flow/model/action scope. Focused tests
passed; the combined HWA batch later passed full M4.

## Scope

This packet covers the handwritten/source-owned surfaces that connect the model
action to flow integration, Jacobian propagation, determinant phase, and swap
energy:

- `src/physics/solve_flow.f90`
- `src/physics/model.f90`
- `src/physics/model_action_body.inc`
- `src/physics/model_generated.f90`
- `src/physics/model_tape_ad.f90`
- `src/sampler/markovchain_phase.f90`
- determinant/packing helpers in `src/core/utils.f90`
- focused tests in `tests/test_odex_flow_jacobian_contract.f90`,
  `tests/test_action_derivatives.f90`, and
  `tests/test_tltm_swap_kernel_contract.f90`

ODEX controller internals remain owned by the F18b.5 packets. This packet only
audits the RHS/model/phase layer above that endpoint ODE backend.

## Mathematical Contract

The model action is

```text
S(z) = sum_i[-i (z_i^3/3 + alpha z_i) - log(z_i - i beta)].
```

The derivative and Hessian implied by that source are

```text
dS_i/dz_i = -i (z_i^2 + alpha) - 1/(z_i - i beta)
d2S_i/dz_i^2 = -2 i z_i + 1/(z_i - i beta)^2
d2S_i/dz_i dz_j = 0 for i /= j.
```

The flow layer implements the holomorphic-gradient flow convention

```text
dz/dt = conjugate(dS/dz)
```

and inverse flow by reversing the RHS sign, not by changing the time sign. For
the flow Jacobian `J = dz(t)/dx`, the code propagates

```text
dJ/dt = conjugate(H(z) J).
```

The phase convention is

```text
phi = exp(-i Im(S(z)) + i Im(log(det(J)))).
```

`log_determinant` uses LU with the permutation sign and Fortran's principal
complex-log branch. This is a project convention, not an independent proof that
branch crossings are physically harmless in every future model.

## Source Readback

- `model_action_body.inc` is the single expression body used by both the
  generated/tape path and the direct generated action path.
- `model_generated.f90` evaluates `calculate_action_generated` directly from
  the action expression and obtains `ds`, full Hessian, and Hessian-vector
  products through `model_tape_ad`.
- `model_tape_ad.f90` implements reverse-mode gradient and forward-over-reverse
  Hessian-vector propagation for the operations used by the action body:
  addition, subtraction, multiplication, division, integer power, `log`, and
  `exp`.
- `solve_flow:rhs_flow_vec_context` converts real ODE state to complex `z`,
  calls `ds`, and packs `conjugate(ds)` as `(Re, -Im)`.
- `solve_flow:flowzr_with_workspace` sets `flow_vec_rhs_scale=-1`, so reverse
  flow integrates the negative RHS over the same nonnegative flow-time span.
- `solve_flow:rhs_flow_jac_context` reconstructs `z` and row-major complex `J`,
  calls `hessian_vec(z, J(:,col))`, and packs `conjugate(HJ)`.
- `markovchain_phase:compute_phase_factor` calls `log_determinant(J)` and
  `calculate_action(z)` and forms the phase expression above.

## Findings And Handling

### HWA-FLOW-001: Direct flow API failure-output contract

Finding: `flowz`, `flowzr`, and `flow` had status/error outputs, but direct
invalid inputs such as wrong `x/z/J` shape or nonfinite `x` could reach array
assignment or ODEX before an explicit API-level failure. Forward-flow failures
also did not explicitly reset outputs to the zero-time endpoint before returning.

Handling: implemented source hardening in `solve_flow.f90`.

- Shape mismatch now returns `error=.true.` and
  `intode_status_failure_invalid` before touching incompatible output buffers.
- For shape-valid forward APIs, `flowz` initializes `z=x(2:)` and `flow`
  initializes `z=x(2:)`, `J=I` before integration.
- Nonfinite `x` now returns `intode_status_failure_invalid` with those
  zero-time outputs.
- `flowzr` preserves the caller's input `z` on invalid or failed reverse-flow
  input, matching its in-place inverse-flow contract.

### HWA-MODEL-001: Derivative proof was mostly finite-difference based

Finding: `test_action_derivatives` checked `ds`, Hessian, and Hessian-vector
products against finite differences, but it did not pin the generated model to
the closed-form derivative of the actual action expression.

Handling: added deterministic closed-form checks for action, `ds`, Hessian, and
`Hv` before the existing finite-difference checks. The test now uses a fixed
random seed.

### HWA-PHASE-001: Phase did not guard `z/J` dimension consistency

Finding: `compute_phase_factor` rejected singular/non-square Jacobians through
`log_determinant`, but did not reject a square Jacobian whose dimension differed
from `z`.

Handling: added an explicit `size(J)==size(z)` guard returning
`error=.true.` and neutral `phi=1`. Added focused swap-kernel coverage.

### HWA-MODEL-STATE-001: Generated tape cache is serial-scoped

Finding: `model_generated.f90` and `model_tape_ad.f90` still use module-level
`save` tape/cache state. The current serial route and tests are source-consistent,
but this is not full OpenMP/reentrant product readiness.

Handling: no behavior change in this packet. Keep the model tape/cache state in
CV-011/F21 as an explicit remaining state-boundary item before claiming
thread-safe productization or single/mixed precision readiness.

## Proof Tests

Passed locally:

```bash
make -C build test_odex_flow_jacobian_contract
make -C build test2
make -C build test_tltm_swap_kernel_contract
```

Key checks:

- zero-flow endpoint/Jacobian identity;
- `flow` and `flowz` endpoint consistency;
- legacy local workspace and explicit flow context equality;
- `flowzr` inverse replay;
- flow-Jacobian finite-difference agreement;
- invalid flow API shape/nonfinite-input failure-output contract;
- action/gradient/Hessian/Hv closed-form agreement;
- generated derivatives finite-difference agreement;
- phase-factor dimension mismatch rejection;
- existing singular-Jacobian swap rejection behavior remains intact.

## F8 Statement

This packet is behavior/API relevant only for previously invalid direct API
inputs and for deterministic proof coverage. The valid flow/model/phase
mathematical path is intended to be unchanged. No local TLTM Stage2/Stage3
simulation screen was run, following the no-local-simulation rule. Full M4 and
any affected-baseline decision remain required before using this batch for
production-comparison synchronization or regeneration.

## Current Scope Closure

HWA-FLOW and HWA-MODEL are closed for the current valid-route mathematical
contract and direct API hardening scope. Reopen if the action expression,
generated derivative pipeline, flow RHS/Jacobian convention, phase/logdet
branch convention, model tape/cache ownership, precision profile, or public
energy/schema semantics change.
