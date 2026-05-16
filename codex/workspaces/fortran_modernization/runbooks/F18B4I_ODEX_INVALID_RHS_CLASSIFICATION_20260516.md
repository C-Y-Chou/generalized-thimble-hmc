# F18b.4i ODEX Invalid-RHS Classification

Date: 2026-05-16 JST

Status: implemented, focused-tested locally, and M4-passed.

Scope:

- Resolve `HODEX-LB-004`: non-finite RHS values in the handwritten ODEX
  package layer now return direct `odex_reason_invalid` / status `102` instead
  of shrinking until `h_min`.

## Source Changes

Files:

- `src/physics/odex_backend.f90`
- `tests/test_odex_controller_observation_contract.f90`
- `tests/test_odex_backend_package_contract.f90`
- `tests/test_odex_foundation_contract.f90`

Implementation:

- `odex_step` and `odex_step_context` now expose an internal `invalid_rhs`
  outcome distinct from `stability_rejected`.
- Initial derivative and later midpoint-row derivative evaluations are checked
  for non-finite values before conservative stability logic or error/rejection
  logic.
- `odex_integrate_endpoint` and `odex_integrate_endpoint_context` convert
  `invalid_rhs` to a direct invalid result with the current accepted/rejected
  counters.  For the deterministic invalid-RHS tests this is
  `accepted_steps=0`, `rejected_steps=0`, and `endpoint_available=.false.`.
- Finite conservative stability rejections still use the existing rejection
  path and can still produce `h_min` when the h-min floor is reached.

## Contract Coverage

Focused readback:

```text
make -C build test_odex_backend_package_contract \
  test_odex_controller_observation_contract \
  test_odex_controller_alignment_spec \
  test_odex_result_contract \
  test_odex_foundation_contract
```

Observed passing evidence:

- `package_invalid_rhs ok=T context=T status=102 context_status=102`
- `initial_invalid_rhs_observation ok=T status=102 accepted=0 rejected=0`
- `later_invalid_rhs_observation ok=T status=102 accepted=0 rejected=0`
- `unknown_context_failure ok=T status=102 attempts=1 success=0 failure=1
  invalid=1 hmin=0 assist_success=0`
- `workspace_runtime_trace_context ok=T context=2 rattle_step=7 substep=2
  newton_iter=3 quasi_iter=5`
- finite h-min classification remains covered:
  `hmin_failure_observation ok=T status=103 rejected=2`.

Full guardrail readback:

```text
make -C build modernization_guardrails
```

Observed:

```text
[M4][SUMMARY] all guardrails passed
[M4][ARTIFACTS] output/tests/m4_guardrails
```

## Behavior Boundary

This is an ODE package failure-classification/API correction.  It does not
change the TLTM MCMC policy that ODE failure at the proposal layer is handled as
proposal failure / rejection-as-stay-put.  The old repeated rejection-to-h-min
path is no longer the default classification for NaN/Inf RHS.

Remaining ODEX line-audit work is now the Hairer outer-controller behavior
surface: first/last-step state, `KC/KOPT`, reject-history coupling, accepted
next-`H` update, initial `H/K` retry after the state machine exists, `SCAL`,
`ERROLD`, `ATOV`, `SAFE*`, `HOPTDE`, h-min/status details, and stability policy.
