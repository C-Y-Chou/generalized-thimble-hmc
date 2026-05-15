# Official DFO-LS Thin Bridge Branch Map - 2026-05-15

Status: F19 source-classification packet, updated after F19.1/F19.2 and the
F19 internal-backend deletion slice.  The original branch map has now been
resolved into an official-only active source route.

## Decisions Carried Forward

- Use the embedded official DFO-LS package as the mature projection-residual
  solver.
- Keep RATTLE failure policy as proposal rejection plus reverse-gate
  certification.  Do not replace it with the paper momentum-flip policy.
- Keep TLTM residual, final-flow, reverse-gate, and Metropolis gates as the
  correctness boundary around any solver package result.
- Delete internal DFO-like rescue, near/far retry routing, force-best
  acceptance, and solver-assist watchdog control from active QN/HMC source.
  Historical outputs that used those paths remain historical/internal evidence.

## Desired Official Route

The canonical official route should read as:

1. Strict Newton projection attempt.
2. If Newton fails and the method enables QN, run one official DFO-LS package
   attempt through the BTN/TLTM residual callback.
3. Accept a package candidate only after strict TLTM residual certification.
   Package success status alone is not an acceptance condition.
4. Run strict final `flow(...)`; non-strict flow status is a step failure.
5. If reverse gate is enabled, reverse-replay the accepted step and reject the
   proposal unless state, Jacobian, and momentum replay within tolerance.
6. Hand the resulting success or rejection to the existing Metropolis/stay-put
   proposal kernel.

This means package failure is not repaired by an internal solver on the
official route.  The only "best" use allowed on the official route is strict
certification of a finite candidate whose residual is already within the active
tolerance.

## Post-F19 Source Map

### `src/sampler/quasi_newton_solver.f90`

| Surface | Classification | Current status |
| --- | --- | --- |
| `solve_constraint_quasi_newton` | Official bridge entry | Runs the official DFO-LS package route only.  There is no internal branch. |
| `run_official_dfols_attempt` and `tltm_official_dfols_solve_c` | Official package mechanism | Kept.  Package output is still checked through TLTM residual and certification gates. |
| `certify_candidate_if_within_tol` | Strict TLTM certification | Kept.  It accepts only candidates whose residual and certification residual are within tolerance. |
| BTN/TLTM residual callback and residual-role tracing | Residual core | Kept for package callback, certification, and reverse replay. |
| `QN_SOLVER_BACKEND=internal` | Removed backend selector | No longer supported.  The loader warns and uses `official_dfols`. |
| `run_dfo_ls_attempt`, `build_dfo_gn_jacobian` | Internal DFO-like solver helpers | Deleted from active source. |
| Force-best, accepted-iter budget, solver-assist watchdog controls | In-house controller leftovers | Deleted from active QN source. |

### `src/sampler/hmc_integrator_core.f90`

| Surface | Classification | Current status |
| --- | --- | --- |
| Strict Newton projection attempt | Core RATTLE/Newton route | Kept. |
| Official QN fallback call | Official bridge wrapper | One official DFO-LS package attempt, then failure classification for diagnostics. |
| Near/mid/far failure classification | Diagnostics only | Kept only to label failures and route/reverse-gate counters.  It does not trigger retry attempts. |
| Near/non-near retry path and `QN_S1_*` knobs | In-house retry leftovers | Deleted from active source. |
| `QN_QUASI_TOL_OVERRIDE` | Relaxed tolerance leftover | Deleted from active source.  Official QN uses `cttol`. |
| Strict final `flow(...)` | TLTM final-state gate | Kept. |
| Reverse gate and RG reject status | TLTM reversibility certification | Kept.  RG reject remains the selected project policy. |

### `src/sampler/quasi_newton_linear_solver.f90`

| Surface | Classification | Current status |
| --- | --- | --- |
| `initial_guess_from_jacobian` | Official package seed mechanism | Kept. |
| `solve_linear_direction` | Internal DFO-like backend helper | Deleted. |
| `initial_guess_from_projection_target` | Unused legacy seed helper | Deleted. |

## Patch Slices

### F19.1 - Rename Strict Certification

Status: implemented in `F19_OFFICIAL_DFOLS_CERTIFICATION_RENAME_20260515.md`.

Behavior intent: no numerical behavior change.

- Rename `rescue_attempt_from_best` to a certification name such as
  `certify_candidate_if_within_tol`.
- Update official-route comments and trace labels so strict certification is
  not described as "rescue" or "force best".
- Verify with compile tests plus retained-core QN/reverse-gate tests.

### F19.2 - Isolate Official Route Policy

Status: implemented in `F19_OFFICIAL_DFOLS_POLICY_ISOLATION_20260515.md`.

Behavior intent: official route cleanup; may intentionally ignore legacy env
knobs that are not part of the selected policy.

- Make `QN_SOLVER_BACKEND=official_dfols` unable to enter internal DFO-like
  retry logic, near/far retry routing, force-best proposal acceptance, or
  solver-assist watchdog termination.
- Keep package failure as failed QN proposal, not internal fallback.
- Preserve TLTM residual certification, final-flow strictness, reverse gate,
  and diagnostics capture.

### F19.3 - Split HMC QN Wrapper Vocabulary

Status: implemented in `F19_INTERNAL_DFO_BACKEND_DELETION_20260515.md`.

Behavior intent: remove misleading stage/rescue language from the official
route without weakening counters or gates.

- Rename/comment the official package attempt path in `hmc_integrator_core`.
- Keep near/far classification as diagnostics-only if retained.
- Preserve reverse-gate path counters and failure capture semantics until a
  later diagnostics/accounting cleanup changes schema intentionally.

### F19.4 - Quarantine Legacy Internal Backend

Status: implemented as deletion in
`F19_INTERNAL_DFO_BACKEND_DELETION_20260515.md`.

Behavior intent: remove the non-official backend rather than keep a transition
window.

- `QN_SOLVER_BACKEND=internal` now warns and uses `official_dfols`.
- Internal DFO-like solver helpers and projection-target seed helpers are
  deleted from active source.
- Historical scripts/outputs remain historical evidence, not official package
  evidence.

## Required Gates For Source Patches

Every behavior-relevant F19 source patch needs an F8 statement, M4, and an
affected-baseline check.  Minimum local gates should include:

- `test_official_dfols_preset_contract`
- retained-core QN route/reverse-gate tests that cover package success, package
  failure without internal fallback, and RG reject stay-put identity
- `test_odex_assist_policy` or its successor if the patch touches residual-role
  or solver-assist policy
- `stage2_rng_v2_anchor` and the M4 guardrail if the patch touches local-update
  control flow
- the assist-off `npt5_r0055` baseline gate before deleting solver-assist code
  or changing adjacent route policy

## Acceptance Criteria

- Official DFO-LS route is visibly one package attempt plus strict TLTM gates.
- Official DFO-LS route cannot be changed by force-best, near/far rescue, or
  internal solver retry knobs.
- Strict certification still requires finite residuals within tolerance in the
  certification role.
- Final flow and reverse gate remain mandatory gates when enabled.
- Package failure, final-flow failure, and reverse-gate failure remain legal
  proposal rejection/stay-put events.
- Internal DFO-like machinery is absent from active source.  Historical outputs
  that used it are explicitly not official package evidence.
