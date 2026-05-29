# WV-HMC Formal Observable Validation 20260530

Scope: Stephanov `n=2` dense WV-HMC formal observable gate before matrix-free
trajectory wiring.

Execution policy: no local Fortran simulation evidence is used. The validation
ran on cluster02 through `cluster02_qsub_gate.sh` from the isolated WV pilot
worktree:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_wv_pilot_01f58ba
```

## Code State

- Branch: `codex/nofb-runtime-optimization-20260528`
- Commit: `8ec6dc0d9b8768c5432e8c9df883a9cd870a82ba`
- Job: `17946.anode01`
- Queue/node: `C16` / `cnode01`
- Exit status: `0`

## Fixed Validation Setting

```text
model = Stephanov n=2
parameters_file = data/parameters_stephanov_n2_smoke.dat
W profile = paper_wall
T0 = 0.005
T1 = 0.2
d0 = 0.005
d1 = 0.05
measurement interval = [0.005, 0.2]
init_mode = bank
init_bank_file = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260530/stephanov_n2_wv_hmc_t0_initial_bank_8x2000_t0005_20260530_repair1_17926.anode01/safe_bank_t0p005/x_bank.dat
epsilon = 0.002
nstep = 2
cycles = 4000
measurement_start_cycle = 1001
seeds = 64
jobs = 16
ODE backend = dop853
constraint_tol = 1.0e-8
constraint_max_iter = 10
adaptive_newton_stop_enabled = 0
```

## Main Artifacts

```text
run_root = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0002_s2_20260530_17946.anode01
readback = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0002_s2_20260530_17946.anode01/readback/wv_hmc_pilot_readback.md
summary_csv = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0002_s2_20260530_17946.anode01/readback/wv_hmc_pilot_summary.csv
observable_z_csv = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0002_s2_20260530_17946.anode01/readback/wv_hmc_pilot_observable_z.csv
manifest = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0002_s2_20260530_17946.anode01/wv_hmc_dense_observable_validation_manifest.csv
```

## Runtime And Transition Diagnostics

```text
manifest_rows = 64
failed_rows = 0
walltime = about 10 minutes
per_seed_runtime_sec_min = 25.75
per_seed_runtime_sec_median = 64.68
per_seed_runtime_sec_max = 351.996
acceptance_min = 0.951
acceptance_median = 0.978125
acceptance_max = 0.99725
flow_time_mean_min = 0.0249272461
flow_time_mean_median = 0.0897267635
flow_time_mean_max = 0.143177813
phase_coherence = 0.955925
metropolis_rejections = 0
reverse_gate_rejections = 5929
forward_construction_failures = 48
ODE_failures = 3
```

## Observable Gate

Exact references used by the readback script:

```text
chiral_condensate = 0.380047505938398
number_density = 0.0387173396674602
```

Readback:

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.303233428 | 0.0279 | -2.75 | -0.0452650279 | 0.0209 | -2.16 |
| logdet_dirac | 0.427355647 | 0.18 |  | 0.430302674 | 0.504 |  |
| min_singular_ba_m2 | 0.603306467 | 0.0458 |  | -0.00803993544 | 0.0106 |  |
| number_density | 0.182650017 | 0.0436 | 3.3 | 0.0726480016 | 0.0445 | 1.63 |
| phase_factor | 0.851011073 | 0.0269 |  | 0.00718206803 | 0.0381 |  |

## Conclusion

This `bankinit_eps0002_s2` WV-HMC dense validation does not pass the observable
correctness gate, and it is no longer treated as a valid formal tuning gate.

The job itself completed cleanly, and transition diagnostics are not the
failure mode. The failure is in the physics readback: `chiral_condensate` has
`z_Re=-2.75` and `z_Im=-2.16`; `number_density` has `z_Re=3.3`.

Do not promote `epsilon=0.002, nstep=2, bank init` as a validated WV-HMC
production setting. The next WV-HMC step should diagnose whether this is caused
by insufficient mixing at very high acceptance / small effective trajectory
length, the bank-start protocol, or an implementation/measurement issue.

Retrospective correction: this run was launched before the WV-HMC tuning
sequence was properly enforced. A formal WV-HMC validation must first choose
`epsilon` from actual transition acceptance, then choose `L = epsilon*nstep`
using configuration-space movement diagnostics (`||delta x||^2/n`,
`||delta z||^2/n`, effective jump including rejections), not flow-time movement
alone. Flow-time movement is only an extended-variable diagnostic.

## Corrected Configuration-Movement Validation

After adding configuration-space movement diagnostics, the fixed-`epsilon`
scan at `epsilon=0.015` selected `nstep=3`, i.e. `L=0.045`, as the first
corrected formal validation candidate. This choice uses effective and accepted
`x/z` movement, not flow-time movement alone.

```text
worktree = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_wv_config_movement_6838a5c
commit = 5f71da6b6fdc7516d46f09e473d01b26150af25a
job = 17961.anode01
queue/node = C16 / cnode01
exit_status = 0
run_root = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0015_s3_configmove_20260530_17961.anode01
readback = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0015_s3_configmove_20260530_17961.anode01/readback/wv_hmc_pilot_readback.md
summary_csv = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0015_s3_configmove_20260530_17961.anode01/readback/wv_hmc_pilot_summary.csv
observable_z_csv = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_formal_validation_n2_64x4000_bankinit_eps0015_s3_configmove_20260530_17961.anode01/readback/wv_hmc_pilot_observable_z.csv
```

Fixed setting:

```text
model = Stephanov n=2
W profile = paper_wall
T0 = 0.005
T1 = 0.2
d0 = 0.005
d1 = 0.05
measurement interval = [0.005, 0.2]
init_mode = bank
epsilon = 0.015
nstep = 3
L = 0.045
cycles = 4000
measurement_start_cycle = 1001
seeds = 64
jobs = 16
ODE backend = dop853
constraint_tol = 1.0e-8
constraint_max_iter = 10
```

Runtime and transition diagnostics:

```text
manifest_rows = 64
failed_rows = 0
walltime = about 20.5 minutes
per_seed_runtime_sec_min = 195.33
per_seed_runtime_sec_median = 256.54
per_seed_runtime_sec_max = 349.22
phase_coherence = 0.928055
accepted_transitions = 199276
accepted_transition_rate_including_failures_and_rejections = 0.778422
metropolis_rejections = 47
reverse_gate_rejections = 32584
forward_construction_failures = 24093
ODE_failures = 736
effective_x_jump_sq_per_cycle = 0.00256
effective_z_jump_sq_per_cycle = 0.00160404
accepted_x_jump_sq_per_accepted_proposal = 0.00328871
accepted_z_jump_sq_per_accepted_proposal = 0.00206063
```

Observable readback:

| observable | Re | SE Re | z Re | Im | SE Im | z Im |
|---|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.359037053 | 0.0106 | -1.98 | -0.00293078253 | 0.0117 | -0.25 |
| logdet_dirac | 0.640649432 | 0.0923 |  | 1.07627648 | 0.23 |  |
| min_singular_ba_m2 | 0.580155349 | 0.0181 |  | 0.00415991337 | 0.00649 |  |
| number_density | 0.0484803706 | 0.024 | 0.408 | -0.0164638007 | 0.0337 | -0.489 |
| phase_factor | 0.747227899 | 0.0232 |  | -0.015636527 | 0.0239 |  |

Interim conclusion: `epsilon=0.015, nstep=3, L=0.045` is the first WV-HMC
dense n=2 candidate that passes this observable smoke gate under the corrected
configuration-space movement tuning rule. This is not yet a production claim:
it is a pre-matrix-free dense validation checkpoint.
