# Stage-2.5 Completion (TLTM Ladder/Transport Tuning)

Date: 2026-04-21

## Objective

Complete stage-2.5 by tuning ladder transport on the 1d model (with shared local-update settings), then freeze one reference ladder for stage-3 matched-control runs.

## Fixed Local-Update Settings

- `trajectory_length (L) = 2`
- `integration_steps (nstep) = 20`
- `local_updates_per_cycle = 1`

## Short Scan (first pass)

- Command: `python3 scripts/run_stage2p5_ladder_scan.py --cycles 60 --seed 20260421`
- Artifacts:
  - `output/tests/stage2p5_scan/candidate_ladder_scan_table.csv`
  - `output/tests/stage2p5_scan/candidate_ladder_scan_summary.md`

Observed low-flow pair (`pair0`) acceptance:

- baseline `0,0.1,0.2,0.3`: ~0.067
- cand_a `0,0.05,0.1,0.2,0.3`: ~0.133
- cand_b `0,0.02,0.05,0.1,0.2,0.3`: ~0.033
- cand_c `0,0.01,0.03,0.05,0.1,0.2,0.3`: ~0.100

Promising ladders selected for long check: `cand_a`, `cand_c`.

## Long Check (transport-focused)

- Cycles: `300`
- Seed: `20260421`
- Cases: baseline, `cand_a`, `cand_c`
- Artifacts:
  - `output/tests/stage2p5_long/long_check_table.csv`
  - `output/tests/stage2p5_long/long_check_summary.md`
  - per-case summaries under `output/tests/stage2p5_long/*_summary.dat`

Key result:

- Baseline pair0 acceptance drops to ~0.013 and round trips remain 0.
- `cand_c` pair0 acceptance ~0.020, round trips 0.
- `cand_a` pair0 acceptance ~0.060 and total round trips observed = 4.

## Frozen Stage-2.5 Reference Ladder

- Selected candidate: `cand_a`
- Frozen ladder: `0,0.05,0.1,0.2,0.3`
- Reference file: `docs/stage_2p5_reference_ladder.json`

This reference is now the stage-3 baseline for fallback-enabled vs fallback-disabled matched-control comparisons.
