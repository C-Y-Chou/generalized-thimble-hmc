# F20d R3 Double Candidate Validation Readback

Date: 2026-05-19 JST

Canonical workspace: `/Users/ccy/Documents/TLTM_qn_error_handling`

Remote workspace:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`

Scheduler request: `FMOD-F20D-R3-DOUBLE-CANDIDATE-VALIDATION-20260519`

Source commit: `fcb1f7522f7bd80aa5e1e143628842c449345bb8`

Scheduler state commits:

- submission: `f0d738746e2e59801177f5b2358f5b58ce8b3f83`
- queue optimization: `a2d3f977948cbba773d75be7b8a32f1b8658609e`
- C8 follow-up: `14b00ade17ae1a78c4ec413acba0e82734e9b311`

## Scope

This validates the F20C-selected double precision candidate at R3 scale:

- scale: 32 seeds x 50000 cycles
- methods: `no_fb`, `fb_norefine`
- config: `docs/modernization_reference_t035_r3_32seed_50k.json`
- comparison root:
  `output/reference/fortran_modernization/m6/r3_32seed_50k`
- output root:
  `output/tests/f20_double_tolerance_validation/f20d_double_ode1e12_ntqn1e10_dfols1e13_candidate_r3_32seed_50k_fcb1f7522f7b`

Candidate preset:

- `TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-12`
- `TLTM_STAGE2_REL_TOL_OVERRIDE=1e-12`
- `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-10`
- `QN_QUASI_TOL_OVERRIDE=1e-10`
- `QN_REVERSE_GATE_TOL=1e-8`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-13`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-20`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`

## PBS Readback

| job | id | queue | result |
|---|---:|---|---|
| build | 16117 | C16 | exit 0, walltime 00:01:58 |
| no_fb chunk_00 | 16118 | F | exit 0, walltime 00:28:40 |
| no_fb chunk_01 | 16119 | F | exit 0, walltime 00:28:45 |
| no_fb chunk_02 | 16120 | F | exit 0, walltime 00:29:31 |
| no_fb chunk_03 | 16121 | F | exit 0, walltime 00:28:39 |
| fb_norefine chunk_00 | 16122 | C8 | exit 0, walltime 00:38:47 |
| fb_norefine chunk_01 | 16123 | C8 | exit 0, walltime 00:38:56 |
| fb_norefine chunk_02 | 16124 | C8 | exit 0, walltime 00:38:59 |
| fb_norefine chunk_03 | 16125 | C8 | exit 0, walltime 00:39:01 |
| merge | 16126 | C12 | exit 0, walltime 00:00:02 |

Queue note:

- The first scheduler placement put all science chunks on `F`, leaving
  `fb_norefine` queued.
- Scheduler moved only queued jobs `16122-16125` to `C8`.
- PBS briefly reported stale `Qlist` resource comments after `qmove`, then
  started all four jobs on `C8` without `qalter` or resubmission.
- No parent-side PBS action was taken.

Preflight:

- log: `output/logs/fortran_modernization/reference_datasets/preflight/m6_reference_preflight_build.20260519T211739.log`
- M4 guardrails passed.
- No `Python.h`, `pyconfig`, traceback, `ModuleNotFoundError`, fatal
  libpython, or `[ERROR]` pattern was found.

Structural readback:

- `no_fb/per_seed_summary_table.csv`: 32 rows
- `fb_norefine/per_seed_summary_table.csv`: 32 rows
- both methods have `aggregated_summary_table.csv`
- both methods have 32/32 per-seed protocol-audit pass rows
- merge generated `reference_comparison/paired_observable_drift.tsv` and
  `reference_comparison/aggregate_delta.tsv`

## Metrics

| source | method | seeds | mean Re | seed std Re | mean err Re | Zmean Re | mean Im | seed std Im | mean err Im | Zmean Im | P68 | P95 | runtime s |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| R3 reference | no_fb | 32 | 0.0201887921 | 0.0856452277 | 0.0802933924 | 1.3334666470 | -0.0049858728 | 0.0509425833 | 0.0462009902 | -0.5536498966 | 0.46875 | 0.87500 | 3433.969112 |
| candidate | no_fb | 32 | 0.0048974857 | 0.0686244606 | 0.0783260329 | 0.4037097384 | -0.0072396734 | 0.0554338186 | 0.0462466364 | -0.7387868658 | 0.43750 | 0.93750 | 1649.019257 |
| R3 reference | fb_norefine | 32 | 0.0001684020 | 0.0664480236 | 0.0672712934 | 0.0143363997 | 0.0015007415 | 0.0489266063 | 0.0427624501 | 0.1735145080 | 0.46875 | 0.90625 | 4066.603039 |
| candidate | fb_norefine | 32 | 0.0297720099 | 0.0602072251 | 0.0681530894 | 2.7972709349 | 0.0019923071 | 0.0384773043 | 0.0434120882 | 0.2929048965 | 0.50000 | 0.90625 | 2240.901680 |

Diagnostic counters:

| source | method | unresolved | projection mean | RG rejects | ODEX calls | accepted steps | rejected steps | RHS evals |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| R3 reference | no_fb | 120858 | 4376.59375 | 19197 | n/a | n/a | n/a | n/a |
| candidate | no_fb | 126696 | 4503.59375 | 23861 | 771302342 | 3958046953 | 135363044 | 112007280656 |
| R3 reference | fb_norefine | 28206 | 1660.40625 | 24927 | n/a | n/a | n/a | n/a |
| candidate | fb_norefine | 25728 | 2263.46875 | 53145 | 812518300 | 4322104595 | 176275477 | 129075030183 |

Reference aggregate deltas:

| method | d mean Re | d mean Im | d Zmean Re | d Zmean Im | d unresolved | d RG rejects | d runtime s | runtime saving |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | -0.0152913064 | -0.0022538005 | -0.9297569086 | -0.1851369692 | 5838 | 4664 | -1784.949855 | 51.98% |
| fb_norefine | 0.0296036079 | 0.0004915656 | 2.7829345352 | 0.1193903885 | -2478 | 28218 | -1825.701358 | 44.89% |

Paired observable drift:

| method | paired seeds | mean dRe | SE dRe | z dRe | max abs dRe | mean dIm | SE dIm | z dIm | max abs dIm |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 32 | -0.0152913064 | 0.0212404716 | -0.7199136950 | 0.3316532240 | -0.0022538005 | 0.0129152960 | -0.1745063011 | 0.2105532445 |
| fb_norefine | 32 | 0.0296036079 | 0.0162157793 | 1.8256050121 | 0.1986831237 | 0.0004915656 | 0.0112277321 | 0.0437813775 | 0.1341055197 |

## Interpretation

The preset is very fast at R3:

- `no_fb` mean runtime improves by `51.98%`;
- `fb_norefine` mean runtime improves by `44.89%`;
- combined mean runtime improves by `48.14%`.

But it is not production-promotable from this validation:

- `fb_norefine` aggregate Re shifts from `0.0001684020` to `0.0297720099`;
- `fb_norefine` aggregate `Zmean Re` becomes `2.7972709349`;
- paired `fb_norefine` Re drift is `1.8256 sigma`, below 2 sigma but close;
- `fb_norefine` reverse-gate rejects increase by `28218`;
- `fb_norefine` projection mean increases from `1660.40625` to `2263.46875`.

`no_fb` is clean enough on physics metrics and much faster, but the preset must
work for both methods. The `fb_norefine` Re signal is strong enough at 32seed x
50k that the `1e-10` shared NT/QN tolerance should not be promoted as the
production preset.

## Decision

Do not promote `double_ode1e12_ntqn1e10_dfols1e13_candidate` to production.

Keep it as a rejected-at-R3 speed candidate unless a later targeted analysis
proves the `fb_norefine` Re shift is statistical noise or a reference-comparison
artifact.

Next validation should use the conservative fallback:

- ODE abs/rel `1e-12`
- constraint/QN `1e-12`
- reverse gate `1e-8`
- DFO-LS `rhoend=1e-15`
- DFO-LS `model_abs=1e-24`
- DFO-LS `model_rel=0`

Single precision remains closed.
