# M3 V0 Output Inventory And Protocol Audit Plan

Updated: 2026-05-10 JST
Scope: planning-only inventory and audit design for the current Stage1/Stage2/Stage3 output contract. No Fortran source, output writer, production workflow, or job submission changes are implied by this document.

## Purpose

M3 schema/wrapper work must not begin by repackaging the current files.

The immediate purpose of this document is to preserve three kinds of knowledge before any v1 output work starts:

- What the current `v0 compatibility` output surface writes.
- Which parts of that surface are physical/protocol data, solver diagnostics, legacy compatibility aliases, or analysis-script flattening.
- Which protocol-audit checks are needed before a publishable TLTM wrapper/schema can be considered safe.

This document complements `M3_TEMPERING_PROTOCOL_AND_OUTPUT_SCHEMA_DESIGN.md`. That file defines the desired protocol and v1 schema direction; this file records the source-backed v0 inventory and the audit/replay plan.

## Source Locations

Current v0 output is spread across source, scripts, and binary/history artifacts:

- `src/sampler/tltm_stage1_driver.f90`: Stage1 summary writer.
- `src/sampler/tltm_stage2_driver.f90`: Stage2 driver, local/swap schedule, summary writer, label trace, and history writers.
- `scripts/run_stage3_3_multiseed.py`: Stage3 multiseed orchestration and per-seed flattened CSV rows.
- `scripts/merge_stage3_multiseed_chunks.py`: aggregate method-level CSV/report merger.
- `src/analysis/evaluate_expectations.f90`: expectation/evaluation outputs consumed by Stage3 scripts.
- `src/diagnostics/constraint_failure_capture.f90`: failure-capture binary/meta side outputs.

## v0 Artifact Graph

The current output contract is not a single schema. It is a loose graph of artifacts:

- Stage1 summary text: replica-level local-transition, projection, flow-status, and reverse-gate diagnostics.
- Stage2 summary text: slot, pair, label, solver, flow-status, swap, accepted-route, and local-transition diagnostics.
- Stage2 label trace: mobile-label position and round-trip history.
- Stage2 binary histories: max-flow/cold-target history and optional all-replica histories.
- Constraint failure captures: binary state deltas, quasi traces, and failure metadata.
- Stage3 per-seed CSV: flattened parser output plus evaluation metrics and file references.
- Stage3 aggregate CSV/report: method-level aggregate observables and diagnostics.
- Evaluation outputs: observable ratio, denominator/sign information, jackknife/error information, and metadata.

Design consequence:

- v1 should be written beside v0 first.
- v1 should be derived from typed state/counters directly, not from lossy parsing of v0 text.
- v0 compatibility names must stay stable until a versioned reader/writer migration exists.

## Stage1 Summary Inventory

Stage1 summary header tags:

- `# TLTM stage-1 summary`
- `# replicas=`
- `# cycles=`
- `# local_updates=`
- `# elapsed_sec=`
- `# newton_eval_flow_status success zero_time stiff_rescue solver_assist failure_max_steps failure_invalid failure_h_min unknown`
- `# reverse_gate_replay_status success output_size_mismatch momentum_size_mismatch initial_force_failed constraint_failed final_flow_failed final_force_failed final_projection_failed reverse_gate_rejected final_flow_max_steps final_flow_invalid final_flow_h_min final_flow_non_strict_success unknown`
- `# qn_eval_flow_status success zero_time stiff_rescue solver_assist failure_max_steps failure_invalid failure_h_min unknown`
- `# local_transition_totals metropolis_reject reverse_gate_reject proposal_failure hamiltonian_invalid delta_h_invalid output_size_mismatch`

Stage1 replica table columns:

```text
replica_id
flow_time
accepts
rejects
accept_rate
projection_fail
samples
abs_mean_phi
runtime_sec
metropolis_reject
reverse_gate_reject
proposal_failure
hamiltonian_invalid
delta_h_invalid
output_size_mismatch
```

Stage1 semantic notes:

- `projection_fail` remains a v0 compatibility field and should not be used as the final v1 public name.
- The detailed local-transition columns are closer to publishable semantics than the older `projection_fail` alias, but their denominator must still be explicit in v1.
- Stage1 is a local-kernel characterization path, not the final TLTM tempering wrapper.

## Stage2 Summary Inventory

Stage2 summary scalar tags:

- `# TLTM stage-2 summary`
- `# slots=`
- `# cycles=`
- `# local_updates=`
- `# swap_enabled=`
- `# elapsed_sec=`
- `# total_round_trip=`

Stage2 solver and flow diagnostic tags:

- `# fallback_stats calls_total calls_integrating attempts success failure max_steps invalid h_min`
- `# constraint_stats total newton quasi failed ratio_newton ratio_quasi ratio_failed`
- `# quasi_stage_stats probe_attempt probe_success full_attempt full_success`
- `# quasi_class_stats local mid global`
- `# far_route_stats skip light anchor`
- `# near_rescue_stats candidate attempt success unusable`
- `# quasi_watchdog_stats hit used_sum used_max budget_last`
- `# far_investment_stats scope success fail fail_fast spent_success spent_fail`
- `# far_investment_units flowzr final success_flowzr success_final fail_flowzr fail_final`
- `# quasi_global_filter_stats candidate pass reject`
- `# newton_eval_flow_status success zero_time stiff_rescue solver_assist failure_max_steps failure_invalid failure_h_min unknown`
- `# reverse_gate_replay_status success output_size_mismatch momentum_size_mismatch initial_force_failed constraint_failed final_flow_failed final_force_failed final_projection_failed reverse_gate_rejected final_flow_max_steps final_flow_invalid final_flow_h_min final_flow_non_strict_success unknown`
- `# qn_eval_flow_status success zero_time stiff_rescue solver_assist failure_max_steps failure_invalid failure_h_min unknown`

Stage2 reverse-gate route diagnostic tags:

- `# reverse_gate_route_candidates total probe_only full_stage near_rescue nonnear_route class_local class_mid class_global far_skip far_light far_anchor`
- `# reverse_gate_route_pass total probe_only full_stage near_rescue nonnear_route class_local class_mid class_global far_skip far_light far_anchor`
- `# reverse_gate_route_reject total probe_only full_stage near_rescue nonnear_route class_local class_mid class_global far_skip far_light far_anchor`

Stage2 local-transition and accepted-local diagnostic tags:

- `# local_transition_totals metropolis_reject reverse_gate_reject proposal_failure hamiltonian_invalid delta_h_invalid output_size_mismatch`
- `# accepted_local_census_totals accepted_total newton_only quasi rescue probe_only full_stage near_rescue nonnear_route uncategorized`
- `# accepted_local_route_totals class_local class_mid class_global far_skip far_light far_anchor`

Stage2 accepted-local census table:

```text
[accepted_local_census]
slot_id
accepted_total
newton_only
quasi
rescue
probe_only
full_stage
near_rescue
nonnear_route
class_local
class_mid
class_global
far_skip
far_light
far_anchor
uncategorized
```

Stage2 slot table:

```text
[slots]
slot_id
label_id
flow_time
accepts
rejects
accept_rate
projection_fail
samples
abs_mean_phi
runtime_sec
metropolis_reject
reverse_gate_reject
proposal_failure
hamiltonian_invalid
delta_h_invalid
output_size_mismatch
```

Stage2 pair table:

```text
[pairs]
pair_id
slot_a
slot_b
proposals
accepts
rejects
accept_rate
last_accept_prob
```

Stage2 label table:

```text
[labels]
label_id
current_slot
farthest_slot_reached
round_trip_count
avg_round_trip_cycles
last_extreme
```

Stage2 semantic notes:

- Fixed slots own `slot_id` and `flow_time`.
- Mobile walkers are represented by `label_id`.
- Local updates and `measure_slot(...)` occur before the swap sweep in the current Stage2 cycle.
- Max-flow and all-replica histories are written before the swap sweep.
- Label trace is refreshed and written after the swap sweep.
- Pair stats currently expose accepted/rejected swap counts and the last acceptance probability, but not explicit invalid-current-energy, invalid-reflow, or invalid-proposed-energy categories.

## Stage3 Per-Seed Flattened Inventory

The Stage3 per-seed CSV row combines parsed Stage2 summary data, evaluation output, runtime metadata, and file references.

Core identity and failure-count fields:

```text
seed_id
method
projection_failure_count
unresolved_failure_count
fallback_trigger_count
```

Quasi route and solver-assist fields:

```text
quasi_probe_success_count
full_stage_trigger_count
full_stage_success_count
quasi_class_local_count
quasi_class_mid_count
quasi_class_global_count
far_route_skip_count
far_route_light_count
far_route_anchor_count
near_rescue_candidate_count
near_rescue_attempt_count
near_rescue_success_count
near_rescue_unusable_count
quasi_watchdog_hit_count
quasi_watchdog_used_sum
quasi_watchdog_used_max
quasi_watchdog_budget_last
far_investment_scope_count
far_investment_success_count
far_investment_fail_count
far_investment_fail_fast_count
far_investment_spent_success_count
far_investment_spent_fail_count
far_investment_flowzr_units
far_investment_final_units
far_investment_success_flowzr_units
far_investment_success_final_units
far_investment_fail_flowzr_units
far_investment_fail_final_units
quasi_global_filter_candidate_count
quasi_global_filter_pass_count
quasi_global_filter_reject_count
```

Dynamic parsed diagnostic families:

- `reverse_gate_*`: route candidate/pass/reject expansions.
- `newton_eval_flow_*`: flow-status expansions.
- `qn_eval_flow_*`: flow-status expansions.
- `reverse_gate_replay_*`: replay-status expansions.
- `local_*`: local-transition status expansions.

Accepted-local fields:

```text
accepted_local_total
accepted_local_newton_only_count
accepted_local_quasi_count
accepted_local_rescue_count
accepted_local_probe_only_count
accepted_local_full_stage_count
accepted_local_near_rescue_count
accepted_local_nonnear_route_count
accepted_local_uncategorized_count
accepted_local_class_local_count
accepted_local_class_mid_count
accepted_local_class_global_count
accepted_local_far_skip_count
accepted_local_far_light_count
accepted_local_far_anchor_count
```

Tempering and runtime fields:

```text
pair0_accept_rate
total_round_trip
avg_round_trip_cycles_if_observed
hot_end_hit_count
runtime_total
runtime_per_cycle
stage2_threads
eval_threads
stage2_init_mode
max_flow_time
schedule
```

Observable/evaluation fields:

```text
Ohat_re
Ohat_im
err_Ohat_re
err_Ohat_im
err_Ohat_valid
Zp_re
Zp_im
Zp_abs_max
Ohat
err_Ohat
Zp
```

Vector/string fields and file references:

```text
local_accept_rate_by_slot
pairwise_swap_acceptance_by_pair
farthest_slot_reached_by_label
summary_file
label_trace_file
stage2_log
eval_log
multichain_meta_file
all_replica_history_dir
```

## Stage3 Aggregate Inventory

Aggregate method-level fields include physical estimates, dispersion summaries, and summed/mean diagnostics:

```text
method
n_seeds
P68_re
P95_re
P68_im
P95_im
P68
P95
mean_Ohat_re
mean_Ohat_im
std_Ohat_re
std_Ohat_im
Zmean_re
Zmean_im
mean_Zp
median_abs_Zp
mean_Zp_re
mean_Zp_im
total_unresolved_failure_count
mean_projection_failure_count
mean_unresolved_failure_count
mean_quasi_probe_success_count
mean_full_stage_trigger_count
mean_pair0_accept_rate
mean_total_round_trip
mean_hot_end_hit_count
mean_runtime_total
median_runtime_total
```

Dynamic aggregate diagnostic families:

- `total_reverse_gate_*`
- `total_newton_eval_flow_*`
- `total_qn_eval_flow_*`
- `total_reverse_gate_replay_*`
- `total_local_*`

Aggregate semantic notes:

- Aggregate rows mix physics diagnostics, algorithm route diagnostics, and workflow performance diagnostics.
- v1 should separate these into observable, protocol, solver, flow, and runtime namespaces.
- Historical aggregate columns should remain in `compatibility/` until downstream readers are migrated.

## v0 Compatibility Names To Preserve For Now

These names are known to be legacy or partially misleading, but they are part of v0 compatibility:

- `projection_failure_count`: a broad historical failure counter, not the final public semantics.
- `proposal_failed`: compatibility boolean below the newer status surface.
- `fallback_*`: legacy output label that should map to solver-assist or deleted-rescue semantics depending on context.
- `final_resort_*`: compatibility alias for retained solver-internal assist fields where applicable.
- `final_resort_budget_*`: compatibility alias for QN solver-assist budget counters.
- `far_investment_final_*`: legacy effort-accounting name; v1 should clarify the denominator and whether "final" means final-flow or final residual unit.
- `quasi_global_filter_*`: retained compatibility group requiring a semantics review before public naming.

Rule:

- Do not rename these in-place.
- Add v1 names beside them, with an explicit migration map, after parser/audit coverage exists.

## v0 Semantic Hazards

The current output surface has several hazards that v1 must fix deliberately:

- Sample boundary is implicit: Stage2 histories/samples are currently post-local/pre-swap, while label trace is post-swap.
- Swap rejection causes are not fully decomposed in v0 pair stats.
- Counter denominators are sometimes implicit or mixed across proposals, residual evaluations, accepted proposals, failure captures, and seeds.
- Solver-assist diagnostics and historical Radau/JFNK/final-resort naming are partially conflated by compatibility columns.
- Stage3 per-seed rows flatten nested protocol state into wide columns, making schema evolution brittle.
- Physical observable fields are mixed with run metadata and solver diagnostics in the same CSV row.
- Binary history semantics are not declared by a machine-readable manifest.
- The current one-parity-per-cycle swap policy is a production policy, not merely an output detail.

## Protocol-Audit Tool Design

Future parser-only tool:

```text
scripts/audit_tltm_tempering_protocol.py
```

Initial scope:

- Read an existing Stage2 summary.
- Read the matching label trace if present.
- Optionally read Stage3 per-seed CSV rows for cross-checking.
- Emit a JSON and text audit report.
- Do not modify Fortran source, output writers, production workflow, or binary histories.

Suggested output:

```text
audit/
  protocol_audit.json
  protocol_audit.txt
```

Required JSON top-level sections:

- `input_files`
- `detected_v0_schema`
- `declared_or_inferred_protocol`
- `summary_parse`
- `accounting_checks`
- `label_trace_checks`
- `pair_swap_checks`
- `stage3_cross_checks`
- `known_unverifiable_from_v0`
- `verdict`

## Parser-Only Checks

The first audit tool can safely check existing artifacts without changing production output.

Summary parse checks:

- Required Stage2 tags are present.
- Required `[slots]`, `[pairs]`, and `[labels]` sections are present.
- Slot count, label count, and pair count match the summary header.
- Flow times remain attached to fixed slots.

Local-transition accounting checks:

- For each slot, `accepts + rejects` should match the expected local-attempt count for completed runs.
- For each slot, detailed local rejection categories should sum to `rejects` once the current status-surface contract is confirmed on a tiny fixture.
- Global `# local_transition_totals` should equal the sum of per-slot detailed local rejection columns.
- `accept_rate` should equal `accepts / (accepts + rejects)` within formatting tolerance.

Pair accounting checks:

- For each adjacent pair, `proposals = accepts + rejects`.
- `accept_rate = accepts / proposals` when proposals are nonzero.
- Pair proposal counts should match the v0 one-parity-per-cycle schedule:
  odd cycles attempt `(0,1),(2,3),...`; even cycles attempt `(1,2),(3,4),...`.
- `last_accept_prob` should be finite and within `[0,1]` for pairs with valid proposals.

Label-trace checks:

- Each recorded cycle should contain exactly one row per label.
- Each recorded cycle should map labels to unique slots.
- Slot IDs in the trace should be within the summary slot range.
- Round-trip counts should be nondecreasing per label.
- Farthest-slot and hot-end indicators inferred from trace should agree with Stage3 flattened fields when available.

Protocol declaration checks:

- Current timing should be reported explicitly as `local_update -> swap -> measure/history/label_trace`.
- The audit report should mark this as the selected replica-exchange-style convention for regenerated datasets.
- If a future manifest declares a different timing, the audit should fail unless the output files also carry a schema-version transition.

Stage3 cross-checks:

- `pair0_accept_rate` in Stage3 should match pair 0 from Stage2.
- `total_round_trip` should match Stage2 label totals.
- `local_accept_rate_by_slot` should match Stage2 slot accept rates.
- Stage3 dynamic `total_*` fields should match parsed Stage2 diagnostic totals.

## Checks Not Verifiable From Current v0 Alone

Some correctness properties cannot be proven from the existing files alone:

- Exact swap energy delta `E_proposed - E_current` for each attempted swap.
- Whether a failed swap reflow left slot states bitwise unchanged.
- Whether current-energy failure and proposed-energy failure are distinguishable.
- Whether a history sample was written before or after a specific successful swap without source knowledge.
- Whether a local rejected proposal left every live state component unchanged.
- Whether all RNG draw points are preserved across refactors.

These need either source-level tests, opt-in diagnostic output, or deterministic replay fixtures.

## Replay And Source-Level Audit Design

Second-stage audit fixture:

```text
tests/test_tltm_swap_kernel_contract.f90
```

Target checks:

- Construct or load two adjacent-slot states with known flow times.
- Compute current energies using `Re S(z) - log |det J|`.
- Reflow each base coordinate to the opposite slot.
- Compute proposed energies.
- Verify the swap acceptance probability equals `min(1, exp(-delta))`.
- Verify invalid reflow is converted to rejection and does not mutate live slot state.

Third-stage optional diagnostic writer:

```text
diagnostics/swap_attempt_audit.csv
```

This should be opt-in only, disabled by default, and never part of v0 compatibility output unless explicitly approved.

Suggested columns:

```text
sweep
pair_id
slot_a
slot_b
label_a_before
label_b_before
energy_a_current
energy_b_current
energy_a_proposed
energy_b_proposed
delta_energy
accept_probability
rng_draw_used
accepted
failure_reason
label_a_after
label_b_after
```

Diagnostic writer gate:

- Do not add this until parser-only audit exists.
- Do not add this to production default outputs.
- If enabled in fixed-seed test mode, confirm it does not alter RNG draw order, proposal route, or output schema when disabled.

## Baselines Required By Change Type

Parser-only audit script:

- `git diff --check`.
- Run audit on at least one existing Stage2 output fixture or tiny local Stage2 smoke output.
- Confirm no source or output-writer changes.

Source-level swap-kernel test:

- `git diff --check`.
- Clean build of the relevant test executable.
- Deterministic test pass.
- No Stage2 summary/schema changes.

Optional diagnostic writer:

- Disabled-by-default smoke confirming v0 summary byte/field compatibility where practical.
- Enabled tiny diagnostic run confirming audit CSV content and no production path dependency.
- Explicit user approval if the diagnostic writer changes any public output directory layout.

v1 manifest/protocol writer:

- Existing Stage3 parser must still parse v0 compatibility output.
- v1 manifest must record `schema_version`, `git_commit`, resolved config, env overrides, flow ladder, sweep schedule, measurement boundary, seed policy, and compatibility-output status.
- Observable values derived through v1 readers must match current evaluation outputs on a deterministic fixture.

Sweep-order or measurement-boundary change:

- Explicit user approval required.
- Fixed-seed route/counter comparison required.
- Physical observable comparison required.
- This is behavior-changing for finite runs even if the invariant target distribution is unchanged.

## Recommended Implementation Sequence

M3b.1: v0 inventory and protocol-audit plan.

- This document.
- No code changes.

M3b.2: parser-only audit script.

- Parse Stage2 summary and label trace.
- Emit audit JSON/text.
- Check accounting and label-trace invariants.
- Implemented as `scripts/audit_tltm_tempering_protocol.py` on 2026-05-10 JST.
- Verification: `py_compile`, eight existing `output/tests/*stage2*summary.dat` plus matching label traces, and a synthetic Stage3 per-seed cross-check fixture passed.

M3b.3: deterministic swap-kernel contract test.

- Source-level test of TLTM exchange energy and rejection semantics.
- No output writer changes.
- Implemented as `tests/test_tltm_swap_kernel_contract.f90` on 2026-05-10 JST.
- Verification: `make -C build FC=gfortran LDFLAGS= test_tltm_swap_kernel_contract` passed.

M3b.4: v1 manifest/protocol writer beside v0.

- Add machine-readable protocol metadata without removing or renaming v0 fields.
- Preserve Stage3 parser compatibility.
- Implemented on 2026-05-10 JST as opt-in `v1alpha1` sidecars.
- Env controls:
  - `TLTM_STAGE2_V1_OUTPUT_DIR`: writes `manifest.json`, `protocol.json`, and the minimal v1alpha diagnostics/observables package under that directory.
  - `TLTM_STAGE2_V1_MANIFEST_FILE`: writes only a manifest sidecar unless paired with other v1 envs.
  - `TLTM_STAGE2_V1_PROTOCOL_FILE`: writes only a protocol sidecar unless paired with other v1 envs.
- Default behavior: no v1 sidecar files are written unless one of these env vars is set.
- Compatibility: v0 summary, label trace, histories, Stage3 parser expectations, cycle order, sample boundary, and RNG behavior are unchanged.

M3b.5: v1 observables/diagnostics package.

- Separate physical observables, protocol diagnostics, solver diagnostics, runtime metadata, and compatibility outputs.
- Add readers before deprecating old columns.
- Minimal implemented package under `TLTM_STAGE2_V1_OUTPUT_DIR`:
  - `diagnostics/local_transition_summary.csv`
  - `diagnostics/swap_summary.csv`
  - `diagnostics/label_summary.csv`
  - `observables/per_slot_phase_summary.csv`
- `scripts/audit_tltm_tempering_protocol.py` now reads optional `--manifest` and `--protocol` sidecars and checks schema/timing/flow-ladder/control consistency plus diagnostics file row counts.

M3b.6: wrapper sweep-order decision.

- Decision recorded 2026-05-10 JST: do not preserve old dataset timing. Regenerate datasets after adopting the standard replica-exchange-style `local update -> swap -> measure/history/label trace` boundary.
- `swap -> local -> measure` remains a valid paper-aligned alternative but is not the selected convention for this codebase.

## Stop Gates

Stop and ask before implementing if the next patch would:

- Change Stage2 cycle order.
- Change history/sample timing.
- Change label trace timing.
- Change swap proposal order or parity schedule.
- Add default-on output files.
- Rename or remove v0 columns.
- Change RNG draw points.
- Change current Stage3 parser expectations.
- Reinterpret compatibility counters without a migration map.

## Current Recommendation

The safest immediate next code step is Stage3 propagation of the already opt-in sidecar/audit contract.

The next executable step after the protocol-timing change is:

- let Stage3 multiseed runs opt into `TLTM_STAGE2_V1_OUTPUT_DIR` per seed/method;
- append sidecar and audit paths/verdicts to the per-seed CSV without removing v0 columns;
- run parser-only protocol audit/readback on Stage2 outputs and sidecars;
- preserve those metadata columns through chunk merge;
- defer official dataset regeneration until the M6 pre-dataset gate.
