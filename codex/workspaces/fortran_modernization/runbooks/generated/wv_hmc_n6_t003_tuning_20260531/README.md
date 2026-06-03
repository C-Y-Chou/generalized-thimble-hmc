# WV-HMC n=6 t=0.03 Tuning Pass

Date: 2026-05-31

Purpose: tune `W(t)`, `epsilon`, and `nstep/L` for the first longer
Stephanov `n=6`, `t_high = 0.03` dense explicit-J WV-HMC validation.

All simulation data in this pass came from scheduler-gated cluster jobs on
`ithems_fe02.intra.riken.jp`.  No local Fortran simulation was used.

## Fixed Inputs

```text
model = Stephanov n=6, nf=1, m=0.004, mu=0.6, tau=0
parameters_file = data/parameters_stephanov_n6_mu06_t0.dat
init = t=0.0001 safe bank
T0 = 0.0001
T1 = 0.03
D0 = 0.0001
D1 = 0.005
measurement interval = [T0,T1]
ODE backend = dop853
constraint_tol = 1e-10
constraint_max_iter = 24
adaptive_newton_stop = off
reverse gate = on
```

## Gamma / W(t) Scan

Scanned `paper_wall` `gamma = 0, 0.5, 1, 2, 4, 8` at
`epsilon=0.010`, `nstep=8`, 8 seeds x 400 cycles.

Decision: use `gamma=0` for the longer validation.

Reason: positive `gamma` did not provide a stable improvement in measurement
flow-time histogram coverage over `gamma=0`.  `gamma=0` already had no empty
histogram bins, reached the high-flow endpoint, and had one of the best
histogram max/min ratios in this short scan.  The selected setting also avoids
adding an unnecessary interior W tilt before the first `t_high=0.03`
validation.

Primary artifact:

```text
gamma_final/wv_hmc_scan_summary.md
```

## Epsilon Scan

Fixed `gamma=0`, `nstep=8`, and scanned
`epsilon = 0.010, 0.0125, 0.015, 0.020, 0.025, 0.030`.

Decision: use `epsilon=0.015`.

Reason: `epsilon=0.015` gave acceptance about `0.73` with a clear movement
gain over `0.0125`.  `epsilon=0.020` already dropped acceptance to about
`0.60`, so `0.015` is the practical bracket point for the movement scan.

Primary artifact:

```text
epsilon_scan/wv_hmc_scan_summary.md
```

## Nstep / L Scan

Fixed `gamma=0`, `epsilon=0.015`, and scanned
`nstep = 4, 6, 8, 10, 12`.

Decision: use `nstep=10`, hence `L=0.15`.

Reason: `nstep=10` is the movement/cost elbow.  It gave much larger
configuration-space movement than `nstep=8` while keeping acceptance about
`0.69`.  `nstep=12` gave additional movement but lower acceptance, no
flow-time movement gain, and noticeably higher wall-clock cost in the scan.

Primary artifact:

```text
nstep_scan/wv_hmc_scan_summary.md
```

## Superseded Longer Validation Attempt

Submitted run:

```text
run_root = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_validation_20260531/wv_hmc_n6_t003_gamma0_eps015_nstep10_64x5000_20260531
jobs = 18381.anode01 ... 18390.anode01
nominal production chunks = 64 seeds x 5000 cycles
replacement chunks = 16 additional seeds x 5000 cycles
measurement_start_cycle = 1001
observable_history = on
final_state = on
```

Early diagnostic: 4 of the first 64 seeds failed at cycle 0 with ODE status
103 from the initial bank draw.  Replacement seeds were submitted immediately.
Final analysis must use the manifest to include only successful seeds and must
report the initial-draw failures separately.

Status update: this long validation attempt was stopped after the early check.
The first completed seed had `accepted=0/5000`, `transitions_failed=4966/5000`,
and `solver_stop_max_iter=4414`, with flow time fixed at the initial value.
That invalidates the `constraint_max_iter=24` carry-over from the small
`T1=1e-3` solver cap gate.  Including `T1=0.03` makes the geometry harder, so
the solver cap must be recalibrated before any long validation is
decision-grade.

Follow-up diagnostic submitted:

```text
hard init-bank record = 70
T1 = 0.03
gamma = 0
epsilon = 0.015
nstep = 10
max_iter candidates = 24, 64, 96, 128
jobs = 18391.anode01 ... 18394.anode01
output root = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_solver_cap_20260531
```

Decision rule: if increasing `max_iter` rescues accepted transitions or sharply
reduces `solver_stop_max_iter`, then the cap was too small.  If even 96/128
does not rescue the hard record, then the next gate is bank/mobility screening
or a different trajectory setting, not a production validation.

Result:

| max_iter | seeds | cycles | accepted/cycle | transition failure/cycle | RG reject/cycle | flow moved? |
|---:|---:|---:|---:|---:|---:|---|
| 24 | 4 | 400 | 0 | 0.9925 | 0.0075 | no |
| 64 | 4 | 400 | 0 | 0.4775 | 0.5225 | no |
| 96 | 4 | 400 | 0 | 0.2750 | 0.7250 | no |
| 128 | 4 | 400 | 0 | 0.2075 | 0.7925 | no |

Conclusion: `max_iter=24` is too small for the `T1=0.03` geometry, but simply
raising the cap does not make the hard record productive.  Higher caps convert
many construction failures into completed proposals that then fail the reverse
gate; the chain still has zero accepted moves and no flow-time movement.  The
next decision must therefore be a large-flow mobility/initial-bank gate and a
fresh trajectory retune under a recalibrated cap, not a direct restart of long
validation.

Local copied artifact:

```text
solver_cap_hard_record70/wv_hmc_scan_summary.md
```

## Final Readback Command

After the jobs finish, run on the cluster worktree:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/write_wv_hmc_history_readback_20260531.py \
  --root /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_validation_20260531/wv_hmc_n6_t003_gamma0_eps015_nstep10_64x5000_20260531 \
  --out-dir /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_validation_20260531/wv_hmc_n6_t003_gamma0_eps015_nstep10_64x5000_20260531/readback \
  --exact-chiral 0.0244771983 \
  --exact-density 0.5661155667 \
  --prefix-cycles 1000,2000,3000,4000,5000 \
  --block-cycle-sizes 250,500,1000
```

The readback must report observable z-scores, phase coherence, seed/block
stability, first/second-half behavior, flow-time histogram, acceptance,
initial-draw failures, and runtime.
