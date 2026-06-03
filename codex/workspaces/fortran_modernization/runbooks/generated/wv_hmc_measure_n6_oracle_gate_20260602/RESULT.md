# WV-HMC Measurement Convention N6 Oracle Gate

Recorded: 2026-06-02 JST

## Submitted Jobs

| job_id | queue | node | status | note |
|---|---|---|---|---|
| 18804.anode01 | C17 | cnode37 | failed | gitless snapshot missed `.deps/python-devel-3.11` |
| 18805.anode01 | C17 | cnode37 | failed | gitless snapshot missed `build/makefile` |
| 18806.anode01 | C17 | cnode37 | passed | deterministic build/test and n=6 oracle gate |

## Passing Gate

| field | value |
|---|---|
| job_id | 18806.anode01 |
| queue | C17 |
| node | cnode37 |
| exit_status | 0 |
| walltime | 00:00:33 |
| cput | 00:00:31 |
| source_pin_id | 4597ced50bd8-6935aef58654 |
| remote_snapshot | `/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_measure_n6_oracle_gate_20260602` |
| remote_log_root | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_measure_n6_oracle_gate_20260602` |

## Required Evidence Lines

From `remote_logs/test_wv_hmc_math_kernels.18806.anode01.log`:

```text
[CHECK] wv_worldvolume_measure_factor_identity_case ok=T n=6 flow_time=  3.0000E-03 alpha_rel=  1.1275E-15 logabs_identity=  0.0000E+00 logdet_volume=  3.1086E-15
[PASS] WV-HMC math kernels
```

From `remote_logs/test_wv_hmc_constraint_kernels.18806.anode01.log`:

```text
[CHECK] wv_boundary_paper_full_flip ok=T
[CHECK] wv_transition_boundary_bounce_rg ok=T
[PASS] WV-HMC constraint kernels
```

From `remote_logs/pbs_boot_18806.anode01.log`:

```text
WV_HMC_GITLESS_BUILD_GATE_COMPLETE
```

## Closed

- W(t) measurement convention deterministic gate.
- Nonzero-W measurement factor test: W is diagnostic/potential only and does not multiply `wv_factor`.
- Explicit n=6 alpha/measure oracle with independent Gram determinant check.
- Constraint kernel boundary/RG gates.
- `run_wv_hmc` build from the same source-pinned gitless snapshot.

## Still Open

- Current-source n=6 short validation with a pre-declared measurement window.
- Production-readiness claim.
