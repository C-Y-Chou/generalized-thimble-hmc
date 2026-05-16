# F18b.4f Pre-Implementation Handwritten ODEX Line Audit

Date: 2026-05-16 JST

Status: line-by-line audit complete for `src/physics/odex_backend.f90` active
handwritten endpoint ODEX path.  The audit itself did not change source
behavior.  Follow-up patch `F18B4G_ODEX_API_GUARD_HARDENING_20260516.md`
resolves `HODEX-LB-001`; follow-up patch
`F18B4H_ODEX_COUNTER_AND_PROMOTION_ALIGNMENT_20260516.md` resolves
`HODEX-LB-002` and `HODEX-LB-003`; follow-up patch
`F18B4I_ODEX_INVALID_RHS_CLASSIFICATION_20260516.md` resolves
`HODEX-LB-004`.

Primary reference: Hairer/Wanner official `odex.f` from the Geneva site.

## Scope

Local source inspected:

- `src/physics/odex_backend.f90` lines 38-65: options and controller policy.
- `src/physics/odex_backend.f90` lines 277-536: endpoint outer loops.
- `src/physics/odex_backend.f90` lines 724-1149: handwritten midpoint,
  extrapolation, error, order, reject, and step-update kernel.
- `src/physics/odex_backend.f90` lines 1151-1518: controller helpers,
  observer helpers, step sequence, work estimate, and workspace tables.
- `src/physics/odex_backend.f90` lines 1520-1712: result/status, option
  normalization, stability, and vector utility helpers.
- `src/physics/solve_flow.f90` lines 150-215 and 250-305: endpoint wrapper
  consumption of `odex_result`.

Reference source inspected:

- `odex.f` lines 129-152: step-size/order safety parameters.
- `odex.f` lines 230-390: package options/defaults.
- `odex.f` lines 445-487: sequence, `A(I)`, scaling, and initial state.
- `odex.f` lines 515-720: `ODXCOR` outer controller.
- `odex.f` lines 736-831: `MIDEX` line kernel.

This audit separates three categories:

- `matched-core`: local code is structurally consistent with Hairer ODEX family
  for TLTM's autonomous endpoint-flow use.
- `paper-mismatch`: local behavior is not the Hairer `odex.f` line behavior.
- `bug-candidate`: local code appears internally wrong or unsafe independent of
  whether the project chooses full Hairer behavior.

## Matched-Core Surfaces

| Local lines | Reference lines | Audit result |
| --- | --- | --- |
| `odex_iwork3_nstep`, `build_nsteps`, `calculate_ak`: 1198-1221 and 1450-1460 | `NSEQU=3`: 455-460; `A(I)`: 470-473 | `matched-core`.  The sequence is `2,4,6,8,12,16,24,32,...`, and `A(k)=1+sum(NJ(1:k))` is consistent. |
| `odex_step` midpoint row: 746-790; context duplicate: 960-1004 | `MIDEX`: 750-796 | `matched-core` for autonomous ODEs.  The Euler start, explicit midpoint recurrence, and smoothing endpoint formula match the ODEX/GBS row structure.  TLTM RHS is autonomous, so the missing explicit `x+HJ*MM` argument is a product-scope difference, not a current bug. |
| Extrapolation tableau: 793-797, 903-907; context duplicate: 1007-1011, 1117-1121 | `MIDEX`: 800-805 | `matched-core`.  The even-power extrapolation denominator `(NJ(j)/NJ(l-1))**2 - 1` is represented by the precomputed `ratio`. |
| `calculate_wk`: 1151-1167 | `MIDEX` `W(J)=A(J)/HH(J)`: 825-826 | `matched-core/partial`.  Local `abs(h)` keeps work positive for signed endpoint intervals.  This is numerically sensible; exact branch use still depends on the controller findings below. |
| Signed endpoint behavior: 344-347, 363-365, 1177-1178 | `POSNEG`: 483 and 518-520 | `matched-core/partial`.  Current endpoint direction is preserved by signed `h`; Hairer's full `POSNEG/HMAX/HOPTDE/LAST` state machine is not implemented yet. |

## Bug Candidates

### HODEX-LB-001: public `res` size guard happens after `res = y`

Status: resolved by `F18B4G_ODEX_API_GUARD_HARDENING_20260516.md`.

Local lines:

- `odex_integrate_endpoint`: 297-303
- `odex_integrate_endpoint_context`: 428-434

Finding:

The routines assign `res = y` before checking `size(res) /= size(y)`.  If a
direct caller passes a nonconforming output buffer, the shape mismatch can occur
before the intended invalid-result branch runs.

Risk:

This is an API guard bug, not a physics change in the current `solve_flow`
callers, because `solve_flow` allocates a matching workspace slice before
calling ODEX.

Implemented handling:

Moved `res = y` after the shape check in both endpoint routines and added a
direct package-contract test with mismatched `res` size for both legacy and
context-aware APIs.  Focused package-contract readback passed.

### HODEX-LB-002: success `accepted_steps` counts attempts, not accepted steps

Status: resolved by
`F18B4H_ODEX_COUNTER_AND_PROMOTION_ALIGNMENT_20260516.md`.

Local lines:

- attempt counter increments at 353-355 and 484-486
- success writes `accepted_steps=step_count` at 402 and 533
- rejected steps are tracked separately at 387-389 and 518-520

Reference lines:

- Hairer tracks `NSTEP`, `NACCPT`, and `NREJCT` separately: 528, 542, 672, 717.

Finding:

On success after one or more rejected attempts, local `accepted_steps` will be
the total attempt count, not accepted endpoint steps.  Tests currently pin a
max-step failure count, but do not prove success-side accepted-count semantics.

Risk:

This is a diagnostics/API semantic bug candidate.  It is unlikely to alter the
trajectory, but it may alter public counters if corrected.

Implemented handling:

Added an explicit accepted-step counter to both endpoint entry points and set
`odex_result%accepted_steps` from accepted endpoint steps rather than total
attempts.  The package contract now pins a success case with rejected attempts
(`accepted=70`, `rejects=76`) so this cannot silently regress to attempt
counting.

### HODEX-LB-003: promotion step-size factor likely uses mutated `k`

Status: resolved by
`F18B4H_ODEX_COUNTER_AND_PROMOTION_ALIGNMENT_20260516.md`.

Local lines:

- `odex_step`: 855-860
- `odex_step_context`: 1069-1074

Reference lines:

- accepted-step next `H`: 700-711

Finding:

In the accepted `KC=K` path, local code does:

```fortran
k_prev = k
k = min(opts%k_max, k + 1)
if (k > k_prev) h = hk2*workspace%ak(k + 1)/workspace%ak(k)
```

After mutating `k`, this uses `A(old K + 2)/A(old K + 1)`.  Hairer's
non-special promote path for `KOPT=KC+1` uses `A(KOPT)/A(KC)`, i.e.
`A(old K + 1)/A(old K)`.

Example with `IWORK(3)=3`:

```text
old K=4: Hairer A(5)/A(4)=1.57142857; local mutated-index ratio A(6)/A(5)=1.48484848
old K=6: Hairer A(7)/A(6)=1.48979592; local mutated-index ratio A(8)/A(7)=1.43835616
```

Risk:

This is the strongest source-level controller bug candidate found in the
line-by-line pass.  It changes accepted next-step size on promotion branches.

Implemented handling:

Added `odex_hairer_promotion_step` plus
`odex_observe_hairer_promotion_step`; both legacy and context-aware promotion
branches now use `A(new K)/A(old K)`.  The alignment spec pins this branch via
`hairer_route_skeleton ... promote=T`.

### HODEX-LB-004: invalid RHS is classified through repeated rejection/h-min

Status: resolved by
`F18B4I_ODEX_INVALID_RHS_CLASSIFICATION_20260516.md`.

Local lines:

- invalid initial derivative returns `err=huge` and halves `h`: 746-754 and
  960-968
- invalid later derivative only becomes a reject unless conservative stability
  is enabled: 764-789 and 978-1003
- test currently expects NaN RHS to end as `h_min`:
  `tests/test_odex_controller_observation_contract.f90` lines 176-185

Reference lines:

- Hairer `MIDEX` uses `ATOV`/`REJECT` for controller failure paths: 817-830.

Finding:

The current behavior treats NaN RHS as an unresolved integration attempt that
shrinks until h-min, rather than returning invalid immediately.

Risk:

This is project-policy-sensitive.  It may be acceptable if TLTM wants solver
failure to become proposal rejection, but it is not a robust package-style ODE
failure contract.

Implemented handling:

`odex_step` and `odex_step_context` now return a distinct internal
`invalid_rhs` outcome for non-finite initial or later RHS values.  The endpoint
entry points convert it directly to `odex_reason_invalid` / status `102`.
Focused package and observation tests pin both legacy and context-aware APIs.

## Paper Mismatches / Open Proof Surfaces

### HODEX-LB-005: local minimum order is 4, while Hairer controller can use 2

Local lines:

- `odex_k_min=4`: 12
- `odex_normalize_options` enforces `k_min >= 4`: 1626
- demotion paths clamp to `opts%k_min`: 752, 771, 787, 824, 831, 853, 882,
  898, 921, 932 and context duplicates

Reference lines:

- initial `K=MAX(2,...)`: 484
- accepted/rejected controller can set `KOPT=2`: 679-682 and 715-716

Finding:

The local active controller cannot demote below order 4.  Hairer ODEX can
operate at `K=2`.

Proposed handling:

For `hairer_experimental`, allow controller-min order 2 or introduce a separate
experimental min-order field.  Keep default F18b.4b behavior unchanged until a
screen decides whether changing default `k_min` is acceptable.

### HODEX-LB-006: outer controller state machine is collapsed

Local lines:

- endpoint loop: 353-398 and 484-529
- `odex_step` does table construction and mutates `h/k` internally: 724-935

Reference lines:

- first/last-step path: 515-538
- basic path with `KC=K-1`, `K`, optional `K+1`: 539-573
- accepted `KOPT`, after-rejected clamp, next-step update, reject restart:
  678-720

Finding:

Local code does not carry the Hairer `REJECT`, `LAST`, `KC`, `KOPT`, `HOPTDE`,
or after-rejected accepted-step clamp as outer-loop state.  F18b.4d/e observers
map some of this behavior, but the live endpoint loop is still not full Hairer.

Proposed handling:

This is exactly the F18b.4f behavior slice.  Implement it under
`TLTM_ODE_CONTROLLER_POLICY=hairer_experimental` first, with deterministic
branch tests before any 1k screen.

### HODEX-LB-007: error scaling is ODEX-family but not line-equivalent `SCAL`

Local lines:

- local error scale from neighboring tableau entries: 802-805, 812-815,
  842-845, 911-915 and context duplicates

Reference lines:

- initial `SCAL=ATOL+RTOL*ABS(Y)`: 474-481
- per-row scaling uses `MAX(ABS(Y),ABS(T(1)))`: 806-816

Finding:

Local RMS normalized error is structurally reasonable, but it is not the same
line-level `SCAL` lifecycle as Hairer `MIDEX`.

Proposed handling:

Do not claim paper-correct error scaling.  F18b.4f should either port `SCAL`
state for experimental Hairer behavior or explicitly preserve TLTM scaling as a
project policy with analytic-ODE and production screens.

### HODEX-LB-008: large-error and hope-for-convergence thresholds differ

Local lines:

- lower-line early rejection threshold: 830 and 1044
- observer threshold: 1394-1401
- K+1 row is attempted whenever current `err >= 1`: 869-918 and 1083-1132

Reference lines:

- convergence monitor threshold:
  `ERR > ((NJ(K+1)*NJ(K))/4)**2`: 552-555
- hope-for-convergence threshold:
  `ERR > (NJ(K+1)/2)**2`: 564-566

Finding:

The local `(k*k+1)**2` threshold and unconditional K+1 attempt are not Hairer
line-equivalent.

Proposed handling:

Fold into F18b.4f controller-state port.  Add branch tests for both Hairer
thresholds before changing behavior.

### HODEX-LB-009: stability control is not Hairer `MIDEX` stability logic

Local lines:

- default disabled: 53
- conservative norm-growth check: 1658-1673
- checks are embedded in every midpoint row when enabled: 766-789, 877-900 and
  context duplicates

Reference lines:

- `MSTAB/JSTAB` option defaults: 262-272
- scaled derivative-difference quotient: 773-786

Finding:

Local stability is a TLTM-specific optional guard, not Hairer default stability
control.

Proposed handling:

Keep current default off for baseline preservation.  If Hairer experimental
becomes canonical, add a separate stability slice after the outer-controller
port.

### HODEX-LB-010: dense output and non-autonomous time are intentionally out of scope

Local lines:

- `endpoint_only=.true.`: 55
- RHS interface has no explicit time argument: 95-106

Reference lines:

- `SOLOUT`, dense output, `CONTEX`, and time-dependent `FCN(N,X,Y,F,...)`:
  65-93, 577-668, 834-918

Finding:

This is not a current TLTM bug.  TLTM uses endpoint autonomous flow solves.

Proposed handling:

Document as product scope.  Do not claim the handwritten backend is a general
replacement for Hairer's ODEX package.

## Required Handling Order

Recommended order before any further Hairer behavior work:

1. HODEX-LB-001 is resolved by F18b.4g.
2. HODEX-LB-002 and HODEX-LB-003 are resolved by F18b.4h.
3. HODEX-LB-004 is resolved by F18b.4i.
4. Implement HODEX-LB-006/F18b.4f as opt-in outer-controller behavior:
   first/last-step, `KC/KOPT`, immediate reject update, after-rejected accepted
   clamp, and accept-side next-`H`.
5. Only after the outer controller is live should we revisit initial `H/K`,
   `SCAL`, Hairer thresholds, and stability as separate behavior families.

## Current Claim Boundary

After this line audit, the allowed claim is:

```text
The handwritten ODEX backend has a matched ODEX/GBS midpoint-extrapolation core
for TLTM's autonomous endpoint-flow use, but its active controller and some
result/status semantics are not full Hairer ODEX.  The line audit found concrete
bug candidates that must be resolved or explicitly accepted as TLTM policy
before any paper-correctness claim.
```
