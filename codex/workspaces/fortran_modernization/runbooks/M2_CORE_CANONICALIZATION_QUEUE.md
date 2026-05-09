# M2 Core Numerical Canonicalization Queue

Updated: 2026-05-09
Scope: decisions to resolve after temporary characterization and before official baseline freeze.

## Gate

Do not freeze official modernization baselines until these core numerical decisions are resolved.

## Decision 1: post-refine retention/removal - resolved

Current evidence:

- 128seed/100k primary characterization used `fb_norefine` and shows large failure reduction versus `no_fb`.
- 32seed/50k three-set judgment favored `fb_norefine` over `fb_refine` in aggregate Zmean and runtime.
- Earlier 10seed/10k evidence favored `fb_refine`, so small-sample disagreement existed.

Decision:

- `fb_norefine` is the canonical p28 production route.
- Post-refine is a deletion candidate and should be removed or disabled in M2c after comparison harness coverage.

## Decision 2: ODEX primary flow backend with solver-internal assist - revised/resolved

Decision:

- Pure ODEX-only is not the final canonical policy because staged validation showed a large avoidable robustness loss.
- Canonical candidate is ODEX primary flow with solver-internal ODE assist allowed only inside NT/QN residual evaluation.
- Final proposal construction remains strict: final `flow(...)` must not be completed by assist.
- Radau/JFNK rescue source has been deleted; final-proposal rescue acceptance remains forbidden by strict final-flow gates.

Required before further flow-policy cleanup:

- Dedicated flow-level characterization of assist/rescue counters.
- Tests that prove assist is forbidden in final proposal construction and external flow calls.

## Decision 3: non-p28 quasi route legacy staging - resolved

Current direction:

- p28 DFO-LS BTN/backflow rescue residual route is production-canonical.
- DFO-GN paper, Broyden/line-search, global continuation/restart, and known non-p28 implementation paths have been removed from active source.

Decision:

- Marked non-p28 quasi routes as legacy/quarantine first, then deleted them after staged 10k -> 50k -> 100k validation and dependency checks.
- Future reintroduction requires an explicit research-mode decision and separate tests.

## Decision 4: official canonical baseline configs

After decisions 1-3:

- Choose official no-fallback control config.
- Choose official p28 canonical fallback config.
- Choose flow/ODEX micro baseline configs.
- Choose RNG-order and wrapper-output schema baselines.

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine has been removed from active source after validation and user approval; it should not be part of the final canonical p28 route unless explicitly re-promoted later.

## Canonical flow backend decision - revised 2026-05-09
- User accepted the 10k -> 50k -> 100k solver-assist observation: pure ODEX-only is not the final production policy.
- Current canonical candidate is ODEX primary integration plus solver-internal ODE assist for NT/QN residual evaluation plus strict final proposal flow.
- Radau rescue, fixed/chunked Radau rescue, and JFNK support paths have been deleted from active source.
- Solver-internal assist must be retained or redesigned as an explicit residual-evaluation status before any naming/schema cleanup.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- That validation gate has passed for the QN-clean canonical route; DFO-GN paper, Broyden/line-search, global continuation/restart, and known non-p28 implementation paths were deleted from active source on 2026-05-09.

## M2 execution policy - 2026-05-08

- Non-flow canonical cleanup before the flow-policy transition is behavior-neutral only: document, quarantine, inventory, and prepare tests, but do not change numerical behavior.
- Flow-policy canonicalization is the first approved numerical canonicalization step that may change trajectories. It requires staged physical validation: 10k -> 50k -> 100k.
- For flow-policy validation, compare physical observables and diagnostics rather than requiring trajectory identity.
- Post-refine and non-p28 quasi family source deletion has been completed after staged validation and dependency checks.
- See `M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md` and `ODEX_ONLY_STAGED_VALIDATION_PLAN.md`.
