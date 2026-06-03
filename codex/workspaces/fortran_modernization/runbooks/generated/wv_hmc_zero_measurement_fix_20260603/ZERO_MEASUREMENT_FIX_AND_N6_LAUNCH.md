# WV-HMC Zero-Measurement Fix and n=6 Launch - 2026-06-03

## Scope

This note records the zero-measurement seed fix and the follow-up n=6 12-hour
cluster launch. It is operational state, not a physics conclusion.

## Zero-Measurement Diagnosis

The n=2 zero-measurement seeds were caused by state-bank records whose fixed
flow-time labels were outside the measurement window `[0, 0.01]`.

Original bank:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/state_bank_from_t001_late_final_20260602/state_bank_t001_final128.bin`

Bank inventory:

- total records: 128
- records inside `[0, 0.01]`: 118
- records outside `[0, 0.01]`: 10
- dropped flow-time range: `0.010018047031206501` to `0.012325912851557045`

Reason this created zero measurements:

- Flow time is a fixed label per WV-HMC state.
- Seeds initialized from out-of-window records can remain outside the
  measurement window for the full run.
- Those seeds then report `measurement_attempted = 0` and
  `measurement_included = 0`.

## Code Changes

Source pin:

`77ffdb4e4771-78e4e09e4c35`

Runtime snapshot:

`/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_zero_fix_n6_20260603_20260602T154012Z`

Relevant changes in the source pin:

- `src/apps/wv_hmc_app_common.f90`
  - emits `WV_HMC_INIT ... init_bank_record ... init_bank_record_count ...`
    before the chain starts, so failed or zero-measurement seeds are still
    attributable to a concrete bank record and initial flow-time label.
- `codex/workspaces/fortran_modernization/tasks/scripts/run_wv_hmc_dense_observable_validation_20260529.py`
  - parses `WV_HMC_INIT` from each seed log.
  - records `init_bank_record_actual`, `init_bank_record_count_actual`, and
    `initial_flow_time_actual` in the manifest.
- `codex/workspaces/fortran_modernization/tasks/scripts/filter_wv_hmc_state_bank_by_flow_time_20260603.py`
  - creates filtered state banks by fixed flow-time label.
- `codex/workspaces/fortran_modernization/tasks/pbs/wv_hmc_n6_observable_validation_20260603.pbs`
  - gitless/source-pinned n=6 12-hour validation wrapper.

## Filtered n=2 Bank

Filtered bank:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/state_bank_from_t001_late_final_20260602/state_bank_t001_final128_measurement001_filtered.bin`

Filter outputs:

- index:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/state_bank_from_t001_late_final_20260602/state_bank_t001_final128_measurement001_filtered.bin.index.csv`
- histogram:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/state_bank_from_t001_late_final_20260602/state_bank_t001_final128_measurement001_filtered.bin.histogram.csv`

Filtered bank inventory:

- records kept: 118
- records dropped: 10
- kept flow-time range: `0.00017256322016385214` to
  `0.009850907948937929`

## n=2 Filtered-Bank Smoke Gate

PBS job:

`18847.anode01`

Run:

`wv_hmc_n2_zero_filtered_128x2000_20260603`

Run root:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_zero_measurement_fix_20260603/wv_hmc_n2_zero_filtered_128x2000_20260603/sample`

Settings:

- seeds: 128
- cycles: 2000
- measurement start cycle: 101
- measurement window: `[0, 0.01]`
- epsilon: `0.003`
- nstep: `20`
- init bank: filtered n=2 bank above

Smoke result:

- rows: 128
- nonzero return codes: 0
- missing summaries: 0
- missing observable files: 0
- missing actual init record fields: 0
- actual initial flow-time min: `0.0001725632201638521`
- actual initial flow-time max: `0.009850907948937929`
- zero-measurement seeds: 0
- `measurement_attempted`: min 1900, max 1900
- `measurement_included`: min 1900, max 1900
- `measurement_failed` sum: 0
- mean acceptance: `0.62648828125`

Conclusion for this specific defect:

The zero-measurement seed issue from out-of-window init-bank records is fixed for
the n=2 filtered-bank path.

## n=6 12-Hour Launch

Launched at approximately `2026-06-03T00:44-00:45+0900`.

Queue:

`C17-LONG`

Jobs:

| chunk | job ID | node slot | seed start | seeds | cycles |
|---:|---|---|---:|---:|---:|
| 00 | `18848.anode01` | `cnode37/1*16` | 8982001 | 16 | 15000 |
| 01 | `18849.anode01` | `cnode37/2*16` | 8982017 | 16 | 15000 |
| 02 | `18850.anode01` | `cnode38/0*16` | 8982033 | 16 | 15000 |
| 03 | `18851.anode01` | `cnode38/1*16` | 8982049 | 16 | 15000 |

Run base:

`wv_hmc_n6_t003_64x15000_zero_fixed_20260603`

Output root:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_validation_20260603`

Log root:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_n6_validation_20260603`

Settings:

- model: Stephanov n=6, `mu=0.6`
- `T0 = 0.0`
- `T1 = 0.03`
- measurement window: `[0.0, 0.03]`
- `D0 = 0.0001`
- `D1 = 0.005`
- W profile: `paper_wall`
- `gamma = 65.0`
- epsilon: `0.009`
- nstep: `10`
- cycles per seed: 15000
- measurement start cycle: 501
- constraint tolerance: `1.0e-10`
- constraint max iter: 192
- adaptive Newton stop: off
- large-residual stop: off
- observable history: on
- x/state history: off
- final state: on
- cyclic snapshots: on, interval 500, slots 8

Initial bank:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat`

Expected walltime:

- hard PBS walltime: 12 hours
- per-seed wrapper timeout: 42000 seconds
- expected finish no later than about `2026-06-03T12:45+0900`
- early progress check at about `2026-06-03T00:50+0900`:
  - all 4 chunks running
  - all 64 seeds writing observable histories
  - no chunk manifest yet, as expected before all 16 seeds complete
  - slowest observed cycle estimate: about 2080 cycles at 5:06 walltime
  - median observed cycle estimate: about 3814 cycles
  - rough runtime ETA from early slowest-seed rate: about `2026-06-03T01:20+0900`
  - conservative ETA: `2026-06-03T01:30-02:00+0900`

First useful progress check:

- after observable histories or manifests appear under each chunk output root.
- if no per-seed logs appear within the first 15-30 minutes, inspect boot logs
  and node placement.

## Parameter Health Warning

Additional live inspection after launch showed that the current n=6 setup is not
moving in flow time:

- sampled observable histories inspected across all 64 seeds had
  `flow_time_max = 0.0`;
- no seed had any current observable-history row with `flow_time >= 0.001`;
- the first completed summary had `flow_time_min = flow_time_max = 0.0`,
  `accepted_flow_time_jump_abs_mean = 0.0`, and
  `effective_flow_time_jump_abs_mean = 0.0`;
- that completed summary also had large lower-boundary activity
  (`bounced_steps = 149035`, `solver_stop_boundary_exit = 149035`).

Therefore the current `T0=0`, tau-0 init-bank launch should not be interpreted
as a valid WV-HMC `T1=0.03` production validation.  As currently initialized, it
is effectively a fixed-`tau=0` diagnostic.  Before another long n=6 WV-HMC
validation, run a short cluster gate that verifies flow-time movement from the
chosen initialization and wall settings.

Immediate implication for `T0/T1/D0/D1`:

- `T1=0.03` remains a plausible target endpoint, but this run does not test it.
- `T0=0` is a valid lower-domain choice only if the kernel is verified to move
  away from the lower wall; exact tau-0 initialization currently fails that
  operational check.
- `D0>0` with `T0=0` is semantically inconsistent in the current nonnegative
  flow-time implementation.  The boundary rule computes a lower wall
  `T0-D0`, which would extend into negative flow time, but the potential,
  constraint residual, and flow routines reject `flow_time < 0`.  Therefore
  `T0=0,D0>0` should be treated as an invalid production setting unless the
  algorithm is explicitly changed to support negative flow time.
- `D1=0.005` is not yet tested, because the chain never approaches the upper
  wall.
