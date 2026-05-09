# State and Information Propagation Audit

Updated: 2026-05-09 JST
Status: planning/audit complete enough for user confirmation before the first code patch.

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

### F1. Failed proposal Hamiltonian is encoded as `0.0`

`hmc.rattle` sets unavailable failed-proposal Hamiltonian values to zero:

- `src/sampler/hmc.f90:95`: output-size failure sets both Hamiltonians to `0.0`.
- `src/sampler/hmc.f90:334`: `abort_with_failure` sets `final_hamiltonian = 0.0`.
- `src/sampler/hmc.f90:231`, `src/sampler/hmc.f90:247`, and `src/sampler/hmc.f90:262`: reverse-probe failure paths set `h_final = 0.0`.
- `src/sampler/hmc.f90:372` and `src/sampler/hmc.f90:468`: warmup integrator failure paths set `final_hamiltonian = 0.0`.

Risk:

- `H=0` is a valid numeric value in principle and should not mean "unavailable".
- The production Metropolis path mostly avoids using this value because it also receives `proposal_ok`, but tests, warmup, and diagnostics still read `0.0` as failure.

### F2. Existing test uses Hamiltonian zero as failure status

`tests/test_hamiltonian_conservation.f90:69` treats `h_final == 0.0` as integrator failure.

Risk:

- This encodes the unwanted sentinel convention into the regression suite.
- It can hide the difference between a valid low Hamiltonian and an unavailable Hamiltonian.

### F3. Legacy warmup uses Hamiltonian zero as failure status

`src/sampler/markovchain_mod.f90:423` exits warmup when `h_proposed == 0.0_dp .and. h_initial /= 0.0_dp`.

Risk:

- This is not the Stage2 production path, but it is a clear status/value conflation.
- If `h_proposed` becomes unavailable, the caller should know through status or non-finite value, not equality to zero.

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

## Safe First Patch Candidate

Patch goal:

Remove Hamiltonian `0.0` as the failed/unavailable status marker without changing the physical acceptance rule.

Suggested changes:

1. In `src/sampler/hmc.f90`, replace failed/unavailable Hamiltonian outputs with IEEE quiet NaN instead of `0.0`.
2. Keep `proposal_ok` as the authoritative production proposal-validity flag.
3. In `tests/test_hamiltonian_conservation.f90`, pass the existing optional `proposal_ok` output from `integrate_hmc_proposal` and stop using `h_final == 0.0` as failure detection.
4. In `src/sampler/markovchain_mod.f90`, replace the legacy warmup `h_proposed == 0.0` check with explicit non-finite/status handling.

Expected behavior impact:

- Production accept/reject physics should not change because `markovchain_metropolis` already rejects when `proposal_ok` is false or Hamiltonians are non-finite.
- Failed proposals remain legal rejections.
- Outputs/logs/tests no longer encode failed Hamiltonian as `0.0`.

Required verification:

- Rebuild `bin/run_tltm_stage2` and `bin/test_program`.
- Run `make -C build test1` or the equivalent local Hamiltonian conservation smoke.
- Run a tiny Stage2 smoke to confirm rejected/failed proposals still leave live state unchanged and counters remain interpretable.
- Optional after confirmation: run a short fixed-seed Stage2 comparison to verify aggregate accept/reject/projection counters do not change except for diagnostics that explicitly report Hamiltonian availability.

## Not In First Patch

These are important, but should be separate patches:

- Introduce a full derived `hmc_transition_result_t` or integer status enum.
- Split `proposal_failed` into `proposal_invalid`, `reverse_gate_rejected`, `metropolis_rejected`, and `hamiltonian_unavailable`.
- Rename `projection_failure_count`.
- Redesign Stage2 output schema/counters.
- Change reverse-gate policy or Metropolis acceptance.

## Recommendation

Use the first code patch to remove `H=0` as the unavailable-Hamiltonian sentinel. Keep the patch small and behavior-preserving.

After that passes local smoke tests, plan the larger typed-state API redesign as a separate modernization slice.
