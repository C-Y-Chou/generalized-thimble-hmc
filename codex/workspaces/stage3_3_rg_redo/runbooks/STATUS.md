# Stage3_3 RG Redo Status

Updated: 2026-05-01 16:18 JST

## Active objective
- Run Stage3_3 redo at 1024 seeds, 50k cycles/seed, RG enabled for both methods.

## Live jobs (current)
- `13586[]` (C17): chunks 00..11 (`s33_rg1024_50k_c17`)
- `13587[]` (G): chunks 12..15 (`s33_rg1024_50k_g`)
- `13588` (C8): merge hold (`afterany:13586[]:13587[]`)

## Protocol
- Config: `docs/stage_3_3_minimal_ladder_1024seed_50k.json`
- Local params: `flow_time=0.3`, `L=2`, `nstep=20`
- Methods: `no_fb` and `fb`, both with `QN_REVERSE_GATE_ENABLED=1`
- Chunking: `64 seeds/chunk`, total `16 chunks`, expected merged rows `2048`

## Queue plan
- Primary throughput queue: `C17` (12 chunks)
- Secondary throughput queue: `G` (4 chunks)
- Goal: maximize first-wave concurrent starts, then finish remaining queued C17 tails.

## Next actions
1. Monitor chunk completion and queue turnover on `13586/13587`.
2. Verify merge `13588` starts and writes merged 2048-row summary.
3. Update report tables (runtime, mean/std, Zmean, rev_rej vs failure split).
