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
- 2026-05-09 JST: Deleted inactive Radau/JFNK rescue implementation from `src/physics/solve_flow.f90`; retained solver-internal residual assist and compatibility rescue-stat fields.
- 2026-05-09 JST: Deleted tracked root-level stale Fortran artifacts and removed no-op `set_intode_strict_mode(...)` API/call sites after strict final-flow status gates made the flag obsolete.
- 2026-05-09 JST: Deleted stale backup config `data/parameters.stage3_2.bak` and refreshed persistent knowledge maps to the current active architecture.
- 2026-05-09 JST: Renamed ODE residual-assist internals from `final_resort` to `solver_assist` while preserving compatibility output/schema labels.
- 2026-05-09 JST: Downgraded the legacy RATTLE `x(2)` progress guard from an active proposal-failure gate to an opt-in state-progress diagnostic.
- 2026-05-09 JST: Renamed QN watchdog internals to solver-assist terminology and added `QN_SOLVER_ASSIST_BUDGET` with legacy env alias support.
- 2026-05-09 JST: Deleted legacy positional `parameters.dat` parsing and the unused `initial_x.dat` runtime compatibility path after user confirmation.
- 2026-05-10 JST: Centralized Stage1/Stage2 runtime env parser helpers in `runtime_env_mod` without changing env names/defaults/override semantics.
- 2026-05-10 JST: Removed remaining duplicated env-token lowercase helpers from `markovchain_mod` and `hmc_reversibility_checks`.
- 2026-05-10 JST: Reused shared int env parser for HMC diagnostic/probe limits and constraint failure-capture limits while preserving clamp/unlimited behavior.
- 2026-05-10 JST: Narrowed all active `param_mod` consumers to explicit `only:` imports as a legacy-global boundary cleanup.
- 2026-05-10 JST: Narrowed all active `utils` consumers to explicit `only:` imports as a shared-helper boundary cleanup.
- 2026-05-10 JST: Updated the model generator so generated `model_generated.f90` also uses explicit imports and repo-relative source headers.
- 2026-05-10 JST: Added `runbooks/M3_ARCHITECTURE_CONTRACT.md` to define wrapper/schema, typed config, explicit context/workspace, regression-gate, and stop-gate rules before broader architecture refactors.
- 2026-05-10 JST: Added `runbooks/M3_TEMPERING_PROTOCOL_AND_OUTPUT_SCHEMA_DESIGN.md` so output schema design is gated by a TLTM plus standard replica-exchange tempering protocol audit rather than current-output repackaging.
- 2026-05-10 JST: Added `runbooks/M3_V0_OUTPUT_INVENTORY_AND_PROTOCOL_AUDIT_PLAN.md` to inventory current v0 output fields/artifacts and define the parser-only/replay protocol audit sequence before v1 writer work.
- 2026-05-10 JST: Implemented parser-only TLTM protocol audit script and a source-level adjacent-swap kernel contract test.
- 2026-05-10 JST: Implemented opt-in Stage2 v1alpha sidecar manifest/protocol plus minimal diagnostics/observables package; next true design-decision node is unified-wrapper sweep order and measurement boundary.
- 2026-05-10 JST: User selected the common replica-exchange-style `local update -> swap -> measure/history/label trace` boundary and explicitly dropped old dataset timing compatibility; future datasets should be regenerated.
- 2026-05-08 JST: Added retained-core implementation correctness audit gate for ODEX, simplified Newton, RATTLE, QN p28 loss, and HMC/Metropolis/RG before any ODEX-only validation jobs.

## 2026-05-08 - M2 retained-core implementation audit
- Completed static source-level audit of retained ODEX, simplified Newton, RATTLE, QN p28 residual, and HMC/Metropolis/RG boundary.
- Wrote `runbooks/M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`.
- Validation remains blocked pending user discussion of ODEX signed work estimate, Newton/QN derivations, and full diagnostics/accounting design. The RATTLE progress guard decision has been implemented as diagnostic-only.
- 2026-05-08 JST: Clarified retained-core audit F1: `flowzr` is inverse flow via reversed RHS under nonnegative production flow time; signed `calculate_wk` is a latent negative-interval robustness issue, not proof of wrong current `flowzr`.
- 2026-05-08 JST: Checked GT-HMC simplified RATTLE equations; simplified Newton residual/update signs match Eqs. (3.37)-(3.44), pending deterministic replay and `del_z` normalization checks.
- 2026-05-08 JST: Completed reference-backed re-audit and added `M2_REFERENCE_BACKED_CORE_AUDIT.md`; source-first audit is superseded for signoff decisions.
- 2026-05-08 JST: User selected Hairer ODEX `IWORK(3)=3` (`2,4,6,8,12,16,24,32,...`) as canonical sequence; this has since been patched and covered by ODEX self-consistency checks.
- 2026-05-08 JST: Confirmed p28 QN as BTN/backflow rescue; sign convention is `xi1=-b`, `xi2=-a` (`a=-xi2`, `b=-xi1`).
- 2026-05-08 JST: Decided future p28 BTN code should use paper variables `xi1=b`, `xi2=a`; residual correction and initial guess RHS must both flip sign together.
