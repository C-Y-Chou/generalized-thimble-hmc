# Task Status: fortran_modernization

Updated: 2026-05-12 JST

## Objective
- Define the governing principles, workstreams, milestones, and verification rules for systematic TLTM Fortran modernization.
- Keep behavior preservation explicit: engineering changes must not silently change the underlying physics or accepted reference outputs.

## Current state
- Initial modernization governance set established.
- User-confirmed alias: "code refine" means this `fortran_modernization` task, not a separate workspace.
- Current position is now tracked by workstream matrix, not by treating M0-M6 as a linear completion ladder:
  - `runbooks/WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`
  - Position: reference-audited core + accepted M6 behavior baseline -> CV-011 route-B RNG streams implemented -> post-B RNG anchor added -> top-level TLTM run context selected and first HMC slice implemented -> full OpenMP/thread-safe productization -> broader modernization blocks.
- Foundation closure decisions recorded on 2026-05-12 JST:
  - `CV-007` is closed by endpoint-only ODEX product boundary;
  - `CV-001` is closed by `official_line_kernel_correctness_gate.py`;
  - `CV-006` is closed by `DFOLS_CLAIM_PROVENANCE_POLICY_V1`;
  - `CV-004` is closed as permanent F8/M4 behavior-preservation governance;
  - `CV-005` is closed by machine-checked script/evidence audit;
  - `CV-011` route-B RNG stream ownership and the first top-level HMC context slice are implemented. CV-011 remains open for full OpenMP/thread-safe productization: remaining behavior-bearing module state/workspaces, counters, diagnostics, policy state, and deterministic serial/reentrant tests.
- Modernization finish decisions recorded on 2026-05-12 JST:
  - `runbooks/MODERNIZATION_FINISH_DECISIONS_20260512.md`
  - Production redo is completely separated into `tltm_production_comparison`; modernization provides frozen commits/contracts but does not own redo queueing, readback, or final production-output promotion.
- Post-B RNG reference anchor added on 2026-05-12 JST:
  - `runbooks/POST_B_RNG_REFERENCE_ANCHOR_20260512.md`
  - `state/POST_B_RNG_REFERENCE_ANCHOR_V1.json`
  - `post_b_rng_reference_anchor.py` runs tiny Stage1/Stage2 twice and checks normalized hashes for `per_replica_rng_v1`.
- First non-RNG CV-011 workspace slice added on 2026-05-12 JST:
  - `runbooks/CV011_DECOMPOSE2_WORKSPACE_SLICE_20260512.md`
  - `hmc_kernels:decompose2` now supports explicit workspace ownership and the RATTLE core path stores that workspace inside `rattle_step_workspace_t`.
- QN linear workspace slice added on 2026-05-12 JST:
  - `runbooks/CV011_QN_LINEAR_WORKSPACE_SLICE_20260512.md`
  - `quasi_newton_linear_solver_mod` now supports optional `qn_linear_workspace_t` and no longer uses module SAVE scratch arrays.
- Newton workspace slice added on 2026-05-12 JST:
  - `runbooks/CV011_NEWTON_WORKSPACE_SLICE_20260512.md`
  - `hmc_constraints:solve_constraint_newton` now supports optional `newton_constraint_workspace_t` and the RATTLE core path owns that workspace explicitly.
- CV-011 remaining state decision point recorded on 2026-05-12 JST:
  - `runbooks/CV011_REMAINING_STATE_DECISION_POINT_20260512.md`
  - User selected top-level TLTM run context route A before wider flow/QN/diagnostics/model/config/profiling API migration.
- CV-011 top-level run context first slice added on 2026-05-12 JST:
  - `runbooks/CV011_TOP_LEVEL_RUN_CONTEXT_SLICE_20260512.md`
  - Stage1 and Stage2 now own per-replica/per-slot run contexts for HMC proposal, reverse-probe, and warmup workspace ownership.
- CV-011 Stage2 audit context slice added on 2026-05-12 JST:
  - `runbooks/CV011_STAGE2_AUDIT_CONTEXT_SLICE_20260512.md`
  - RG-reject and local-transition audit file state now lives in a Stage2-owned context rather than module-level SAVE state.
- Algorithm reference bundle is collected under `references/`, including TLTM HMC, simplified Newton/RATTLE/HMC, DFO-GN/DFO-LS, Hairer ODEX, and the user original quasi-Newton projection formulation.
- Low-level algorithm review set is complete and has already driven the first source canonicalization wave:
  - `runbooks/ODEX_FLOW_REVIEW_NOTES.md`
  - `runbooks/SIMPLIFIED_NEWTON_RATTLE_REVIEW_NOTES.md`
  - `runbooks/QUASI_NEWTON_PROJECTION_REVIEW_NOTES.md`
  - `runbooks/HMC_METROPOLIS_TLTM_REVIEW_NOTES.md`
  - `runbooks/BASELINE_VERIFICATION_MATRIX.md`
  - `runbooks/PLANNING_DISCUSSION_BRIEF.md`
- Current flow policy is ODEX primary integration with solver-internal ODE assist for NT/QN residual evaluation and strict final proposal/live-state flow.
- Current p28 route is Newton -> p28 QN BTN/backflow rescue residual solved by embedded official DFO-LS -> reverse gate -> Metropolis, without post-refine or non-p28 QN families.
- ODEX completeness is closed by explicit TLTM endpoint-only product boundary: dense output and a general-purpose Hairer ODEX library claim are non-goals, solver assist is default-off diagnostic-only pending later deletion, and broader ODEX claims require reopening CV-007.

## Current architecture understanding
- `solve_flow.f90` is flow mapping plus ODEX-like integration plus solver-internal residual-assist policy plus diagnostics.
- `hmc_integrator_core.f90` is the central proposal hub: Newton, canonical p28 quasi fallback, reverse gate, flow/Jacobian update, momentum projection, and solver statistics.
- `quasi_newton_solver.f90` now carries the retained p28 DFO-LS-style residual/solver machinery plus traces, solver-internal assist/watchdog accounting, and route counters; legacy DFO-GN/Broyden/global-continuation/post-refine source paths have been removed.
- DFO-LS replacement is now implemented as an embedded official `DFO-LS==1.6.5` backend through Python's C API. TLTM still owns the residual callback, residual gate, reverse gate, Metropolis logic, and failure-as-rejection semantics. The stable production preset is documented in `runbooks/OFFICIAL_DFOLS_PRESET_TUNING_POLICY.md`; `QN_SOLVER_BACKEND=internal` is retained only for controlled legacy comparison.
- `tltm_stage2_driver.f90` owns production orchestration and output/counter contracts used by Stage3_4 interpretation.
- `runtime_env_mod.f90` centralizes Stage1/Stage2 runtime environment parser helpers while preserving caller defaults and existing env names.

## State/information propagation refine queue - 2026-05-09 JST
- User clarified that the flagged `h==0` issue means Hamiltonian `H==0` when a proposal is rejected, not ODE step size.
- Added `runbooks/STATE_INFORMATION_PROPAGATION_REFACTOR.md` as the broader workflow item replacing the narrower error-handling framing.
- Future target: typed state/status propagation for ODE integration, residual evaluation, solver convergence, proposal construction, reverse-gate rejection, Metropolis rejection, and live-chain state update.
- Policy boundary: solver-internal ODE assist may help NT/QN residual evaluation, but strict final `flow(...)` must construct the actual proposal.
- Solver-assist 10k -> 50k -> 100k validation is complete and analyzed.
- Source-level state/status refactor should continue slice-by-slice; stop only for compatibility, output-schema, or physics-policy decisions.

## HMC unavailable-Hamiltonian sentinel patch - 2026-05-09 JST
- First source slice implemented: failed/unavailable HMC Hamiltonians now use IEEE quiet NaN instead of `0.0` sentinel values.
- Updated Hamiltonian conservation test to use `proposal_ok` plus finite-Hamiltonian checks.
- Updated warmup guard in `markovchain_mod.f90` to exit on unavailable/non-finite Hamiltonians rather than `H==0`.
- Local verification: `make -C build FC=gfortran LDFLAGS= ../bin/test_program` and `make -C build FC=gfortran LDFLAGS= test1` pass on macOS/gfortran.
- Local Stage2 smoke with `TLTM_STAGE2_CYCLES=2`, `TLTM_STAGE2_NUM_REPLICAS=2`, `TLTM_STAGE2_MAX_FLOW_TIME=0.1` still fails slot-1 initialization; the same smoke fails on clean `HEAD`, so this is not attributable to the sentinel patch.

## Proposal status surface patch - 2026-05-09 JST
- Next state/status audit finding: `proposal_failed` is still a compatibility boolean that conflates proposal construction failure, reverse-gate rejection, unavailable Hamiltonian, invalid `Delta H`, and ordinary Metropolis rejection context.
- Implemented a narrow status-surface patch without changing the acceptance rule, RNG draw point, or output schema:
  - `hmc_integrator_core.f90` now exposes optional RATTLE-step status codes.
  - `hmc.f90` maps step status to proposal status and exposes optional proposal status from `integrate_hmc_proposal`.
  - `markovchain_metropolis.f90` maps proposal status to optional transition status while preserving `accept` and `proposal_failed`.
  - `tests/test_hamiltonian_conservation.f90` now verifies successful proposals return `hmc_proposal_status_success`.
- Verification: after a clean rebuild, `make -C build FC=gfortran LDFLAGS= ../bin/test_program`, `make -C build FC=gfortran LDFLAGS= test1`, and `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2` pass/build locally.
- Build-system note: incremental build after public module API changes can leave stale objects because the local makefile lacks complete Fortran module dependency tracking. Use a clean rebuild for this patch; proper dependency/build tooling remains a modernization item.

## Fortran module dependency build patch - 2026-05-09 JST
- Promoted `build/makefile` into tracked source by narrowing `.gitignore` from ignoring all of `build/` to ignoring `build/*` except `build/makefile`.
- Added `scripts/fortran_module_deps.py`, a conservative scanner for Fortran `module`/`use` relationships.
- `build/makefile` now generates and includes `.obj/fortran_module_deps.mk`; consumer objects depend on provider objects, preventing stale-object ABI crashes after public module API changes.
- Incremental rebuild check: after `touch src/sampler/hmc.f90`, `make -C build FC=gfortran LDFLAGS= ../bin/test_program` rebuilt `hmc.o`, downstream sampler/driver consumers, and `tests/test_hamiltonian_conservation.o`.
- Verification: `make -C build clean && make -C build FC=gfortran LDFLAGS= ../bin/test_program`, `make -C build FC=gfortran LDFLAGS= test1`, and `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2` pass/build locally.

## State/information propagation audit - 2026-05-09 JST
- Added `runbooks/STATE_INFORMATION_PROPAGATION_AUDIT.md`.
- Audit result: live-chain state update on reject appears safe, but failed/unavailable Hamiltonian is still encoded as `0.0` in `hmc.f90`, `markovchain_mod.f90`, and `tests/test_hamiltonian_conservation.f90`.
- First proposed code patch before broader typed-status redesign: replace `H=0` failure sentinels with explicit proposal status/non-finite unavailable Hamiltonian handling while preserving Metropolis physics.

## Next action
Current source state has passed the Radau/JFNK deletion, non-p28 QN deletion, post-refine deletion, ODE/QN solver-assist naming, RATTLE progress-diagnostic, and state/status surface slices.

Current sequencing decision:

- M6 is the active reference-baseline/product-readiness gate, not completion of all modernization.
- Remaining modernization blocks are tracked in `WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`.
- User decision, 2026-05-10 JST: continue modernization through M6 before building/registering modernization reference packages.
- Modernization reference-dataset construction/registration is now gated by M3 protocol/schema completion, M4 guardrails, M5 repo-wide refactor decisions, and M6 product-readiness/provenance docs.
- Temporary smoke runs remain allowed for development; they are not final datasets and are not sufficient modernization reference packages.

Stop-for-decision rule:

- Continue without routine approval for behavior-preserving hygiene, audit/readback/test additions, parser/reporting improvements that preserve existing fields, already-confirmed M3 -> M6 work, and clear status/sentinel/state-propagation bug fixes.
- Stop only when there are multiple reasonable paths with no clear winner and the choice affects physics semantics, data interpretation, RNG/seed streams, public schema meaning/removal/renaming, wrapper/product interface, production workflow deletion, or future modernization reference-package provenance.

Latest source-level compatibility decision:

- User confirmed deletion of legacy positional `parameters.dat` parsing and the unused `initial_x.dat` compatibility path.
- `src/config/param_mod.f90` now requires key-value `parameters.dat` and fails fast on positional input.
- Unused initial-state file helpers were removed from active source/docs; runtime initialization stays in sampler/driver codepaths.

Latest behavior-neutral infrastructure cleanup:

- Stage1/Stage2 duplicated runtime env parser helpers were moved into `src/config/runtime_env_mod.f90`.
- Parser behavior is unchanged: caller defaults are preserved for missing/invalid env values; valid int/real/logical/list env values still override.
- `build/makefile` now includes the new config module before `param_mod`.
- Verification passed on 2026-05-10 JST: `git diff --check`, Stage1/Stage2 executable build, `test_odex_solver`, `test1`, tiny Stage1/Stage2 smokes, `TLTM_STAGE*_FLOW_TIME_LADDER` list-parser smokes, and invalid logical default-preservation smoke.
- Follow-up cleanup removed duplicated ASCII-lower helpers from `markovchain_mod.f90` and `hmc_reversibility_checks.f90`; both now use the shared `runtime_env_mod` helper for env-token normalization.
- Follow-up cleanup moved HMC diagnostic/probe integer limits and constraint failure-capture integer limits onto the shared parser, preserving the existing clamp/unlimited semantics.
- `param_mod` consumers now use explicit `only:` imports; no active source/test file has a bare `use param_mod`.
- `utils` consumers now use explicit `only:` imports; no active source/test file has a bare `use utils`.
- Active source/test imports are explicit; `model_generated.f90` now receives its `model_tape_ad` `only:` list from `scripts/generate_model_generated.py`.
- Generated model headers now use repo-relative source paths instead of machine-local absolute paths.
- External DFO-LS comparison bridge added:
  - `src/apps/evaluate_btn_residual_case.f90` evaluates retained BTN residuals from the legacy failure-capture file shape.
  - `scripts/run_external_dfols_btn_compare.py` calls official `DFO-LS==1.6.5` through a residual-only callback.
  - `requirements/external-dfols.txt` pins the tested package.
  - Local dtype probe confirmed objective inputs and result arrays are `np.float64`; the bridge refuses non-double residual plumbing.
  - Opt-in `QN_ATTEMPT_CAPTURE_DIR` now records representative QN-entry attempts with prefix `qn_attempt`; when unset, production solver behavior remains unchanged.
  - A local 20-attempt probe found official DFO-LS preserves double precision but package success flags are not enough: TLTM must apply its own residual gate. Best tested external setting so far was `maxfun=112`, `model.abs_tol=1e-26`, `rhobeg=0.25`, giving 17/20 residuals `<=1e-6` and 13/20 `<=1e-12`.
  - Follow-up tuning found an official-package-only candidate: `objfun_has_noise=True`, `rhobeg=0.05`, `rhoend=1e-16`, `model.abs_tol=1e-30`, `model.rel_tol=0`, `maxfun=250`, with TLTM residual gate `<=1e-13`.
  - On a 69-attempt representative probe, the candidate solved 61/61 in-house-converged attempts to residual `<=1e-13` and solved 5/8 in-house-nonconverged attempts; the remaining 3 failures were already nonconverged in the in-house solver.
  - Replacement-gate cost proxy: in-house-converged attempts have in-house residual-call median/mean/p90/max `46/50.6/72/92`; official candidate `nf` is `40/65.4/127/250`.
  - Final gate status: algorithmically viable as a backend candidate, but direct Python subprocess production replacement is rejected. The GPL-compatible distribution decision is resolved in favor of GPL-3.0-or-later; full replacement remains held pending runtime architecture and behavior-preservation gates.
  - License/toolchain policy added: root `LICENSE` carries GPL v3 text; root `LICENSE_POLICY.md` states GPL-3.0-or-later; root `THIRD_PARTY_NOTICES.md` tracks DFO-LS and Tapenade; Tapenade is an external MIT-licensed code-generation tool whose generated-source provenance must be recorded.
  - PBS validation scaffold added:
    - `tasks/config/official_dfols_backend_gate_1seed_500cycle_t035.json`
    - `tasks/pbs/official_dfols_backend_gate_20260511.pbs`
    - The gate generates representative QN-entry attempts from a 1-seed, 500-cycle `fb_norefine` t=0.35 Stage3-style smoke, replays them through official `DFO-LS==1.6.5` with the tuned preset, and fails if float64 plumbing breaks or any in-house-converged attempt regresses under the official residual gate.
  - PBS gate readback:
    - First gate job failed because the capture path was relative while Stage2 ran from `build/`; the scaffold was fixed to use absolute output/log/capture paths.
    - The fixed gate captured 77 QN-entry attempts and replayed all rows through official `DFO-LS==1.6.5`.
    - Old preset `rhobeg=0.05`, `npt=default`, `maxfun=250` failed the safety gate because one in-house-converged attempt regressed.
    - Revised official-only preset `npt=4`, `rhobeg=0.018`, `objfun_has_noise=True`, `rhoend=1e-16`, `model.abs_tol=1e-30`, `model.rel_tol=0`, `maxfun=250` passed the 77-attempt safety gate: 71/77 residual successes, 63/63 in-house-converged attempts preserved, 0/77 float64 failures.
    - Updated-scaffold rerun `14728.anode01` / `official_dfols_backend_gate_20260511_1543cb4` completed with PBS `Exit_status=0` and the same safety-gate summary.
  - This remains offline backend-comparison tooling and does not alter the production HMC/QN path. Failure-only replay is not considered sufficient evidence for solver replacement.

Next expected modernization area after this slice:

- M3 completion: propagate Stage2 v1alpha sidecar awareness into Stage3 orchestration and sidecar-aware protocol audit/readback before moving to M4-M6.
- `runbooks/M3_ARCHITECTURE_CONTRACT.md` now records the next-phase rules before public schema, wrapper, config, or module-state refactors begin.
- `runbooks/M3_TEMPERING_PROTOCOL_AND_OUTPUT_SCHEMA_DESIGN.md` now records that schema design must first verify the TLTM tempering protocol against both TLTM-specific rules and standard replica-exchange practice.
- `runbooks/M3_V0_OUTPUT_INVENTORY_AND_PROTOCOL_AUDIT_PLAN.md` now records the current v0 output inventory and the parser/replay audit sequence needed before v1 writer work.
- `runbooks/M3_TO_M6_BEFORE_REFERENCE_DATASET_PLAN.md` now records that modernization reference-dataset construction/registration waits until after the M6 gate.
- `scripts/audit_tltm_tempering_protocol.py` now provides a parser-only Stage2/label-trace/optional-Stage3 protocol audit without changing production output.
- `tests/test_tltm_swap_kernel_contract.f90` now checks the source-level TLTM adjacent-swap energy/probability contract and invalid-current-energy rejection behavior.
- Stage2 now has opt-in v1alpha sidecars:
  - `TLTM_STAGE2_V1_OUTPUT_DIR` writes `manifest.json`, `protocol.json`, diagnostics CSVs, and per-slot phase summary CSV.
  - `TLTM_STAGE2_V1_MANIFEST_FILE` and `TLTM_STAGE2_V1_PROTOCOL_FILE` allow individual sidecar file output.
  - Default output behavior is unchanged when these env vars are absent.
- The protocol audit script now accepts optional `--manifest` and `--protocol` sidecars and cross-checks schema, declared timing, flow ladder, controls, and v1 diagnostics row counts.
- User decision recorded 2026-05-10 JST: old dataset timing compatibility is not required. Stage2/TLTM should use the common replica-exchange habit `local update -> swap -> measure/history/label trace`; Stage3_4 production outputs and modernization reference datasets are separate outputs under that convention.

Current protocol state:

- Stage2 cycle order has been migrated to post-swap measurement/history/label trace.
- `swap -> local -> measure` remains a valid paper-aligned alternative but is not the selected convention for regenerated production/reference outputs.
- Modernization reference-dataset construction/registration should not start now; it starts only after the M6 gate and an explicit user instruction. Stage3_4 production remains separate.
- Current M3 code slice complete: Stage3 multiseed orchestration can opt into Stage2 v1alpha sidecars, record sidecar/audit paths in per-seed CSV rows, run sidecar-aware protocol audit/readback, and preserve those metadata columns through chunk merge.
- Current M4 entry slice complete: `scripts/run_m4_guardrails.py` and `make -C build modernization_guardrails` collect the local compile/build/audit/Stage3 sidecar smoke/merge checks into a repeatable guardrail runner.
- Verification passed on 2026-05-10 JST through direct script invocation and the make target, including Python compile, `git diff --check`, ODEX/swap tests, Stage3 sidecar dry-run, Stage2 protocol audit smoke, sidecar-on/off tiny Stage3 smokes, and chunk merge preservation.
- M5 source-backed inventory is now available in `state/M5_STATE_CONFIG_OWNERSHIP_INVENTORY.tsv`, with summary and interpretation in `runbooks/M5_STATE_CONFIG_OWNERSHIP_INVENTORY_SUMMARY.md` and `runbooks/M5_STATE_CONFIG_OWNERSHIP_PLAN.md`.
- User chose Lane A: config/env/provenance ownership.
- First Lane A source slice complete: Stage1/Stage2 string env reads now use `runtime_env_mod:read_string_env`; env-read inventory dropped from 52 to 36 rows; M4 guardrails passed.
- Second Lane A source slice complete: `evaluate_expectations` env reads now use `runtime_env_mod:read_string_env`; env-read inventory dropped from 36 to 24 rows; M4 guardrails passed.
- Third Lane A source slice complete: HMC/QN policy loaders, Markov-chain random-start controls, perf profiling, reversibility probe config, and `generate_markov_chain` seed selection now use `runtime_env_mod:read_string_env`; env-read inventory dropped from 24 to 5 rows; M4 guardrails passed.
- Final direct-env consolidation slice complete: the test-local `HMC_SKIP_PLOT` read now uses `runtime_env_mod:read_string_env`; env-read inventory dropped from 5 to 4 rows; M4 guardrails passed.
- All direct `get_environment_variable` calls are now centralized in `runtime_env_mod`.
- M4 guardrails now include a source-level check that blocks direct env reads outside `runtime_env_mod`.
- `runbooks/M5_PRE_M6_GATE_ASSESSMENT.md` records the M5 gate result: proceed to M6 product-readiness work while deferring RNG ownership, large module `save` workspace migration, model/tape cache ownership, public schema deletion/renaming, and full `param_mod` global replacement until stronger baselines or explicit wrapper/schema decisions exist.
- M6 product-readiness docs are now started:
  - `runbooks/M6_REFERENCE_DATASET_PRODUCT_READINESS_PLAN.md`
  - `runbooks/M6_REFERENCE_DATASET_CHECKLIST.md`
  - `runbooks/M6_PROVENANCE_READBACK_CHECKLIST.md`
- User clarified on 2026-05-10 JST that this modernization workstream is separate from the Stage3_4 `nofb` vs `withfb` production-comparison workstream.
- `runbooks/PARALLEL_WORKSTREAM_BOUNDARY_AND_REFERENCE_DATASET_POLICY.md` now records that `tltm_production_comparison` owns production completion, scheduling, output cleanup, and possible workspace reorganization. Legacy alias: `stage3_4`.
- Modernization owns the future behavior-preservation reference dataset/package contract, using Stage3_4 as workflow-design context rather than a required result source.
- `runbooks/M6_REFERENCE_DATASET_DESIGN_SPEC.md` now defines the reference dataset/package shape, Stage3_4-context alignment, manifest fields, artifact pointers, and acceptance criteria.
- `runbooks/M6_REFERENCE_DATASET_READBACK_PLAN.md` now defines manual/future-automated readback checks and acceptance states.
- `runbooks/M6_REFERENCE_DATASET_GENERATION_AND_COVERAGE_PLAN.md` now defines R0-R4 reference levels, protected refactor classes, required outputs, pre-generation checklist, and stop-for-decision points.
- `runbooks/M6_REFERENCE_DATASET_EXECUTION_PLAN_20260510.md` now records the concrete R1-R4 config/PBS/chunk/queue plan.
- `runbooks/M6_TO_CODE_MODERNIZATION_ENTRY_GATE.md` now records the boundary before future source-code refactors resume.
- `state/M6_REFERENCE_PACKAGES.tsv` now exists as the reference-package registry template.
- User explicitly started R1-R4 reference generation planning on 2026-05-10 JST.
- Configs and PBS scripts for R1-R4 are prepared, with the submit launcher now delegated to a manual-aware dynamic queue planner.
- `runbooks/M6_DYNAMIC_QUEUE_POLICY_20260510.md` records the iTHEMS cluster02 manual-derived queue rules, GPU/C17 exclusions, and no-`qmove` repair policy.
- `runbooks/CLUSTER02_SCHEDULING_AGENT.md`, `state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`, and `state/CLUSTER02_QUEUE_OBSERVATIONS.tsv` now define a persistent cluster02 scheduling agent for long-term queue/work-splitting optimization.
- The scheduler agent utility `tasks/scripts/cluster02_scheduler_agent.py` can show the persistent policy, capture live `qstat -Qf` snapshots, summarize jobs, and append new queue observations.
- The original static wave exposed scheduling hazards: GPU queues were unsuitable for CPU chunks, `C17/C17-LONG` failed for 8-core TLTM production-shape chunks, and qmove-created jobs could finish without usable execution/logs.
- Current active cluster jobs are pinned to commit `a1028ad`; do not fast-forward that active worktree while they run.
- Repo entry docs now point to M6 guardrails/checklists and no longer describe single-chain output as the Stage3_4 production or modernization reference-package path.
- Master/M3-to-M6 planning docs now mark M3/M4/M5 as completed or explicitly deferred where appropriate, with M6 review as the next gate before modernization reference-dataset construction/registration.
- M6 queue probe/optimization is complete:
  - Production-shape probes passed on `C8`, `C12`, and `C12-LONG`.
  - R3 queued replacement `14657` and merge `14658` were superseded by running chunk `14669` and held merge `14670`.
  - R4 queued replacements `14645`/`14649`/`14660`/`14662` and merge `14663` were superseded by running chunks `14671`/`14672`/`14673`/`14674` and held merge `14675`.
  - The probe-first decision and replacement map are recorded in `runbooks/M6_QUEUE_PROBE_AND_RESUBMISSION_20260510.md`.
- M6 reference dataset readback is complete and accepted:
  - R1-R4 have package manifests, aggregate comparisons, registry rows, expected per-method row counts, and protocol audit bad=0.
  - R4 final replacement `14674` and merge `14675` completed with `Exit_status=0`.
  - Accepted package rows are recorded in `state/M6_REFERENCE_PACKAGES.tsv`.
  - Readback report: `runbooks/M6_REFERENCE_DATASET_READBACK_20260510.md`.
  - No active PBS jobs remain after the latest refresh.

## After confirmation
- Behavior-changing source modernization remains gated by the affected rows in `BASELINE_VERIFICATION_MATRIX.md` plus the M6 code-entry gate.
- Already-approved cleanup slices may proceed only after the code-entry gate is satisfied or the user explicitly approves a narrower baseline.
- Public input compatibility, output schema, wrapper API, and production workflow deprecations remain explicit user-decision gates.

## Quasi route decision - 2026-05-08 JST
- Production-canonical quasi route: current p28 path (`QN_S1_PROBE_MAX_ITER=28`) using DFO-LS BTN/backflow rescue on `evaluate_constraint_residual` after Newton failure.
- Legacy non-p28 quasi, DFO-GN paper, Broyden/line-search, global continuation/restart, and post-refine source paths have been removed after validation and user approval.

## Wrapper direction decision - 2026-05-08 JST
- Current Stage2/Stage3/Stage3_4 workflow is transitional scaffolding.
- After TLTM construction/Stage3_4 judgment, modernization should converge to a unified TLTM wrapper/runner with versioned output schema.
- Short-term output contracts remain frozen for Stage3_4 compatibility.

## Baseline source decision - 2026-05-08 JST
- Official modernization baselines will be regenerated after Stage3_4/TLTM judgment completes.
- Existing `output/tests` artifacts remain historical/reference evidence only.

## Reverse gate decision - 2026-05-08 JST
- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It must be preserved and baselined during modernization.

## Flow backend direction decision - revised 2026-05-09 JST
- Pure ODEX-only is retained as a comparison artifact, not the final production policy.
- Current canonical candidate is ODEX primary integration plus solver-internal ODE assist for NT/QN residual evaluation plus strict final proposal flow.
- Radau/JFNK rescue source has been deleted; final-proposal rescue acceptance remains forbidden by strict final-flow gates.
- Solver-internal assist must be kept or explicitly redesigned before any further flow-policy cleanup.

## Thread-safety decision - 2026-05-08 JST
- Long-term modernization target is in-process parallel/OpenMP-capable TLTM execution.
- Hidden module `save` workspaces/counters/RNG/traces/policies should eventually become explicit context/workspace state.
- No source refactor before Stage3_4/TLTM judgment and fresh baselines.

## Confirmed roadmap update - 2026-05-08 JST
- Added `runbooks/CONFIRMED_DECISIONS_AND_NEXT_PLAN.md`.
- Modernization workstreams now include algorithm mapping, behavior baselines, code hygiene cleanup, architecture/API redesign, legacy deletion, reentrancy/OpenMP, and product readiness.
- Plan is structurally complete at planning level; remaining items are future decision gates after Stage3_4/TLTM judgment.

## Scope correction - 2026-05-08 JST
- Five core algorithm audits are safety gates, not the center of the full modernization roadmap.
- Full modernization is repo-wide and includes utils, RNG, config, I/O/output schema, build/test tooling, scripts/PBS orchestration, diagnostics/logging, memory/workspace ownership, and documentation.
- `CONFIRMED_DECISIONS_AND_NEXT_PLAN.md` updated with cross-cutting infrastructure modernization scope.

## Pre-Stage3_4 planning completion - 2026-05-08 JST
- Added `PRE_STAGE3_4_COMPLETION_PLAN.md`, `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`, `CODE_HYGIENE_AUDIT.md`, `LEGACY_DELETION_CANDIDATES.md`, and `PLANNING_INDEX.md`.
- Roadmap sequence corrected: Stage3_4/TLTM judgment -> temporary characterization baseline -> core numerical canonicalization -> official canonical baseline freeze -> repo-wide modernization.
- M0 planning artifacts are initially complete; no source edits or jobs were performed.

## M1 characterization update - 2026-05-08 JST
- Stage3_4 128seed/100k p28 RG report is available and characterized.
- Added `runbooks/M1_TEMPORARY_CHARACTERIZATION_BASELINE.md`.
- Added `runbooks/M2_CORE_CANONICALIZATION_QUEUE.md`.
- Added `state/M1_CHARACTERIZATION_METRICS_20260508.tsv`.
- Key primary characterization: `fb_norefine` reduces unresolved failures from 946129 to 224439 versus `no_fb`, increases RG rejects from 136997 to 200447, and increases mean runtime by about 1680 seconds per seed.
- This is temporary characterization, not official canonical baseline freeze.

## Canonical p28 route decision - 2026-05-08
- User confirmed `fb_norefine` as the canonical p28 production route.
- Canonical route: Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis.
- Post-refine has been removed from active source and should not be part of the final canonical p28 route unless explicitly re-promoted later.

## Canonical flow backend decision - revised 2026-05-09
- User accepted the solver-assist validation observation: pure ODEX-only should not be the final policy because it introduces avoidable solver robustness loss.
- Current canonical candidate: ODEX primary integration, solver-internal ODE assist for NT/QN residual evaluation, strict final proposal flow.
- Radau rescue, fixed/chunked Radau rescue, and JFNK support paths have been removed from active source.
- Any remaining flow-policy refactor must preserve explicit residual-assist semantics and prove final proposal strictness.

## Non-p28 quasi route staging decision - 2026-05-08
- User confirmed non-p28 quasi routes should be marked legacy first, not immediately deleted.
- Deletion requires staged physical validation: 10k -> 50k -> 100k checks must show no major physical-observable problem for the canonical p28 path.
- That validation gate has passed for the QN-clean canonical route; DFO-GN paper, Broyden/line-search, global continuation/restart, and known non-p28 implementation paths have been removed from active source.

## M2 execution policy - historical 2026-05-08 JST
- Non-flow cleanup before the first flow-policy transition was limited to behavior-neutral canonical route documentation, legacy/quarantine labeling, dependency inventory, and test planning.
- Pure ODEX-only was originally the first numerical canonicalization step expected to possibly change trajectories; it was later retained as a comparison artifact after solver-assist validation showed avoidable robustness loss.
- Added `runbooks/M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md` and `runbooks/ODEX_ONLY_STAGED_VALIDATION_PLAN.md`.
- Historical note: no Fortran source edits were performed at the time this policy was recorded.

## ODEX-only source policy change - 2026-05-08 JST
- Updated `src/physics/solve_flow.f90` so the production `intode` failure path no longer enables Radau rescue or final-resort acceptance.
- Historical note: legacy Radau/JFNK routines were initially kept in quarantine, then deleted on 2026-05-09 after solver-assist validation and strict final-flow gates.
- No production job was submitted for this change.

## Retained-core correctness audit correction - 2026-05-08 JST
- User identified a critical gap: prior audits emphasized which legacy/rescue paths to disable, but did not yet prove that the retained five core numerical implementations are correct.
- Added `runbooks/M2_CORE_NUMERICAL_IMPLEMENTATION_AUDIT_PLAN.md`.
- Historical note: ODEX-only 10k -> 50k -> 100k validation was blocked until retained ODEX, simplified Newton, RATTLE, QN p28 loss, and HMC/Metropolis/RG boundary code were accepted for staged validation.
- No production job was submitted for this correction.

## M2 retained-core audit completion - 2026-05-08 JST
- Added `runbooks/M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`.
- Static source-level retained-core audit is complete enough for user discussion.
- Historical note: ODEX-only staged validation was blocked until the identified bug candidates and derivation/signoff items were resolved.
- Key blockers/signoff items: inverse-flow semantics are clarified as reversed RHS under nonnegative production flow time; remaining items are ODEX signed-interval robustness, simplified Newton residual/update now matched to GT-HMC but still needing replay/normalization tests, QN p28 residual signoff against the original formulation, and full typed diagnostics/accounting redesign. The `x(2)` RATTLE progress sentinel has been downgraded to diagnostics.
- No production job was submitted for this audit.

## Inverse-flow clarification - 2026-05-08 JST
- User confirmed `flowzr` is the inverse flow of `flow`.
- Audit wording was corrected: current `flowzr` reverses the RHS with nonnegative production flow time, so signed `calculate_wk` is not evidence of wrong current inverse-flow behavior.
- `calculate_wk` remains a latent/general ODEX robustness issue if negative integration intervals are ever supported.

## Simplified Newton GT-HMC mapping - 2026-05-08 JST
- Checked GT-HMC simplified RATTLE equations from `2311.10663v4.pdf`, especially Eqs. (3.37)-(3.44).
- Code residual `B = z + del_z - ld - flowz(xt+u)` matches the paper's `B = z + Delta z - lambda - znew` when `del_z=Delta z` and `ld=lambda`.
- `solve_projected_step` matches the paper decomposition `B = E B0,v + Bn`, with `Delta u = B0,v` and `Delta lambda = Bn`.
- Remaining checks are deterministic residual replay, `del_z`/`partial V` normalization, and ensuring the Jacobian is the fixed base Jacobian required by simplified Newton.

## Reference-backed retained-core re-audit - 2026-05-08 JST
- Added `runbooks/M2_REFERENCE_BACKED_CORE_AUDIT.md`.
- The earlier retained-core audit is now explicitly marked as a source-level risk scan, not final reference-backed signoff.
- Key correction: simplified Newton signs and `Delta z` normalization match GT-HMC/TLTM for unit mass.
- Key correction: active p28 QN residual is BTN/backflow rescue after standard Newton failure, not standard `(u,lambda)` residual.
- ODEX sequence decision: use Hairer ODEX `IWORK(3)=3` (`2,4,6,8,12,16,24,32,...`); implementation and ODEX self-consistency checks have since been completed.
- Historical note: ODEX-only long validation was blocked pending these decisions and deterministic replay tests.

## ODEX sequence decision - 2026-05-08 JST
- User selected Hairer ODEX `IWORK(3)=3` as the canonical modernization sequence.
- Target sequence: `2,4,6,8,12,16,24,32,...`.
- Historical code sequence `2,4,6,12,18,36,...` is now legacy.
- Implementation updated `build_nsteps` and `calculate_ak` together, cleaned signed-interval/work-estimate robustness in the same patch, and added ODE solver self-consistency tests.
- Later cleanup deleted Radau/JFNK rescue source; solver-internal assist remains explicit and final proposal flow remains strict.

## QN p28 BTN sign convention - 2026-05-08 JST
- User confirmed p28 should be treated as BTN/backflow rescue after standard Newton failure.
- Historical sign convention before the source cleanup had `xi1=-b`, `xi2=-a`; modernization target is paper variables `xi1=b`, `xi2=a`.
- Source cleanup is now implemented: correction uses `-J*(xi2+i*xi1)`, and `initial_guess_from_jacobian` solves `J dz=+del_z`.
- Older planning text saying p28 is a standard `(u,lambda)` residual is superseded by the reference-backed audit.

## QN p28 paper-variable decision - 2026-05-08 JST
- User requested BTN variables follow the paper directly.
- Implemented target: `xi1=b`, `xi2=a`.
- Implemented residual correction: `residual_jlc = -J*(xi2 + i*xi1)`.
- Implemented initial guess: solve `J dz = +del_z`, then `xi1=Im(dz)`, `xi2=Re(dz)`.
- `Jl`/recovery continue treating `Jl` as the actual correction added to `z+del_z`; no extra recovery sign flip is applied.
- Historical note: optional post-refine seed mapping was previously updated to use `ld0=b_qn` under paper variables; the post-refine route has since been removed and canonical p28 remains no-refine.

## BTN validation policy - 2026-05-08 JST
- User decided not to require old-convention/new-convention regression equivalence for BTN variable cleanup.
- Required validation is the BTN residual contract itself: after convergence, build `ztrial = z + del_z + Jl`, verify `Imag(flowzr(ztrial))` is small, and verify the second residual block `a` is small.
- `Jl`/recovery should be judged by whether this reconstructed `ztrial` satisfies the inverse-flow manifold condition, not by matching a previous coordinate convention.

## State representation / RATTLE progress decision - 2026-05-08 JST
- User identified that `state_has_progress` cannot be repaired cleanly as a single-line RATTLE fix because the whole codebase encodes `x(1)` as flow time and `x(2:)` as physical seed/state.
- Current `x(2)`-only progress guard is therefore a state-layout symptom and should be marked legacy/diagnostic, not promoted as a publishable algorithmic criterion.
- Short-term proposal validity should rely on solver convergence, constraint residual contract, reverse gate, and Metropolis rejection boundary.
- Long-term modernization should introduce typed state/workspace APIs separating `flow_time` from physical coordinates, then migrate kernels away from implicit positional indexing.

## Failure-as-rejection MCMC policy - 2026-05-08 JST
- User decided failure-as-rejection is the project policy and can be a valid MCMC transition boundary.
- Conditions to preserve: failed proposal/integration/projection/RG paths set `accept=.false.` or `proposal_ok=.false.`, live chain state is updated only when `accepted=.true.`, and successful proposals retain the required constraint/reverse-gate checks before Metropolis acceptance.
- Failed proposal output buffers may contain partial/intermediate values; this is acceptable only because callers must not commit them to live state on rejection.
- Publishable documentation should phrase failure as a stay-put event in the marginal chain, replacing the paper's momentum-flip/replacement fallback at the implementation boundary.

## Reverse gate proposal-boundary decision - 2026-05-08 JST
- User confirmed reverse gate is part of the proposal definition, not a debug-only diagnostic.
- Reverse-gate failure is handled as proposal failure and therefore as failure-as-rejection/stay-put in the marginal chain.
- Accepted proposals must satisfy the reverse-gate contract; rejected/RG-failed proposals must not update live chain state.

## Diagnostics/counters modernization decision - 2026-05-08 JST
- User confirmed diagnostic accounting must be repaired, but not as a narrow reverse-gate replay patch.
- The current count/capture/switch design is patchwork across ODE, QN, RATTLE, reverse gate, probes, rescue/failure paths, and Stage2 output contracts.
- Future modernization should introduce a typed diagnostics/accounting context that separates forward proposal work, reverse-gate replay, probes/debug, rescue attempts, failed proposal work, accepted-proposal counters, and output-schema reporting.
- Until the redesign, benchmark/validation reports must state whether counters include replay/probe/failure work.

## ODEX canonicalization scope decision - 2026-05-08 JST
- User selected synchronous cleanup for ODEX canonicalization: Hairer `IWORK(3)=3` sequence, matching `calculate_ak`, and signed-interval/work-estimate robustness should be handled together.
- Pre-long-validation test target is ODE solver self-consistency, not old/new trajectory equality: analytic ODE convergence/order sanity, step subdivision consistency, inverse/round-trip checks where applicable, and failure classification sanity.
- Superseded cleanup target: Radau/JFNK legacy source has since been deleted; solver-internal residual assist remains explicit and final proposal flow remains strict.

## ODEX canonicalization implementation - 2026-05-08 JST
- Implemented Hairer ODEX `IWORK(3)=3` step sequence in `src/physics/solve_flow.f90`: `2,4,6,8,12,16,24,32,...`.
- `build_nsteps` and `calculate_ak` now share `odex_iwork3_nstep`, so the extrapolation sequence and work-estimate cost model cannot silently diverge.
- `calculate_wk` now uses `abs(h)` for the positive work measure and guards non-finite/tiny candidate steps; `calculate_hk` remains signed so integration direction is unchanged.
- Local checks passed: `git diff --check`; build of `../bin/scan_flow_vs_flowz` and `../bin/scan_flowzr_stability`; `flowz`/`flow` 21-point scan with max `|delta z| = 5.00e-16`; `flowzr` signed roundtrip 81/81 with max roundtrip `4.42e-15`; 2-cycle local `test_tltm_stage2` smoke.
- No production job was submitted from this local preflight. The later staged ODEX-only validation completed and is retained as a comparison artifact.

## ODEX solver-level analytic check - 2026-05-08 JST
- Added `tests/test_odex_solver.f90` plus `scripts/run_odex_solver_check.sh` as the preferred pre-tolerance-tuning ODE solver test.
- The test calls `intode` directly with module-level RHS callbacks to avoid GNU Fortran internal-procedure trampoline issues under `-Wl,-z,noexecstack`.
- Coverage: scalar exponential forward/backward integration, harmonic oscillator forward/backward integration, full-step vs two-half-step consistency for both systems, and zero fallback attempts/failures.
- Local run passed at `abs_tol=rel_tol=3.0e-14`: max observed analytic/split errors were `5.33e-15` or smaller for exponential/backward checks, `7.77e-16` or smaller for oscillator checks, and fallback attempts/failures were 0.

## ODEX TLTM-wrapper preflight and 10k protocol - 2026-05-08 JST
- Added `scripts/run_odex_flow_wrapper_check.sh` for TLTM-specific flow wrapper checks using existing `scan_flow_vs_flowz` and `scan_flowzr_stability` apps.
- Local wrapper check passed for flow times `0.1` and `0.3`: `flowz/flow` success 21/21 for both, `flowzr` roundtrip success 81/81 for both, fallback attempts/failures 0/0.
- Observed wrapper maxima: `max|flowz-flow| = 5.00e-16` at t=0.1 and `1.31e-13` at t=0.3; max roundtrip errors `4.42e-15` at t=0.1 and `1.39e-14` at t=0.3.
- Added `runbooks/ODEX_10K_VALIDATION_PROTOCOL.md`; no production job was submitted.

## Current discussion scope - 2026-05-08 JST
- User narrowed the active discussion scope back to the five retained core numerical blocks.
- Typed state API redesign, diagnostics context redesign, repo-wide module/API cleanup, utilities/RNG/I/O/output-schema modernization, and broader productization remain recorded as future modernization blocks, but should not drive the immediate discussion sequence.

## QN invalid-evaluation handling - 2026-05-09 JST
- Implemented QN/DFO failure signaling cleanup in `src/sampler/quasi_newton_solver.f90`: invalid constraint evaluations now return `ierr=.true.` with neutral `fq=0`/`Jl=0`, rather than artificial `fq=1e10`.
- Initial evaluation retry seeds now use `x=0`, matching the user decision that failed trust-region attempts should not poison later retries.
- This is an error-handling/code-design change, not a physics-model change; failed solver attempts remain proposal failures/rejections unless a later valid trial converges and passes reverse gate/Metropolis.
- The pending ODEX scale-up jobs were stopped because they predated this QN change and must be regenerated after the new QN handling is validated.

## QN error-handling 10k validation - 2026-05-09 JST
- Dedicated validation branch/worktree: `codex/qn-error-handling-validation` at commit `7b2971c`.
- Initial validation job completed the 10 seed x 10k stage2 trajectories but failed during final evaluation because the PBS script had built only `run_tltm_stage2`, not `evaluate_expectations`.
- Workflow was fixed so future validation PBS builds both required binaries; an evaluation-only recovery wrapper was added to reuse completed stage2 outputs without rerunning trajectories.
- Recovery PBS job `14323.anode01` completed successfully with `Exit_status=0`.
- Artifacts: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/tests/qn_error_handling/20260509_10seed_10k_fb_norefine_ct1e13_qn1e13/`.
- Aggregate result: `mean Re<O>=-0.0386029170`, `mean Im<O>=0.0183377376`, `Zmean Re=-0.491730824`, `Zmean Im=0.576115891`, unresolved failures `2521`, projection failures mean `408.5`, reverse-gate rejects `1564`, pair0 accept rate `0.44008`.
- This is the first 10k check after the QN invalid-evaluation cleanup. It is not a 50k/100k signoff.
- Immediate priority: complete decisions/signoff prerequisites for ODEX, simplified Newton, RATTLE, QN p28/BTN, and HMC/Metropolis/reverse-gate before moving to other cross-cutting refactors.

## ODEX 10k baseline supersession - 2026-05-09 JST
- User correctly identified that the original `ODEX_10K_VALIDATION_RESULT_20260508.md` predates the QN invalid-evaluation handling cleanup and should not govern forward ODEX scale-up.
- The 2026-05-08 ODEX 10k result is now marked superseded/historical only.
- The QN-clean 10k result was copied into the active ODEX validation namespace at `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`.
- Added `runbooks/ODEX_10K_VALIDATION_RESULT_20260509_QNCLEAN.md` as the active 10k ODEX baseline for the next 50k gate.
- Raw historical output was not deleted; a supersession marker was written beside the old 2026-05-08 output so future work does not confuse it with the active baseline.

## QN-clean promotion and ODEX scale-up submission - 2026-05-09 JST
- Promoted QN-clean state into the canonical `codex/preprod-hardening` branch without force-pushing. Merge/promotion commit: `4bd26b3`; PBS scale-up commit: `5b93aaa`.
- Updated the production worktree `/lustre1/home/cychou/TLTM` (`/home/cychou/TLTM` resolves to the same path) to `5b93aaa`.
- Copied the active QN-clean 10k baseline into the production ODEX namespace: `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`.
- Cleaned stale build module/object cache and rebuilt `bin/run_tltm_stage2` plus `bin/evaluate_expectations` with `compiler/2025.3.0`, `mpi/2021.17`, and `mkl/2025.3`.
- Submitted refreshed QN-clean ODEX scale-up jobs from the canonical production worktree:
  - 32seed x 50k job: `14324.anode01`, output `output/tests/odex_validation/20260509_32seed_50k_qnclean_fb_norefine_ct1e13_qn1e13`.
  - 128seed x 100k chunks: `14325.anode01` through `14332.anode01`, offsets `0,16,32,48,64,80,96,112`.
  - 100k merge dependency job: `14333.anode01`, held on `afterok` of all eight chunks.
- The side worktree `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation` is no longer the active source of truth; it remains only as temporary historical/backup context until the refreshed ODEX validation finishes.

## QN-clean ODEX 50k/100k completion - 2026-05-09 JST
- Refreshed QN-clean ODEX validation completed successfully and produced reports for 32seed x 50k and 128seed x 100k.
- 50k result: `mean Re<O>=-0.0190826825`, `mean Im<O>=0.0037547361`, `Zmean Re=-1.450635`, `Zmean Im=0.567061`, unresolved failures `40715`, reverse-gate rejects `24986`, mean pair0 accept `0.438705`.
- 100k result: `mean Re<O>=0.0017729074`, `mean Im<O>=-0.0005999719`, `Zmean Re=0.385239`, `Zmean Im=-0.200998`, unresolved failures `326569`, reverse-gate rejects `202530`, mean pair0 accept `0.438907`.
- ODE failure-boundary counters: 100k fallback attempts `2862514`, success `0`, failure `2862514`, invalid `0`, h-min `2862168`, max-steps `346`.
- Compared with the pre-ODEX 128seed/100k `fb_norefine` characterization, ODEX-only increases unresolved failures by `102130` and projection failures by `104213`, but physical observables remain compatible with zero and RG/acceptance diagnostics remain stable.
- Judgment recorded in `runbooks/ODEX_50K_100K_VALIDATION_RESULT_20260509_QNCLEAN.md`: staged ODEX-only validation passes the physical-observable gate, with higher failure counters documented as the expected failure-as-rejection tradeoff.

## QN p28 BTN source cleanup - 2026-05-08 JST
- Implemented the first M2 core source patch for QN p28/BTN paper variables.
- Changed `evaluate_constraint_residual` to build `ztrial = z + del_z - J*(a+i*b)` with `xi1=b`, `xi2=a`.
- Changed `initial_guess_from_jacobian` to solve `J dz=+del_z` for the paper-variable seed.
- Kept `Jl` recovery semantics unchanged: `Jl` is the actual correction used in `ztrial = z + del_z + Jl`.
- Historical note: updated optional post-refine seed mapping to use `ld0=b_qn`; the post-refine route has since been removed and canonical p28 remains no-refine.
- Verified by rebuilding `../bin/replay_quasi_failures` and running a 2-cycle local `test_tltm_stage2` smoke; no production job was submitted.

## QN p28 BTN contract verification - 2026-05-08 JST
- Added BTN contract diagnostics to `src/apps/replay_quasi_failures.f90`: `btn_contract_ok`, `btn_flow_im_norm`, and `btn_a_norm`.
- Diagnostic reconstructs `ztrial = z + del_z + Jl`, calls `flowzr(ztrial)`, and reports `max|Imag(flowzr(ztrial))|` plus `max|a|` from the paper-variable solution.
- Local replay on `output/production/constraint_solver_fail_{z0,delz,x0}.dat` with `tol=1e-13`, `max_iter=28` produced 26/26 solver successes and 26/26 BTN contract OK.
- Observed maxima: `max|Imag(flowzr(ztrial))| = 6.77e-14`, `max|a| = 6.72e-16`, `max min_res = 6.77e-14`.
- Output CSV was written under ignored test output (`output/tests/btn_contract/replay_btn_contract_p28.csv`); no production job was submitted.

## ODEX 10k validation result - 2026-05-08 JST
- Completed ODEX-only 10seed/10k `fb_norefine` validation on commit `ae234a2` with p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`.
- Result artifacts are under `output/tests/odex_validation/20260508_10seed_10k_fb_norefine_ct1e13_qn1e13`.
- Aggregate observable readout remains compatible with the target: mean `Re<O> = -0.0386029`, mean `Im<O> = 0.0183377`, `Zmean Re = -0.491731`, `Zmean Im = 0.576116`.
- Acceptance and reverse-gate diagnostics are stable relative to the closest 10seed/10k baseline: pair0 accept `0.44008` vs `0.43984`; reverse-gate rejects `1566` vs `1585`.
- Projection/unresolved failures increased relative to the closest baseline (`2519` vs `1769` unresolved; mean projection failures/seed `408.5` vs `335.4`), so these are required 50k watch items.
- ODEX-only fallback semantics are active as expected: fallback success is `0`, invalid fallback count is `0`, and fallback failures are almost entirely h-min classified (`21761/21762`) with one max-step-classified failure.
- Judgment recorded in `runbooks/ODEX_10K_VALIDATION_RESULT_20260508.md`: provisional pass to matching 50k validation, not final physics signoff.

## ODEX 50k/100k validation submission - 2026-05-08 JST
- Added and submitted matching ODEX-only `fb_norefine` scale-up jobs from commit `4b5b99a`.
- 50k job: `14306.anode01`, PBS `codex/workspaces/fortran_modernization/tasks/pbs/odex_50k_validation_20260508_fb_norefine.pbs`, config `docs/stage_3_4_t035_paired_10seed_50k_rg.json`.
- 100k job: `14307.anode01`, PBS `codex/workspaces/fortran_modernization/tasks/pbs/odex_100k_validation_20260508_fb_norefine.pbs`, config `docs/stage_3_4_t035_paired_10seed_100k_rg.json`.
- Both jobs use 10 matched seeds, p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`, `jobs=20`, `stage2_threads=1`, `eval_threads=1`.
- Output directories:
  - `output/tests/odex_validation/20260508_10seed_50k_fb_norefine_ct1e13_qn1e13`
  - `output/tests/odex_validation/20260508_10seed_100k_fb_norefine_ct1e13_qn1e13`
- Log directories:
  - `output/logs/odex_validation/20260508_10seed_50k_fb_norefine_ct1e13_qn1e13`
  - `output/logs/odex_validation/20260508_10seed_100k_fb_norefine_ct1e13_qn1e13`
- At submission check, both jobs were running on C12 with start time `2026-05-08 23:44 JST`; requested walltimes are 4h for 50k and 8h for 100k.
- ETA from the 10k measured walltime is approximately 60-75 minutes for 50k and 2-2.5 hours for 100k, assuming similar node behavior.

## ODEX 50k/100k scale-up correction - 2026-05-08 JST
- Correction: the first submitted 50k/100k jobs used only 10 seeds and did not match the original Stage3_4 scale-up seed counts.
- Cancelled incorrect jobs:
  - `14306.anode01` (`odex50k_fbnr`), cancelled after about 2m48s, `Exit_status=271`.
  - `14307.anode01` (`odex100k_fbnr`), cancelled after about 2m48s, `Exit_status=271`.
- Removed the incorrect 10seed scale-up PBS/config files from HEAD and cleaned their partial 10seed 50k/100k output/log directories.
- Corrected script commit: `334e114`.
- Correct 50k validation now matches the original intermediate scale: 32 seeds x 50k cycles, `fb_norefine` only.
  - Job: `14308.anode01`
  - PBS: `codex/workspaces/fortran_modernization/tasks/pbs/odex_32seed_50k_validation_20260508_fb_norefine.pbs`
  - Config: `docs/stage_3_4_t035_paired_32seed_50k_rg.json`
  - Output: `output/tests/odex_validation/20260508_32seed_50k_fb_norefine_ct1e13_qn1e13`
  - Logs: `output/logs/odex_validation/20260508_32seed_50k_fb_norefine_ct1e13_qn1e13`
- Correct 100k validation now matches the original final gate seed count: 128 seeds x 100k cycles, `fb_norefine` only, split into 8 chunks x 16 seeds.
  - Chunks: `14309.anode01` offset 0 C8, `14310.anode01` offset 16 C8, `14311.anode01` offset 32 C8, `14312.anode01` offset 48 C8, `14313.anode01` offset 64 G, `14314.anode01` offset 80 G, `14315.anode01` offset 96 G, `14316.anode01` offset 112 F.
  - Merge dependency job: `14317.anode01`, `afterok` on all 8 chunks.
  - PBS: `codex/workspaces/fortran_modernization/tasks/pbs/odex_128seed_100k_validation_20260508_fb_norefine_chunk.pbs`
  - Merge PBS: `codex/workspaces/fortran_modernization/tasks/pbs/odex_128seed_100k_validation_20260508_fb_norefine_merge.pbs`
  - Config: `docs/stage_3_4_t035_paired_128seed_100k_rg_nofb_fbnorefine.json`
  - Output root: `output/tests/odex_validation/20260508_128seed_100k_fb_norefine_ct1e13_qn1e13`
  - Logs root: `output/logs/odex_validation/20260508_128seed_100k_fb_norefine_ct1e13_qn1e13`
- At submission check, `14308` and all 8 compute chunks `14309`-`14316` were running; merge job `14317` was held by dependency as intended.

## QN invalid-evaluation handling and ODEX scale-up stop - 2026-05-09 JST
- User clarified that QN/DFOLS trust-region failures are valid trial failures, but must not be encoded as artificial residuals that can pollute the model or progress logic.
- Implemented QN evaluator contract cleanup: invalid constraint/flow evaluations now return neutral `fq=0`, `Jl=0`, and `ierr=.true.` via `mark_constraint_eval_invalid`; solver logic must branch on `ierr`/`eval_ok`, not sentinel residual magnitude.
- Changed the non-paper-exact initial-evaluation retry seed in DFO-LS, DFO-GN/Broyden, and non-paper DFO-GN paper-attempt fallback from `x=xt` to `x=0`.
- Preserved trace semantics: failed trials are still recorded as `eval_ok=.false.` and cannot count as accepted progress.
- Local verification: rebuilt `../bin/run_tltm_stage2` successfully in the dedicated QN validation worktree.
- Stopped the in-flight ODEX-only scale-up because QN error handling changes invalidate it as the next comparison gate. Cancelled `14308`-`14316`; cancelled held merge `14318`. The scale-up will be rerun from the QN-cleaned state after a fresh 10k validation.
- Added PBS `codex/workspaces/fortran_modernization/tasks/pbs/qn_error_handling_10k_validation_20260509_fb_norefine.pbs` for a fresh 10seed x 10k `fb_norefine`, p28, reverse-gate, post-refine-off validation at `ct=1e-13`, `QN=1e-13`.

## Local transition counter split - 2026-05-09 JST
- Implemented the next state/information propagation slice: Stage1/Stage2 local transitions now record detailed Metropolis transition-status counters while preserving old accept/reject and `projection_failure_count` semantics.
- Added lightweight `markovchain_transition_status` module so transition-status constants are shared without making TLTM type definitions depend on the Metropolis implementation module.
- Added counters for ordinary Metropolis rejection, reverse-gate rejection, proposal construction failure, invalid Hamiltonian, invalid `Delta H`, and output-size mismatch.
- Stage1/Stage2 summary rows append the new counters after legacy columns; Stage2 also writes `# local_transition_totals ...` for robust parser consumption.
- RG reject audit CSV now includes `transition_status`, so future analysis can distinguish reverse-gate rejection from other failed-proposal modes without overloading `proposal_failed`.
- `scripts/run_stage3_3_multiseed.py` and `scripts/merge_stage3_multiseed_chunks.py` now carry the new local transition counters through per-seed and aggregate CSV output.
- Behavior-preservation note: no proposal, reverse-gate, Metropolis acceptance, RNG, or live-state update logic was changed; this patch is output/status observability only.
- Verification passed: `python3 -m py_compile ...`; `git diff --check`; `make -C build FC=gfortran LDFLAGS= test1`; Stage1/Stage2 executable build; tiny local Stage2 smoke and parser readback of the new counters.

## ODE/flow status surface - 2026-05-09 JST
- Implemented the next state/information propagation slice: `intode`, `flowz`, `flowzr`, and `flow` now expose optional integer status outputs while preserving the existing `logical error_flag` callers.
- New `intode_status_*` values distinguish strict ODEX success, zero-time no-op success, legacy stiff-rescue success, solver-internal assist success, and failures from max-step, invalid-state, or h-min boundaries.
- Added the existing ODEX analytic test to the build as `make test_odex_solver` and extended it to assert status values.
- Behavior-preservation note: ODEX/Radau/assist decisions, fallback counters, final proposal strictness, and all existing callers remain unchanged; the status is a contract surface for later patches.
- Verification passed: `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `git diff --check`; `make -C build FC=gfortran LDFLAGS= test1`; Stage1/Stage2 executable build; tiny local Stage2 smoke.

## Strict final proposal flow gate - 2026-05-09 JST
- Implemented the next state/information propagation slice: RATTLE final proposal `flow(...)` now consumes the optional ODE/flow status.
- Only strict ODEX success and zero-time no-op are accepted as final proposal flow success; max-step, invalid-state, h-min, and unexpected non-strict success statuses become explicit final-flow step failures.
- Proposal-level compatibility is preserved by mapping these detailed step statuses back to the existing final-flow failure category in `hmc.f90`.
- Behavior-preservation note: current canonical paths should be unchanged because solver-internal assist is already gated to Newton/QN residual contexts and stiff rescue is disabled; the patch fails closed if a future legacy path tries to finalize a proposal through non-strict flow.
- Verification passed: `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `git diff --check`; `make -C build FC=gfortran LDFLAGS= test1`; Stage1/Stage2 executable build; tiny local Stage2 smoke.

## QN residual flow-status counters - 2026-05-09 JST
- Implemented the next state/information propagation slice: QN residual evaluators now request optional ODE/flow status from `flowzr(...)` and `flowz(...)`.
- Added counters for strict success, zero-time success, stiff rescue, solver assist, max-step failure, invalid-state failure, h-min failure, and unknown status.
- Stage1/Stage2 summaries now write `# qn_eval_flow_status ...`; multiseed run/merge scripts carry the new per-seed and aggregate columns.
- Behavior-preservation note: this is observability only. `ierr` remains the behavior-bearing residual validity signal, and trust-region, line-search, acceptance, reverse-gate, RNG, and final proposal logic are unchanged.
- Verification passed: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke, and parser readback of the new columns.

## Strict initialization flow gate - 2026-05-09 JST
- Implemented the next state/information propagation slice: Stage1/Stage2 initialization now requests optional `flow(...)` status and accepts only strict ODEX success or zero-time no-op.
- Added shared helper `intode_status_is_strict_success(...)` in `solve_flow.f90`; HMC final proposal flow now uses the same helper instead of a private duplicate.
- Behavior-preservation note: current canonical strict ODEX and zero-time initialization paths are unchanged. Non-strict solver-assist or legacy rescue success is fail-closed for initialization, matching the final physical proposal boundary.
- Verification passed: `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, Stage1/Stage2 executable build, `make -C build FC=gfortran LDFLAGS= test1`, and tiny local Stage2 smoke.

## Strict physical flow call sites - 2026-05-09 JST
- Implemented the next state/information propagation slice: remaining physical-state `flow(...)` call sites now consume optional status and require strict success.
- Updated generic Markov-chain initial flow, warmup reflow, adaptive preflow trial flow, and Stage2 adjacent-swap reflow candidates.
- Behavior-preservation note: canonical strict ODEX/zero-time paths are unchanged. Solver-internal assist remains confined to residual-evaluation contexts and cannot construct live chain, warmup, preflow, swap, initialization, or final proposal states.
- Verification passed: `git diff --check`, Stage1/Stage2 executable build, `make -C build FC=gfortran LDFLAGS= test1`, and tiny local Stage2 smoke with swap enabled.

## Newton residual flow-status counters - 2026-05-09 JST
- Implemented the next state/information propagation slice: simplified Newton residual `flowz(...)` calls now request optional ODE/flow status and record diagnostic counters.
- Added Stage1/Stage2 `# newton_eval_flow_status ...` summary lines; multiseed run/merge scripts carry the new per-seed and aggregate CSV columns.
- Behavior-preservation note: Newton convergence, failure returns, line-search/rescue behavior, and HMC/RATTLE acceptance logic are unchanged. `solve_failed` remains the behavior-bearing signal.
- Verification passed: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke, and parser readback with observed Newton zero-time residual-flow counts.

## Reverse-gate replay status counters - 2026-05-09 JST
- Implemented the next state/information propagation slice: reverse-gate replay now records the nested `rattle_step_core(...)` step status.
- Added Stage1/Stage2 `# reverse_gate_replay_status ...` summary lines; multiseed run/merge scripts carry the new per-seed and aggregate CSV columns.
- Behavior-preservation note: RG replay, tolerance comparison, pass/reject decision, and counter suppression semantics are unchanged. The new counters describe replay construction status, not the tolerance comparison outcome.
- Verification passed: `py_compile`, `git diff --check`, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, `make -C build FC=gfortran LDFLAGS= test1`, Stage1/Stage2 executable build, tiny local Stage2 smoke/parser readback, and RG-enabled tiny smoke observing `reverse_gate_replay_success=80`.

## Source hygiene cleanup - 2026-05-09 JST
- Removed tracked backup artifact `src/sampler/hmc_integrator_core.f90.bak_codex_20260429`.
- Behavior-preservation note: the file was not a build source and only polluted source search/audit results.
- Verification: `rg --files src | rg "bak|backup|copy|old|legacy"` no longer reports tracked backup source artifacts.

## Test strict-flow contract cleanup - 2026-05-09 JST
- Updated `tests/test_hamiltonian_conservation.f90` so initial flow requests optional ODE status and requires strict success.
- Behavior-preservation note: this changes only the test guard; successful strict ODEX initialization and the Hamiltonian convergence calculation are unchanged.
- Verification passed: `git diff --check` and `make -C build FC=gfortran LDFLAGS= test1`.

## Legacy diagnostic and post-refine deletion - 2026-05-09 JST
- Deleted the tracked root-level Fortran copies `hmc_integrator_core.f90` and `constraint_solver_stats.f90`; they were not build sources and polluted source search/audit.
- Deleted standalone diagnostic apps and build targets: `sample_flow_manifold`, `replay_quasi_failures`, `probe_hmc_volume`, `scan_flow_vs_flowz`, and `scan_flowzr_stability`.
- Deleted helper scripts that depended on those removed diagnostic binaries, and removed the replay command section from `docs/commands.md`.
- Removed the post-refine executable path from HMC/QN fallback: no `QN_POST_NEWTON_REFINE_*` environment controls remain in active `src/`, no post-refine solver attempt/capture code remains, and Stage2/multiseed output schemas no longer report post-refine counters.
- Preserved the canonical p28 QN route as fallback-enabled without post-refine; the `fb_norefine` method name remains as a compatibility alias in the Stage3 runner.
- Behavior-preservation note: production proposal physics, ODEX/RATTLE/HMC acceptance logic, reverse gate decisions, RNG, and live-state updates were not intentionally changed by the deletion. Removed Newton `rescue_mode` branches were unreachable from active callers and corresponded to the deleted post-refine/newton-rescue path.
- Verification passed: `python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/merge_stage3_multiseed_chunks.py scripts/fortran_module_deps.py`; `git diff --check`; production executable build; `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `make -C build FC=gfortran LDFLAGS= test1`; tiny Stage2 smoke with explicit `TLTM_STAGE2_INIT_SIGMA=0.1`.
- Historical note: this Stage2 parser hazard was resolved by the Stage env-parser default repair below.

## Stage env-parser default repair - 2026-05-09 JST
- Fixed the Stage1/Stage2 environment parser helper interface to keep defaults in the caller and overwrite only when a valid environment value is present.
- Removed same-variable default/output aliasing for `TLTM_STAGE1_*` and `TLTM_STAGE2_*` integer, real, and logical parser calls.
- Behavior-preservation note: runs that explicitly set these environment variables keep the same intended override behavior. Runs that omit them now receive the intended defaults instead of nonconforming alias-dependent values such as `init_sigma=0.0000`.
- Verification passed: `git diff --check`; no remaining three-argument parser calls in `src/sampler`; Stage1/Stage2 executable build; `make -C build FC=gfortran LDFLAGS= test_odex_solver`; tiny Stage1 smoke without `TLTM_STAGE1_INIT_SIGMA` observed `init_sigma=0.1000`; tiny Stage2 smoke without `TLTM_STAGE2_INIT_SIGMA` observed `init_sigma=0.1000`; explicit Stage2 override `TLTM_STAGE2_INIT_SIGMA=0.2` observed `init_sigma=0.2000`.

## QN legacy route source cleanup - 2026-05-09 JST
- Removed legacy QN solver-family implementations from active source: DFO-GN, DFO-GN paper interpolation/geometry route, Broyden/line-search route, strict continuation, diversified restart/sweep helpers, and the post-refine Newton-loss residual.
- Removed the standalone `quasi_newton_line_search` and `quasi_newton_jacobian_update` modules from the build because their only remaining consumers were deleted legacy routes.
- Removed the `QN_QUASI_GLOBAL_FALLBACK_ENABLED` runtime control. Existing Stage2/multiseed `quasi_global_filter_*` output columns remain for schema compatibility and now describe only the retained candidate counter surface.
- Preserved the canonical p28 route: Newton -> `solve_constraint_quasi_newton(evaluate_constraint_residual, ...)` -> DFO-LS standard residual with bounded local priority pass -> reverse gate -> Metropolis.
- Behavior-preservation note: production proposal physics, DFO-LS residual semantics, ODEX/solver-assist residual evaluation, strict final proposal flow, reverse gate decisions, RNG, and live-state updates were not intentionally changed. Behavior changes only for explicitly legacy routes or removed env controls.
- Verification passed: `python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/merge_stage3_multiseed_chunks.py scripts/fortran_module_deps.py`; deleted-symbol census is clean for active `src/sampler`; `git diff --check`; forced Stage1/Stage2 executable rebuild; `make -C build FC=gfortran LDFLAGS= test_odex_solver`; `make -C build FC=gfortran LDFLAGS= test1`; tiny Stage1 smoke; tiny Stage2 smoke with `QN_QUASI_GLOBAL_FALLBACK_ENABLED=1` confirming the removed env no longer activates a route and summary compatibility columns remain present with zero counts.

## Radau/JFNK flow-rescue source cleanup - 2026-05-09 JST
- Removed the inactive secondary-integrator rescue implementations from `src/physics/solve_flow.f90`: adaptive Radau, fixed/chunked Radau, JFNK, and Radau last-failure replay diagnostics.
- Kept `intode_stiff_rescue(...)` as an explicit disabled compatibility stub.
- Kept `get_intode_rescue_stats(...)` schema-compatible: Radau fields now return zero; legacy `final_resort` fields remain compatibility labels for solver-internal residual assist.
- Preserved the canonical flow policy: ODEX primary integration, solver-internal assist only for NT/QN residual evaluation, and strict final `flow(...)` for proposal/live-state construction.
- Behavior-preservation note: ODEX stepping, assist gating, final proposal strictness, Metropolis acceptance, RNG, and live-state updates were not intentionally changed. Removed source was unreachable under the validated canonical policy.
- Verification passed: Stage1/Stage2 executable build, `make -C build FC=gfortran LDFLAGS= test_odex_solver`, and `make -C build FC=gfortran LDFLAGS= test1`.

## Root stale-source and no-op strict-mode cleanup - 2026-05-09 JST
- Deleted tracked root-level stale Fortran artifacts `quasi_newton_solver.f90`, `tltm_stage2_driver.f90`, and `replay_quasi_failures.f90`; active canonical sources live under `src/` and these root files were not referenced by `build/makefile`.
- Deleted stale backup config `data/parameters.stage3_2.bak`, which was not referenced by active scripts/docs and duplicated an obsolete Stage3_2-era parameter snapshot.
- Updated persistent knowledge maps to describe the current no-post-refine, no-DFO-GN/Broyden, no-Radau/JFNK active architecture.
- Removed the no-op `set_intode_strict_mode(...)` API and its call sites. After Radau/JFNK deletion, final-flow strictness is enforced by explicit ODE status gates rather than a mutable module flag.
- Updated `generate_markov_chain` startup logging from `strict=` to `final_flow_strict=` to describe the actual policy.
- Behavior-preservation note: no production route, ODEX stepping, residual assist gate, Metropolis acceptance, RNG, or output schema was intentionally changed.
- Verification passed: `rg` found no remaining `set_intode_strict_mode`/`intode_strict_mode` references in active `src` or `tests`; root source-artifact scan now finds only canonical `src/sampler` files; `git diff --check`; `make -C build FC=gfortran LDFLAGS= ../bin/generate_markov_chain ../bin/run_tltm_stage1 ../bin/run_tltm_stage2 test_odex_solver test1`; tiny Stage1 smoke; tiny Stage2 smoke.

## Solver-assist internal naming cleanup - 2026-05-09 JST
- Renamed the ODE h-min residual-assist implementation in `src/physics/solve_flow.f90` from internal `final_resort` names to `solver_assist` names.
- Added `get_intode_solver_assist_policy(...)` and kept `get_intode_final_resort_policy(...)` as a compatibility alias for older diagnostics.
- Updated `generate_markov_chain` local variable names and startup diagnostics to report `solver_assist` rather than `final_resort`.
- Preserved the existing `get_intode_rescue_stats(...)` output argument names and Stage2/multiseed summary labels for schema compatibility.
- Behavior-preservation note: no assist gate, status code, ODEX stepping, Metropolis acceptance, RNG, or Stage2 output schema was intentionally changed.
- Verification passed: `git diff --check`; `make -C build FC=gfortran LDFLAGS= ../bin/generate_markov_chain ../bin/run_tltm_stage1 ../bin/run_tltm_stage2 test_odex_solver test1`; tiny Stage1 smoke; tiny Stage2 smoke; Stage2 summary status/schema readback.

## RATTLE progress-guard downgrade - 2026-05-09 JST
- Removed the active proposal-failure use of the legacy state-progress sentinel from `src/sampler/hmc.f90`.
- Added opt-in `HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT` reporting in `src/sampler/hmc_reversibility_checks.f90`; the diagnostic measures physical-coordinate displacement across `x(2:)` and is disabled by default.
- Proposal validity now rests on solver convergence, constraint residual handling, strict final flow, reverse gate, finite Hamiltonians, and Metropolis/status gates rather than an `x(2)`-only coordinate sentinel.
- `hmc_proposal_status_no_progress` is kept only as a reserved legacy status value and is no longer emitted by the active proposal path.
- Behavior-preservation note: this intentionally removes a previously identified non-reference-backed rejection criterion. Output schema and default logging remain unchanged.
- Verification passed: `git diff --check`; `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage1 ../bin/run_tltm_stage2 test_odex_solver test1`; tiny Stage1 smoke; tiny Stage2 smoke; Stage1/Stage2 summary readback.

## QN solver-assist watchdog naming cleanup - 2026-05-09 JST
- Renamed QN watchdog internals from `final_resort` terminology to `solver_assist` terminology in `src/sampler/quasi_newton_solver.f90`.
- Added preferred env `QN_SOLVER_ASSIST_BUDGET`; retained legacy `QUASI_FINAL_RESORT_BUDGET` as a fallback alias for existing scripts/manifests.
- Preserved Stage2/failure-meta compatibility fields such as `final_resort_budget_*`; public output schema versioning is still a future task.
- Behavior-preservation note: budget default, watchdog comparison, accepted-iter budget, force-best-proposal policy, QN residual logic, and Metropolis/RG behavior are unchanged.
- Verification passed: `git diff --check`; `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage1 ../bin/run_tltm_stage2 test_odex_solver test1`.

## M6 reference dataset R1-R4 submission - 2026-05-10 JST
- Remote repository guard was added to the M6 execution plan: PBS/queue work must commit locally, push to `origin`, SSH to `cychou@ithems_fe02.intra.riken.jp`, fast-forward the target remote worktree, verify branch/commit/clean status/`qsub`, and submit only from the verified remote worktree.
- Target remote worktree: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`.
- Additional operational guard learned during submission: do not update or fast-forward the remote worktree after PBS jobs are submitted and before they finish, because the job guard pins `TLTM_EXPECTED_GIT_COMMIT`.
- Additional cluster-build guard learned during submission: preflight must run `make -C build clean` before building, and M4 guardrails must use the normal build `LDFLAGS`; otherwise stale or Intel `-ipo` object/link mismatches can fail before large chunks start.
- Superseded submissions: `14416-14464`, `14465-14513`, and `14514-14562` were canceled or superseded after preflight/early chunk failures exposed the above guards.
- Active submitted commit: `a1028ad` on branch `codex/qn-error-handling-validation`.
- Active submit manifest: `output/logs/fortran_modernization/reference_datasets/submit/submit_manifest_20260510T180815.env`.
- Active PBS job range: `14563.anode01` through `14611.anode01`, plus R4 replacement chunks `14612.anode01` through `14621.anode01` and replacement R4 merge `14622.anode01`.
- Build job: `14563.anode01` (`m6refbuild`) completed preflight with `Exit_status=0`; latest preflight log reports `[M4][SUMMARY] all guardrails passed`.
- R1 jobs: chunks `14564.anode01`, `14565.anode01`; merge `14566.anode01`. R1 merge started, confirming chunk `afterok` release.
- R2 jobs: chunks `14567.anode01`, `14568.anode01`; merge `14569.anode01`.
- R3 jobs: chunks `14570.anode01` through `14577.anode01`; merge `14578.anode01`.
- R4 original jobs: chunks `14579.anode01` through `14610.anode01`; original merge `14611.anode01` was canceled because several chunks hit node-local `Exit_status=127`.
- R4 replacement jobs: failed chunks `03`, `06`, `07`, `12`, and `14` were resubmitted as `14612.anode01` through `14621.anode01`, avoiding the observed failing C12/C17 node placements; replacement merge is `14622.anode01`.
- Queue check after replacement showed active R/Q chunks and held merge dependencies as expected; continue monitoring for additional node-local `Exit_status=127` before final readback.

## M6 reference dataset triage - 2026-05-10 JST
- Added `runbooks/M6_REFERENCE_DATASET_TRIAGE_20260510.md`.
- Read-only triage result: R1 and R2 are structurally merged and ready for full package readback; R3 and R4 are still in progress.
- Current semantic remote target id is `fortran_modernization_m6_active`; the physical path/branch still use the legacy `qn_error_handling_validation` name while pinned PBS jobs run.
- No repair is currently indicated: R3/R4 missing or partial chunks correspond to queued/running jobs; R3 merge `14658` and R4 merge `14663` are held pending dependencies.
- Updated `codex/state/DATASETS.tsv` and `codex/state/OPEN_ITEMS.tsv` to reflect triage status.

Superseding decoupling note, 2026-05-10 JST:

- M6 R1-R4 are now accepted reference baselines.
- New semantic modernization target: `fortran_modernization`, branch `codex/fortran-modernization`, worktree `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- The old `qn_error_handling_validation` branch/worktree remains historical and should not be the active target for new modernization work.
- The production-comparison workstream is now `tltm_production_comparison`, with legacy alias `stage3_4`.
