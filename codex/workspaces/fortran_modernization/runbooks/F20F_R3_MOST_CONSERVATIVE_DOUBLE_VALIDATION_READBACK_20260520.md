# F20F R3 Most Conservative Double Validation Readback

Date: 2026-05-20 JST

Canonical workspace: `/Users/ccy/Documents/TLTM_qn_error_handling`

Remote workspace:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`

Scheduler request:
`FMOD-F20F-R3-MOST-CONSERVATIVE-DOUBLE-VALIDATION-20260519`

Source commit: `59e9d10acd3592c44293f435d65a50ad05351ef2`

Scheduler state commits:

- request row: `00f7114a0a5ce240ad43e6d7e6177e66828be7d8`
- submission row: `1b3ba5441919137bda22a340225c94de0f62d0f5`

## Scope

This validates the user-specified most-conservative double precision preset at
R3 scale after F20E passed with caution.

- scale: 32 seeds x 50000 cycles
- methods: `no_fb`, `fb_norefine`
- config: `docs/modernization_reference_t035_r3_32seed_50k.json`
- comparison root:
  `output/reference/fortran_modernization/m6/r3_32seed_50k`
- output root:
  `output/tests/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35`

Preset:

- `TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-14`
- `TLTM_STAGE2_REL_TOL_OVERRIDE=1e-14`
- `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-13`
- `QN_QUASI_TOL_OVERRIDE=1e-13`
- `QN_REVERSE_GATE_TOL=1e-8`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-16`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-26`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`

## PBS Readback

All submitted jobs finished with exit status 0.

| job | id | queue | result |
|---|---:|---|---|
| build | 16137 | C16 | exit 0, walltime 00:01:56 |
| no_fb chunk_00 | 16138 | C8 | exit 0, walltime 00:41:18 |
| no_fb chunk_01 | 16139 | C8 | exit 0, walltime 00:40:58 |
| no_fb chunk_02 | 16140 | C8 | exit 0, walltime 00:40:57 |
| no_fb chunk_03 | 16141 | C8 | exit 0, walltime 00:41:10 |
| fb_norefine chunk_00 | 16142 | C8 | exit 0, walltime 01:02:38 |
| fb_norefine chunk_01 | 16143 | C8 | exit 0, walltime 01:00:49 |
| fb_norefine chunk_02 | 16144 | C8 | exit 0, walltime 01:01:09 |
| fb_norefine chunk_03 | 16145 | C8 | exit 0, walltime 01:00:46 |
| merge | 16146 | C16 | exit 0, walltime 00:00:02 |

Structural readback:

- `no_fb/per_seed_summary_table.csv`: 32 rows
- `fb_norefine/per_seed_summary_table.csv`: 32 rows
- both methods have `aggregated_summary_table.csv`
- both methods have 32/32 protocol-audit pass rows with zero errors/warnings
- strict R3 reference comparison artifacts are present

Preflight / environment:

- no `Python.h` / `pyconfig` / fatal `libpython` failure pattern was found
- DFO-LS bridge runtime traces are present in logs:
  2458 `Traceback` records of `RuntimeError: TLTM residual callback failed`
- these are rejected QN attempts recorded by the official DFO-LS bridge, not
  Python environment or preflight failures; all PBS jobs and protocol audits
  completed successfully

## Metrics

| method | seeds | mean Re | seed std Re | Zmean Re | P68 Re | P95 Re | mean Im | seed std Im | Zmean Im | P68 Im | P95 Im | runtime s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 32 | 0.0093236730 | 0.0730294814 | 0.7222105130 | 0.75000 | 0.96875 | -0.0069709609 | 0.0568229711 | -0.6939747969 | 0.62500 | 0.93750 | 2409.259408 |
| fb_norefine | 32 | 0.0117964990 | 0.0681349720 | 0.9793953613 | 0.68750 | 0.96875 | -0.0004064170 | 0.0379895704 | -0.0605177135 | 0.75000 | 0.96875 | 3595.629249 |

Diagnostic counters:

| method | unresolved | projection mean | RG rejects | ODEX calls | accepted steps | rejected steps | RHS evals |
|---|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 133379 | 4683.31250 | 16487 | 964684044 | 5743587354 | 228665718 | 196887655509 |
| fb_norefine | 26714 | 1243.71875 | 13085 | 1024661422 | 6275844149 | 294434340 | 229584343047 |

Reference aggregate deltas:

| method | d mean Re | d mean Im | d Zmean Re | d Zmean Im | d unresolved | d RG rejects | d runtime s | runtime saving |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | -0.0108651191 | -0.0019850881 | -0.6112561340 | -0.1403249003 | 12521 | -2710 | -1024.709704 | 29.84% |
| fb_norefine | 0.0116280970 | -0.0019071586 | 0.9650589615 | -0.2340322215 | -1492 | -11842 | -470.973789 | 11.58% |

Paired observable drift:

| method | paired seeds | mean dRe | SE dRe | z dRe | max abs dRe | mean dIm | SE dIm | z dIm | max abs dIm | d failures/seed | d RG rejects/seed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 32 | -0.0108651191 | 0.0214261844 | -0.5070953817 | 0.3173598241 | -0.0019850881 | 0.0130824990 | -0.1517361518 | 0.2035420793 | 391.28125 | -169.37500 |
| fb_norefine | 32 | 0.0116280970 | 0.0166603622 | 0.6979498359 | 0.1743931831 | -0.0019071586 | 0.0111662765 | -0.1707962864 | 0.1328377496 | -46.62500 | -740.12500 |

## Interpretation

F20F is the cleanest relaxed double preset tested so far at R3:

- `fb_norefine` aggregate `Zmean Re` is `0.9794`, compared with F20E's
  caution-level `1.9218` and F20D's rejected `2.7973`
- paired `fb_norefine` Re drift z is `0.6979`, compared with F20E's `1.3973`
  and F20D's `1.8256`
- `fb_norefine` reverse-gate rejects decrease by `11842` versus strict R3
  reference, while F20E increased them by `3358`

The cost is runtime:

- `no_fb` saves `29.84%` versus strict R3 reference
- `fb_norefine` saves only `11.58%`
- combined mean runtime saving is `19.94%`

## Decision

Treat `double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative` as the
current most conservative double precision preset.

It is cleaner than F20E on `fb_norefine` physics but substantially less useful
as a speed preset. Use it as the conservative boundary / validation anchor, not
as the best speed-accuracy tradeoff.

Single precision remains closed as an active direction.
