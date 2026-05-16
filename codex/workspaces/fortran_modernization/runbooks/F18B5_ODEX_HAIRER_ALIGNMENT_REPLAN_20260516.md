# F18b.5 ODEX Hairer Alignment Replan

Date: 2026-05-16 JST

## Purpose

Reset the route from the current handwritten TLTM endpoint ODEX to a Hairer-
aligned experimental controller without relying on random detail reminders or
runtime-first patching.

This replan supersedes the earlier "patch selected controller pieces, then
screen" route for `hairer_experimental`.  The previous remote telemetry remains
useful debug evidence for hybrid-controller behavior, but it is not evidence of
the cost of a coherent Hairer controller.

## Immediate Finding

The dangerous boundary is structural:

- Hairer `ODXCOR` owns the outer controller state machine.
- Hairer `MIDEX(J)` computes one row and returns row-local quantities:
  extrapolated row state, `ERR`, `HH(J)`, `W(J)`, and `ATOV`.
- Current TLTM `odex_step` computes several rows and mutates `h/k` internally.

Therefore the safe route is not to continue adding Hairer formulas inside
`odex_step`.  The next route must first separate "compute a row" from "decide
which row/order/step comes next".

## Evidence Status Reset

| Evidence | Status after replan |
| --- | --- |
| F18b.4m/F18b.4n 10seed/10k opt-in screen | Valid evidence that the then-current hybrid `hairer_experimental` was behavior-near but slower.  Not evidence for coherent Hairer cost. |
| F18b.4o direct telemetry | Valid localization of hybrid cost to accepted endpoint work and K+1 overwork.  Not a final route decision. |
| `15539.anode01` H=0 fallback run | Negative evidence only for using Hairer's `H=0 -> 1e-4` fallback as the TLTM live caller value. |
| `15540.anode01` caller-H + partial controller run | Negative hybrid evidence; the route still had controller-state/lifecycle mixing. |
| `15541.anode01` | Invalid: remote build failed from mixed gfortran/ifx module artifacts. |
| `15542.anode01` | Stopped intentionally after user requested replan; partial diagnostic only. |

## Reference State Map

Reference source: Hairer/Wanner official `odex.f` from the Geneva site:
`https://www.unige.ch/~hairer/prog/nonstiff/odex.f`.

| Symbol / State | Hairer role | Dependency |
| --- | --- | --- |
| `NJ(:)` | step-number sequence.  TLTM deliberately uses `IWORK(3)=3`: `2,4,6,8,12,...`. | row primitive |
| `A(:)` | cumulative work model `A(1)=1+NJ(1)`, `A(i)=A(i-1)+NJ(i)`. | `W`, promotion |
| `SCAL(:)` | mutable error scale.  Initial `ATOL+RTOL*ABS(Y)`; per row uses `MAX(ABS(Y),ABS(T(1)))`. | row lifecycle |
| `HH(:)` | candidate next step per row. | row lifecycle, controller |
| `W(:)` | work per unit step `A(J)/HH(J)`. | controller |
| `ERROLD` | monotonicity guard; `J>2` and `ERR>=ERROLD` triggers `ATOV`. | row lifecycle |
| `ATOV` | row-level "step too large / no useful continuation" signal; shrinks `H` by `SAFE3` and marks rejected. | row lifecycle, controller retry |
| `H`, `HMAX`, `POSNEG`, `HOPTDE`, `LAST` | signed step-entry state.  `HOPTDE` is mostly dense-output-related for TLTM's endpoint-only use but still part of the step-entry clamp. | controller |
| `K`, `KC`, `KOPT`, `REJECT` | outer order-selection state.  `K` can be 2; `KC` records the highest computed row accepted/rejected this step; `KOPT` controls next order. | controller |
| `SAFE1`, `SAFE2`, `SAFE3`, `FAC1`, `FAC2`, `FAC3`, `FAC4` | step-size, shrink, and order-selection constants. | row lifecycle, controller |
| `MSTAB`, `JSTAB` | Hairer stability check bounds inside `MIDEX`. | stability slice |

## Current TLTM Map

| Local surface | Current behavior |
| --- | --- |
| `odex_integrate_endpoint*` | endpoint-only outer loop.  Default `tltm_endpoint` still delegates to `odex_step*`; opt-in `hairer_experimental` now owns a controller state and calls the F18b.5e live Hairer row/controller helper. |
| `odex_step*` | default TLTM route only: computes rows `1..k`, may attempt `k+1`, computes errors, chooses accept/reject, and mutates `h/k` internally. |
| `odex_step_hairer_controller*` | F18b.5e opt-in route: consumes `odex_hairer_row_lifecycle` plus `odex_hairer_controller_state`, including first/last/basic row decisions, accept/reject update, K+1 hope, `ERROLD`, and `ATOV` retry. |
| `odex_error_scale` | policy split: default uses old TLTM neighboring-estimate scale.  The opt-in Hairer row lifecycle uses Hairer-style `ATOL+RTOL*MAX(ABS(Y),ABS(T(1)))` scaling directly in the row primitive. |
| `odex_observe_hairer_*` | observer/helper surface plus the live opt-in endpoint route.  Default endpoint behavior remains separated from this experimental path. |
| `odex_normalize_options` | clamps `options%k_min >= odex_k_min`, with `odex_k_min=4`.  Some Hairer helper paths bypass this, so lower-bound behavior is currently mixed rather than designed. |
| Stability | TLTM-specific optional norm-growth guard, not Hairer `MIDEX` stability logic. |

## Gap / Dependency Matrix

| Gap | Layer | Must be solved before | Notes |
| --- | --- | --- | --- |
| Single-row `MIDEX(J)` primitive missing | row primitive | any coherent controller port | Highest priority.  Without it, controller and row computation remain mixed. |
| `J=1` no-error and `J=2` first legal error lifecycle | row primitive | `K=2`, first-step branch, K+1 hope branch | This is not an isolated user-reminder item; it is a necessary consequence of single-row `MIDEX`. |
| Mutable `SCAL(:)` lifecycle missing from live route | row lifecycle | trustworthy endpoint controller consumption | Closed for the opt-in `hairer_experimental` endpoint route by F18b.5e; default `tltm_endpoint` intentionally stays on the old route. |
| `HH(:)` / `W(:)` as persistent per-step row arrays missing from live route | row lifecycle | `KOPT`, reject update, promotion | Closed for the opt-in `hairer_experimental` endpoint route by F18b.5e. |
| `ERROLD/ATOV` missing from live row lifecycle | row lifecycle | safe continuation/retry decisions | Closed for the opt-in `hairer_experimental` endpoint route by F18b.5e; package telemetry now expects live `ERROLD` checks. |
| `REJECT/LAST/KC/KOPT` not live in outer loop | controller | runtime screens | Closed for the opt-in `hairer_experimental` endpoint route by F18b.5e. |
| lower bound `K=2` not consistently designed | controller policy | full Hairer route | Default TLTM should remain `K>=4`; experimental Hairer must be explicitly `K>=2`. |
| after-reject accepted-step clamp missing | controller | production-sized screen | Cannot infer from telemetry without state identity. |
| dense-output pieces | product scope | not required for endpoint-only TLTM route | Keep documented out of scope unless product goals change. |
| Hairer stability check | stability slice | canonical adoption claim | Can be implemented after controller identity; default remains unchanged until approved. |

## Safe Implementation Order

### F18b.5a: Identity Map And Branch Counters

Status: implemented on 2026-05-16 JST.

No behavior change.  Add or update tests/telemetry so `hairer_experimental` can
prove which reference branches are actually active.  Implemented counters:

- first-step, last-step, basic-step branch counts;
- row calls by `J`;
- `J=1` no-error returns and `J>=2` error estimates;
- `ATOV`, `ERROLD`, convergence-monitor reject, K+1 hope reject;
- accept by `KC`, reject by `KC`, `KOPT` transitions;
- after-rejected accepted-step clamps.

Implementation surfaces:

- `src/physics/odex_backend.f90`: `odex_result` / `odex_step_telemetry`
  counters plus branch recording helpers.
- `src/physics/solve_flow.f90`: run-level ODEX aggregate diagnostics.
- `src/sampler/tltm_stage2_driver.f90`: Stage2 `# odex_stats` summary lines.
- `scripts/run_stage3_3_multiseed.py`: per-seed and aggregate CSV columns.
- `tests/test_odex_result_contract.f90` and
  `tests/test_odex_backend_package_contract.f90`: reset, policy, row, scale,
  and currently-missing-branch identity checks.

Important readback:

- Current hybrid `hairer_experimental` can now prove which policy/row/scale and
  KOPT branches are active.
- `ERROLD`, `ATOV`, and after-rejected accepted-step clamp counters are
  intentionally explicit and currently remain zero; that is a state-map fact,
  not evidence that those Hairer branches are implemented.
- This patch does not introduce the single-row `MIDEX(J)` primitive and does
  not change default `tltm_endpoint` behavior.

Focused verification passed:

```text
git diff --check
python3 -m py_compile scripts/run_stage3_3_multiseed.py
make -C build test_odex_result_contract test_odex_backend_package_contract test_odex_controller_alignment_spec
```

Do not run more 1k/10seed telemetry until this identity surface and the
single-row primitive gates exist together.

### F18b.5b: Single-Row Primitive

Status: implemented on 2026-05-16 JST.

Introduces an internal row primitive under tests, not wired as the live
endpoint default:

```text
compute_row(j, state, h, y, fbase, scal, errold) ->
  tableau row update, err_available, err, hh(j), w(j), atov, rhs_count
```

Hard gates:

- `J=1` computes midpoint/smoothing row and returns no error estimate.
- `J=2` computes the first legal error estimate from the two extrapolated
  estimates.
- `J>=3` updates `ERROLD` and can return `ATOV`.
- Signed `H` keeps endpoint direction, while `HH/W` remain positive work
  quantities.

Implementation surfaces:

- `src/physics/odex_backend.f90`: public test-facing
  `odex_observe_hairer_midex_row` plus `odex_row_result`.
- `tests/test_odex_controller_alignment_spec.f90`: focused contract for
  `J=1`, `J=2`, signed-H/positive-work behavior, non-ATOV `J=3`, and forced
  `J=3` ATOV.

Important readback:

- The primitive follows the official Hairer `MIDEX(J)` row structure: explicit
  midpoint row, polynomial extrapolation for `J>1`, mutable `SCAL(:)`, error
  estimate, `ERROLD` monotonic guard, `HH/W`, and `SAFE3=0.5` ATOV shrink.
- The default endpoint route still uses the existing `odex_step*` path.  This
  is intentionally not yet a live controller rewrite.
- Row lifecycle observer ownership is now F18b.5c work; controller consumption
  remains F18b.5d work.

Focused verification passed:

```text
git diff --check
python3 -m py_compile scripts/run_stage3_3_multiseed.py
make -C build test_odex_controller_alignment_spec test_odex_backend_package_contract test_odex_result_contract
```

### F18b.5c: Row Lifecycle

Status: implemented on 2026-05-16 JST.

Make `SCAL(:)`, `HH(:)`, `W(:)`, `ERROLD`, and `ATOV` first-class state for the
experimental row path.  This should still be exercised through analytic and
branch tests, not TLTM production screens.

Implementation surfaces:

- `src/physics/odex_backend.f90`: public test-facing
  `odex_hairer_row_lifecycle`, `odex_hairer_errold_initial`,
  `odex_observe_hairer_row_lifecycle_begin`, and
  `odex_observe_hairer_midex_lifecycle_row`.
- `tests/test_odex_controller_alignment_spec.f90`: lifecycle contract for
  initial `SCAL(:)` and `ERROLD=1D10`, `J=1` no-error/no-`HH/W`, `J=2`
  `HH/W` storage and `SCAL(:)` mutation, forced `J=3` `ATOV`, and reset.

Important readback:

- This slice keeps the default endpoint route unchanged.  The lifecycle
  wrapper is still an observer/test surface around the single-row primitive.
- `J=1` correctly leaves `HH(1)/W(1)` unset, because Hairer `MIDEX(J)` returns
  before error/stepsize estimation for the first row.
- `ATOV` shrinks signed `H` by `SAFE3=0.5` and records the event without
  fabricating `HH(J)/W(J)` for the rejected row.

Focused verification passed:

```text
git diff --check -- src/physics/odex_backend.f90 tests/test_odex_controller_alignment_spec.f90
make -C build test_odex_controller_alignment_spec test_odex_backend_package_contract test_odex_result_contract
```

### F18b.5d: Pure Outer Controller State Machine

Status: implemented in test-facing form on 2026-05-16 JST.

Implement a pure or near-pure controller-decision layer that consumes row
outcomes and returns the next action:

- step entry: endpoint reached, last-step clipping, signed `H`;
- first/last step: compute `J=1..K`, accept once `J>1 && ERR<=1`, else K+1
  hope;
- basic step: compute `1..K-1`, convergence monitor, row `K`, then K+1 hope;
- accepted step: update `X/Y`, compute `KOPT`, apply after-reject clamp if
  `REJECT=.true.`, otherwise compute next `H/K`;
- rejected step: `K=MIN(K,KC,KM-1)`, possible demotion by `W(K-1)<W(K)*FAC3`,
  `H=POSNEG*HH(K)`, `REJECT=.true.` and restart from the basic path.

This layer must be tested with synthetic `ERR/HH/W/K/KC/REJECT/LAST` cases
before it controls TLTM flow solves.

Implementation surfaces:

- `src/physics/odex_backend.f90`: public test-facing
  `odex_hairer_controller_state`, `odex_hairer_controller_decision`, controller
  action/phase constants, and observer helpers for initial state, step entry,
  row action, accepted-step update, and rejected-step update.
- `tests/test_odex_controller_alignment_spec.f90`: synthetic controller
  contract for step-entry endpoint/last-step behavior, first/last-step row
  accept and K+1 hope, basic-step convergence monitor, after-reject accepted
  clamp, rejected-step demotion, signed `H`, and `ATOV` retry.

Important readback:

- The helper layer follows the official Hairer `ODXCOR` outer-controller
  structure but remains outside the live endpoint route.
- `ATOV` produces a retry with `REJECT=.true.` and the `SAFE3`-shrunk signed
  `H`; ordinary rejected steps apply `K=MIN(K,KC,KM-1)`, possible demotion by
  `W(K-1)<W(K)*FAC3`, and signed `HH(K)`.
- Accepted-step update computes `KOPT`, preserves the after-reject clamp
  `H=POSNEG*MIN(ABS(H),ABS(HH(K)))`, and uses the Hairer promotion special case
  with `A(KOPT+1)/A(KC)` when `KC<K` and the work comparison requires it.

Focused verification passed:

```text
git diff --check -- src/physics/odex_backend.f90 tests/test_odex_controller_alignment_spec.f90
make -C build test_odex_controller_alignment_spec test_odex_backend_package_contract test_odex_result_contract
```

### F18b.5e: Opt-In Endpoint Wiring

Status: implemented on 2026-05-16 JST.

Wire the row primitive plus outer controller only under
`TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`.  Keep `tltm_endpoint`
unchanged and keep the old `odex_step*` path available until the experimental
route has completed analytic and remote gates.

Implementation surfaces:

- `src/physics/odex_backend.f90`: `odex_integrate_endpoint` and
  `odex_integrate_endpoint_context` now branch under
  `odex_controller_policy_hairer_experimental` into
  `odex_step_hairer_controller` / `odex_step_hairer_controller_context`.
- The live opt-in helper computes the base RHS once per attempted endpoint step,
  runs one `MIDEX(J)` row at a time through the row lifecycle, passes each row to
  the controller action helper, and applies accepted-step or rejected-step update
  before returning to the endpoint loop.
- A private context-row equivalent keeps `intode_with_context` on the same
  controller path, so Stage2/Stage3 flow calls are not silently left on the old
  hybrid route when the opt-in policy is selected.
- `tests/test_odex_backend_package_contract.f90`: the package contract now
  verifies both non-context and context `hairer_experimental` endpoint solves and
  expects live `ERROLD` checks to equal Hairer error-estimate counts.

Important readback:

- Default `tltm_endpoint` still uses `odex_step*`; this patch is opt-in only.
- The earlier F18b.4m/F18b.4n/F18b.4o telemetry remains hybrid-route evidence.
  It is not evidence for this F18b.5e coherent state-machine route.
- Local focused endpoint checks passed for this slice, but no TLTM Stage2/Stage3
  simulation screen was run locally.  F18b.5f later added the analytic endpoint
  gates; the next pre-telemetry step is the remote tiny smoke.
- The current live helper still leaves dense-output/general-purpose ODEX and full
  Hairer stability logic out of scope; those remain explicit product-boundary
  decisions.

Focused verification passed:

```text
git diff --check -- src/physics/odex_backend.f90 tests/test_odex_backend_package_contract.f90
make -C build test_odex_controller_alignment_spec test_odex_backend_package_contract test_odex_result_contract test_odex_controller_observation_contract
```

### F18b.5f: Analytic And Tiny Remote Gates

Status: local analytic endpoint gates implemented on 2026-05-16 JST.  The first
remote tiny PBS smoke (`15543.anode01`) completed Stage3 but failed the terminal
counter assertion because Stage2 summary aggregation did not yet carry the
F18b.5a+ ODEX policy/row/lifecycle counters from per-run contexts into the
aggregate summary.  The aggregation repair is implemented locally and the tiny
smoke must be rerun at the repair commit before any 1k telemetry.

Before any 1k/10seed screen:

- local analytic ODE tests: exponential, forward/backward, signed interval,
  first-step only, last-step clipping, forced reject, and `K=2` branches;
- no local TLTM Stage2/Stage3 simulation;
- remote tiny TLTM smoke only after branch counters prove the intended route is
  active.

Implementation surfaces so far:

- `tests/test_odex_backend_package_contract.f90`: adds
  `check_hairer_experimental_analytic_gates`, covering opt-in signed
  forward/backward composition, live `K=2` first/last branch under a max-step
  budget, and a stiff scalar endpoint that forces rejected steps plus one
  `ATOV` event.
- `codex/workspaces/fortran_modernization/tasks/pbs/f18b5f_hairer_endpoint_tiny_smoke_20260516.pbs`:
  remote tiny Stage3 smoke for one seed, 200 cycles, `no_fb` plus
  `fb_norefine`, official DFO-LS `npt5_r0055`, assist off, Stage2 RNG v2, and
  opt-in `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`.  The PBS script
  verifies aggregated ODEX counters have Hairer policy steps, zero TLTM policy
  steps, live `ERROLD` checks, Hairer scales, and no default scales.
- `src/sampler/tltm_stage2_driver.f90`: `add_intode_diagnostics` now aggregates
  the F18b.5a+ ODEX policy/row/lifecycle counters instead of only the older
  call/step/RHS counters.
- `tests/test_odex_foundation_contract.f90`: adds
  `check_controller_policy_diagnostics`, which verifies the default controller
  reports TLTM policy counters and `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`
  reports Hairer policy counters through `intode_with_context`.

Local focused verification passed:

```text
git diff --check -- tests/test_odex_backend_package_contract.f90
make -C build test_odex_backend_package_contract
make -C build test_odex_controller_alignment_spec test_odex_backend_package_contract test_odex_result_contract test_odex_controller_observation_contract test_odex_foundation_contract
TLTM_ODE_CONTROLLER_POLICY=hairer_experimental make -C build test_odex_foundation_contract
```

### F18b.5g: Telemetry Promotion Gates

Only after F18b.5f:

1. remote 1k/10seed telemetry compare;
2. stop and discuss if runtime/counters are not plausibly 10k-scalable;
3. remote 10k/10seed only if 1k is coherent and close enough;
4. default-route adoption only after separate approval.

## Current Decision

Do not use the older hybrid `hairer_experimental` telemetry as the route
decision for the coherent Hairer state-machine path.  F18b.5a identity-map/
counter/test surface, F18b.5b single-row `MIDEX(J)` primitive, F18b.5c
row-lifecycle state, F18b.5d outer-controller decision layer, F18b.5e opt-in
endpoint wiring, and F18b.5f local analytic gates are implemented.  The next
actionable engineering step is the F18b.5f remote tiny TLTM smoke, still before
any additional 1k telemetry.

## Claim Boundary

Allowed claim after this replan:

```text
The TLTM handwritten ODEX midpoint/extrapolation core remains the strongest
matched surface.  The route to Hairer alignment must now proceed by state-machine
port: row primitive, row lifecycle, outer controller, then endpoint wiring.
Existing hybrid Hairer telemetry is debug evidence only and cannot decide the
true cost of a coherent Hairer controller.  F18b.5a identity counters,
F18b.5b single-row primitive, F18b.5c row lifecycle, F18b.5d outer controller
decision state, F18b.5e opt-in endpoint wiring, and F18b.5f local analytic gates
are implemented; the next claim boundary is F18b.5f remote tiny-smoke evidence.
```
