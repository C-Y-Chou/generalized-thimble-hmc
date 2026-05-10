# M6 Reference Dataset Triage - 2026-05-10

Updated: 2026-05-10 19:20 JST

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
- R3 is still in progress; merge is held and one `no_fb` replacement chunk is still queued.
- R4 is still in progress; merge is held and four replacement chunks are still queued.
- No repair action is indicated by this triage. Missing/partial R3/R4 chunks currently correspond to queued/running jobs, not confirmed failed chunks.

## Current PBS Snapshot

From `codex/state/JOBS.tsv` refreshed at `2026-05-10T19:19:33+09:00`:

- R3 active/pending: `R=3`, `Q=1`, `H=1`
- R4 active/pending: `R=28`, `Q=4`, `H=1`
- Queued replacement chunks:
  - `14657.anode01` `m6R3fnofb02` on `C8-LONG`
  - `14645.anode01` `m6R4enofb04` on `C8-LONG`
  - `14649.anode01` `m6R4efbnorefine06` on `C8-LONG`
  - `14660.anode01` `m6R4fnofb13` on `C8-LONG`
  - `14662.anode01` `m6R4ffbnorefine15` on `C8-LONG`
- Held merge jobs:
  - `14658.anode01` `m6R3mergeF`
  - `14663.anode01` `m6R4mergeF`

## Package Readiness

| Level | Status | Readback interpretation |
| --- | --- | --- |
| R1 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R2 | merged | Package files exist; both methods have expected rows and protocol audits pass. Ready for full M6 readback. |
| R3 | in progress | Package-level merge files absent as expected; wait for remaining chunks and merge. |
| R4 | in progress | Package-level merge files absent as expected; wait for remaining chunks and merge. |

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
- `no_fb`: chunks `00`, `01`, and `03` complete; chunk `02` is queued as replacement job `14657`.
- `fb_norefine`: chunk `01` complete; chunks `00`, `02`, and `03` are still running/partial.
- merge job `14658` is held pending dependencies.

R4:

- package-level merge files: absent.
- queued/not-started replacement chunks:
  - `no_fb/chunk_04` -> `14645`
  - `no_fb/chunk_13` -> `14660`
  - `fb_norefine/chunk_06` -> `14649`
  - `fb_norefine/chunk_15` -> `14662`
- other incomplete chunk directories have boot logs/manifests and correspond to running jobs.
- merge job `14663` is held pending dependencies.

## Recommendation

- Do not repair yet.
- Continue monitoring until queued `C8-LONG` replacement chunks start or show a stable queue blockage.
- After R3 merge completes, perform full readback for R1-R3 while R4 continues if needed.
- After R4 merge completes, run full M6 package readback and update `state/M6_REFERENCE_PACKAGES.tsv`.
- If any queued replacement chunk fails with `Exit_status != 0`, repair through the scheduler policy: cancel/supersede, remove only that chunk's partial output/log directory, resubmit CPU-only replacement, and rebuild merge dependency.
