# F18b.4 ODEX Controller Paper-Alignment Plan

Date: 2026-05-16 JST
Scope: HWM-ODEX-001 from
`HANDWRITTEN_MISMATCH_RESOLUTION_TABLE_20260516.md`.
Status: F18b.4a spec/probe slice implemented; F18b.4b first
behavior-changing controller family accepted locally after M4 plus 1k/10k
screens; F18b.4c isolated initial `H`/initial `K` alignment attempted and
blocked by 1k/timing evidence, with active source restored to F18b.4b; user
selected the coherent Hairer route, F18b.4d adds the behavior-free Hairer
controller-skeleton observer/readback, and F18b.4e adds the explicit
`hairer_experimental` opt-in gate plus current-vs-Hairer delta map.

## Confirmed Decision

The user selected:

```text
HWM-ODEX-001 = change_to_paper_or_stronger_reference
```

This supersedes the historical F18b.2 recommendation to preserve current
controller behavior as TLTM endpoint policy.  It does not remove the
endpoint-only product boundary, and it does not claim that the current backend is
already full Hairer ODEX.

## Goal

Align the handwritten TLTM endpoint ODEX controller toward Hairer/paper behavior
or an explicitly stronger reference-backed rule, while keeping the patch series
auditable and reversible.

The first implementation step is not a numerical patch.  It is a spec/test
slice:

1. Extract the controller reference targets.
2. Write deterministic branch tests against those targets.
3. Classify every behavior change under F8.
4. Patch one controller family at a time.

## Reference Targets To Extract

Use the existing audit packets as source maps:

- `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`
- `F18B_HANDWRITTEN_ODEX_ENDPOINT_HARDENING_20260516.md`
- `F18B_CONTROLLER_DECISION_PACKET_20260516.md`

The F18b.4 spec must cover:

- initial step `h0` selection;
- min-step / h-min policy and failure classification;
- explicit step-size growth and shrink bounds;
- order promotion/demotion and large-error rejection thresholds;
- rejected-step retry/status behavior;
- signed endpoint interval behavior and positive work estimates;
- controller error floor and strict-double tolerance boundary;
- stability-control policy.

## Patch Families

Patch families must stay separate:

| Family | First artifact | Source patch allowed only after |
| --- | --- | --- |
| growth/shrink bounds and order thresholds | branch spec and branch tests | F8 statement, focused tests, M4, 1k paired screen plan |
| initial-step estimator | `h0` spec and endpoint tests | F8 statement, focused tests, M4, 1k paired screen plan |
| min-step / h-min policy | h-min spec and failure tests | F8 statement, focused tests, M4, 1k paired screen plan |
| rejected-step/status behavior | rejection spec and status tests | F8 statement, focused tests, M4, 1k paired screen plan |
| stability policy | stability spec and opt-in/default tests | F8 statement, focused tests, M4, 1k paired screen plan |

## Required Tests Before Numerical Patch

The first F18b.4 source-facing slice adds tests/probes, not controller behavior
changes:

- synthetic branch tests for `calculate_hk`, `calculate_wk`, order
  promotion/demotion, and reject/retry paths;
- first-step tests for short, long, forward, and backward endpoint intervals;
- h-min/min-step classification tests;
- signed interval tests for forward and reverse endpoint calls;
- stability predicate/default-policy tests;
- analytic endpoint ODE tests with known exact endpoint behavior.

## Implemented F18b.4a Spec/Probe Slice

Implemented locally on 2026-05-16 JST:

- added the behavior-free `odex_observe_order_transition` helper to expose the
  current final-order branch policy for deterministic tests;
- added `tests/test_odex_controller_alignment_spec.f90`;
- wired `test_odex_controller_alignment_spec` into `build/makefile`;
- added the new target to M4 `modernization_guardrails`.

The new target intentionally distinguishes aligned surfaces from expected
controller gaps.  Passing the test does not mean the controller is now
paper-aligned.  It means the first F18b.4 patch has a deterministic branch map
to edit against.

F18b.4a expected gaps observed by the target before behavior-changing source
patches:

| Gap | Current observation |
| --- | --- |
| initial step | `h0` remains `0.01*t`, independent of tolerance/RHS scale |
| growth bound | zero-error controller estimate grows by about `88.39x` in the probe |
| order demotion threshold | current demotion probe uses `0.9`, while the audit target is the Hairer-style separate decrease threshold near `0.8` |
| stability policy | default route does not reject the conservative-growth probe; conservative opt-in does |

Aligned/currently protected observations:

- Hairer `IWORK(3)=3` step sequence remains `2,4,6,8,12,16,24,32`;
- signed `h` is preserved for controller estimates;
- work estimates remain positive under negative `h`;
- the current promotion/keep order-threshold probes are deterministic.

## Implemented F18b.4b Behavior Patch

Implemented locally on 2026-05-16 JST:

- added Hairer-style step-size control fields to `odex_options`:
  `step_size_bound_fac1=0.02`, `step_size_bound_fac2=4.0`,
  `order_decrease_factor=0.8`, and `order_increase_factor=0.9`;
- routed `calculate_hk` and `calculate_wk` through a bounded
  `odex_step_scale`, preserving signed step candidates and positive work
  estimates;
- updated final-order demotion/promotion predicates to use the separate
  decrease/increase factors instead of the old single `0.9` demotion rule;
- updated `odex_observe_controller_estimate` and
  `odex_observe_order_transition` so deterministic tests exercise the same
  normalized policy fields as endpoint integration.

The deterministic branch target now expects only two remaining controller gaps:

| Remaining gap | Current observation after F18b.4b |
| --- | --- |
| initial step | `h0` remains `0.01*t`, independent of tolerance/RHS scale |
| stability policy | default route does not reject the conservative-growth probe; conservative opt-in does |

The first focused verification passed:

```bash
make -C build test_odex_controller_alignment_spec test_odex_controller_observation_contract
```

Recorded readback:

- growth bound probe clamps zero-error growth to about `1.7487x` at order 4;
- shrink bound probe clamps large-error shrink to about `0.1430x` at order 4;
- order probes keep at `wk_lower=0.85, wk_current=1.0`, demote at
  `0.75,1.0`, and promote at `1.0,0.85`;
- observation contract still preserves signed endpoint intervals, positive work
  estimates, max-step failure classification, h-min failure classification, and
  conservative stability opt-in behavior.

The affected-baseline gates also passed after updating the post-B deterministic
anchor for the expected trajectory change:

- 10seed/1k current-worktree screen:
  `output/tests/f18b4b_odex_bounds_order_10seed_1k_20260516T063826`;
- 10seed/10k current-worktree screen:
  `output/tests/f18b4b_odex_bounds_order_10seed_10k_20260516T064256`;
- full M4:
  `make -C build modernization_guardrails`.

The 10seed/10k screen stayed on the accepted npt5_r0055 assist-off surface:
`no_fb` failures `8300` versus baseline `8340`, and `fb_norefine` failures
`166` versus baseline `167`.

## Gates

Minimum gate for each later behavior-changing family:

```text
F8 behavior statement
focused ODEX branch tests
make -C build modernization_guardrails
retained-core ODEX/QN/RATTLE/RG contracts
1k paired screen before any 10k rerun
```

If the 1k screen is not clean and does not look uniformly extrapolatable to 10k,
stop and discuss before scaling.

## Non-Goals

- Do not add dense output or make the backend a general-purpose ODE package.
- Do not promote SUNDIALS CVODE to canonical through this plan.
- Do not mix F20 single/mixed precision or weaker-tolerance work into this
  strict double controller-alignment slice.
- Do not change RATTLE failure policy here; HWM-RATTLE-001 keeps
  rejection-as-stay-put as project policy.
- Do not change Metropolis output buffer semantics here; HWM-MET-001 is a
  separate focused API contract patch.

## Immediate Next Step

The h0 decision is now option 2: try the larger coherent Hairer-controller
route.  Do not continue by replaying the isolated F18b.4c initialization
transplant.

The next slice is F18b.4f: attach the first opt-in behavior under
`TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`, starting with first/last-step,
`KOPT`, and reject-history coupling while keeping current `h0=0.01*t` until the
controller state machine is in place.  Keep each behavior family behind its own
F8 statement, focused tests, M4, and affected-baseline screen.  Do not treat the
local F18b.4b screen as production-comparison regeneration; that still needs a
clean frozen commit and remote provenance wrapper or an explicit narrower
decision.
