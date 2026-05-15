# QN Assist Preset Matrix

Date: 2026-05-13 JST

Status: completed_readback_pass

## Purpose

Test whether `QN+assist` can replace the effective role previously played by
`NT+assist`, without assuming that assist-off tuning winners transfer to the
assist-on residual landscape.

## Fixed Contract

- Remote worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Expected branch: `codex/tltm-production-comparison-official-dfols`
- Expected commit: `6f98b5bfce60678293c163764e1cefe8307736ba`
- Method: `fb_norefine` only for screening.
- Scale: 10 seeds x 10000 cycles.
- Physical point: `t=0.35,L=2,nstep=20`.
- Solver contract:
  `NT strict -> QN navigation assist -> unassisted certification -> strict final flow -> RG -> Metropolis`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Rescue surface: S1-only; near/non-near/global fallback disabled.

## Matrix

The first screen intentionally scans `npt` rather than treating `npt=4` as
privileged.  It also includes the prior stable/legacy anchors, `rhobeg`
variation, a limited `maxfun=1000` extension, and two noise-model controls.

Candidates:

| index | candidate |
|---:|---|
| 0 | `stable_gate77_npt4_r0018_m250` |
| 1 | `legacy_defaultnpt_r0050_m250` |
| 2 | `npt0_r0018_m500` |
| 3 | `npt4_r0018_m500` |
| 4 | `npt5_r0018_m500` |
| 5 | `npt6_r0018_m500` |
| 6 | `npt8_r0018_m500` |
| 7 | `npt10_r0018_m500` |
| 8 | `npt0_r0030_m500` |
| 9 | `npt4_r0030_m500` |
| 10 | `npt5_r0030_m500` |
| 11 | `npt6_r0030_m500` |
| 12 | `npt8_r0030_m500` |
| 13 | `npt10_r0030_m500` |
| 14 | `npt0_r0050_m500` |
| 15 | `npt4_r0050_m500` |
| 16 | `npt5_r0050_m500` |
| 17 | `npt6_r0050_m500` |
| 18 | `npt8_r0050_m500` |
| 19 | `npt10_r0050_m500` |
| 20 | `npt4_r0080_m500` |
| 21 | `npt8_r0080_m500` |
| 22 | `npt4_r0120_m500` |
| 23 | `npt8_r0120_m500` |
| 24 | `npt4_r0050_m1000` |
| 25 | `npt8_r0050_m1000` |
| 26 | `npt4_r0050_m500_no_noise` |
| 27 | `npt8_r0050_m500_no_noise` |

## Output

- Label: `qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1`
- Output root:
  `output/tests/qn_assist_preset_matrix/qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1`
- Log root:
  `output/logs/qn_assist_preset_matrix/qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1`

## Submission

Submitted from `ithems_fe02.intra.riken.jp` at 2026-05-13T19:50:59+09:00.

- Array job: `15112[].anode01`
- Initial merge job: `15113.anode01`
- Initial dependency: `afterok:15112[].anode01`
- Queue: `C12`

Startup repair:

- Array indices `20`-`23` entered `E` immediately with `Exit_status=127`
  before candidate logs were opened, so this was a PBS/job-start layer failure,
  not a Stage2 scientific failure.
- Old merge job `15113.anode01` was canceled because its `afterok` dependency
  on the failed array would never release.
- Replacement jobs were submitted with the same candidate indices through a
  no-array copy of the PBS script:
  - index `20`: `15114.anode01`
  - index `21`: `15115.anode01`
  - index `22`: `15116.anode01`
  - index `23`: `15117.anode01`
- Replacement merge job: `15118.anode01`
- Replacement merge dependency:
  `afterany:15112[].anode01:15114.anode01:15115.anode01:15116.anode01:15117.anode01`

Second startup repair:

- Original array indices `24`-`27` also expired with `Exit_status=127` on
  `cnode36`.
- Replacement jobs `15114`-`15117` also landed on `cnode36` and exited with the
  same 0-walltime startup failure.
- Canceled replacement merge `15118.anode01`.
- Resubmitted all affected indices `20`-`27` on `C8`, using copies of the PBS
  scripts staged under the ignored worktree output namespace:
  - index `20`: `15119.anode01`
  - index `21`: `15120.anode01`
  - index `22`: `15121.anode01`
  - index `23`: `15122.anode01`
  - index `24`: `15123.anode01`
  - index `25`: `15124.anode01`
  - index `26`: `15125.anode01`
  - index `27`: `15126.anode01`
- Active merge job: `15127.anode01`
- Active merge dependency:
  `afterany:15112[].anode01:15119.anode01:15120.anode01:15121.anode01:15122.anode01:15123.anode01:15124.anode01:15125.anode01:15126.anode01`

Live qstat snapshot after second repair:

- `15112[].anode01`: original matrix array; indices `0`-`19` running on C12.
- `15119`-`15126`: all eight replacement candidates running on C8
  (`cnode17` and `cnode23`).
- `15127`: held merge/report job.
- Candidate manifests/log roots present: `28/28`.

Live qstat snapshot after repair:

- `15112[].anode01`: array began on `C12`; indices `0`-`19` running,
  `24`-`27` queued at first check; original `20`-`23` failed at startup and
  are superseded by replacements.
- `15114`-`15117`: queued replacements for indices `20`-`23`.
- `15118`: held merge/report job.

Remote manifests:

- `output/tests/qn_assist_preset_matrix/qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1/submit_manifest.env`
- `output/tests/qn_assist_preset_matrix/qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1/submitted_jobs.env`
- `output/tests/qn_assist_preset_matrix/qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1/replacement_jobs.env`

## Readback

The original merge report used the wrong aggregate path and initially reported
0 rows. The fixed readback was rerun directly against completed raw candidate
outputs.

- Candidate directories: `28/28`
- Aggregates: `28/28`
- Per-seed tables: `28/28`
- Expected rows in fixed `REPORT.md`: `28/28`

Top results by unresolved failure count:

| rank | candidate | npt | rhobeg | maxfun | failures | mean Re | mean Im | Zmean Re | Zmean Im |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | `npt5_r0050_m500` | 5 | 0.050 | 500 | 1786 | +0.02644360 | -0.00519660 | +0.5707 | -0.2610 |
| 2 | `npt0_r0050_m500` | 0 | 0.050 | 500 | 1925 | +0.08001704 | -0.03128165 | +2.2496 | -1.7484 |
| 3 | `npt4_r0050_m1000` | 4 | 0.050 | 1000 | 1936 | +0.06437097 | +0.01635226 | +1.6369 | +0.7003 |
| 4 | `npt4_r0050_m500` | 4 | 0.050 | 500 | 2207 | +0.09396069 | -0.00688404 | +2.1676 | -0.4757 |

Log audit: DFO-LS bridge tracebacks were all residual-callback rejection
warnings inside candidate attempts; no non-residual fatal errors were found at
the candidate log layer.

Follow-up: `npt5_r0050_m500` was promoted to the local refinement campaign
documented in `QN_ASSIST_NPT5_REFINE_20260513.md`.
