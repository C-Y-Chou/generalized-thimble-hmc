# CV-005 Script Evidence Audit

Updated: 2026-05-12 JST

Scope: tracked files under `scripts/`, `codex/tasks/`, and
`codex/workspaces/fortran_modernization/tasks/`.

## Decision

CV-005 is closed for the current modernization tree by making script evidence
boundaries explicit and machine checked.

The audit registry is:

```text
codex/workspaces/fortran_modernization/state/SCRIPT_EVIDENCE_AUDIT_20260512.tsv
```

The gate is:

```text
python3 codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py --repo-root .
```

M4 now runs this gate. Any newly tracked helper, PBS script, config, wrapper, or
analysis script under the audited roots must receive an audit row before M4
evidence can pass.

## Current Evidence Scripts

Current scientific or governance evidence may use only rows marked as current
tiers:

- `current_evidence`
- `current_governance`
- `current_build`
- `current_control_plane`

Rows marked `historical_reference` are quarantined. They may be cited only as
historical/internal evidence and must not be used to claim current official
DFO-LS, final production, or current ODEX product behavior without a rerun or a
new audit row.

## Deep-Audit Findings

- The active current path is cleanly separated from historical helper scripts.
  Current gates use the canonical modernization route or local repo-derived
  paths.
- Old PBS scripts under ODEX, M6, and qn-error-handling validation are retained
  only as historical references. They include hardcoded old routes or retired
  worktree names and cannot support current official claims.
- `scripts/run_stage3_3_multiseed.py`,
  `scripts/merge_stage3_multiseed_chunks.py`, and
  `scripts/audit_tltm_tempering_protocol.py` remain the current Stage3 evidence
  tools. They are Python-3.6-safe for remote worker use.
- Official current evidence is limited to the explicit official DFO-LS gate,
  provenance/readback scripts, ODEX assist diagnostic readbacks, and the
  offline BTN residual comparison tool. Those tools carry explicit claim
  boundaries.
- Historical multichain and rescue-tuning scripts stay in tree for traceability,
  but they are not part of the current single-chain official-line modernization
  baseline.

## Reopen Rule

Reopen CV-005 if:

- a tracked file is added under the audited roots without a registry row;
- a historical/quarantined script is used to support a current official or
  publication claim;
- a current-tier script gains a legacy hardcoded route without an explicit
  route guard and audit update;
- a script's evidence role changes, for example from diagnostic/readback to
  production submission.

## Verification

The gate writes:

```text
output/tests/script_evidence_audit/CV005_script_evidence_audit_manifest.json
```

Expected status: `pass`.
