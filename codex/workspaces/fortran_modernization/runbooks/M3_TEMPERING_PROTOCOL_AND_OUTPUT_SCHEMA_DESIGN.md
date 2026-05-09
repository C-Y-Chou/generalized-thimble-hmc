# M3 Tempering Protocol And Output Schema Design

Updated: 2026-05-10 JST
Scope: design-only contract for TLTM tempering correctness and the future versioned output schema. No Fortran source, output writer, production workflow, or job submission changes are implied by this document.

## Purpose

The output schema must describe the correct TLTM tempering process, not merely repackage the current Stage2/Stage3 files.

The design therefore has two layers:

- Tempering protocol contract: combine TLTM-specific rules with standard replica-exchange / parallel-tempering invariants.
- Output schema contract: represent that protocol with versioned, machine-readable files while keeping current Stage-facing outputs as `v0 compatibility`.

## References And Scope

TLTM-specific rules:

- `references/1912.13303_TLTM_HMC.pdf`: HMC implementation on TLTM.
- `references/2311.10663v4.pdf`: constrained HMC / RATTLE / simplified Newton mechanics used by the local kernel.
- `references/new_algorithm__Copy_.pdf`: project-specific p28 BTN/backflow rescue and QN loss design.

Standard tempering rules:

- Swendsen and Wang, replica Monte Carlo simulation.
- Geyer, Markov chain Monte Carlo maximum likelihood.
- Hukushima and Nemoto, exchange Monte Carlo method.

Design principle:

- TLTM defines the flowed-surface measures, phase reweighting, flow-time tempering parameter, and swap acceptance in terms of flowed configurations and Jacobians.
- Standard replica exchange supplies the production workflow requirements: fixed zones, mobile labels/walkers, local invariant kernels, swap invariant kernels, explicit sweep schedule, equilibration, round-trip/flow-ladder diagnostics, and measurement-boundary conventions.

## TLTM Measure Contract

For each flow time `t_a`, the flowed surface is `Sigma_ta = z_ta(R^N)`.

The per-replica target density can be represented in base coordinates `x` as

```text
pi_a(x) proportional to |det J_ta(x)| * exp(-Re S(z_ta(x)))
```

Equivalently, the effective real energy is

```text
E_a(x) = Re S(z_ta(x)) - log |det J_ta(x)|
```

The phase-reweighted observable at a chosen flow time is

```text
<O> = < exp(i theta(z)) O(z) >_Sigma / < exp(i theta(z)) >_Sigma
```

where the phase includes the residual Jacobian phase and the imaginary action phase.

Schema implication:

- `energy_real`, `log_abs_det_jacobian`, `phase_jacobian`, `phase_action`, and `phase_total` should be conceptually separate in v1 even if v0 only writes derived histories.
- Per-flow-time observable estimates must record their denominator/sign-average, not only the final ratio.
- The flow-time independence check of reweighted observables is part of TLTM correctness, not a cosmetic diagnostic.

## Replica-Exchange Protocol Contract

The simulation state must distinguish fixed zones from mobile walkers.

Fixed zone:

- `slot_id`.
- `flow_time`.
- local kernel policy.
- local counters and per-zone samples.

Mobile walker:

- `label_id`.
- base coordinate `x_seed` or full state representation.
- current slot.
- round-trip state.

Slot state representation:

- At slot `a`, a walker with base coordinate `x` is represented as `z_ta(x)` and `J_ta(x)`.
- The flow time belongs to the slot, not to the walker identity.
- A swap exchanges base configurations between fixed slots; it does not exchange the slot flow times.

Local kernel invariant:

- For every fixed slot `a`, the local transition kernel must preserve `pi_a`.
- HMC/RATTLE proposal failure is a legal rejection and must leave the slot state unchanged.
- Reverse gate is part of the canonical p28 proposal validity boundary.
- Solver-internal ODE assist may help NT/QN residual evaluation, but strict final `flow(...)` must construct accepted physical states.

Swap kernel invariant:

- For adjacent slots `a,b`, propose exchanging base configurations `x,y`.
- The proposed states are `z_ta(y)` and `z_tb(x)`.
- Accept with

```text
min(1, pi_a(y) pi_b(x) / (pi_a(x) pi_b(y)))
```

or equivalently

```text
min(1, exp(-[(E_a(y) + E_b(x)) - (E_a(x) + E_b(y))]))
```

- If reflowing either base configuration to the other slot fails, the swap proposal is rejected.
- The RNG draw point for a valid finite swap proposal is behavior and must be baselined before refactors.

Sweep schedule invariant:

- A production wrapper must declare its sweep order and measurement boundary.
- Alternating even/odd adjacent-pair sub-sweeps are the standard parallelizable exchange schedule.
- The schedule order can be valid in more than one form because local and swap kernels each preserve the product target, but the chosen convention affects autocorrelation, labels, histories, and reproducibility.

## Current Stage2 Protocol Audit

Source-backed current behavior:

- `src/sampler/tltm_stage2_driver.f90` initializes fixed slots with `slot_id`, `label_id`, `flow_time`, `x`, `z`, and `jac`.
- `run_local_updates(...)` applies `metropolis_step(...)` to each fixed slot and records detailed local transition counters.
- `attempt_adjacent_swap(...)` reflows `slot_b%x` at `slot_a%flow_time` and `slot_a%x` at `slot_b%flow_time`, computes `Re S - Re logdetJ`, and accepts with `exp(-delta)`.
- On accepted swap, the code assigns the reflowed states to the fixed slots and swaps `label_id`.
- If the current or proposed swap energies cannot be computed, the swap is rejected with probability zero.
- Pairing alternates parity by cycle: odd cycles attempt `(0,1),(2,3),...`; even cycles attempt `(1,2),(3,4),...`.

Preliminary assessment:

- The swap acceptance formula matches the TLTM base-coordinate exchange rule when `compute_effective_energy = Re S - Re logdetJ`.
- The accepted-swap state update is conceptually correct for fixed flow-time zones and mobile labels.
- Flow failure as swap rejection is compatible with the TLTM zero/invalid-flow rejection rule.
- The code uses one parity sub-sweep per cycle, whereas the 1912 example repeats multiple swap sub-sweeps with alternating pairings. This is not automatically wrong, but it is a production policy choice that must be explicit in v1.
- Current Stage2 measurement and history timing are v0 conventions, not yet a publishable protocol contract.

Important v0 timing detail:

- Within each Stage2 cycle, local updates and `measure_slot(...)` happen before the swap sweep.
- Max-flow and all-replica histories are also written before the swap sweep.
- Label trace is refreshed and written after the swap sweep.
- Therefore v0 mixes a `post-local/pre-swap` sample stream with a `post-swap` label trace. This can be valid as a historical output convention, but v1 must not leave this implicit.

## Canonical v1 Tempering Recommendation

For a future unified wrapper, use an explicit sweep contract:

```text
for sweep k:
  1. attempt configured adjacent swap sub-sweeps
  2. refresh labels and round-trip state
  3. run local HMC/RATTLE updates independently in each fixed slot
  4. measure and write samples at the declared measurement boundary
```

Rationale:

- This follows the ordering described in the 1912 HMC-on-TLTM example: swap first, then transitions on flowed surfaces, then measurements.
- Labels and measured slot states are aligned at the same declared cycle boundary.
- It separates sweep scheduling from output writing, making future parallel implementation easier.

Compatibility warning:

- Changing Stage2 from v0 `post-local/pre-swap` sampling to v1 `post-swap/local/measure` timing is behavior-changing for finite runs and must not be done silently.
- v0 compatibility writers should preserve current timing until an explicit wrapper/schema migration is approved.

Allowed v1 alternatives:

- A wrapper may choose `local -> swap -> measure` instead if declared in the manifest and validated by fixed-seed baselines.
- What is forbidden is an undocumented measurement boundary.

## v0 Output Inventory

v0 consists of several related but not unified artifacts:

- Stage1 summary text: replica-level local transition and flow-status diagnostics.
- Stage2 summary text: slot, pair, label, local transition, solver, flow-status, reverse-gate, and accepted-route diagnostics.
- Stage2 label trace: `cycle label_id slot_id round_trip_count`.
- Stage2 cold/max-flow history: binary `z_history.dat` and `phi_history.dat` for a fixed max-flow slot, currently sampled before swap.
- Optional all-replica histories: per-slot binary histories, currently sampled before swap.
- Constraint failure capture files: binary `z0`, `delz`, `x0` snapshots plus quasi trace CSV and failure-meta CSV.
- Stage3 per-seed CSV: parsed and flattened Stage2/evaluation metrics.
- Stage3 aggregate CSV/report: per-method aggregate physical and diagnostic summaries.
- Evaluation output: multichain observable metadata, jackknife information, and expectation summaries.

v0 compatibility names that should not be renamed in place:

- `projection_failure_count`.
- `proposal_failed`.
- `final_resort_*`.
- `final_resort_budget_*`.
- `far_investment_final_*`.
- `quasi_global_filter_*` compatibility columns.

v0 design problem:

- Some names describe old implementation history rather than current semantics.
- Some counters lack explicit denominators.
- Physical observables, sampling protocol, solver diagnostics, output paths, and provenance are spread across multiple files.
- Timing convention is implicit and partly mixed across sample/history/label outputs.

## v1 Output Package Design

Recommended package root:

```text
run/
  manifest.json
  protocol.json
  config.resolved.json
  observables/
    per_slot_observables.csv
    fit_window_summary.json
    jackknife_summary.csv
  samples/
    slot_samples.meta.json
    cold_or_target_history.dat
    all_slot_histories/
  diagnostics/
    local_transition_summary.csv
    swap_summary.csv
    label_trajectory.csv
    solver_summary.csv
    flow_status_summary.csv
    reverse_gate_summary.csv
    failure_capture_manifest.json
  compatibility/
    stage2_summary_v0.dat
    per_seed_summary_table_v0.csv
    aggregated_summary_table_v0.csv
```

`manifest.json` required fields:

- `schema_version`.
- `writer_version`.
- `git_commit`.
- `algorithm_id`.
- `canonical_route_id`.
- `flow_policy_id`.
- `reverse_gate_policy_id`.
- `tempering_protocol_id`.
- `sweep_order`.
- `measurement_boundary`.
- `flow_ladder`.
- `seed_policy`.
- `config_digest`.
- `config_file`.
- `env_overrides`.
- `output_units`.
- `compatibility_outputs_written`.

`protocol.json` required fields:

- `target_density`: formula and field names used for `E_a(x)`.
- `local_kernel`: HMC/RATTLE policy, proposal-failure handling, final-flow strictness, reverse-gate requirement.
- `swap_kernel`: adjacent exchange policy, invalid-reflow rejection, acceptance-energy definition.
- `sweep_schedule`: parity pattern, number of swap sub-sweeps per measurement, local updates per sweep.
- `measurement_policy`: slots sampled, sample timing, burn-in/warmup handling, thinning if any.
- `history_policy`: fixed slot versus mobile label convention, binary dtype/order, phase history definition.
- `equilibration_policy`: required diagnostics for round trips, per-slot observable consistency, and sign averages.

## v1 Tables And Counters

`observables/per_slot_observables.csv`:

- `slot_id`.
- `flow_time`.
- `n_samples`.
- `phase_mean_re`.
- `phase_mean_im`.
- `phase_abs_mean`.
- `observable_name`.
- `numerator_re`.
- `numerator_im`.
- `denominator_re`.
- `denominator_im`.
- `estimate_re`.
- `estimate_im`.
- `err_re`.
- `err_im`.
- `autocorr_method`.
- `sample_boundary`.

`diagnostics/local_transition_summary.csv`:

- `slot_id`.
- `flow_time`.
- `attempt_count`.
- `accepted_count`.
- `metropolis_rejected_count`.
- `proposal_construction_failed_count`.
- `reverse_gate_rejected_count`.
- `hamiltonian_invalid_count`.
- `delta_h_invalid_count`.
- `output_size_mismatch_count`.

`diagnostics/swap_summary.csv`:

- `pair_id`.
- `slot_a`.
- `slot_b`.
- `flow_time_a`.
- `flow_time_b`.
- `attempt_count`.
- `accepted_count`.
- `metropolis_rejected_count`.
- `invalid_current_energy_count`.
- `invalid_reflow_count`.
- `invalid_proposed_energy_count`.
- `last_accept_probability`.
- `mean_accept_probability`.
- `sweep_parity`.

`diagnostics/label_trajectory.csv`:

- `sweep`.
- `label_id`.
- `slot_id`.
- `flow_time`.
- `round_trip_count`.
- `last_extreme`.
- `sample_boundary`.

`diagnostics/solver_summary.csv`:

- Newton/QN attempt and success counts.
- QN route counts.
- accepted-route census.
- solver-assist counters.
- denominator fields for each group: residual evaluations, local proposals, accepted local proposals, or failure captures.

`diagnostics/flow_status_summary.csv`:

- `context`: initialization, local residual, QN residual, final proposal, swap reflow, history reflow if applicable.
- strict success, zero-time success, solver-assist success, max-step failure, invalid-state failure, h-min failure, unknown.

`diagnostics/reverse_gate_summary.csv`:

- route candidate/pass/reject counts.
- replay status counts.
- tolerance and max-difference summaries if enabled.
- suppression policy for nested replay counters.

## v0 To v1 Migration Map

Compatibility mappings:

- `projection_failure_count` maps to a v1 sum over proposal-construction and proposal-boundary failure categories, not to ordinary Metropolis rejection.
- `proposal_failed` maps to `proposal_construction_failed` or boundary-failed categories depending on transition status.
- `final_resort_*` maps to `solver_assist_*` when it refers to retained residual-evaluation assist.
- Radau/JFNK `final_resort` historical fields map to explicit zero-valued legacy compatibility fields unless source support is reintroduced.
- `far_investment_final_*` maps to solver-assist effort counters with explicit denominator.
- `quasi_global_filter_*` remains a legacy compatibility group until a retained semantics review decides whether it is still meaningful.
- Stage3 `Ohat*`, `err_Ohat*`, `Zp*` map to `observables/per_slot_observables.csv` plus `fit_window_summary.json`.

Migration rule:

- v1 should be generated beside v0 first.
- v0 parser readback must remain unchanged.
- v1 should be derived from the same state/counters as v0, not from lossy parsing of v0 text.
- Only after v1 readers exist may compatibility field deprecation be discussed.

## Required Correctness Gates Before Implementing v1 Writers

Tempering protocol audit:

- Verify local kernel invariance boundaries: accepted/rejected/failed local proposals leave states and labels as expected.
- Verify swap kernel formula by replaying a small fixed pair and checking `delta = E_proposed - E_current`.
- Verify invalid reflow causes swap rejection without state mutation.
- Verify label swaps track mobile walkers and fixed slots keep flow times.
- Verify measurement boundary and history boundary are explicitly recorded.

Schema compatibility gate:

- Run a tiny Stage2 smoke and parse v0 summary with the existing Stage3 parser.
- Confirm old columns and summary tags remain present.
- Confirm v1 manifest declares the same git commit, config, ladder, seed, and policy metadata.

Observable gate:

- For a deterministic small run, v1 per-slot observable estimates derived from histories must match the current evaluation output within parser tolerance.
- Sign/phase denominators must be explicitly present.

Regression gate:

- Any change to sweep order, sample timing, history convention, or label trace timing is behavior-changing and requires user approval plus fixed-seed route/counter and observable comparison.

## Open Decisions

These require user confirmation before code changes:

- Final v1 wrapper sweep order: keep v0 timing for compatibility, adopt paper-aligned `swap -> local -> measure`, or adopt standard `local -> swap -> measure`.
- Which slot(s) are publication-observable targets: max-flow slot, fit window over high-flow slots, or all slots with automatic constant-fit selection.
- Whether v1 should write histories for fixed slots, mobile labels, or both.
- Whether current one-parity-swap-per-cycle policy is sufficient, or whether the wrapper should support multiple alternating swap sub-sweeps per measurement.
- Final public names for legacy `projection_failure_count` and solver-assist fields.

## Recommendation

Do not start by editing output writers.

The best next implementation sequence is:

- Finish this protocol/schema design.
- Use `M3_V0_OUTPUT_INVENTORY_AND_PROTOCOL_AUDIT_PLAN.md` as the source-backed v0 column inventory and audit contract.
- Add a tiny protocol-audit parser or replay tool that checks current Stage2 timing and swap formula without changing production code.
- Only then add v1 manifest/protocol files beside v0 outputs.
- Defer any sweep-order or history-timing change until after explicit user approval and baseline comparison.
