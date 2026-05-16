# F18b.4g ODEX API Guard Hardening

Date: 2026-05-16 JST

Status: implemented.  This patch resolves `HODEX-LB-001` from
`F18B4F_PRE_IMPLEMENTATION_HANDWRITTEN_ODEX_LINE_AUDIT_20260516.md`.

## Purpose

The handwritten ODEX line audit found that both direct endpoint APIs assigned
`res = y` before checking whether the output buffer size matched the input
state size.  A mismatched direct caller could therefore trigger a shape error
before the intended invalid-result status path.

This is API hardening, not a physics or valid-trajectory behavior change.
Current `solve_flow` product callers allocate matching workspace buffers before
calling ODEX.

## Source Change

Updated `src/physics/odex_backend.f90`:

- `odex_integrate_endpoint`
- `odex_integrate_endpoint_context`

Both routines now:

1. compute `state_size = size(y)`;
2. set `error_flag = .true.`;
3. check `size(res) /= state_size .or. state_size <= 0`;
4. return `odex_status_failure_invalid` before assigning `res = y`;
5. only assign `res = y` after the shape guard passes.

For nonempty mismatched `res`, the invalid branch fills `res` with zero to avoid
leaving a caller-visible uninitialized output buffer.

## Tests

Updated `tests/test_odex_backend_package_contract.f90` with
`check_output_size_guard`.

The test covers both:

- `odex_integrate_endpoint`
- `odex_integrate_endpoint_context`

with `size(y)=2` and `size(res)=1`, expecting:

- `failed = .true.`;
- `status = odex_status_failure_invalid`;
- `endpoint_available = .false.`.

Focused readback:

```bash
make -C build test_odex_backend_package_contract
```

Observed:

```text
[CHECK] package_output_size_guard ok=T context=T status=102 context_status=102
[DONE] standalone ODEX backend package contract complete.
```

## Claim Boundary

`HODEX-LB-001` is resolved as a direct API guard bug.

Follow-up patch `F18B4H_ODEX_COUNTER_AND_PROMOTION_ALIGNMENT_20260516.md`
resolves `HODEX-LB-002` and `HODEX-LB-003`.  This patch does not resolve the
remaining ODEX line-audit findings.

Follow-up patch `F18B4I_ODEX_INVALID_RHS_CLASSIFICATION_20260516.md`
resolves `HODEX-LB-004`.  Remaining ODEX line-audit findings now start at the
outer-controller/product-scope surfaces:

- `HODEX-LB-005` through `HODEX-LB-010`: Hairer/paper mismatch or product-scope
  surfaces.
