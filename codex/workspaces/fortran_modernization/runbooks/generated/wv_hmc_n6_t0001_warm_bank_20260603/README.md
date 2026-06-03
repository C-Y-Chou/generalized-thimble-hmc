# WV-HMC n=6 t=1e-4 Warm-Bank Attempt - 2026-06-03

## Scope

This note records the `n=6` WV-HMC initialization attempt requested after the
invalid `T0=0,D0>0` runs.  The tested target was:

- `T0 = 1.0e-4`
- `D0 = 1.0e-4`
- `T1 = 0.03`
- `D1 = 0.005`
- `W(t) = paper_wall`, `gamma = 55`
- `epsilon = 0.010`
- `nstep = 8`
- `constraint_max_iter = 192`

The goal was to build a warm bank at `t=1e-4` and check whether it can start a
nonzero-measurement, non-sticky WV-HMC chain.

## Cluster Jobs

| job | purpose | queue | status | exit | walltime |
|---:|---|---|---|---:|---:|
| `18860.anode01` | build `t=1e-4` warm/safe bank | `C17` | finished | 0 | 00:01:30 |
| `18861.anode01` | exact-`T0` state-bank smoke | `C17` | finished | 0 | 00:00:33 |
| `18862.anode01` | interior `t_init=5.5e-4` x-bank smoke | `C17` | finished | 3 | 00:00:34 |
| `18863.anode01` | low-end/oldwarm Newton trace before boundary fix | `C17` | finished | 0 | 00:01:32 |
| `18864.anode01` | same trace after boundary fix | `C17` | finished | 0 | 00:01:32 |
| `18865.anode01` | fixed-kernel tau=0 x-bank smoke, flow to `T0=1e-4` | `C17` | finished | 0 | 00:13:15 |

## Bank Build

Builder:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260603/stephanov_n6_wv_hmc_t0001_warm_bank_16x5000_20260603_18860.anode01
```

Settings:

- `WV_BANK_CHAINS=16`
- `WV_BANK_CYCLES=5000`
- `WV_BANK_HISTORY_STRIDE=10`
- `WV_BANK_BURN_RECORDS=100`
- `WV_BANK_SEED_BASE=8790000`
- `WV_BANK_INIT_SIGMA=0.1`
- `WV_BANK_TARGET_FLOW_TIME=0.0001`
- `WV_BANK_VALIDATE_RECORDS=4096`

Outputs:

- source `t=0` x-bank:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260603/stephanov_n6_wv_hmc_t0001_warm_bank_16x5000_20260603_18860.anode01/t0_bank/bank/x_bank.dat`
- safe x-bank flowable to `t=1e-4`:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260603/stephanov_n6_wv_hmc_t0001_warm_bank_16x5000_20260603_18860.anode01/safe_bank_t0p0001/x_bank.dat`
- fixed-label WV state bank:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260603/stephanov_n6_wv_hmc_t0001_warm_bank_16x5000_20260603_18860.anode01/state_bank_t0p0001/state_bank_t0p0001.bin`

Coverage:

- diagnosed source records: `4096`
- records safe to `t=1e-4`: `4090`
- copied records: `4090`
- state size: `72`

The bank build itself succeeded.  It is a usable pool of `x` states that can be
flowed to `t=1e-4`.  The first downstream WV-HMC transition tests exposed a
kernel regression rather than proving that the bank itself cannot move.

## Exact-T0 State-Bank Smoke

Run:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_warm_bank_smoke_20260603/wv_hmc_n6_t0001_warm_bank_g55_eps010_n8_16x200_20260603/sample_18861.anode01
```

Initialization:

- `init_mode=state_bank`
- fixed state-bank flow label: `t=1e-4`
- `16` seeds x `200` cycles
- measurement starts at cycle `21`

Aggregate result:

- cycles completed: `3200`
- measurement attempted: `2880`
- measurement included: `2880`
- measurement failed: `0`
- zero-measurement seeds: `0`
- accepted: `2413`
- rejected: `787`
- metropolis rejected: `0`
- reverse-gate rejected: `784`
- transitions failed: `3`
- ODEX failures: `3`
- solver boundary exits: `21809`
- reverse solver boundary exits: `24589`

Movement diagnostics:

- `flow_time_min = flow_time_max = flow_time_mean = 1.0e-4`
- `accepted_x_jump_sq_mean = 0`
- `effective_x_jump_sq_mean = 0`
- `accepted_flow_time_jump_abs_mean = 0`
- `effective_flow_time_jump_abs_mean = 0`
- zero-effective-movement seeds: `16 / 16`

Pre-fix conclusion:

The exact-`T0` state-bank start fixes the zero-measurement symptom, but it does
not produce a moving chain under the pre-fix source.  This result is now
interpreted as a symptom of the boundary/Newton regression diagnosed below, not
as a standalone proof that exact-`T0` initialization must be sticky.

## Interior X-Bank Smoke

Run:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_warm_bank_interior_smoke_20260603/wv_hmc_n6_t0001_warm_xbank_tinit00055_g55_eps010_n8_16x200_20260603/sample_18862.anode01
```

Initialization:

- `init_mode=bank`
- x-bank safe only to `t=1e-4`
- requested initial flow time: `t_init=5.5e-4`
- `16` seeds x `200` cycles
- measurement starts at cycle `21`

Run status:

- job exit: `3`
- one seed failed at cycle `0` with dense-chain/ODE failure while initializing
  from record `3882`
- `15 / 16` seed summaries were produced

Completed-seed aggregate:

- cycles completed: `3000`
- measurement attempted: `2700`
- measurement included: `2700`
- measurement failed: `0`
- zero-measurement seeds: `0`
- accepted: `2138`
- rejected: `862`
- metropolis rejected: `0`
- reverse-gate rejected: `861`
- transitions failed: `1`
- ODEX failures among completed summaries: `1`
- solver boundary exits: `19943`
- reverse solver boundary exits: `23052`

Movement diagnostics among completed seeds:

- `flow_time_min = flow_time_max = flow_time_mean = 5.5e-4`
- `accepted_x_jump_sq_mean = 0`
- `effective_x_jump_sq_mean = 0`
- `accepted_flow_time_jump_abs_mean = 0`
- `effective_flow_time_jump_abs_mean = 0`
- zero-effective-movement seeds: `15 / 15`

Pre-fix conclusion:

The interior start did not solve the movement problem.  It also shows that a
bank validated only to `t=1e-4` is not sufficient for arbitrary interior
initialization such as `t=5.5e-4`; interior banks must be prevalidated to the
actual intended initial flow time.  The zero-movement part of this run is now
also attributed to the boundary/Newton regression diagnosed below.

## Boundary/Newton Trace Diagnosis

Trace job `18863.anode01` ran three one-seed, 20-cycle cases with Newton trace
enabled:

- `lowend_g55`: `state_bank_t0p0001.bin`, `gamma=55`
- `lowend_g0`: `state_bank_t0p0001.bin`, `gamma=0`
- `oldwarm_g55`: older interval-warm bank from the previous moving retune,
  `gamma=55`

All three pre-fix cases had zero effective movement, including the old interval
warm bank.  This ruled out the simple explanation that the newly built
`t=1e-4` bank alone was bad.

Pre-fix summary:

| case | effective x jump sq mean | effective flow-time jump abs mean | solver boundary exits | reverse boundary exits | trace stop_reason=10 |
|---|---:|---:|---:|---:|---:|
| `lowend_g55` | 0 | 0 | 138 | 159 | 297 |
| `lowend_g0` | 0 | 0 | 142 | 160 | 302 |
| `oldwarm_g55` | 0 | 0 | 158 | 160 | 318 |

The trace showed repeated `wv_newton_stop_boundary_exit` events from internal
Newton updates.  The production kernel then treated those internal Newton exits
as boundary reflections and returned the original state with flipped momentum.
This produced accepted no-op trajectories.

The fix in `src/sampler/wv_hmc_constraints.f90` is:

- restore trajectory-level predicted-boundary detection with
  `wv_predict_first_constraint_delta_h`;
- do not pass `target_flow_time_min=0` from the production boundary RATTLE step
  into the no-boundary Newton solve;
- bounce on construction failure only when the trajectory-level prediction says
  the proposal is a boundary hit;
- keep the existing boundary momentum policy (`paper_full_flip` or
  `normal_reflect`) for real boundary bounces.

Retest job `18864.anode01` used the same three cases and source pin
`4597ced50bd8-920ebfb7d17f`.

Post-fix summary:

| case | effective x jump sq mean | effective flow-time jump abs mean | flow-time in -> out | bounced steps | trace stop_reason=10 |
|---|---:|---:|---|---:|---:|
| `lowend_g55` | 5.2116e-3 | 1.1224e-2 | 1.0e-4 -> 3.1774e-2 | 3 | 0 |
| `lowend_g0` | 3.8759e-3 | 7.3460e-3 | 1.0e-4 -> 1.0113e-2 | 5 | 0 |
| `oldwarm_g55` | 2.8977e-3 | 7.7273e-3 | 1.8728e-2 -> 2.6496e-2 | 4 | 0 |

The no-effective-movement problem is therefore traced to the boundary/Newton
gate regression.  After the fix, all three short traces show nonzero movement.

## Tau=0 X-Bank Restart Smoke After Fix

Job `18865.anode01` tested the user's requested restart path:

```text
T0=1e-4, D0=1e-4, T1=0.03, D1=0.005
init_mode=bank
initial_flow_time=1e-4
init_bank_file=<20260603 tau=0 x_bank.dat>
W(t)=paper_wall, gamma=55
epsilon=0.010, nstep=8, max_iter=192
seeds=16, cycles=500, measurement_start_cycle=51
```

The tau=0 bank path was:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260603/stephanov_n6_wv_hmc_t0001_warm_bank_16x5000_20260603_18860.anode01/t0_bank/bank/x_bank.dat
```

Initialization used `init_bank_record=-1`, so each seed randomly selected a
bank record from the tau=0 bank.  The 16 selected records were:

```text
4223, 6229, 3174, 4605, 4284, 4302, 5362, 3282,
1728, 4612, 3555, 1819, 6000, 1260, 1928, 3256
```

Movement and transition summary:

| metric | value |
|---|---:|
| cycles completed | 8000 |
| accepted / cycles | 7316 / 8000 = 0.9145 |
| transitions failed | 520 |
| reverse-gate rejected | 111 |
| ODE failures | 488 |
| measurement included / attempted | 6109 / 6109 |
| measurement skipped outside `[T0,T1]` | 1891 |
| measurement failed | 0 |
| zero-effective-movement seeds | 0 / 16 |
| zero-measurement seeds | 0 / 16 |
| mean effective x jump sq | 3.8962e-3 |
| mean effective flow-time jump abs | 7.2324e-3 |
| mean flow-time range per seed | min 9.84e-5, max 3.4845e-2 |
| measurement flow histogram | all 32 bins nonzero, min 148, max 221 |

Preliminary pooled ratio estimates from this short smoke are not production
quality:

| observable | Re | Im | seed-SE Re | seed-SE Im | z_Re | z_Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral condensate | 0.0137166 | -0.0129982 | 0.003987 | 0.002990 | -2.70 | -4.35 |
| number density | 0.9183304 | 0.6089822 | 0.17956 | 0.14841 | 1.96 | 4.10 |

Interpretation boundary: this run confirms that the fixed kernel plus tau=0
x-bank restart no longer has the zero-effective-movement problem.  It does not
approve observable correctness; a longer validation and/or parameter retune is
still required.

## Decision

The `t=1e-4` warm bank exists and is valid as a `t=1e-4` flowability-filtered
bank.  The original zero-effective-movement smoke no longer blocks the bank by
itself, because the root cause was a transition-kernel regression that has a
targeted fix and a positive short trace retest.

Do not treat this as production approval yet.  Before a long `n=6` production,
rerun the parameter-tuned validation with the fixed kernel and confirm:

```text
T0=1e-4, D0=1e-4, T1=0.03, D1=0.005,
gamma=55, epsilon=0.010, nstep=8, max_iter=192
```

or the subsequently selected tuned values.

## Fixed-Kernel Acceptance Smoke

After the fixed-kernel movement smoke, a short acceptance-only scan was run on
cluster02 with the same interval and bank:

```text
T0=1e-4, D0=1e-4, T1=0.03, D1=0.005
gamma=55, nstep=8, max_iter=192
init_bank=tau0 x_bank, initial_flow_time=1e-4
16 seeds x 100 cycles per epsilon
```

Acceptance is counted as `accepted / total attempted cycles`.  Failure and ODE
failure counts are diagnostic/runtime information only and are not used as an
epsilon rejection criterion for this scan.

| epsilon | seeds | cycles | accepted | rejected | acceptance | accepted x jump sq mean | effective x jump sq mean |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.010 | 16 | 1600 | 1471 | 129 | 0.9194 | 0.00440389 | 0.00404818 |
| 0.012 | 16 | 1600 | 1443 | 157 | 0.9019 | 0.00576861 | 0.00520314 |
| 0.014 | 16 | 1600 | 1378 | 222 | 0.8612 | 0.00721818 | 0.00622368 |
| 0.016 | 16 | 1600 | 1266 | 334 | 0.7913 | 0.00867640 | 0.00685563 |

The epsilon scan moves acceptance out of the overly conservative `0.90+`
range while increasing effective x movement.  The first epsilon selection was
`epsilon=0.016`; nstep then still needed its own movement scan.

## Fixed-Epsilon Nstep Smoke

The nstep scan fixes `epsilon=0.016,gamma=55,max_iter=192` and varies only
`nstep`.  Acceptance remains `accepted / total attempted cycles`; failure and
ODE failure counts are diagnostic/runtime information only and are not used as
the nstep rejection criterion.

| nstep | L | seeds | cycles | acceptance | effective x jump sq mean | effective flow-time jump abs mean |
|---:|---:|---:|---:|---:|---:|---:|
| 4 | 0.064 | 16 | 1600 | 0.8875 | 0.00256259 | 0.00590010 |
| 6 | 0.096 | 16 | 1600 | 0.8219 | 0.00465767 | 0.00723569 |
| 8 | 0.128 | 16 | 1600 | 0.7913 | 0.00685563 | 0.00742700 |
| 10 | 0.160 | 16 | 1600 | 0.7906 | 0.00938710 | 0.00817071 |
| 12 | 0.192 | 16 | 1600 | 0.7369 | 0.01097340 | 0.00716964 |

Working selection for the next validation: `epsilon=0.016,nstep=10,gamma=55`.
Compared with `nstep=8`, this keeps acceptance essentially unchanged while
raising effective x movement by about 37%.  `nstep=12` gives larger x movement
but lower acceptance and higher apparent cost, so it is a secondary candidate
only if validation shows `nstep=10` still mixes too slowly.

## 10k Validation Launch

The next validation was submitted through the cluster02 scheduler gate:

| field | value |
|---|---|
| job id | `18880.anode01` |
| queue | `C17` |
| run name | `wv_hmc_n6_t0001_tau0bank_val10k_eps016_n10_g55_16x10000_20260603` |
| output root | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_tau0bank_validation_20260603` |
| seeds | `16` |
| cycles per seed | `10000` |
| epsilon / nstep / L | `0.016 / 10 / 0.160` |
| gamma | `55` |
| interval | `T0=1e-4,D0=1e-4,T1=0.03,D1=0.005` |
| measurement start | `1` |
| histories | observable, x, and state history enabled |
| final state | enabled |
| cyclic snapshots | enabled, interval `500`, slots `24` |

Boot log checked: the job is running on `cnode37` with source pin
`4597ced50bd8-20a2258de6d8`, `WV_OBS_CYCLES=10000`,
`WV_OBS_STEP_SIZE=0.016`, `WV_OBS_NUM_STEPS=10`, and
`WV_OBS_WRITE_CYCLIC_SNAPSHOT=1`.

## Continuation Contract

This WV-HMC validation is restartable as a chain-state continuation.  The final
state format is one real `flow_time` followed by the 72 real `x` components.
It does not store the RNG state, so continuation uses new RNG streams from the
stored endpoint configurations; it is not a bitwise identical RNG checkpoint.

After successful completion, build a 16-record restart state bank from the
final states:

```bash
RUN_ROOT=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_tau0bank_validation_20260603/wv_hmc_n6_t0001_tau0bank_val10k_eps016_n10_g55_16x10000_20260603/sample_18880.anode01
OUT=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_t0001_tau0bank_validation_20260603/restart_banks/val10k_final_state_bank.dat
python3 /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/codex/workspaces/fortran_modernization/tasks/scripts/build_wv_hmc_state_bank.py \
  --input-root "$RUN_ROOT" \
  --output "$OUT" \
  --state-size 72
```

For a matched-seed continuation run, use:

```text
WV_OBS_INIT_MODE=state_bank
WV_OBS_INIT_BANK_FILE=$OUT
WV_OBS_INIT_BANK_RECORD=-1
WV_OBS_INIT_BANK_RECORD_MODE=seed_offset
WV_OBS_SEED_COUNT=16
```

If the job is interrupted before final states are written, use the cyclic
snapshot or state-history records to build a fallback state bank with
`build_wv_hmc_state_bank_from_history.py`.  This fallback is suitable for
resuming from recently visited states but should be labeled as snapshot-bank
restart, not final-state continuation.

## Relation To Earlier Moving Runs

This result should not be confused with the earlier moving `T1=0.03` retune.
The earlier retune that reported nonzero movement used different initialization
and sampling-shape conditions:

- the `gamma=0` retune used `init_mode=bank`, `initial_flow_time=0.001`, and
  produced nonzero movement with `epsilon=0.010,nstep=8`;
- the later `gamma=55` validation used a warm WV state bank generated from the
  successful `gamma=0` interval run, not a fresh state pinned at the lower edge;
- the current smoke starts at `t=1e-4` or `5.5e-4` from a bank validated only to
  `t=1e-4`.

The trace comparison shows that this was not primarily a low-end restart trap:
the old interval-warm bank also became an accepted no-op chain under the
pre-fix source.  The root issue was the current source treating internal Newton
boundary exits as production boundary reflections.

## Immediate Next Checks

1. Run the fixed-kernel `n=6` validation with history enabled and confirm that
   movement, flow histogram, and observables behave over a non-smoke cycle
   count.
2. Keep the trace comparison as a regression guard: stop_reason=10 should not
   reappear as the dominant accepted-transition path in production.
3. If interior initialization is used, build a bank prevalidated to the intended
   initial flow time, not just `t=1e-4`.
4. Prefer a staged warm-up path for production restarts: `t=0`/`t=1e-4` x-bank
   to a moving low-gamma or known-good interval run, then build a target-matched
   WV state bank from state history after burn-in.
5. Only after nonzero movement remains stable should epsilon/nstep and
   W-profile tuning resume.

## Current Interpretation Boundary

This result does not prove the WV-HMC mathematical construction is wrong.  It
does prove that the pre-fix executable/source/settings combination was not a
valid production sampler for `n=6,T1=0.03`, because the transition kernel was
effectively sticky under the tested starts.  The fixed kernel restores movement
in short trace tests; observable correctness still requires the next validation
run.
