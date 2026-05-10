# M6 Reference Dataset Triage - 2026-05-10

Updated: 2026-05-10 21:35 JST

Scope: read-only triage of M6 R1-R4 reference dataset generation on `fortran_modernization_m6_active`.

Final superseding note, 2026-05-10 22:50 JST: R4 chunk `14674` and merge `14675` completed with `Exit_status=0`; R1-R4 are accepted. Use `M6_REFERENCE_DATASET_READBACK_20260510.md` as the current readback record. This file is retained as the historical mid-run triage snapshot.

Remote worktree safety:

- Semantic target id: `fortran_modernization_m6_active`
- Physical path: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Branch: `codex/qn-error-handling-validation`
- Pinned commit: `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`
- Action boundary: do not fast-forward, rename, or clean this worktree while active/pending jobs remain.

## Summary

- R1 is structurally generated and merged.
- R2 is structurally generated and merged.
- R3 is structurally generated and merged. Replacement job `14669` and merge job `14670` both completed with `Exit_status=0`.
- R4 is still in progress. `no_fb` has complete chunk rows; `fb_norefine` is waiting on `chunk_15` job `14674`, with merge job `14675` held.
- The probe/resubmission record is `M6_QUEUE_PROBE_AND_RESUBMISSION_20260510.md`.

## Current PBS Snapshot

From `codex/state/JOBS.tsv` refreshed at `2026-05-10T21:34:56+09:00`:

- R3 active/pending: none.
- R3 completed jobs: `14669.anode01` and `14670.anode01`, both `Exit_status=0`.
- R4 active/pending: `14671.anode01` and `14674.anode01` are running; merge `14675.anode01` is held.
- R4 completed probe replacements: `14672.anode01` and `14673.anode01`, both `Exit_status=0`.
- Superseded queued jobs: `14657`, `14645`, `14649`, `14660`, `14662`.
- Superseded held merge jobs: `14658`, `14663`.

## Package Readiness

| Level | Status | Readback interpretation |
| --- | --- | --- |
| R1 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R2 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R3 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R4 | in progress | Package-level merge files absent as expected; `fb_norefine/chunk_15` is still running and merge is held. |

## Structural Checks

R1:

- package files: `reference_aggregate_comparison.csv`, `reference_manifest.json`, `reference_registry_rows.tsv` exist.
- aggregate comparison rows: `2`.
- manifest status: `generated_pending_readback`.
- `no_fb`: `4/4` per-seed rows; protocol audit `4 rows, 0 bad`.
- `fb_norefine`: `4/4` per-seed rows; protocol audit `4 rows, 0 bad`.

R2:

- package files: `reference_aggregate_comparison.csv`, `reference_manifest.json`, `reference_registry_rows.tsv` exist.
- aggregate comparison rows: `2`.
- manifest status: `generated_pending_readback`.
- `no_fb`: `10/10` per-seed rows; protocol audit `10 rows, 0 bad`.
- `fb_norefine`: `10/10` per-seed rows; protocol audit `10 rows, 0 bad`.

R3:

- package files: `reference_aggregate_comparison.csv`, `reference_manifest.json`, `reference_registry_rows.tsv` exist.
- replacement job `14669` and merge job `14670` completed with `Exit_status=0`.
- `no_fb`: `32/32` per-seed rows; protocol audit `32 rows, 0 bad`.
- `fb_norefine`: `32/32` per-seed rows; protocol audit `32 rows, 0 bad`.

R4:

- package-level merge files: absent.
- probe-optimized replacement chunks:
  - `no_fb/chunk_04` -> `14671`, still running on `C8`; chunk output already has `8` rows and audit `bad=0`.
  - `no_fb/chunk_13` -> `14673`, completed with `Exit_status=0`.
  - `fb_norefine/chunk_06` -> `14672`, completed with `Exit_status=0`.
  - `fb_norefine/chunk_15` -> `14674`, still running on `C8`; chunk output not yet present at readback.
- current row status:
  - `no_fb`: `128/128` chunk rows; protocol audit `bad=0`.
  - `fb_norefine`: `120/128` chunk rows; protocol audit `bad=0` for completed chunks.
- merge job `14675` is held pending dependencies.

## Recommendation

- Continue monitoring `14674` and held merge job `14675`.
- R1-R3 are ready for full M6 readback while R4 continues if needed.
- After R4 merge completes, run full M6 package readback and update `state/M6_REFERENCE_PACKAGES.tsv`.
- If any queued replacement chunk fails with `Exit_status != 0`, repair through the scheduler policy: cancel/supersede, remove only that chunk's partial output/log directory, resubmit CPU-only replacement, and rebuild merge dependency.
