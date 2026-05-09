# State and Information Propagation Refactor

Updated: 2026-05-09 JST
Status: first two narrow source slices implemented locally; broader typed-status refactor remains future work after patch review.

## Purpose

The current code still mixes physical state, proposal state, solver state, failure status, diagnostic counters, and output quantities. This is acceptable only as transitional research code. For a publishable TLTM codebase, state and information propagation must become explicit, typed, and test-protected.

This is broader than error handling. A failure can be a legitimate MCMC rejection, but it must not be represented by fake physical or numerical values.

## Core Principle

Numerical values must carry numerical meaning only. They must not double as status sentinels.

Examples:

- A rejected proposal must not be represented by Hamiltonian `H=0`.
- An invalid residual evaluation must not be represented by an artificial objective such as `fq=1e10`.
- A missing or failed Jacobian/recovery quantity must not be represented as a fake successful zero-valued object.
- Solver-internal ODE assist may help Newton/QN residual evaluation make progress, but it must not finalize the physical proposal.

The code must distinguish:

- live chain state
- candidate proposal state
- strict final proposal construction status
- solver-internal residual-assist status
- residual-evaluation validity
- solver convergence status
- reverse-gate rejection
- Metropolis rejection
- unavailable numerical quantities
- diagnostic/replay/assist work that is not a physical proposal event

These categories should not be compressed into one `logical error` flag, one overloaded Hamiltonian value, or one overloaded fallback counter.

## Placement In Modernization Workflow

This refactor belongs after the core numerical policy decisions and before broad code hygiene/module splitting.

Reason:

- The five core algorithms decide which behavior is canonical.
- This refactor defines how canonical behavior is represented and propagated safely.
- Only after state/status contracts are explicit should large-scale cleanup split modules, rename APIs, or redesign output schemas.

## Specific Issues To Refactor

### HMC rejection-state semantics

- User clarified the flagged `h==0` issue means Hamiltonian `H==0` when a proposal is rejected.
- Rejection is a transition status, not a Hamiltonian value.
- If a proposal is rejected, the live chain state remains the old/current state.
- If the output reports the live sample Hamiltonian after rejection, it should report the current state's true Hamiltonian.
- If the failed proposal Hamiltonian is unavailable, it should be recorded as unavailable/invalid via status, not as `0`.
- Proposal failure can be a legal MCMC rejection, but it must not create fake physical or diagnostic quantities.

### State/status separation

- Separate current/live state, trial/proposal state, accepted state update, rejected stay-put transition, and diagnostic replay state.
- Ensure rejected proposal data cannot overwrite accepted/live sample data.
- Make proposal validity, Hamiltonian validity, Jacobian validity, and observable availability explicit.

### Solver-internal assist policy

- Rename final-resort terminology in code/docs after validation. The intended role is solver-internal ODE assist, not final proposal acceptance.
- Allow assist only in Newton/QN residual contexts and only for progress-boundary cases accepted by the canonical policy.
- Forbid assist in final proposal `flow(...)`, external flow calls, and any path that constructs final `z/jac` for Metropolis without a strict final integration pass.

### QN/DFOLS failure semantics

- Failed residual evaluations should be communicated as invalid evaluations to the trust-region/least-squares logic, not as large sentinel residuals.
- A failed trial should not poison the local model or slow progress more than the solver policy intends.
- Solver traces should record invalid trials without making them look like converged or accepted residuals.

### ODE integration status

- ODE success, h-min boundary, max-step exhaustion, invalid RHS, underflow/no-progress, solver-internal assist, and strict final-flow failure should be distinct statuses.
- These statuses must be propagated upward without losing whether they occurred during residual evaluation, reverse replay, diagnostic work, or final proposal construction.

### Counters and diagnostics

- Split counters by work role: forward proposal, residual evaluation, solver-internal assist, final strict flow, reverse-gate replay, debug/probe, failed proposal, rejected stay-put, and accepted proposal.
- Avoid global suppression/capture switches that make output interpretation depend on call history.
- Output summaries should report physical proposal events separately from diagnostic/assist events.

## Proposed Refactor Sequence

1. Inventory all current state/status/value overloading in `solve_flow.f90`, `hmc.f90`, `hmc_integrator_core.f90`, `hmc_constraints.f90`, `quasi_newton_solver.f90`, `markovchain_metropolis.f90`, and Stage2 reporting.
2. Define a typed transition/result taxonomy for ODE integration, residual evaluation, solver convergence, proposal construction, reverse gate, and Metropolis update.
3. Add compatibility wrappers so existing callers can still receive legacy `logical error`/counter outputs while internal code carries typed status.
4. Refactor HMC rejection handling so rejected/failed proposals preserve live state and never encode unavailable Hamiltonians as `H=0`.
5. Refactor Newton/QN residual evaluators to consume typed ODE status and return typed residual-evaluation status.
6. Refactor RATTLE/proposal boundary so only strict final integration can produce `final_z/final_jac`.
7. Redesign counters and output schema to separate assist/diagnostic work from physical proposal events.
8. Run behavior-preservation gates after each slice.

## Required Tests Before Any Source Refactor

- Rejected proposal leaves live state unchanged.
- Rejected proposal output reports true live-state quantities or explicit unavailable proposal quantities, never fake `H=0`.
- Failed proposal is treated as legal rejection without consuming or mutating accepted-state fields incorrectly.
- Proposal failure, reverse-gate rejection, and Metropolis rejection produce distinct status/counter records.
- Solver-assist allowed in Newton/QN residual evaluation and forbidden in final `flow(...)`.
- QN invalid evaluation handling: failed residual callback must not create sentinel objective values.
- Reverse-gate replay counters stay separate from forward proposal counters.
- 10k smoke comparison after each behavior-sensitive slice.

## Current Gate

The solver-assist 10k -> 50k -> 100k validation completed and supports solver-internal assist as part of the canonical flow-policy candidate.

The first approved source slice removes `H=0` as an unavailable-Hamiltonian sentinel in HMC proposal/test/warmup paths. The broader typed state/status refactor remains gated and should proceed patch-by-patch. The required taxonomy should assume:

- ODEX primary integration.
- Solver-internal residual assist for NT/QN.
- Strict final proposal flow.
- Distinct rejected proposal, failed proposal, unavailable Hamiltonian, assist, replay, and live-chain state-update statuses.

## First Source Slice - 2026-05-09 JST

- `src/sampler/hmc.f90`: failed/unavailable Hamiltonian outputs are initialized or set to IEEE quiet NaN instead of `0.0`.
- `tests/test_hamiltonian_conservation.f90`: failure detection now uses optional `proposal_ok` and finite-Hamiltonian checks.
- `src/sampler/markovchain_mod.f90`: warmup exits on unavailable/non-finite Hamiltonians instead of checking for `H==0`.
- Verification: local macOS/gfortran build of `../bin/test_program` passes; `make -C build FC=gfortran LDFLAGS= test1` passes with `estimated_order_tail=2.0289`.
- Local Stage2 smoke note: the selected tiny smoke fails slot-1 initialization both on the patch and on clean `HEAD`, so it is recorded as a pre-existing local smoke limitation, not this slice's regression evidence.

## Second Source Slice - Proposal Status Surface - 2026-05-09 JST

Audit result:

- Existing `proposal_failed` remains useful as a compatibility boolean, but it is too coarse for publishable state propagation.
- It can represent RATTLE/proposal construction failure, reverse-gate rejection, unavailable Hamiltonian, invalid `Delta H`, or other proposal-unavailable cases.
- Ordinary Metropolis rejection is separate from proposal failure, but the status boundary was not machine-readable by callers.

Implemented boundary:

- `hmc_integrator_core.f90`: optional RATTLE-step status codes distinguish output mismatch, momentum mismatch, force failure, constraint failure, strict final-flow failure, final projection failure, and reverse-gate rejection.
- `hmc.f90`: optional HMC proposal status maps step failures to proposal-level reasons, including reverse-gate rejection and no-progress failure.
- `markovchain_metropolis.f90`: optional transition status maps proposal status to accepted, ordinary rejected, proposal failed, reverse-gate rejected, invalid Hamiltonian, invalid `Delta H`, or output mismatch.
- `tests/test_hamiltonian_conservation.f90`: successful test proposals now assert `hmc_proposal_status_success`.

Compatibility:

- Existing `accept`, `proposal_ok`, and `proposal_failed` callers remain source-compatible.
- Acceptance probability, RNG draw location, live-chain state update, and output schema are unchanged.
- The new statuses are a surface for the next counter/output cleanup; they do not yet split Stage1/Stage2 summary columns.

Verification:

- Clean local rebuild: `make -C build clean && make -C build FC=gfortran LDFLAGS= ../bin/test_program`.
- Hamiltonian test: `make -C build FC=gfortran LDFLAGS= test1` passes with `estimated_order_tail=2.0289`.
- Stage2 executable rebuild: `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2` passes.

Build-system risk:

- Incremental rebuild after this public module API change produced a stale-object crash before clean rebuild.
- Cause: the local makefile does not track complete Fortran module dependencies.
- Until build tooling is modernized, clean rebuild is required after module API changes.
