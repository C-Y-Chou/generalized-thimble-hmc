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
- Radau/JFNK/final-proposal rescue acceptance remains a legacy robustness/deletion candidate.

Required before deletion:

- Dedicated flow-level characterization of assist/rescue counters.
- Tests that prove assist is forbidden in final proposal construction and external flow calls.

## Decision 3: non-p28 quasi route legacy staging - resolved

Current direction:

- p28 DFO-LS BTN/backflow rescue residual route is production-canonical.
- DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants are legacy/deletion candidates.

Decision:

- Mark non-p28 quasi routes as legacy/quarantine first, not immediate deletion.
- Deletion approval requires staged 10k -> 50k -> 100k physical validation with no major observable problem for canonical p28.
- Dependency search and p28 tests are still required before deletion.

## Decision 4: official canonical baseline configs

After decisions 1-3:

- Choose official no-fallback control config.
- Choose official p28 canonical fallback config.
- Choose flow/ODEX micro baseline configs.
- Choose RNG-order and wrapper-output schema baselines.

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine is a deletion candidate and should not be part of the final canonical p28 route unless explicitly re-promoted later.
- M2c implementation may remove or disable post-refine after comparison harness coverage.

## Canonical flow backend decision - revised 2026-05-09
- User accepted the 10k -> 50k -> 100k solver-assist observation: pure ODEX-only is not the final production policy.
- Current canonical candidate is ODEX primary integration plus solver-internal ODE assist for NT/QN residual evaluation plus strict final proposal flow.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and final-proposal rescue acceptance remain deletion candidates.
- Solver-internal assist must be retained or redesigned as an explicit residual-evaluation status before any deletion attempt.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- Until that validation gate passes, DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants remain legacy/quarantine candidates rather than approved deletions.

## M2 execution policy - 2026-05-08

- Non-flow canonical cleanup before the flow-policy transition is behavior-neutral only: document, quarantine, inventory, and prepare tests, but do not change numerical behavior.
- Flow-policy canonicalization is the first approved numerical canonicalization step that may change trajectories. It requires staged physical validation: 10k -> 50k -> 100k.
- For flow-policy validation, compare physical observables and diagnostics rather than requiring trajectory identity.
- Actual source deletion of post-refine or non-p28 quasi families waits until the staged validation gate and dependency checks pass.
- See `M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md` and `ODEX_ONLY_STAGED_VALIDATION_PLAN.md`.
