# Session Log: stage3_3_rg_redo

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
- Workspace promoted from planned to active.
- Tracked live jobs: 13515[] (C8), 13516[] (C12), 13517 merge hold.
- Manifest/status initialized for `stage3_3_with_rg_redo_200k`.
- Adopted global refresh flow via `codex/tasks/refresh_live_board.sh`.

## 2026-05-01 16:17 JST
- Switched stage3_3 redo campaign from 1024seed/200k to 1024seed/50k per user request.
- Removed old output dir `output/tests/stage3_3_with_rg_redo_1024seed_200k` and reset stage3_3 submit scripts.
- Deployed new config `docs/stage_3_3_minimal_ladder_1024seed_50k.json`.
- Submitted jobs:
  - 13586[] on C17 (chunks 00..11, 64 seeds/chunk)
  - 13587[] on G (chunks 12..15, 64 seeds/chunk)
  - 13588 merge hold on C8.
- Early queue state: 14 chunk jobs running, 2 chunk jobs queued.

## 2026-05-01 22:34 JST
- Chunk-00 sufficiency check for 50k cycles completed (64 seeds x 2 methods).
- Across-seed quality (chunk_00 aggregate): Zmean remained within about ±1 for both Re/Im and both methods.
- Per-seed split-drift diagnostic (first half vs second half normalized by robust error): no seed exceeded 1 sigma in either Re or Im for both methods.
- Jackknife tail-growth diagnostic indicates long-tail autocorrelation remains on a subset of seeds:
  - no_fb: tailmax/robust >1.25 in Re 14/64, Im 17/64.
  - fb:    tailmax/robust >1.25 in Re 11/64, Im 20/64.
- Interim interpretation: 50k is usable for trend-level comparison, but may be marginal for strict per-seed uncertainty closure on worst-tail seeds.
