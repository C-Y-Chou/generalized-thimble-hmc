# M2 Core Numerical Canonicalization Queue

Updated: 2026-05-08
Scope: decisions to resolve after temporary characterization and before official baseline freeze.

## Gate

Do not freeze official modernization baselines until these core numerical decisions are resolved.

## Decision 1: post-refine retention/removal

Current evidence:

- 128seed/100k primary characterization used `fb_norefine` and shows large failure reduction versus `no_fb`.
- 32seed/50k three-set judgment favored `fb_norefine` over `fb_refine` in aggregate Zmean and runtime.
- Earlier 10seed/10k evidence favored `fb_refine`, so small-sample disagreement existed.

Proposed next decision:

- Treat post-refine as a deletion candidate unless user chooses to run more refine-vs-norefine evidence.

## Decision 2: ODEX-only flow backend

Current direction:

- Long-term target is ODEX-only.
- Radau/JFNK/final-resort stack is legacy robustness/deletion candidate.

Required before deletion:

- Dedicated flow-level characterization of rescue counters.
- ODEX-only comparison run or user-approved algorithm version change.

## Decision 3: non-p28 quasi route deletion

Current direction:

- p28 DFO-LS standard residual route is production-canonical.
- DFO-GN paper, Broyden/line-search, global continuation/restart, and non-p28 variants are legacy/deletion candidates.

Required before deletion:

- Dependency search confirms no production config uses these paths.
- Characterization records current p28 route behavior.
- Tests cover p28 residual and route counters.

## Decision 4: official canonical baseline configs

After decisions 1-3:

- Choose official no-fallback control config.
- Choose official p28 canonical fallback config.
- Choose flow/ODEX micro baseline configs.
- Choose RNG-order and wrapper-output schema baselines.
