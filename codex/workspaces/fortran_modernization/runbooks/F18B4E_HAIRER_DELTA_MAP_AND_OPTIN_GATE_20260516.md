# F18b.4e Hairer Delta Map And Opt-In Gate

Date: 2026-05-16 JST

Status: implemented as a non-canonical behavior gate plus delta map, with a
post-readback correction to the rejected-step observer.  Active default endpoint
integration behavior remains F18b.4b.

## Purpose

F18b.4c showed that a standalone initial `H`/initial `K` transplant is not a
safe next step.  F18b.4d then added behavior-free Hairer controller observers.
F18b.4e turns that into an explicit implementation route:

- make the Hairer path opt-in only;
- keep the default route at `tltm_endpoint`;
- document the current-vs-Hairer deltas before a behavior patch;
- select the first behavior patch surface without retrying initial `H/K` yet.

## Primary Reference

Primary source is Hairer and Wanner's official `odex.f`:

- interface/default parameters: lines 46-52 and 129-152;
- `ODXCOR` initial preparations: lines 482-487;
- first/last-step and basic step split: lines 515-572;
- accepted-step `KOPT`, after-rejected-step, next-step update, and rejected
  step path: lines 678-720;
- `MIDEX` stability and optimal step update: lines 773-831.

The local endpoint backend intentionally keeps dense output out of scope.

## Detail Readback Correction

The gate/API names are not treated as proof of correctness.  A post-challenge
readback against official `odex.f` found that the first
`odex_observe_hairer_reject_update` helper was under-specified: it could not
represent the full Hairer/Wanner rejected-step update after
`K=MIN(K,KC,KM-1)`.

The helper now consumes full `W(:)` and `HH(:)` observer arrays and checks both:

- no-demotion rejected-step restart, where `K` remains at the min-clamped value;
- demotion-after-min, where `W(K-1)<W(K)*FAC3` moves the restart order down.

This is a bug fix in the executable reference map only.  The active default
endpoint loop is still unchanged, and the after-rejected accepted-step clamp
from `ODXCOR` lines 693-699 still belongs to the F18b.4f behavior patch.

## Implemented Gate

Added explicit controller policy constants and name parsing in
`src/physics/odex_backend.f90`:

- `odex_controller_policy_tltm_endpoint = 0`
- `odex_controller_policy_hairer_experimental = 1`
- `odex_apply_controller_policy_name`
- `odex_controller_policy_name`

`solve_flow` now parses:

```text
TLTM_ODE_CONTROLLER_POLICY
```

Accepted names:

- default/TLTM route: `default`, `tltm`, `tltm_endpoint`, `endpoint`,
  `f18b4b`;
- experimental Hairer route: `hairer`, `hairer_experimental`,
  `hairer_route`, `experimental`.

Invalid controller-policy tokens become invalid ODEX options.  The active
integration loop currently validates the token but still uses the F18b.4b
endpoint controller for both valid policies.  This is intentional: the gate is
ready before behavior is attached.

## Delta Map

| Surface | Current TLTM endpoint route | Hairer route | F18b.4e decision |
| --- | --- | --- | --- |
| product scope | endpoint-only flow solve, no dense output | general ODE package with optional dense output | keep endpoint-only scope |
| default policy | implicit TLTM endpoint controller | official ODEX controller | default remains `tltm_endpoint` |
| opt-in switch | none | not applicable in original package | add `hairer_experimental` gate |
| initial `H/K` | `h0=0.01*t`, `k=opts%k_min` | caller `H`, `H=0 -> 1e-4`, tolerance-derived `K` | blocked until controller coupling is implemented |
| step entry | simple endpoint clamp before each step | `HMAX`, `HOPTDE`, endpoint reached test, first/last step path | first behavior-patch candidate |
| first/last step | same `odex_step` path as ordinary steps | special path runs lines `1..K` and accepts once `J>1` and `ERR<=1` | first behavior-patch candidate |
| basic step | `odex_step` performs table, accept/reject, h/k mutation internally | outer `ODXCOR` runs `K-1`, then `K`, then optional `K+1` | needs larger refactor |
| accepted `KOPT` | local `odex_step` mutates `k` from work estimates | outer controller computes `KOPT` after accepted `KC` | first behavior-patch candidate |
| rejected step | local shrink/demote happens inside `odex_step` | immediate reject uses `K=MIN(K,KC,KM-1)`, `W(K-1)<W(K)*FAC3`, and signed `HH(K)`; after-rejected accepted step clamps `K/H` before clearing `REJECT` | observer corrected; behavior patch candidate |
| h-min/failure | TLTM status mapping with failure-as-rejection compatibility | original code has fail exit on too many steps; no TLTM statuses | keep TLTM status mapping |
| stability | default off, conservative opt-in | `MIDEX` activates low-table stability checks by default | later gated patch |
| final flow/reverse gate | TLTM-specific certification outside ODEX | not part of Hairer ODEX | preserve TLTM certification |

## First Behavior Patch Design

F18b.4f should be opt-in only:

```text
TLTM_ODE_CONTROLLER_POLICY=hairer_experimental
```

Recommended first behavior slice:

1. move `REJECT`, `LAST`, `KOPT`, `KC`, `HOPTDE`, immediate rejected-step
   update, and after-rejected accepted-step clamp into the endpoint outer loop
   for the experimental policy;
2. keep the current midpoint/extrapolation table kernel as the line evaluator;
3. keep current `h0=0.01*t` for this first slice to avoid replaying F18b.4c;
4. add focused deterministic tests comparing current route vs experimental
   route on first/last step and reject-history transitions;
5. only after that passes, retry official initial `H/K` under the experimental
   route.

The point is to port the controller state machine before changing the initial
condition that feeds it.

## Gates

F18b.4e verification:

```bash
make -C build test_odex_controller_alignment_spec test_odex_result_contract
make -C build modernization_guardrails
```

Readback includes:

```text
[CHECK] hairer_route_policy_gate ok=T policy=1
[CHECK] hairer_route_skeleton init=T step=T kopt=T reject=T
[CHECK] controller_policy_name ok=T policy=hairer_experimental
```

Full M4 passed with artifact root:

```text
output/tests/m4_guardrails
```

Before accepting any F18b.4f behavior:

1. focused deterministic controller tests pass for both default and
   `hairer_experimental`;
2. full M4 passes;
3. local 10seed/1k screen is acceptable in failure surface and runtime;
4. only then consider 10seed/10k;
5. production-comparison use remains blocked until a clean frozen commit and
   remote provenance wrapper or explicit narrower decision.
