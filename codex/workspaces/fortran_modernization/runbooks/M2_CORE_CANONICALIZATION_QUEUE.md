# M2 Core Numerical Canonicalization Queue

Updated: 2026-05-08
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

## Decision 2: ODEX-only flow backend - resolved

Decision:

- Canonical long-term flow backend is ODEX-only.
- Radau/JFNK/final-resort stack is legacy robustness/deletion candidate.

Required before deletion:

- Dedicated flow-level characterization of rescue counters.
- ODEX-only comparison run or user-approved algorithm version change.

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

## Canonical flow backend decision - 2026-05-08
- User confirmed ODEX-only as the canonical long-term flow backend target.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and ODE final-resort acceptance are deletion candidates.
- M2c implementation may remove or disable the rescue stack after flow-level characterization and ODEX-only comparison coverage.
- If ODEX-only failure rate is unacceptable, improve ODEX/step control/failure handling rather than preserving a hidden secondary integrator stack by default.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- Until that validation gate passes, DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants remain legacy/quarantine candidates rather than approved deletions.

## M2 execution policy - 2026-05-08

- Non-ODEX canonical cleanup before the ODEX-only transition is behavior-neutral only: document, quarantine, inventory, and prepare tests, but do not change numerical behavior.
- ODEX-only is the first approved numerical canonicalization step that may change trajectories. It requires staged physical validation: 10k -> 50k -> 100k.
- For ODEX-only, validation compares physical observables and diagnostics rather than requiring trajectory identity.
- Actual source deletion of post-refine or non-p28 quasi families waits until the staged validation gate and dependency checks pass.
- See `M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md` and `ODEX_ONLY_STAGED_VALIDATION_PLAN.md`.
