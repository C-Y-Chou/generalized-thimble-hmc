# F20F TLTM t=0.5 Paired Validation Plan

Date: 2026-05-21 JST

## Control Method

Use the parent session as the controller. The parent performs readback, gate
decisions, dry-run validation, and scheduler request updates. The scheduler
agent performs only the gated real PBS submission through
`codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh`.

Do not leave delayed decision logic inside the scheduler agent. If a delayed
readback is needed, wake the parent controller, re-evaluate the gate, then hand
off a concrete job spec to the scheduler.

## Ladder Selection

The no_fb-only two-replica short scan selected `low005 = [0.05, 0.5]` as the
first paired-validation ladder.

Selection evidence from the 4seed x 5000cycle scan:

- `pair0_accept_rate` mean: `0.2413`
- `total_round_trip` mean: `602.25`
- high-flow `Re z` sign changes: `1198`
- high-flow both-sign seed count: `4/4`
- fixed-flow `t=0.5` no_fb `mean_Ohat_re`: `-0.2412559808`
- low005 no_fb short-scan `mean_Ohat_re`: `-0.0241257823`

This is the smallest tested ladder that restored high-flow sign motion and did
not remain locked near the fixed-flow pathology.

## Paired Validation

- method set: `no_fb`, `fb_norefine`
- replica count: `2`
- selected ladder: `[0.05, 0.5]`
- scale: `32 seeds x 50000 cycles` per method
- seed start: `20260421`
- seed stride: `97`
- chunks: `4` per method
- seeds per chunk: `8`
- chunk workers: `8`
- preset: `f20f_most_conservative_double`
- fallback policy: all fallback/rescue toggles off

Launcher:

```bash
bash codex/workspaces/fortran_modernization/tasks/scripts/submit_f20f_tltm_t050_low005_pair_validation_32seed_50k.sh
```

Scheduler request:

- request id: `FMOD-F20F-TLTM-T050-LOW005-PAIR-32X50K-20260521`
- runnable source commit: `d2a365e0a195bf6bf61b9b103d3e63cb53ab22c4`
- dry-run manifest:
  `output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195/submit/submit_manifest_20260521T030319.env`
- dry-run queue plan:
  `output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195/submit/submit_queue_plan_20260521T030319.json`
- expected output root:
  `output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195`
- expected log root:
  `output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195`

Actual scheduler submit:

- submit time: `2026-05-21T03:08:45+0900`
- control commit on remote: `b69d61757c6ee3c5bdf9949dbe896af3aabc8442`
- real manifest:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195/submit/submit_manifest_20260521T030845.env`
- real queue plan:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195/submit/submit_queue_plan_20260521T030845.json`
- queues: build `C16`, chunks `C12`, merge `C12`
- jobs: build `16501.anode01`; `no_fb` chunks `16502`..`16505`;
  `fb_norefine` chunks `16506`..`16509`; merge `16510.anode01`
- immediate qstat: build running on `C16` with `exec_host=cnode01/0*16`;
  all chunks and merge are held normally on `afterok` dependencies
- scheduler returned after actual qsub and immediate readback; parent controls
  science completion/readback

Expected job shape:

- one build job
- four `no_fb` chunk jobs
- four `fb_norefine` chunk jobs
- one paired merge job with `TLTM_EXPECTED_ROWS_PER_METHOD=32`

## Readback Required

- `no_fb/per_seed_summary_table.csv` has 32 rows
- `fb_norefine/per_seed_summary_table.csv` has 32 rows
- both methods have `aggregated_summary_table.csv`
- protocol audit passes
- preflight has no `Python.h`, `libpython`, or `pyconfig` failure
- `fixed_flow_mode=F` and `replica_exchange_active=T`
- report `no_fb` vs `fb_norefine`: `mean Ohat Re/Im`, seed std,
  cycle/jackknife error, `Z_mean`, `P68/P95`, unresolved/projection failures,
  reverse-gate rejects, pair acceptance/round trips, ODEX counters, and runtime
- inspect high-flow `Re z` sign motion against the fixed-flow `t=0.5` no_fb
  sign-sector lock

## Promotion Logic

If 32seed x 50k shows a clear no_fb pathology that is reduced by `fb_norefine`,
promote to a larger paired scale. If both methods remain statistically
compatible, the current one-dimensional model may not support the strong BTN
fallback claim at this endpoint without either larger flow time, more replicas,
or a higher-dimensional stress test.
