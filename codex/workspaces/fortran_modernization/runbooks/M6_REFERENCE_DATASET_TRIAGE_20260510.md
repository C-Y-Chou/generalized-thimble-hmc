# M6 Reference Dataset Triage - 2026-05-10

Updated: 2026-05-10 19:45 JST

Scope: read-only triage of M6 R1-R4 reference dataset generation on `fortran_modernization_m6_active`.

Remote worktree safety:

- Semantic target id: `fortran_modernization_m6_active`
- Physical path: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Branch: `codex/qn-error-handling-validation`
- Pinned commit: `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`
- Action boundary: do not fast-forward, rename, or clean this worktree while active/pending jobs remain.

## Summary

- R1 is structurally generated and merged.
- R2 is structurally generated and merged.
- R3 is still in progress; the previous queued `C8-LONG` chunk was superseded by probe-optimized job `14669`, now running on `C12`, with merge job `14670` held.
- R4 is still in progress; previous queued `C8-LONG` chunks were superseded by probe-optimized jobs `14671`-`14674`, all running, with merge job `14675` held.
- The probe/resubmission record is `M6_QUEUE_PROBE_AND_RESUBMISSION_20260510.md`.

## Current PBS Snapshot

From `codex/state/JOBS.tsv` refreshed at `2026-05-10T19:36:11+09:00`:

- R3 active/pending: replacement `14669.anode01` is running; merge `14670.anode01` is held.
- R4 active/pending: replacements `14671.anode01`, `14672.anode01`, `14673.anode01`, and `14674.anode01` are running; merge `14675.anode01` is held.
- Superseded queued jobs: `14657`, `14645`, `14649`, `14660`, `14662`.
- Superseded held merge jobs: `14658`, `14663`.

## Package Readiness

| Level | Status | Readback interpretation |
| --- | --- | --- |
| R1 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R2 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R3 | in progress | Package-level merge files absent as expected; probe-optimized replacement chunk is running and merge is held. |
| R4 | in progress | Package-level merge files absent as expected; probe-optimized replacement chunks are running and merge is held. |

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

- package-level merge files: absent.
- `no_fb`: chunks `00`, `01`, and `03` complete; chunk `02` is running as replacement job `14669`.
- `fb_norefine`: chunk `01` complete; chunks `00`, `02`, and `03` are still running/partial.
- merge job `14670` is held pending dependencies.

R4:

- package-level merge files: absent.
- probe-optimized replacement chunks:
  - `no_fb/chunk_04` -> `14671`, running on `C8`
  - `no_fb/chunk_13` -> `14673`, running on `C12`
  - `fb_norefine/chunk_06` -> `14672`, running on `C12-LONG`
  - `fb_norefine/chunk_15` -> `14674`, running on `C8`
- other incomplete chunk directories have boot logs/manifests and correspond to running jobs.
- merge job `14675` is held pending dependencies.

## Recommendation

- Continue monitoring probe-optimized replacement chunks and held merge jobs.
- After R3 merge completes, perform full readback for R1-R3 while R4 continues if needed.
- After R4 merge completes, run full M6 package readback and update `state/M6_REFERENCE_PACKAGES.tsv`.
- If any queued replacement chunk fails with `Exit_status != 0`, repair through the scheduler policy: cancel/supersede, remove only that chunk's partial output/log directory, resubmit CPU-only replacement, and rebuild merge dependency.
