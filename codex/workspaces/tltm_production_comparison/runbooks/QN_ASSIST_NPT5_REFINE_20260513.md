# QN Assist NPT5 Refinement

Date: 2026-05-13 JST

Status: completed_readback_pass

## Purpose

Refine the QN navigation-assist parameter region suggested by the completed
`qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1` screen.

The first matrix found `npt5_r0050_m500` as the best 10seed/10k candidate:

- unresolved failures: `1786`
- mean Re/Im: `+0.02644360/-0.00519660`
- Zmean Re/Im: `+0.571/-0.261`

The next test focuses on whether a nearby `npt=5`/`rhobeg=0.05` region can
push failure density low enough to justify 32seed/50k confirmation.

## Fixed Contract

- Remote worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Expected branch: `codex/tltm-production-comparison-official-dfols`
- Expected commit: `6f98b5bfce60678293c163764e1cefe8307736ba`
- Method: `fb_norefine` only.
- Scale: 10 seeds x 10000 cycles.
- Physical point: `t=0.35,L=2,nstep=20`.
- Solver contract:
  `NT strict -> QN navigation assist -> unassisted certification -> strict final flow -> RG -> Metropolis`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Rescue surface: S1-only; near/non-near/global fallback disabled.
- Legacy `INTODE_SOLVER_ASSIST_ENABLED` remains unset.

## Candidates

| index | candidate | npt | rhobeg | maxfun | noise |
|---:|---|---:|---:|---:|---:|
| 0 | `npt5_r0040_m500` | 5 | 0.040 | 500 | 1 |
| 1 | `npt5_r0045_m500` | 5 | 0.045 | 500 | 1 |
| 2 | `npt5_r0050_m500_anchor` | 5 | 0.050 | 500 | 1 |
| 3 | `npt5_r0055_m500` | 5 | 0.055 | 500 | 1 |
| 4 | `npt5_r0060_m500` | 5 | 0.060 | 500 | 1 |
| 5 | `npt5_r0070_m500` | 5 | 0.070 | 500 | 1 |
| 6 | `npt5_r0080_m500` | 5 | 0.080 | 500 | 1 |
| 7 | `npt3_r0050_m500` | 3 | 0.050 | 500 | 1 |
| 8 | `npt7_r0050_m500` | 7 | 0.050 | 500 | 1 |
| 9 | `npt5_r0050_m750` | 5 | 0.050 | 750 | 1 |
| 10 | `npt5_r0050_m1000` | 5 | 0.050 | 1000 | 1 |
| 11 | `npt5_r0060_m750` | 5 | 0.060 | 750 | 1 |

## Output

- Label: `qn_assist_npt5_refine_20260513_6f98b5b_10s10k_v1`
- Output root:
  `output/tests/qn_assist_npt5_refine/qn_assist_npt5_refine_20260513_6f98b5b_10s10k_v1`
- Log root:
  `output/logs/qn_assist_npt5_refine/qn_assist_npt5_refine_20260513_6f98b5b_10s10k_v1`

## Decision Rule

Promote to 32seed/50k confirmation only if a candidate clearly improves on the
current `1786/100k` failure density while keeping mean Re/Im sane. A rough
target is `<=1250/100k`; this is the scale at which linear extrapolation begins
to approach old NT+assist failure density.

## Submission

Submitted from `ithems_fe02.intra.riken.jp` at 2026-05-13T21:26:19+09:00.

- Array job: `15130[].anode01`
- Merge job: `15131.anode01`
- Queue: `C8`
- Dependency: `afterany:15130[].anode01`
- Resource shape: 12 array indices, each 10 cores; 120 cores active when fully
  running.

Initial qstat verification:

- `15130[0]`-`15130[11]`: all running on `C8`.
- `15131`: held merge/report job, waiting for the array.
- C8 assigned ncpus: `120`.

Remote staged scripts:

- `output/pbs_scripts/qn_assist_npt5_refine_20260513/qn_assist_npt5_refine_10seed_10k_array_20260513.pbs`
- `output/pbs_scripts/qn_assist_npt5_refine_20260513/qn_assist_npt5_refine_10seed_10k_merge_20260513.pbs`

## Readback

Completed 2026-05-13 JST. Merge job `15131.anode01` exited with status 0.

- Candidate rows: `12/12`
- Missing aggregate rows: `0`

Top candidates by unresolved failure count:

| rank | candidate | failures | mean Re | mean Im | Zmean Re | Zmean Im | 32s50k projected failures |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `npt5_r0050_m1000` | 1544 | +0.106073 | -0.058417 | +2.63 | -2.43 | 24704 |
| 2 | `npt5_r0055_m500` | 1560 | +0.003135 | +0.013989 | +0.08 | +0.94 | 24960 |
| 3 | `npt5_r0060_m750` | 1565 | -0.008980 | -0.014603 | -0.21 | -0.64 | 25040 |
| 4 | `npt5_r0050_m750` | 1589 | +0.082884 | +0.001789 | +1.40 | +0.09 | 25424 |

Interpretation:

- The refinement improved the best failure density from `1786/100k` to
  `1544/100k`, but did not reach the rough parity target of `~1224/100k`.
- The lowest-failure candidate, `npt5_r0050_m1000`, has poor mean Re/Im and is
  not a clean promotion candidate.
- The cleanest near-top candidates are `npt5_r0055_m500` and
  `npt5_r0060_m750`, but their projected 32seed/50k failure counts remain
  around `25k`, above the old NT+assist reference `19579`.
