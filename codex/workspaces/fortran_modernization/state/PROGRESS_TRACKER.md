# Progress Tracker: fortran_modernization

## Current milestone
- M0: planning and governance establishment

## Milestones
- M0: planning and governance established
- M1: architecture audit completed
- M2: verification baseline matrix established
- M3: target architecture and solver redesign spec approved
- M4: guardrail tests and benchmarks in place
- M5: first core refactor wave completed with preserved outputs
- M6: publication/product readiness package assembled

## Status log
- 2026-04-30 16:05 JST: created master modernization workspace, principles, preservation protocol, master plan, redesign guide, test roadmap, risk register, and progress tracker.
- 2026-05-08 JST: collected algorithm reference bundle and created algorithm-to-implementation review map.
- 2026-05-08 JST: added Hairer ODEX reference, focused excerpts, and ODEX location guide.
- 2026-05-08 JST: created behavior-preserving algorithm audit plan; next deep review target is ODEX flow integration.
- 2026-05-08 JST: completed `runbooks/ODEX_FLOW_REVIEW_NOTES.md`; identified ODEX mechanism, flow wrapper boundary, fallback-policy coupling, behavior risks, and required baselines. Next planning deliverable is `runbooks/BASELINE_VERIFICATION_MATRIX.md`.
- 2026-05-08 JST: completed planning information collection for ODEX, simplified Newton/RATTLE, quasi-Newton projection, HMC/Metropolis/TLTM driver, and baseline verification matrix; ready for user discussion/confirmation.
- 2026-05-08 JST: decision recorded that p28 DFO-LS standard-residual route is the only production-canonical quasi route; other quasi routes are legacy/deletion candidates; post-refine remains under observation.
- 2026-05-08 JST: decision recorded that stage-specific workflows are transitional; final modernization target is a unified TLTM wrapper/runner with versioned output schema after TLTM construction/Stage3_4 judgment.
- 2026-05-08 JST: decision recorded that official modernization baselines will be regenerated after Stage3_4/TLTM judgment; existing `output/tests` are historical/reference evidence only.
- 2026-05-08 JST: decision recorded that reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- 2026-05-08 JST: tentative flow backend decision recorded: long-term publishable target is ODEX-only; Radau/JFNK/final-resort rescue stack is legacy/deletion candidate after Stage3_4/TLTM judgment and ODEX-only comparison.
- 2026-05-08 JST: decision recorded that long-term modernization target includes in-process parallel/OpenMP-capable TLTM execution through explicit context/workspace state.
- 2026-05-08 JST: added confirmed decisions and full modernization roadmap including code hygiene/sloppy artifact cleanup as a formal baseline-gated workstream.
- 2026-05-08 JST: corrected roadmap scope: five core algorithm audits are safety gates, not the center; full modernization is repo-wide and now includes cross-cutting infrastructure such as utils, RNG, config, I/O, build/test tooling, diagnostics, scripts, and workspace/state ownership.
- 2026-05-08 JST: completed pre-Stage3_4 planning artifacts and corrected stage order to characterization baseline -> core canonicalization -> official baseline freeze -> repo-wide modernization.
- 2026-05-08 JST: created M1 temporary characterization baseline from completed Stage3_4 128seed/100k p28 RG report and created M2 core canonicalization decision queue.
- 2026-05-08 JST: M2a decision recorded: `fb_norefine` is canonical p28 route; post-refine is deletion candidate.
- 2026-05-08 JST: M2a decision recorded: canonical long-term flow backend is ODEX-only; Radau/JFNK/final-resort rescue stack is deletion candidate.
- 2026-05-08 JST: M2a decision recorded: non-p28 quasi routes are legacy/quarantine first; deletion waits for staged 10k->50k->100k physical validation.
- 2026-05-08 JST: M2 execution policy recorded: non-ODEX cleanup is behavior-neutral quarantine/inventory only; ODEX-only gets staged 10k->50k->100k physical validation before legacy deletion.
- 2026-05-08 JST: Implemented ODEX-only source policy gates in `src/physics/solve_flow.f90`; Radau/final-resort acceptance disabled, legacy routines retained for quarantine and comparison.
- 2026-05-08 JST: Added retained-core implementation correctness audit gate for ODEX, simplified Newton, RATTLE, QN p28 loss, and HMC/Metropolis/RG before any ODEX-only validation jobs.
