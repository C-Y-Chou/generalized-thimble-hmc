# WV-HMC n=6 Gamma55 Long Validation Launch 2026-06-01

Purpose: validate the histogram-flat `paper_wall` setting after the gamma scan
showed that `gamma=55` is the current count-flat baseline on
`[T0,T1]=[0.0001,0.03]`.

This run is not choosing `gamma` by phase coherence.  Phase coherence,
observable z-scores, acceptance, transition failures, and runtime are
downstream health checks after the flow-time histogram criterion is satisfied.

## Run

```text
request_id = FMOD-WV-HMC-N6-T003-GAMMA55-VALIDATION-768X15000-GITLESS-20260601
run_name = wv_hmc_n6_t003_gamma55_validation_768x15000_gitless_20260601
remote_root = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_gamma55_validation_20260601/wv_hmc_n6_t003_gamma55_validation_768x15000_gitless_20260601
runtime_snapshot = /lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n6_t003_prod15k_gitless_r3_20260601
source_pin = 8ec6dc0d9b87-86f750bba994
parameters = data/parameters_stephanov_n6_mu06_t0.dat
model = Stephanov n=6, mu=0.6, tau=0
```

## Parameters

```text
T0 = 0.0001
T1 = 0.03
D0 = 0.0001
D1 = 0.005
measurement = [0.0001, 0.03]
W profile = paper_wall
gamma = 55
epsilon = 0.010
nstep = 8
L = 0.080
constraint_tol = 1e-10
constraint_max_iter = 192
adaptive_newton_stop = off
large_residual_stop = off
ODE backend = dop853
init_mode = state_bank
warm_state_bank = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_retune_validation_20260531/wv_hmc_n6_t003_retuned_g0_eps010_n8_max192_32x1000_20260531/warm_bank/x_bank.dat
cycles = 15000
measurement_start_cycle = 501
observable_history = on
final_state = on
```

## Submission

Initial submission used 48 chunks x 16 seeds on C17:

```text
jobs = 18531-18578
seed_start = 9100001 + 16 * chunk
```

C17 admitted only the first 3 chunks immediately.  Queued chunks were moved to
eligible queues and memory requests were reduced to 16gb for queued jobs.
Chunk 03 was split into two 8-seed chunks after canceling queued job 18534:

```text
18579: chunk 03a, seeds 9100049-9100056
18580: chunk 03b, seeds 9100057-9100064
```

Initial scheduler behavior exposed a packing bug in the local scheduler model:
the ranking table had node CPU capacity, but did not explicitly expose
`jobs_per_node` or PBS `max_run_res.nodect` per-user queue caps.  The scheduler
agent has been patched to report:

```text
jobs_per_node_min
jobs_per_node_max
max_jobs_by_ncpus
free_jobs_by_ncpus
user_nodect_cap
user_cap_remaining
schedulable_jobs_now
```

After queue optimization and canceling over-cap queued jobs, active coverage is:

```text
running jobs = 35
running seeds = 552
queued jobs = 0
queued seeds = 0
```

Canceled queued jobs were over-cap excess, not failed simulation jobs.  If the
552-seed first wave is borderline, submit a second wave using the patched
schedulable job counts rather than submitting more seeds than the queue can
start.

## Health Checks Required

- Boot logs exist for every running job.
- No source-pin, `libpython`, missing-bank, or initial-state errors.
- Exact `run_wv_hmc` kernel counts match active jobs on sampled nodes.
- `seed_*_observable_history.csv` files exist.
- After cycle 501, history row counts advance; use row-count slope for ETA.
- Completion requires all expected seeds, no timed out manifest rows, observable
  history, summary, observable, and final-state files present.
