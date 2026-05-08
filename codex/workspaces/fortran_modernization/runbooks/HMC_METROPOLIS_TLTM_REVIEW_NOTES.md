# HMC / Metropolis / TLTM Driver Review Notes

Updated: 2026-05-08
Scope: planning-only, behavior-preserving review. No source edits, no jobs.

## Purpose

This note fixes the top-level algorithm boundary: how constrained HMC proposals, Metropolis acceptance, tempered flow-time replicas, swaps, histories, and summary diagnostics connect into the TLTM production workflow.

## Reference Definition

Primary references:

- `1912.13303_TLTM_HMC.pdf`: TLTM and HMC algorithm context.
- `2311.10663v4.pdf`: constrained HMC proposal mechanics and reversibility/volume-preservation concerns.
- Existing project knowledge: `codex/knowledge/FULL_PROGRAM_MAP_CHECK.md` records current Stage3_4 risk and audit status.

## Current Implementation Map

Primary files:

- `/home/cychou/TLTM/src/apps/run_tltm_stage2.f90`
- `/home/cychou/TLTM/src/sampler/tltm_stage2_driver.f90`
- `/home/cychou/TLTM/src/sampler/markovchain_metropolis.f90`
- `/home/cychou/TLTM/src/sampler/hmc.f90`
- `/home/cychou/TLTM/src/sampler/hmc_integrator_core.f90`
- `/home/cychou/TLTM/src/physics/solve_flow.f90`
- `/home/cychou/TLTM/src/sampler/constraint_solver_stats.f90`

Local update path:

1. `tltm_stage2_driver.execute_tltm_stage2` reads parameters, sets strict mode, resets fallback/solver stats, initializes replica slots and flow ladder.
2. `run_local_updates` calls `metropolis_step` for each local update, snapshots solver counters, and records accepted-route census.
3. `metropolis_step` calls `integrate_hmc_proposal`, rejects explicit proposal failures/non-finite Hamiltonians, and otherwise accepts with `min(1, exp(-Delta H))`.
4. `integrate_hmc_proposal` delegates to `rattle` for current active method.
5. `rattle` performs momentum generation/projection, constrained steps, optional reversibility probe, and returns explicit `proposal_ok`.
6. Accepted local updates replace `x/z/jac`; rejected or failed proposals leave the slot unchanged.

Swap path:

1. `perform_swap_sweep` attempts adjacent swaps in alternating parity order.
2. `attempt_adjacent_swap` computes current effective energies with `Re(S)-Re(logdetJ)`.
3. It reflows each slot's `x` at the other slot's flow time using `flow`.
4. It accepts by `exp(-delta)` on the sum of effective energies.
5. On accept, it swaps label ids and assigns reflowed `x/z/jac` states.

History and summaries:

- Stage2 can write cold-slot history and all-replica history.
- Current knowledge notes the Stage2 history convention: fixed max-flow-slot history is written before swap unless intentionally changed/documented.
- `write_stage2_summary` writes fallback stats, constraint stats, quasi stage/post-refine/class/far/near/watchdog/global filter/reverse-gate stats, slot accept/reject rates, pair accept rates, and label round-trip stats.

## Behavior Preservation Risks

High-risk behavior surfaces:

- Metropolis currently uses only Hamiltonian difference for local proposal acceptance, assuming proposal symmetry/volume correctness is handled by the proposal design and reverse-gate/audit strategy.
- QN fallback route mixtures remain an explicitly tracked risk in `FULL_PROGRAM_MAP_CHECK.md`; modernization must not obscure this risk.
- Proposal failure vs rejection semantics: failed proposals increment projection failure count and must leave live slot unchanged.
- Swap acceptance depends on `flow` and `log_determinant`; changing flow or Jacobian behavior propagates to replica exchange.
- Summary/counter format is part of Stage3_4 diagnostics and script contracts.
- Environment/config knobs alter route behavior. A refactor that moves initialization order may change production results.
- RNG ordering is behavior: momentum generation, Metropolis random draw, slot initialization, and swap acceptance draws must not shift accidentally.

## Existing Verification Assets

Existing tests/scripts/logs found during planning scan:

- `tests/test_action_derivatives.f90`: derivative, Hessian, and Hessian-vector finite-difference check.
- `tests/test_hamiltonian_conservation.f90`: HMC Hamiltonian conservation trend and solver stats reporting.
- `scripts/benchmark_hamiltonian.sh`.
- `scripts/check_autodiff_integrity.sh`.
- `scripts/check_online_geometry_alignment.py`.
- Existing output reports under `output/tests/`, including Stage3_1, Stage3_3, Stage3_4, post-QN/post-refine smokes, and kernel correctness audit outputs.
- `codex/knowledge/FULL_PROGRAM_MAP_CHECK.md`: records current proposal symmetry/volume audit status and remaining risk.


## Wrapper Direction Decision

Decision recorded: current Stage2/Stage3/Stage3_4 workflow is transitional experiment/debug scaffolding.

Long-term modernization target:

- Build a unified TLTM wrapper/runner as the user-facing product interface.
- Stage-specific scripts should become compatibility layers or internal implementation details.
- The wrapper should expose config-driven modes such as production run, diagnostic run, benchmark run, and regression run.
- Output should converge to one versioned TLTM schema: manifest, summary, history, observables, diagnostics, and provenance.
- Existing Stage3_4-facing outputs remain frozen until current TLTM construction/judgment work is complete.

## Refactorability Assessment

Safe now, as planning work:

- Define a summary/output contract for Stage2 and Stage3 scripts.
- Identify exact local update, swap, and history semantics that must stay fixed during modernization.
- Build a baseline matrix that covers accepted/rejected/failed local proposals and swap attempts.

Potentially safe after baselines:

- Split Stage2 driver into configuration resolution, slot initialization, local updates, swaps, history, and summary modules.
- Encapsulate summary counters in typed records if output text remains identical or intentionally versioned.
- Separate Metropolis acceptance from proposal generation API more clearly, preserving RNG order.

Blocked until Stage3_4 completion or explicit approval:

- Changing local Metropolis ratio or adding route-probability corrections.
- Changing history timing or sampled-slot convention.
- Changing swap flow-time reassignment semantics.
- Changing RNG draw order in production paths.
- Changing summary field names used by existing Stage3 scripts.

## Required Baselines

- Fixed-seed one-replica local update baseline for no-fallback and with-fallback/RG policies.
- Accepted proposal baseline: `x/z/jac`, Hamiltonian delta, solver route counters, reverse-gate counters.
- Rejected proposal baseline: live slot unchanged, proposal output captured if enabled, counters consistent.
- Swap baseline: pair proposal/accept counts, labels, effective energies, and history convention.
- Stage2 summary contract baseline: exact required header fields and route-stat fields.
- RNG-order baseline: a small run whose accept/reject sequence is compared before and after structural refactors.

## Open Questions For Confirmation

- Should Stage2 fixed max-flow-slot history remain the publication convention, or should modernization document/rename it more explicitly?
- Should summary outputs be frozen byte-for-byte for Stage3_4, or can they be versioned after current jobs complete?
- Should proposal symmetry/volume audit become a mandatory pre-refactor gate for any HMC/QN route change?

## Reverse Gate Decision - 2026-05-08
- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It is not merely a temporary debug guard or optional diagnostic mode.
- Modernization must preserve reverse-gate semantics, tolerance behavior, Jacobian comparison, replay accounting suppression, and live-slot identity on reject.
- Any future wrapper should expose this as part of the canonical p28 algorithm contract, not as an experimental add-on.
