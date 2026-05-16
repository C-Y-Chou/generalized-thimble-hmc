# F18b.4d Hairer Controller Route Skeleton

Date: 2026-05-16 JST

Status: user selected the Hairer route.  The first implementation is a
behavior-free controller-skeleton observer, not an endpoint-trajectory change.

## Decision

After the isolated F18b.4c initial `H`/initial `K` screen was invalidated, the
selected route is still to try Hairer alignment, but only with a working
official DFO-LS bridge/env and with a coherent controller porting order.

This means:

- do not treat the isolated F18b.4c screen as ODEX negative evidence;
- do not claim the current backend is full Hairer ODEX;
- build a deterministic map of the Hairer controller state machine first;
- only then patch behavior in coupled controller slices.

Primary reference is Hairer and Wanner's official `odex.f` source from the
Geneva site:

- `ODEX` interface/defaults: initial `H`, `HMAX`, `IWORK(2)`, `IWORK(3)`,
  `FAC1/FAC2`, `FAC3/FAC4`, `SAFE1/SAFE2`;
- `ODXCOR` initial preparations: signed interval, tolerance-derived initial
  `K`, `H=0 -> 1e-4`, `HMAX`, and half-span cap;
- `ODXCOR` loop controller: first/last-step path, basic integration path,
  hope-for-convergence line, accepted-step `KOPT`, after-rejected-step path,
  and rejected-step update.

## Implemented Skeleton

The local source now exposes behavior-free observers for the Hairer route:

- `odex_observe_hairer_initial_state`
- `odex_observe_hairer_step_entry`
- `odex_observe_hairer_kopt`
- `odex_observe_hairer_reject_update`

These helpers do not change `odex_integrate_endpoint` or
`odex_integrate_endpoint_context`.  They are an executable reference map for the
next behavior patch.

## Detail Readback Correction

After a user-requested detail check, the rejected-step observer was corrected.
The first skeleton version was too compressed: it only carried scalar
`W(K-1)`, `W(K)`, `HH(K-1)`, and `HH(K)` style inputs and therefore could not
faithfully represent Hairer/Wanner `ODXCOR` lines 713-720:

```fortran
K=MIN(K,KC,KM-1)
IF (K.GT.2.AND.W(K-1).LT.W(K)*FAC3) K=K-1
H=POSNEG*HH(K)
```

`odex_observe_hairer_reject_update` now takes `work_values(:)` and
`step_values(:)`, first applies `K=MIN(K,KC,KM-1)`, then applies the
`W(K-1)<W(K)*FAC3` demotion test, and finally returns the signed `HH(K)`.
The focused spec includes both no-demotion and demotion-after-min cases.

This correction still proves only the observer map.  It does not yet implement
the after-rejected accepted-step path from `ODXCOR` lines 693-699 in endpoint
behavior.

The existing F18b.4 alignment target now checks:

- official-style initial `H=0 -> 1e-4`;
- tolerance-derived initial `K`;
- signed half-span cap;
- step-entry `HMAX`/`HOPTDE`/last-step behavior;
- accepted-step `KOPT` demotion/promotion cases;
- immediate rejected-step order/step update using full `W(:)`/`HH(:)` values.

The expected active-controller gaps remain:

- `h0_fraction_policy`;
- default stability policy off.

## Verification

Focused readback:

```bash
make -C build test_odex_controller_alignment_spec
make -C build test_odex_controller_alignment_spec test_odex_controller_observation_contract test_odex_result_contract
```

Observed:

```text
[CHECK] hairer_route_skeleton init=T step=T kopt=T reject=T
[CHECK] expected controller gaps=2 expected=2
```

Full modernization guardrail readback also passed:

```bash
make -C build modernization_guardrails
```

Artifact root:

```text
output/tests/m4_guardrails
```

This proves only the skeleton readback and guard surface.  It is not numerical
acceptance of a Hairer behavior patch.

## Required Next Slice

F18b.4e should be a delta-map plus first behavior patch design, not a blind
source edit.

The delta map must classify each current-vs-Hairer surface:

| Surface | Current TLTM state | Hairer route requirement | Patch mode |
| --- | --- | --- | --- |
| initial `H`/`K` | F18b.4c isolated screen invalidated by missing official DFO-LS bridge/env | retry only with bridge/env preflight and inside coherent controller route | corrected gated screen |
| first/last step | current loop has simple endpoint clamp | Hairer has special first/last path before basic step | behavior patch |
| `KOPT` after accept | current `odex_step` mutates `k` locally | Hairer computes `KOPT` after accepted `KC` | behavior patch |
| after rejected step | current shrink/demote happens inside step helper | Hairer preserves reject history and restarts basic path | behavior patch |
| h-min/failure | TLTM project status mapping | must remain compatible with TLTM failure-as-rejection contracts | gated behavior patch |
| stability | default off, conservative opt-in | Hairer activates low-table stability checks by default | gated behavior patch |

The first behavior patch should be opt-in or tightly gated until a local 1k
screen proves it is not repeating the invalid F18b.4c bridge/env setup.

## Gate

No 10k run or post-B anchor update is allowed from the skeleton alone.

Before canonical adoption of any Hairer-route behavior patch:

1. focused deterministic controller tests pass;
2. full M4 passes;
3. 10seed/1k TLTM screen has reasonable failure/runtime behavior;
4. only then consider 10seed/10k;
5. production-comparison use still requires a clean frozen commit and remote
   provenance wrapper or an explicit narrower decision.
