# State and Information Propagation Audit

Updated: 2026-05-09 JST
Status: source slices implemented through HMC Hamiltonian availability, proposal-status surface, transition counters, flow-status counters, and RATTLE progress-guard downgrade.

## Scope

This audit follows the HMC transition data path where numerical values, proposal status, rejection status, and live-chain state can be conflated:

- `src/sampler/hmc.f90`
- `src/sampler/markovchain_metropolis.f90`
- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/tltm_stage2_driver.f90`
- `src/sampler/tltm_stage1_driver.f90`
- `src/sampler/markovchain_mod.f90`
- `tests/test_hamiltonian_conservation.f90`

No Fortran source changes were made during this audit.

## Current Data Flow

1. `metropolis_step` asks `integrate_hmc_proposal` to produce a trial state plus `h_initial`, `h_final`, and `proposal_ok`.
2. If `proposal_ok` is false or Hamiltonians are non-finite, `metropolis_step` returns `accept=.false.` and `proposal_failed=.true.`.
3. If the proposal is valid, Metropolis uses `delta_h = h_final - h_initial`.
4. Stage1/Stage2 update live state only when `accepted=.true.`.
5. Rejected or failed proposals do not overwrite live `x/z/jac`.

This means the live-chain state update is broadly safe, but proposal status and diagnostic values are still overloaded.

## Findings

### F1. Failed proposal Hamiltonian was encoded as `0.0` - resolved

Historical finding: `hmc.rattle` set unavailable failed-proposal Hamiltonian values to zero:

- `src/sampler/hmc.f90:95`: output-size failure sets both Hamiltonians to `0.0`.
- `src/sampler/hmc.f90:334`: `abort_with_failure` sets `final_hamiltonian = 0.0`.
- `src/sampler/hmc.f90:231`, `src/sampler/hmc.f90:247`, and `src/sampler/hmc.f90:262`: reverse-probe failure paths set `h_final = 0.0`.
- `src/sampler/hmc.f90:372` and `src/sampler/hmc.f90:468`: warmup integrator failure paths set `final_hamiltonian = 0.0`.

Resolution:

- Current `src/sampler/hmc.f90` initializes and sets unavailable Hamiltonians to IEEE quiet NaN.
- `H=0` is no longer the unavailable-Hamiltonian sentinel.

### F2. Existing test used Hamiltonian zero as failure status - resolved

Historical finding: `tests/test_hamiltonian_conservation.f90` treated `h_final == 0.0` as integrator failure.

Resolution:

- The test now calls `integrate_hmc_proposal(...)` with optional `proposal_ok` and `proposal_status`.
- It rejects failed proposals by status/non-finite Hamiltonians rather than `H==0`.

### F3. Legacy warmup used Hamiltonian zero as failure status - resolved

Historical finding: legacy warmup exited when the proposed Hamiltonian was numerically zero.

Resolution:

- Current warmup code exits on non-finite Hamiltonians, not zero equality.
- `integrate_hmc_warmup(...)` failed paths return unavailable Hamiltonian as NaN.

### F4. Live-chain update is safe but status names are overloaded

Stage2 live-state update is guarded:

- `src/sampler/tltm_stage2_driver.f90:479`: only accepted proposals copy `x_new/z_new/j_new` into the live slot.
- `src/sampler/tltm_stage2_driver.f90:485`: rejected or failed proposals only increment reject count.
- `src/sampler/tltm_stage2_driver.f90:488`: `proposal_failed` increments `projection_failure_count`.

Risk:

- The live state is not overwritten on rejection, which is good.
- However, `proposal_failed` currently conflates several distinct statuses: RATTLE/projection failure, reverse-gate rejection, invalid Hamiltonian, and output-buffer failure.
- `projection_failure_count` is therefore not a clean "projection failed" counter; it is closer to "proposal construction failed or was rejected by a proposal-boundary guard".

### F5. Reverse-gate rejection is behaviorally safe but semantically compressed

`hmc_integrator_core.rattle_step_core` records reverse-gate rejection and returns without setting `method_converged`:

- `src/sampler/hmc_integrator_core.f90:431`: reverse gate evaluates the candidate.
- `src/sampler/hmc_integrator_core.f90:433`: reverse-gate counters are recorded.
- `src/sampler/hmc_integrator_core.f90:439`: rejection returns from the step without success.

Risk:

- This is a legal rejection boundary, but upstream it becomes `proposal_ok=.false.` and then `proposal_failed=.true.`.
- The current boolean API does not distinguish "proposal numerically failed" from "proposal was rejected by reverse gate".

## Implemented Source Slices

Patch goals implemented:

- Remove Hamiltonian `0.0` as the failed/unavailable status marker without changing the physical acceptance rule.
- Add a proposal/transition status surface while keeping compatibility booleans.
- Split local transition counters while preserving legacy `projection_failure_count`.
- Add Newton/QN residual, strict physical-flow, and reverse-gate replay status observability.
- Downgrade the legacy RATTLE `state_has_progress` check from an active proposal-failure gate to an opt-in diagnostic.

Implemented changes:

1. In `src/sampler/hmc.f90`, failed/unavailable Hamiltonian outputs use IEEE quiet NaN instead of `0.0`.
2. `proposal_ok` remains the authoritative production proposal-validity flag.
3. In `tests/test_hamiltonian_conservation.f90`, failure detection uses optional `proposal_ok`, proposal status, and finite-Hamiltonian checks.
4. In `src/sampler/markovchain_mod.f90`, warmup exits on unavailable/non-finite Hamiltonians instead of checking for `H==0`.
5. In `src/sampler/hmc_reversibility_checks.f90`, no-progress observation is available only through `HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT`; it no longer rejects proposals.

Behavior impact:

- Production accept/reject physics should not change because `markovchain_metropolis` already rejects when `proposal_ok` is false or Hamiltonians are non-finite.
- Failed proposals remain legal rejections.
- Outputs/logs/tests no longer encode failed Hamiltonian as `0.0`.
- The old `x(2)`-only progress sentinel no longer defines proposal validity; strict flow, solver convergence, constraint residuals, reverse gate, and Metropolis/status gates carry that role.

Required verification pattern:

- Rebuild `bin/run_tltm_stage2` and `bin/test_program`.
- Run `make -C build test1` or the equivalent local Hamiltonian conservation smoke.
- Run a tiny Stage2 smoke to confirm rejected/failed proposals still leave live state unchanged and counters remain interpretable.
- Optional after confirmation: run a short fixed-seed Stage2 comparison to verify aggregate accept/reject/projection counters do not change except for diagnostics that explicitly report Hamiltonian availability or state-progress diagnostics.

## Not In First Patch

These are important, but should be separate patches:

- Introduce a full derived `hmc_transition_result_t` beyond the current integer status surface.
- Replace compatibility `proposal_failed`/`projection_failure_count` names with a versioned public schema.
- Rename `projection_failure_count`.
- Redesign Stage2 output schema/counters.
- Change reverse-gate policy or Metropolis acceptance.

## Recommendation

Continue with the larger typed-state API redesign as a separate modernization slice. The short-term source now follows the project policy: unavailable values are status/NaN, rejected proposals are stay-put transitions, and the state-layout progress check is diagnostic rather than a physical proposal criterion.
