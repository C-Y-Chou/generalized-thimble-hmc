# M6 Provenance And Reference Readback Checklist

Updated: 2026-05-10 JST

Scope: checklist for verifying that v1alpha sidecars, Stage3 summaries, and protocol-audit outputs are sufficient for the modernization workstream to interpret and reuse TLTM reference packages. This is not the Stage3_4 production-completion plan.

## Required Files Per Seed

For sidecar-enabled Stage3 runs, each seed output directory should contain:

- `run_manifest.json`
- `tltm_stage2_summary.dat`
- `tltm_stage2_label_trace.dat`
- `stage2_v1alpha/manifest.json`
- `stage2_v1alpha/protocol.json`
- `stage2_v1alpha/diagnostics/local_transition_summary.csv`
- `stage2_v1alpha/diagnostics/swap_summary.csv`
- `stage2_v1alpha/diagnostics/label_summary.csv`
- `stage2_v1alpha/observables/per_slot_phase_summary.csv`
- `protocol_audit.json`
- `protocol_audit.txt`

## Required Stage3 Summary Columns

`per_seed_summary_table.csv` and merged outputs must preserve:

- `stage2_v1_sidecar_enabled`
- `stage2_v1_output_dir`
- `stage2_v1_manifest_file`
- `stage2_v1_protocol_file`
- `stage2_protocol_audit_json`
- `stage2_protocol_audit_text`
- `stage2_protocol_audit_verdict`
- `stage2_protocol_audit_errors`
- `stage2_protocol_audit_warnings`
- `stage2_protocol_audit_checks`

Expected reference-package values:

- `stage2_v1_sidecar_enabled == 1`
- `stage2_protocol_audit_verdict == pass`
- error count is zero
- manifest/protocol paths resolve from the repo/output root

## Manifest Readback

Check `manifest.json` declares:

- `schema_version == tltm.stage2.manifest.v1alpha1`
- `writer_version`
- `git_commit`
- `algorithm_id`
- `canonical_route_id`
- `flow_policy_id`
- `reverse_gate_policy_id`
- `tempering_protocol_id`
- `sweep_order == local_update_swap_measure_history_label_trace`
- `measurement_boundary == post_swap`
- `label_trace_boundary == post_swap`
- `flow_ladder`
- `resolved_stage2_controls`
- `env_overrides`
- diagnostics and observables file paths

Cross-check against v0 Stage2 summary:

- cycle count
- local updates
- swap-enabled flag
- slot count
- flow ladder values
- transition counter row counts where available

## Protocol Readback

Check `protocol.json` declares:

- `schema_version == tltm.stage2.protocol.v1alpha1`
- protocol id matching the manifest `tempering_protocol_id`
- target-density definitions
- local HMC/RATTLE kernel policy
- strict final-flow proposal policy
- failure-as-rejection semantics
- reverse-gate policy
- adjacent-swap acceptance probability
- invalid-reflow rejection semantics
- sweep schedule with post-swap measurement

## Audit Commands

Per seed:

```bash
python3 scripts/audit_tltm_tempering_protocol.py \
  --summary <seed_dir>/tltm_stage2_summary.dat \
  --label-trace <seed_dir>/tltm_stage2_label_trace.dat \
  --manifest <seed_dir>/stage2_v1alpha/manifest.json \
  --protocol <seed_dir>/stage2_v1alpha/protocol.json \
  --fail-on error \
  --out-json <seed_dir>/protocol_audit.json \
  --out-text <seed_dir>/protocol_audit.txt
```

Stage3 sidecar-aware orchestration should run this automatically when:

```bash
--stage2-v1-sidecars on --stage2-protocol-audit auto
```

## Merge Readback

After chunk merge, confirm:

- `protocol_audit_summary.csv` exists.
- every row has audit verdict `pass`.
- merged `per_seed_summary_table.csv` preserves all sidecar/audit metadata columns.
- sidecar paths still resolve or are relocatable by documented output-root rules.

## Failure Conditions

Treat these as M6 blockers before a run or registered package is accepted as a modernization reference:

- missing v1 manifest/protocol file
- invalid JSON sidecar
- manifest/protocol schema version mismatch
- sweep order or measurement boundary mismatch
- flow ladder mismatch between manifest and Stage2 summary
- missing Stage3 sidecar metadata columns
- audit verdict not `pass`
- sidecar path lost during chunk merge
- v0 compatibility summary no longer parseable

## Current Guardrail Coverage

`make -C build modernization_guardrails` currently verifies:

- direct env reads are centralized
- Stage2/evaluation builds and ODEX/swap tests pass
- Stage3 sidecar dry-run works
- existing Stage2 protocol audit smoke works
- tiny sidecar-on Stage3 smoke records sidecar metadata and audit pass
- tiny sidecar-off Stage3 smoke keeps sidecars disabled
- chunk merge preserves sidecar metadata and audit summary

This is sufficient for local preflight. A modernization-generated reference package still requires the full 10k -> 50k -> 100k validation ladder or an explicitly approved narrower baseline; Stage3_4 provides workflow context, not a required result dependency.
