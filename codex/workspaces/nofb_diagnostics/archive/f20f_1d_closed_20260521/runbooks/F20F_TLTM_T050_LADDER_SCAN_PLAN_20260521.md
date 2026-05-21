# F20F TLTM t=0.5 no_fb 2-Replica Ladder Scan Plan

Date: 2026-05-21 JST

## Purpose

The fixed-flow `t=0.5` no-fallback run is a clean pathology: all 128 seeds
remain locked in one `Re z` sign sector and `Ohat_re` sits near `-0.241`.
Before launching a full nofb-vs-withfb TLTM comparison, run a short nofb-only
two-replica scan to choose a minimal ladder that repairs transport at the
`t=0.5` endpoint.

## Short Scan

- method: `no_fb` only
- replica count: `2`
- high endpoint: `t=0.5`
- candidate ladders:
  - `low005`: `[0.05, 0.5]`
  - `low010`: `[0.1, 0.5]`
  - `low020`: `[0.2, 0.5]`
  - `low030`: `[0.3, 0.5]`
- scale: `4 seeds x 5000 cycles` per candidate
- seed set: `20260421, 20260518, 20260615, 20260712`
- preset: `f20f_most_conservative_double`
- fallback policy: all fallback/rescue toggles off

## Scheduler Handoff

- request id: `FMOD-F20F-TLTM-T050-NOFB-LADDER-SCAN-4X5K-20260521`
- runnable source commit: `f2a51e712fc13536a9c2d134ca4a818026e2cb47`
- launcher:
  `bash codex/workspaces/fortran_modernization/tasks/scripts/submit_f20f_tltm_t050_nofb_ladder_scan.sh`
- dry-run manifest:
  `output/logs/f20f_tltm_t050_ladder_scan/f20f_tltm_t050_nofb_ladder_scan_4seed_x_5000cycles_f2a51e712fc1/submit/submit_manifest_20260521T002323.env`
- dry-run queue plan:
  `output/logs/f20f_tltm_t050_ladder_scan/f20f_tltm_t050_nofb_ladder_scan_4seed_x_5000cycles_f2a51e712fc1/submit/submit_queue_plan_20260521T002323.json`
- job shape: one build job, four no_fb candidate chunk jobs with
  `TLTM_JOBS=4`, and four candidate merge jobs with
  `TLTM_EXPECTED_ROWS_PER_METHOD=4`

## Selection Gate

Pick the smallest two-replica ladder that simultaneously shows:

- `pair0_accept_rate >= 0.10`;
- `total_round_trip > 0`;
- high-flow `Re z` is no longer sign-locked across the diagnostic window;
- `Ohat_re` is not locked near the fixed-flow `t=0.5` no_fb value
  `-0.24125598`;
- protocol audit passes and there is no Python embedding/preflight failure.

If no two-replica ladder passes this gate, the next conclusion is not
"withfb failed"; it is that `t=0.5` needs either more replicas or a different
high-flow strategy before the nofb-vs-withfb comparison is meaningful.

## Next Step After Selection

After a ladder is selected, run the paired TLTM comparison on the chosen ladder:

1. `no_fb` at validation scale.
2. `fb_norefine` at the same seed/cycle scale.
3. Compare high-flow sign motion, `Ohat_re/im`, `Z_mean`, failures, RG rejects,
   ODEX counters, and runtime.
