# Session Log: ngport_rg_single_replica_t03_nstep_grid

## Template
- Date:
- Goal:
- Config:
- Env vars:
- Output dir:
- Logs dir:
- Key findings:
- Next action:

## 2026-05-01 10:23 JST
- Workspace promoted from planned to active (protocol-prep stage).
- Frozen matched-control plan recorded (`x=24 chains`, `y=10 seeds`, `z=50000 cycles`).
- Manifest/status initialized; no queue submission yet.
- Adopted global refresh flow via `codex/tasks/refresh_live_board.sh`.

## 2026-05-01 10:37 JST
- Scope redesign applied.
- Added condition points `tau=0.20` and `tau=0.35` at fixed `nstep=20, L=2`.
- Replaced old xyz framing with budget-first cluster design:
  - chains_per_seed=20, samples_per_chain=50000, seeds_per_condition=12.
- Created condition matrix file:
  - `/home/cychou/TLTM/codex/workspaces/ngport_rg_single_replica_t03_nstep_grid/runbooks/CONDITION_TABLE.tsv`
- Queue submission is still pending.

## 2026-05-01 10:44 JST
- User requested removal of chain->seed two-layer design.
- Redesigned to single-layer chain budget:
  - chains_per_job=20, jobs_per_condition=3, chains_total_per_condition=60.
  - samples_per_chain=50000.
- Condition matrix unchanged (14 method-conditions), with tau checkpoints at 0.20 and 0.35 for nstep=20.
- Submission still pending.

## 2026-05-01 10:52 JST
- Updated samples_per_chain from 50000 to 200000.
- Kept single-layer chain design (no chain->seed hierarchy in experiment axis).
- Defined rollout waves:
  - Wave-1: 6 conditions (`c01,c02,c07,c08,c13,c14`).
  - Wave-2: remaining 8 conditions.
