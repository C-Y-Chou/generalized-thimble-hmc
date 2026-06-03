# WV-HMC n=6 T1=0.03 Production SOP

Date: 2026-05-31

Purpose: freeze the currently tuned dense explicit-J WV-HMC Stephanov `n=6`,
`T1=0.03` production workflow.  This is the operator SOP for running the
current production preset, not a tuning plan.

## Scope

This SOP applies to the current dense WV-HMC Stephanov production setting:

```text
model = Stephanov
n = 6
nf = 1
m = 0.004
mu = 0.6
tau = 0
parameters_file = data/parameters_stephanov_n6_mu06_t0.dat
```

Do not silently reuse this SOP for a different model, `n`, action derivative,
`[T0,T1]`, `W(t)`, ODE backend, bank, `epsilon`, `nstep`, or Newton policy.
Changing any of those upstream inputs returns the workflow to
`WV_HMC_PARAMETER_TUNING_SOP_20260531.md`.

All production simulations run on the cluster through the cluster02 scheduler
gate.  No local Fortran production runs.

Current production must run from a gitless runtime snapshot with a source pin.
Do not depend on node-local `git` on compute nodes.

## Current T0=0 Candidate Preset

This preset is not production-approved.  It is the best current `T0=0`
mechanical tuning candidate after rebuilding the `T0` bank and retuning
`W(t)`/HMC parameters.  The 32 x 1500 full-interval validation run did not pass
the observable gate; see `runbooks/generated/wv_hmc_t0_retune_20260601/README.md`.
The follow-up window/cut diagnostic shows that the failure is concentrated in
early and low-flow measurements, while late high-flow cuts are statistically
compatible with the exact references at current precision.  Therefore this is
not yet evidence for a deterministic measurement-formula bug; treat it as a
thermalization / measurement-subinterval warning until a high-flow late-measure
validation is run:

```text
runbooks/generated/wv_hmc_t0_retune_20260601/diagnose_slow_mixing_vs_bug/README.md
```

```text
T0 = 0
T1 = 0.03
D0 = 0.0001
D1 = 0.005
transition interval = [T0,T1]
default diagnostic measurement interval = [T0,T1]
next validation measurement interval = [0.025,T1] or [0.028,T1]
W(t) = paper_wall
W gamma = 65.0
W c0 = 1.0
W c1 = 1.0

ODE backend = dop853
TLTM_DOP853_HINIT_ENABLED = 1
TLTM_DOP853_STIFFNESS_CHECK_ENABLED = 1
TLTM_DOP853_STIFFNESS_CHECK_INTERVAL = 1000
TLTM_DOP853_STIFFNESS_MAX_HITS = 15
TLTM_DOP853_STIFFNESS_THRESHOLD = 6.1

epsilon = 0.009
nstep = 10
L = 0.090

constraint_tol = 1.0e-10
constraint_max_iter = 192
adaptive_newton_stop = off
large_residual_stop = off

reverse_gate_state_tol = 1.0e-5
reverse_gate_momentum_tol = 1.0e-3
reverse gate = on
```

The large-residual Newton gate exists only as a diagnostic/fail-fast knob.  The
current calibrated production default is off because the A/B test found no
material production speedup.

## Initial Bank

Use the `T0=0` state bank built from the lower fixed-tau HMC builder:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat
```

This is a WV state bank with record format:

```text
flow_time + x
```

Required loader:

```text
WV_OBS_INIT_MODE = state_bank
WV_OBS_INIT_BANK_RECORD = -1
```

Do not use x-only `bank` mode for this file.

If this warm bank is replaced, the preferred rebuild path is a lower fixed-tau
flow-state bank:

- default to `tau_bank = 0`, the physical manifold lower endpoint.  Do not use a
  positive lower `tau_bank` to hide solver/reflow failures;
- if a positive lower `tau_bank` is intentionally used, it must show zero
  proposal/reflow solver failures at the already selected fixed-tau builder
  `epsilon` and `L`; otherwise lower `tau_bank`, not `epsilon`;
- tune the fixed-tau builder independently, allowing larger `epsilon` and
  larger `L` than the WV-HMC production kernel when acceptance and
  configuration-space movement support it;
- enable cyclic snapshots and harvest only a declared post-burn-in window;
- pack records as `flow_time + x` with `flow_time=tau_bank`;
- rerun the WV-HMC solver trace, HMC tuning health checks, flow-histogram check,
  and observable validation before treating the replacement bank as production
  equivalent.

## Production Chunk Shape

Default 12-hour production package:

```text
total seeds = 64
chunks = 4
seeds per chunk = 16
cycles per seed = 15000
measurement_start_cycle = 501
observable_history = on
final_state = on
x_history = off
state_history = off
history_stride = 1
per-seed timeout = 42000 sec
PBS walltime = 12:00:00
```

Rationale:

- the `32 x 1000` smoke had max seed runtime about `2402 sec / 1000 cycles`;
- the later matched A/B run had a slower node around `2.6 sec / cycle`;
- `15000 cycles` gives an expected slow-node runtime around `10-11 hr`, leaving
  scheduler overhead below the 12-hour walltime;
- `16` seeds per chunk uses the `ncpus=16` PBS allocation.

If a future node class is slower than this envelope, reduce cycles before
submission.  Do not rely on PBS killing the job as a normal stopping condition.

## Submission Contract

Use only:

```text
TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler
TLTM_SCHEDULER_REQUEST_ID=<request-id>
codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh ...
```

Do not use bare `qsub`.

Every chunk must set:

```text
TLTM_WORKTREE=<runtime snapshot root>
TLTM_REQUIRE_SOURCE_PIN=1
TLTM_SOURCE_PIN_FILE=<runtime snapshot root>/codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env
TLTM_PARAMETERS_FILE=data/parameters_stephanov_n6_mu06_t0.dat
TLTM_OUTPUT_ROOT=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_production_20260531
TLTM_RUN_NAME=wv_hmc_n6_t003_prod64x15000_20260531

WV_OBS_CYCLES=15000
WV_OBS_MEASUREMENT_START_CYCLE=501
WV_OBS_STEP_SIZE=0.010
WV_OBS_NUM_STEPS=8
WV_OBS_INIT_MODE=state_bank
WV_OBS_INIT_BANK_FILE=<warm state bank>
WV_OBS_INIT_BANK_RECORD=-1
WV_OBS_SEED_COUNT=16
WV_OBS_JOBS=16
WV_OBS_TIMEOUT_SEC=42000

WV_OBS_WRITE_FINAL_STATE=1
WV_OBS_WRITE_OBSERVABLE_HISTORY=1
WV_OBS_WRITE_X_HISTORY=0
WV_OBS_WRITE_STATE_HISTORY=0
WV_OBS_HISTORY_STRIDE=1
WV_OBS_WRITE_CYCLIC_SNAPSHOT=1
WV_OBS_SNAPSHOT_INTERVAL=500
WV_OBS_SNAPSHOT_SLOTS=8

WV_OBS_CONSTRAINT_TOL=1.0e-10
WV_OBS_CONSTRAINT_MAX_ITER=192
WV_OBS_ADAPTIVE_NEWTON_STOP_ENABLED=0
WV_OBS_LARGE_RESIDUAL_STOP_ENABLED=0

WV_OBS_T0=0.0
WV_OBS_T1=0.03
WV_OBS_D0=0.0001
WV_OBS_D1=0.005
WV_OBS_MEASUREMENT_T0=0.0
WV_OBS_MEASUREMENT_T1=0.03
WV_OBS_W_PROFILE=paper_wall
WV_OBS_W_GAMMA=0.0
WV_OBS_W_C0=1.0
WV_OBS_W_C1=1.0
```

Seed starts for the default 64-seed run:

```text
chunk 00: 8980001
chunk 01: 8980017
chunk 02: 8980033
chunk 03: 8980049
```

For larger production, extend the same seed convention by adding `16` per
chunk.  Use only queues that the scheduler ranks as safe for the current
source-pin guard.

## Runtime Snapshot And Queue Ranking

Before submission, create a source-pinned runtime snapshot on the cluster login
node:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py runtime-snapshot \
  --snapshot-root /lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/<run-id> \
  --allow-dirty \
  --delete
```

Then refresh inventory and rank queues for the gitless guard:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py inventory \
  --hardware-probe \
  --max-workers 16 \
  --ssh-timeout 5

python3 codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py rank-queues \
  --ncpus 16 \
  --mem-gb 32 \
  --walltime 12:00:00 \
  --gitless-guard \
  --output-csv codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_RANKING_WV_HMC_N6_16CPU_12H.csv
```

For `15000`-cycle chunks, prefer `C17`/`C17-LONG`, then `C12`/`C12-LONG`, then
`C8`/`C8-LONG`.  Avoid `C16` for 15000-cycle production when faster queues are
available; it is an eligible slow fallback but the 2026-05-31 run showed it can
miss the 12-hour envelope.

## First Progress Check

Check after 20-30 minutes:

- all chunks are `R`, or queued chunks have a clear scheduler reason;
- each running chunk has created its `pbs_boot` log;
- no `invalid_initial_state`, missing `bin/run_wv_hmc`, or timeout errors;
- exact `run_wv_hmc` process counts match the intended packing. Use
  `pgrep -x run_wv_hmc`, not `pgrep -af bin/run_wv_hmc`; the latter also
  matches wrapper Python commands that contain `--binary bin/run_wv_hmc`;
- `seed_*_observable_history.csv` files exist. They may initially contain only
  the header because measurement rows start at `measurement_start_cycle`.

Early absence of summary files is not automatically a failure because summaries
are written after each seed process finishes.

## Completion Checks

After all chunks finish, require:

```text
manifest rows = 64
return_code = 0 for all rows
summary_present = 1 for all rows
observable_present = 1 for all rows
observable_history_present = 1 for all rows
final_state_present = 1 for all rows
timed_out = 0 for all rows
```

Then run the standard readback:

- scan summary grouped by the production preset;
- observable-history ratio readback with exact references;
- cumulative estimates by cycle prefix;
- first-half vs second-half comparison;
- seed/block uncertainty checks;
- flow-time histogram and movement summary;
- Newton stop table;
- runtime distribution.

Exact references:

```text
chiral_condensate = 0.0244771983
number_density = 0.5661155667
```

## Current Evidence Boundary

The current preset passed a `32 x 1000` smoke with exact-reference z-scores
below 1, good acceptance, and nonzero configuration-space movement.  The
production run is needed for precision, stability, and seed/block robustness.
Do not promote the smoke result to a final production physics conclusion.
