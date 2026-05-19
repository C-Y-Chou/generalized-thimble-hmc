# F20E R3 Conservative Relaxed Validation Readback

Date: 2026-05-19 JST

Canonical workspace: `/Users/ccy/Documents/TLTM_qn_error_handling`

Remote workspace:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`

Scheduler request:
`FMOD-F20E-R3-CONSERVATIVE-RELAXED-VALIDATION-20260519`

Source commit: `5605ca4ade833d5eac8bbe1677fdb13cfee43317`

Scheduler state commits:

- request row: `39748b4adee4b7a4e49d5ad9eb2c4ec0e3555c6f`
- submission row: `932857ec42c8f2b7330b61aa1cd2c667e39af3df`

## Scope

This validates the conservative fallback after the F20D R3 `tau1e10`
candidate failed the `fb_norefine` Re aggregate check.

- scale: 32 seeds x 50000 cycles
- methods: `no_fb`, `fb_norefine`
- config: `docs/modernization_reference_t035_r3_32seed_50k.json`
- comparison root:
  `output/reference/fortran_modernization/m6/r3_32seed_50k`
- output root:
  `output/tests/f20_double_tolerance_validation/f20e_double_ode1e12_ntqn1e12_dfols1e15_conservative_r3_32seed_50k_5605ca4ade83`

Preset:

- `TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-12`
- `TLTM_STAGE2_REL_TOL_OVERRIDE=1e-12`
- `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-12`
- `QN_QUASI_TOL_OVERRIDE=1e-12`
- `QN_REVERSE_GATE_TOL=1e-8`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-15`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-24`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`

## PBS Readback

All submitted jobs finished with exit status 0.

| job | id | queue | result |
|---|---:|---|---|
| build | 16127 | C16 | exit 0, walltime 00:01:54 |
| no_fb chunk_00 | 16128 | C8 | exit 0, walltime 00:29:23 |
| no_fb chunk_01 | 16129 | C8 | exit 0, walltime 00:29:07 |
| no_fb chunk_02 | 16130 | C8 | exit 0, walltime 00:28:46 |
| no_fb chunk_03 | 16131 | C8 | exit 0, walltime 00:29:04 |
| fb_norefine chunk_00 | 16132 | C8 | exit 0, walltime 00:51:54 |
| fb_norefine chunk_01 | 16133 | C8 | exit 0, walltime 00:46:52 |
| fb_norefine chunk_02 | 16134 | C8 | exit 0, walltime 00:46:26 |
| fb_norefine chunk_03 | 16135 | C8 | exit 0, walltime 00:47:04 |
| merge | 16136 | C16 | exit 0, walltime 00:00:01 |

Structural readback:

- `no_fb/per_seed_summary_table.csv`: 32 rows
- `fb_norefine/per_seed_summary_table.csv`: 32 rows
- both methods have `aggregated_summary_table.csv`
- both methods have 32/32 protocol-audit pass rows with zero errors/warnings
- strict R3 reference comparison artifacts are present

Preflight / environment:

- no `Python.h` / `pyconfig` / fatal `libpython` failure pattern was found
- DFO-LS bridge runtime traces are present in `fb_norefine` logs:
  2468 `Traceback` records of `RuntimeError: TLTM residual callback failed`
- those traces are rejected QN attempts recorded by the official DFO-LS bridge,
  not Python environment or preflight failures; all PBS jobs and protocol audits
  completed successfully

## Metrics

| method | seeds | mean Re | seed std Re | mean err Re | Zmean Re | P68 Re | P95 Re | mean Im | seed std Im | mean err Im | Zmean Im | P68 Im | P95 Im | runtime s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 32 | 0.0095557645 | 0.0734120394 | 0.0794091038 | 0.7363310926 | 0.75000 | 0.96875 | -0.0068730890 | 0.0568975981 | 0.0463496345 | -0.6833339926 | 0.62500 | 0.93750 | 1681.008447 |
| fb_norefine | 32 | 0.0237220990 | 0.0698269906 | 0.0661562226 | 1.9217849044 | 0.56250 | 0.93750 | -0.0009638549 | 0.0401098819 | 0.0427124285 | -0.1359362505 | 0.71875 | 0.96875 | 2735.621056 |

Diagnostic counters:

| method | unresolved | projection mean | RG rejects | ODEX calls | accepted steps | rejected steps | RHS evals |
|---|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 133261 | 4676.84375 | 16398 | 898991122 | 4606880728 | 154537626 | 129981632656 |
| fb_norefine | 26621 | 1715.81250 | 28285 | 951924160 | 5054056604 | 199441902 | 150417195507 |

Reference aggregate deltas:

| method | d mean Re | d mean Im | d Zmean Re | d Zmean Im | d unresolved | d RG rejects | d runtime s | runtime saving |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | -0.0106330276 | -0.0018872162 | -0.5971355544 | -0.1296840960 | 12403 | -2799 | -1752.960665 | 51.05% |
| fb_norefine | 0.0235536970 | -0.0024645965 | 1.9074485046 | -0.3094507585 | -1585 | 3358 | -1330.981983 | 32.73% |

Paired observable drift:

| method | paired seeds | mean dRe | SE dRe | z dRe | max abs dRe | mean dIm | SE dIm | z dIm | max abs dIm | d failures/seed | d RG rejects/seed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 32 | -0.0106330276 | 0.0215486428 | -0.4934430314 | 0.3168291220 | -0.0018872162 | 0.0131188555 | -0.1438552458 | 0.2044209324 | 387.59375 | -174.93750 |
| fb_norefine | 32 | 0.0235536970 | 0.0168569211 | 1.3972715933 | 0.2038027445 | -0.0024645965 | 0.0114359357 | -0.2155133192 | 0.1199052532 | -49.53125 | 209.87500 |

## Interpretation

Compared with the rejected F20D `tau1e10` candidate, this conservative preset
removes the clear `fb_norefine` aggregate failure:

- F20D `fb_norefine` candidate `Zmean Re`: `2.7972709349`
- F20E `fb_norefine` candidate `Zmean Re`: `1.9217849044`
- F20D paired `fb_norefine` Re drift z: `1.8256050121`
- F20E paired `fb_norefine` Re drift z: `1.3972715933`

The tradeoff is runtime:

- `no_fb` remains fast, saving `51.05%` versus strict R3 reference
- `fb_norefine` saves `32.73%`, less than F20D's `44.89%`
- combined mean runtime saving is `41.12%`

This is the first R3 relaxed double preset that passes the primary aggregate
and paired-drift screen for both methods, but `fb_norefine` Re is close enough
to 2 sigma that it should be carried forward with a caution label.

## Decision

Treat `double_ode1e12_ntqn1e12_dfols1e15_conservative` as the current
conservative relaxed double candidate.

Do not call it final production default yet. The next step should be a targeted
confirmation, either a second independent 32seed x 50k block or a larger
production-scale validation, before promoting this preset.

Single precision remains closed as an active direction.
