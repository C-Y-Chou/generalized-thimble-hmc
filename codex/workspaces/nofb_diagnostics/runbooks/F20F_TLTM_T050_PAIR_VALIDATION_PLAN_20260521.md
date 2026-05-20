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

## Readback

Readback time: `2026-05-21T05:03:55+0900`

All jobs finished with `Exit_status=0`.

- build `16501`: walltime `00:02:00`, host `cnode01`
- `no_fb` chunks `16502`..`16505`: walltime `00:44:39` to `00:46:13`,
  host `cnode25`
- `fb_norefine` chunks `16506`..`16509`: walltime `01:29:24` to `01:34:19`,
  hosts `cnode25`, `cnode26`
- merge `16510`: walltime `00:00:02`, host `cnode25`

Root-level readback passed:

- `no_fb/per_seed_summary_table.csv`: 32 rows
- `fb_norefine/per_seed_summary_table.csv`: 32 rows
- both aggregate tables present
- protocol audit: `32/32` pass for both methods
- preflight grep found no real `Python.h`, `libpython`, `pyconfig`,
  `Traceback`, or `[ERROR]` failure; only the queue-plan expectation text
  matched the grep pattern

Preliminary aggregate table:

| metric | no_fb | fb_norefine |
| --- | ---: | ---: |
| `mean_Ohat_re` | `-0.0160712166` | `0.0016347789` |
| `mean_Ohat_im` | `-0.0007337249` | `-0.0070309860` |
| seed std Re / Im | `0.0871994 / 0.0635735` | `0.0558787 / 0.0498222` |
| seed SE Re / Im | `0.0154148 / 0.0112383` | `0.00987805 / 0.00880740` |
| mean per-seed err Re / Im | `0.0770893 / 0.0541553` | `0.0584162 / 0.0386868` |
| `Zmean_re`, `Zmean_im` | `-1.04258`, `-0.06529` | `0.16550`, `-0.79830` |
| `P68`, `P95` | `0.3125`, `0.84375` | `0.4375`, `0.84375` |
| unresolved failures | `255406` | `11727` |
| mean projection failures | `8492.0` | `1028.59375` |
| reverse-gate rejects | `16338` | `21188` |
| pair0 accept rate | `0.2406175` | `0.240895` |
| mean round trips | `6014.4375` | `6021.375` |
| mean high-end hits | `24945.75` | `24971.25` |
| mean runtime total | `2611.09 s` | `5362.39 s` |
| ODEX calls | `965531523` | `1108562297` |
| ODEX RHS evals | `244406558285` | `331968704305` |

High-flow `Re z` sign motion, using `replica_001/z_history.dat`:

- `no_fb`: `32/32` seeds visit both signs; total sign changes `96457`;
  mean positive fraction `0.501946`
- `fb_norefine`: `32/32` seeds visit both signs; total sign changes `103432`;
  mean positive fraction `0.500994`

Paired seed difference `no_fb - fb_norefine`:

- Re: mean `-0.0177060`, SE `0.0136608`, paired Z `-1.296`
- Im: mean `0.0062973`, SE `0.0088851`, paired Z `0.709`

Initial interpretation: `fb_norefine` strongly reduces unresolved/projection
failures and has slightly more high-flow sign motion, but this 32seed x 50k
paired run does not yet show a >2 sigma observable shift. It supports
transport/failure repair, while the strong observable-bias claim still needs a
larger paired scale, a harder flow time, more replicas, or a higher-dimensional
stress test.

## Cycle-Length Validation Request

The 32seed x 50k readback shows that per-seed cycle/jackknife errors are still
comparable to the cross-seed error scale, so the next gate is not a wider 50k
seed-scale run.  It is a same-seed, same-ladder cycle-length validation:

- request id: `FMOD-F20F-TLTM-T050-LOW005-PAIR-32X200K-20260521`
- scale: `32 seeds x 200000 cycles` per method
- methods: `no_fb`, `fb_norefine`
- ladder: `[0.05, 0.5]`
- config: `docs/f20f_tltm_t050_low005_pair_32seed_200k.json`
- launcher:
  `bash codex/workspaces/fortran_modernization/tasks/scripts/submit_f20f_tltm_t050_low005_pair_validation_32seed_200k.sh`
- source commit: `d60e7467d7d8a2827f9d8a5c6ebbfab62fff42fa`
- dry-run manifest:
  `output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8/submit/submit_manifest_20260521T051240.env`
- dry-run queue plan:
  `output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8/submit/submit_queue_plan_20260521T051240.json`
- output root:
  `output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8`
- log root:
  `output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8`

Expected job shape:

- one build job
- four `no_fb` chunk jobs, `TLTM_JOBS=8`, walltime `12:00:00`
- four `fb_norefine` chunk jobs, `TLTM_JOBS=8`, walltime `12:00:00`
- one paired merge job with `TLTM_EXPECTED_ROWS_PER_METHOD=32`

Readback decision:

- If the paired `Ohat_re` shift remains near the 50k value and cycle errors
  shrink, promote to larger seed scale at 200k.
- If the shift collapses, treat the 50k observable difference as finite-cycle
  noise and do not seed-scale the 50k run.

Actual scheduler submit:

- submit time: `2026-05-21T05:16:12+0900`
- control commit on remote: `0068a0ad6099a21e6b61df80a1753c118048f6e4`
- real manifest:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8/submit/submit_manifest_20260521T051612.env`
- real queue plan:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8/submit/submit_queue_plan_20260521T051612.json`
- queues: build `C16`, chunks `C12`, merge `C12`
- jobs: build `16511.anode01`; `no_fb` chunks `16512`..`16515`;
  `fb_norefine` chunks `16516`..`16519`; merge `16520.anode01`
- immediate qstat: build running on `C16` with `exec_host=cnode01/0*16`;
  all chunks and merge are held normally on `afterok` dependencies
- scheduler returned after actual qsub and immediate readback; parent controls
  science completion/readback
