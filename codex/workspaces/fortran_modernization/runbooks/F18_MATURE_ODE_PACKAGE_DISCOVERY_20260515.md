# F18 Mature ODE Package Discovery - 2026-05-15

## Scope

This records the first F18 dependency spike after F19 official DFO-LS thin
bridge cleanup and F15b solver-assist deletion.

This packet does not switch the canonical TLTM ODE backend. The current
handwritten endpoint-only ODEX backend remains the behavior baseline unless a
package backend passes endpoint, retained-core, Stage2, M4, and affected
baseline gates.

## Baseline Jobs Submitted First

The requested direct assist-off baseline was rerun before source work
continued.

- Remote worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- Pinned commit: `40224b1873938d5c3566e6cca2a4cc6f27cfc9f4`
- Run stamp: `20260515T195449`
- PBS script:
  `codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_npt5_assistoff_10seed_10k_20260515.pbs`
- `no_fb`: `15457.anode01`, queue `C12`, state `R` at submit/readback
- `fb_norefine`: `15458.anode01`, queue `C12`, state `R` at submit/readback

Readback:

```text
no_fb:
  Exit_status: 0
  walltime: 00:09:58
  mean_Ohat_re: 0.0152194490582967
  mean_Ohat_im: -0.03448959379182772
  std_Ohat_re: 0.17922899689068134
  std_Ohat_im: 0.13371984472883489
  Zmean_re: 0.2685286677494353
  Zmean_im: -0.8156281678112081
  total_unresolved_failure_count: 8390
  mean_pair0_accept_rate: 0.44036

fb_norefine:
  Exit_status: 0
  walltime: 00:17:02
  mean_Ohat_re: 0.01812635706450244
  mean_Ohat_im: 0.001527176163312534
  std_Ohat_re: 0.17607865557826502
  std_Ohat_im: 0.11298508259999036
  Zmean_re: 0.32553959375179914
  Zmean_im: 0.04274329808194781
  total_unresolved_failure_count: 173
  mean_pair0_accept_rate: 0.4404
```

This direct rerun shows no obvious PBS/source-cleanup route problem before the
CVODE source work.

## Package Availability

Local macOS discovery:

- no `sundials-config` on `PATH`;
- no `pkg-config` entry for `sundials-cvode`;
- no Homebrew SUNDIALS install detected;
- no local SUNDIALS or ODEPACK libraries/headers found under the usual
  Homebrew prefixes;
- local C toolchain exists, but local `cmake` was not detected.

Remote cluster02 discovery:

- no `sundials-config` on `PATH`;
- no `pkg-config` entry for `sundials-cvode`;
- no SUNDIALS/CVODE/ODEPACK module found in `module avail`;
- no common-prefix SUNDIALS or ODEPACK install found under `/usr`,
  `/usr/local`, `/opt`, `/lustre1/app`, `/lustre1/apps`,
  `/lustre1/home/cychou/TLTM/.deps`, or `/lustre1/home/cychou/.local`;
- `cmake` 3.26.5 is available by default, and `cmake/3.30.5` and
  `cmake/4.2.1` modules are advertised;
- GCC 8.5.0 and Intel 2025.3 `icx`/`ifx` are available;
- remote `curl` can fetch the official SUNDIALS GitHub release archive.

Conclusion: no usable preinstalled package exists, but SUNDIALS is buildable
as a project dependency on the remote target.

## SUNDIALS Dependency Spike

Built and installed a serial CVODE-focused SUNDIALS dependency outside the
active remote worktree:

- Version: SUNDIALS `v7.7.0`
- Source archive:
  `https://github.com/LLNL/sundials/archive/refs/tags/v7.7.0.tar.gz`
- Source cache:
  `/lustre1/home/cychou/TLTM/.deps/src/sundials-v7.7.0.tar.gz`
- Build directory:
  `/lustre1/home/cychou/TLTM/.deps/build/sundials-7.7.0-cvode-serial`
- Install prefix:
  `/lustre1/home/cychou/TLTM/.deps/sundials-7.7.0-cvode-serial`

Installed artifacts include:

- `include/cvode/cvode.h`
- `include/sundials/sundials_config.h`
- `lib64/libsundials_cvode.so`
- `lib64/libsundials_core.so`
- `lib64/cmake/sundials/SUNDIALSConfig.cmake`

The configure step accepted the legacy `BUILD_*` / `ENABLE_*` options but
warned that they are deprecated. Any checked-in setup helper should use the new
`SUNDIALS_ENABLE_*` option names.

## Link Smoke

A minimal C smoke test compiled and linked against the remote install:

```text
cvode_smoke_ok
libsundials_cvode.so.7 => /lustre1/home/cychou/TLTM/.deps/sundials-7.7.0-cvode-serial/lib64/libsundials_cvode.so.7
libsundials_core.so.7 => /lustre1/home/cychou/TLTM/.deps/sundials-7.7.0-cvode-serial/lib64/libsundials_core.so.7
```

This proves the remote package is not merely present on disk; it can be linked
and loaded by the cluster login toolchain.

## F18 Position

SUNDIALS CVODE remains the primary F18 candidate. ODEPACK remains a fallback
only if the CVODE shim proves too disruptive or cannot satisfy TLTM endpoint
status/failure contracts.

## Disabled-By-Default Shim Implementation

Implemented the first endpoint shim slice locally:

- optional build flag:
  `ENABLE_SUNDIALS_CVODE=1 SUNDIALS_PREFIX=<prefix>`;
- default build remains `ENABLE_SUNDIALS_CVODE=0` with a stub C bridge;
- runtime switch remains explicit:
  `TLTM_ODE_BACKEND=sundials_cvode`;
- current default backend remains handwritten endpoint-only ODEX;
- CVODE path maps TLTM endpoint RHS callbacks through a C bridge, returns
  TLTM-style success/max-steps/invalid statuses, and keeps zero-time handling
  in Fortran;
- `solve_flow` only applies the env switch through the existing
  `odex_default_options` wrapper, so direct ODEX package tests remain
  deterministic unless they explicitly select CVODE;
- added `test_sundials_cvode_backend_contract`, which skips under the default
  stub build and requires `TLTM_EXPECT_SUNDIALS_CVODE=1` for enabled gates.

Local verification under the default stub build:

```text
make -C build fast test_sundials_cvode_backend_contract
make -C build test_odex_backend_package_contract test_odex_result_contract
git diff --check
```

Results:

- default stub build passes and reports `sundials_cvode_available=F`;
- standalone ODEX backend package contract still passes;
- ODEX result/status contract still passes;
- `git diff --check` reports no whitespace errors.

Implemented source commits:

- `6d682b5` adds the optional SUNDIALS CVODE backend and default stub build.
- `a1c5704` fixes the enabled build by using an explicit
  `SUNNonlinSol_FixedPoint` nonlinear solver instead of CVODE's default Newton
  path, which segfaulted without an attached linear solver in this no-Jacobian
  endpoint configuration.
- `6d322cd` centralizes the runtime backend env parse through
  `runtime_env_mod`; this is a local M4 cleanup commit and was intentionally
  not pulled into the remote worktree while `a1c5704` comparison jobs were
  active.

Remote enabled build details:

```text
ENABLE_SUNDIALS_CVODE=1
SUNDIALS_PREFIX=/lustre1/home/cychou/TLTM/.deps/sundials-7.7.0-cvode-serial
PYTHON_EMBED_LDFLAGS=/lib64/libpython3.11.so.1.0 -lpthread -ldl -lutil -lm -Xlinker -export-dynamic
```

The explicit `PYTHON_EMBED_LDFLAGS` is required on the cluster because the
remote Python embed flags advertise `-lpython3.11`, but the corresponding
linker symlink is not available.

Remote enabled contract result:

```text
sundials_cvode_available=T
endpoint accuracy ok, err 6.5314E-12, steps 64
forward/backward ok, err 2.0542E-11
context endpoint ok, err 3.9269E-12
zero-time ok
```

Enabled binary load check shows `run_tltm_stage2` and
`evaluate_expectations` linked to:

```text
libsundials_cvode.so.7
libsundials_sunnonlinsolfixedpoint.so.4
libsundials_nvecserial.so.7
libsundials_core.so.7
```

Direct remote Stage2 CVODE smoke:

```text
TLTM_ODE_BACKEND=sundials_cvode
cycles: 2
replicas: 2
ladder: 0,0.05
fallback_stats: attempts=0, failure=0
newton_eval_flow_status: success=912, zero_time=80, failures=0
reverse_gate_replay_status: success=80, failures=0, rejects=0
accepted_total=4, newton_only=4
```

Important operational note: do not run remote make targets for enabled CVODE
work without `ENABLE_SUNDIALS_CVODE=1`; doing so can relink the executable
against the default stub bridge.

## CVODE 10seed/10k Comparison

Submitted the requested first CVODE comparison after the direct assist-off
baseline and enabled smoke:

- Remote worktree:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- Runtime source commit:
  `a1c57044620c5624e7f467bf1ac3fbed35337863`
- Local source head:
  `6d322cd` after the M4 env-centralization cleanup
- Run stamp: `20260515T205005`
- Campaign:
  `observable_regression_true_rngv2_assistoff_dfols_npt5_r0055_sundials_cvode_10seed_10k_20260515T205005_a1c57044620c`
- `no_fb`: `15459.anode01`, queue `C12`
- `fb_norefine`: `15460.anode01`, queue `C12`

Readback:

```text
no_fb:
  job: 15459.anode01
  Exit_status: 0
  walltime: 00:14:57
  n_seeds: 10
  mean_Ohat_re: 0.004166671375074893
  mean_Ohat_im: -0.030939184791133445
  std_Ohat_re: 0.18337663800814658
  std_Ohat_im: 0.14253007986707178
  Zmean_re: 0.07185305581879542
  Zmean_im: -0.6864396131684608
  total_unresolved_failure_count: 8295
  mean_projection_failure_count: 935.9
  mean_unresolved_failure_count: 829.5
  mean_quasi_probe_success_count: 0.0
  mean_pair0_accept_rate: 0.44012
  mean_total_round_trip: 2199.6
  mean_hot_end_hit_count: 4972.8
  mean_runtime_total: 854.6848699999998
  total_reverse_gate_total_candidate_count: 3924787
  total_reverse_gate_total_reject_count: 1064
  total_local_reverse_gate_reject_count: 1064
  total_local_proposal_failure_count: 8295

fb_norefine:
  job: 15460.anode01
  Exit_status: 0
  walltime: 00:37:13
  n_seeds: 10
  mean_Ohat_re: -0.004615987646110003
  mean_Ohat_im: -0.00925965404288124
  std_Ohat_re: 0.17233042822719438
  std_Ohat_im: 0.10785506931132235
  Zmean_re: -0.08470375640024912
  Zmean_im: -0.27149022579708504
  total_unresolved_failure_count: 165
  mean_projection_failure_count: 187.9
  mean_unresolved_failure_count: 16.5
  mean_quasi_probe_success_count: 1048.0
  mean_pair0_accept_rate: 0.44133999999999995
  mean_total_round_trip: 2205.7
  mean_hot_end_hit_count: 4998.8
  mean_runtime_total: 2101.6108684
  total_reverse_gate_total_candidate_count: 4008363
  total_reverse_gate_total_reject_count: 1714
  total_local_reverse_gate_reject_count: 1714
  total_local_proposal_failure_count: 165
```

Against the direct ODEX assist-off rerun above:

```text
no_fb:
  unresolved failures: 8390 -> 8295
  mean_Ohat_re: 0.0152194490582967 -> 0.004166671375074893
  mean_Ohat_im: -0.03448959379182772 -> -0.030939184791133445
  mean_pair0_accept_rate: 0.44036 -> 0.44012
  mean_runtime_total: 586.9923013 -> 854.6848699999998

fb_norefine:
  unresolved failures: 173 -> 165
  mean_Ohat_re: 0.01812635706450244 -> -0.004615987646110003
  mean_Ohat_im: 0.001527176163312534 -> -0.00925965404288124
  mean_pair0_accept_rate: 0.4404 -> 0.44133999999999995
  mean_runtime_total: 983.9350281999999 -> 2101.6108684
```

Interpretation:

- the first CVODE candidate completes both methods with strict double
  tolerances and no PBS/source-route failure;
- the failure counts and pair0 acceptance rates are in the same practical
  range as the ODEX baseline for this 10seed/10k comparison;
- observable means differ by less than one standard error in this small
  comparison and do not by themselves indicate a target-measure failure;
- runtime is the main concern: `no_fb` is roughly 1.46x slower by mean runtime,
  and `fb_norefine` is roughly 2.14x slower;
- this evidence is good enough to keep CVODE as a viable mature-backend
  candidate, but not enough to switch the canonical backend.

Next F18 decision point:

1. inspect CVODE tolerance/options and step statistics before scaling;
2. decide whether the performance hit is acceptable for correctness
   comparison only, or whether backend tuning is required;
3. only after that run retained-core and affected-baseline gates for any
   stronger backend claim.

After these jobs completed, the remote worktree no longer needed to stay
pinned at `a1c5704`; it should be fast-forwarded through `6d322cd` or the
latest local docs/source head before new source/PBS work.

## Post-Readback Remote Sync

After both CVODE comparison jobs reached `Exit_status=0`, the remote
modernization worktree was fast-forwarded to:

```text
7dac27df46e0bcd8323e4c037f20a3480198ecf8
```

The worktree was clean and no PBS jobs were active at refresh.

The enabled CVODE binaries were rebuilt after fast-forward. A clean rebuild
first exposed that the cluster's system Python 3.11 runtime has
`/lib64/libpython3.11.so.1.0` but no installed Python 3.11 development headers
under `/usr/include/python3.11`. To make clean rebuilds reproducible without
changing TLTM source, a CPython 3.11.11 source/configure header tree was placed
under the external dependency area:

```text
/lustre1/home/cychou/TLTM/.deps/src/Python-3.11.11/Include
/lustre1/home/cychou/TLTM/.deps/build/python-3.11.11-headers
```

Remote enabled rebuild invocation:

```text
module purge
module load compiler/2025.3.0
module load mpi/2021.17
module load mkl/2025.3

PYTHON_EMBED_CFLAGS="-I/lustre1/home/cychou/TLTM/.deps/src/Python-3.11.11/Include -I/lustre1/home/cychou/TLTM/.deps/build/python-3.11.11-headers"
PYTHON_EMBED_LDFLAGS="/lib64/libpython3.11.so.1.0 -lpthread -ldl -lutil -lm -Xlinker -export-dynamic"

make -C build ENABLE_SUNDIALS_CVODE=1 \
  SUNDIALS_PREFIX=/lustre1/home/cychou/TLTM/.deps/sundials-7.7.0-cvode-serial \
  PYTHON_EMBED_CFLAGS="${PYTHON_EMBED_CFLAGS}" \
  PYTHON_EMBED_LDFLAGS="${PYTHON_EMBED_LDFLAGS}" \
  ../bin/evaluate_expectations ../bin/test_sundials_cvode_backend_contract
```

The rebuilt `bin/run_tltm_stage2`, `bin/evaluate_expectations`, and
`bin/test_sundials_cvode_backend_contract` link against `/lib64/libpython3.11`
and the SUNDIALS CVODE/fixed-point/nvec/core libraries under the SUNDIALS
prefix. The enabled contract passed again:

```text
sundials_cvode_available=T
endpoint accuracy ok, err 6.5314E-12, steps 64
forward/backward ok, err 2.0542E-11
context endpoint ok, err 3.9269E-12
zero-time ok
```

## Local Post-Implementation Gate

At local source head `6d322cd`:

```text
rg -n "get_environment_variable" src tests
git diff --check
make -C build test_sundials_cvode_backend_contract
make -C build modernization_guardrails
```

Results:

- only `src/config/runtime_env_mod.f90` reads environment variables directly;
- `git diff --check` passes;
- default stub `test_sundials_cvode_backend_contract` passes and reports
  `sundials_cvode_available=F`;
- full local M4 guardrails pass, including the M4 summary.

Blocked claims remain blocked:

- this does not prove the handwritten ODEX controller is full Hairer ODEX;
- this does not prove SUNDIALS preserves TLTM outputs;
- this does not switch the canonical backend.

## CVODE Tuning Instrumentation and Fixed-Point Sweep

After the first 10seed/10k CVODE comparison showed a significant runtime
cost, source head `d9e817f` added CVODE tuning/status instrumentation without
changing the default ODEX output path:

- `TLTM_CVODE_FIXEDPOINT_M` selects the fixed-point nonlinear solver iteration
  limit used by the optional CVODE backend;
- `TLTM_CVODE_MAX_ORDER` can cap CVODE order for later tuning;
- Stage2 summaries and the multiseed aggregator now report CVODE call,
  step, RHS, error-test, nonlinear-iteration, nonlinear-convergence-failure,
  step-solve-failure, and final-order statistics when the CVODE backend is
  active;
- default non-CVODE runs omit the new CVODE lines, so the ODEX baseline summary
  hash remains unchanged.

Local/default validation at `d9e817f`:

```text
python3 -m py_compile scripts/run_stage3_3_multiseed.py
make -C build ../bin/test_sundials_cvode_backend_contract
./bin/test_sundials_cvode_backend_contract
make -C build ../bin/run_tltm_stage2 ../bin/evaluate_expectations
python3 scripts/run_m4_guardrails.py
```

The enabled remote CVODE build and contract also passed after fast-forward to
`d9e817f`.

The requested first tuning slice was run as a parallel 10seed/1k matrix rather
than a sequential campaign:

```text
campaign: cvode_tuning_parallel_true_rngv2_assistoff_dfols_npt5_r0055_10seed_1k_20260515T230436_d9e817fbd5bb
output root: /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/production_comparison/observable_regression/cvode_tuning_parallel_true_rngv2_assistoff_dfols_npt5_r0055_10seed_1k_20260515T230436_d9e817fbd5bb
log root:    /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/production_comparison/observable_regression/cvode_tuning_parallel_true_rngv2_assistoff_dfols_npt5_r0055_10seed_1k_20260515T230436_d9e817fbd5bb
jobs:        15469.anode01 on C12; 15477-15483.anode01 on C16
```

All eight matrix jobs completed and wrote `aggregated_summary_table.csv`.

Compact readback:

| fixedpoint_m | method | mean runtime, 1k | naive 10k x10 | unresolved | pair0 accept | rhs/call | steps/call | nonlinear iters/call | errtest/call |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | no_fb | 86.51 | 865.07 | 880 | 0.4390 | 262.84 | 131.36 | 260.84 | 11.67 |
| 2 | no_fb | 115.39 | 1153.94 | 878 | 0.4392 | 263.27 | 131.74 | 261.27 | 11.74 |
| 4 | no_fb | 115.77 | 1157.68 | 878 | 0.4392 | 263.27 | 131.74 | 261.27 | 11.74 |
| 8 | no_fb | 117.32 | 1173.21 | 878 | 0.4392 | 263.27 | 131.74 | 261.27 | 11.74 |
| 0 | fb_norefine | 283.12 | 2831.16 | 15 | 0.4366 | 317.46 | 164.56 | 315.39 | 11.47 |
| 2 | fb_norefine | 299.98 | 2999.84 | 17 | 0.4392 | 321.64 | 166.56 | 319.56 | 11.87 |
| 4 | fb_norefine | 302.85 | 3028.46 | 17 | 0.4392 | 321.64 | 166.56 | 319.56 | 11.87 |
| 8 | fb_norefine | 305.65 | 3056.51 | 17 | 0.4392 | 321.64 | 166.56 | 319.56 | 11.87 |

Interpretation:

- `fixedpoint_m > 0` does not improve the current CVODE candidate. It reduces
  some nonlinear-convergence-failure counters but increases wall time and does
  not improve the TLTM acceptance/failure surface enough to matter.
- For `fb_norefine`, all fixed-point candidates ran on C16 and `m=0` is still
  the fastest. For `no_fb`, `m=0` ran on C12 while the others ran on C16, so
  the exact speed ratio is queue-confounded, but the CVODE per-call statistics
  also do not suggest a useful `m>0` route.
- The `m=0` 1k `no_fb` x10 estimate, about 865 s, is consistent with the
  earlier 10seed/10k CVODE `no_fb` runtime of about 855 s. The `fb_norefine`
  1k x10 estimate overstates the earlier 10seed/10k runtime, about 2102 s,
  but `m=0` remains the best fixed-point setting in this slice.
- Do not scale `m=2`, `m=4`, or `m=8` to 10k. The fixed-point tuning branch is
  rejected for now.

Current F18 position after this sweep:

- keep `TLTM_CVODE_FIXEDPOINT_M=0` as the default optional CVODE setting;
- keep CVODE as a viable mature-backend comparison candidate, not as the
  canonical backend;
- continue only with a narrowly chosen next tuning question, such as max-order
  or tolerance/profile behavior, if the performance budget still justifies it;
- do not run the expensive 10seed/10k extension for a candidate unless the 1k
  evidence shows a plausible runtime or correctness win.

## CVODE Fail-Fast Max-Step Sweep

The next test answered whether CVODE can be made to fail fast in a controlled
way.  Source head `1d750409cf3e4b7f15ccb203958a685aa922bf2c` added
disabled-by-default, CVODE-only knobs:

- `TLTM_CVODE_MAX_STEPS`;
- `TLTM_CVODE_MIN_STEP`;
- `TLTM_CVODE_MAX_ERR_TEST_FAILS`;
- `TLTM_CVODE_MAX_CONV_FAILS`;
- `TLTM_CVODE_MAX_NONLIN_ITERS`.

These are passed through `odex_options` and the SUNDIALS C bridge.  Defaults
are zero/off, so the handwritten ODEX baseline is unchanged unless
`TLTM_ODE_BACKEND=sundials_cvode` is selected.

Local/default validation at `1d750409`:

```text
make -C build ../bin/test_sundials_cvode_backend_contract
./bin/test_sundials_cvode_backend_contract
make -C build ../bin/run_tltm_stage2 ../bin/evaluate_expectations
python3 -m py_compile scripts/run_stage3_3_multiseed.py
git diff --check
python3 scripts/run_m4_guardrails.py
```

The remote enabled CVODE contract also passed after fast-forwarding the
modernization worktree to `1d750409`; the contract included a deliberate
`cvode_max_steps=1` failure case with `status=101`.

First fail-fast screen:

```text
campaign: cvode_failfast_true_rngv2_assistoff_dfols_npt5_r0055_10seed_1k_20260515T235342_1d750409cf3e
output root: /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/production_comparison/observable_regression/cvode_failfast_true_rngv2_assistoff_dfols_npt5_r0055_10seed_1k_20260515T235342_1d750409cf3e
log root:    /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/production_comparison/observable_regression/cvode_failfast_true_rngv2_assistoff_dfols_npt5_r0055_10seed_1k_20260515T235342_1d750409cf3e
```

Compact 1k readback:

| label | method | mean runtime, 1k | naive 10k x10 | pair0 accept | unresolved | proposal failures | Zmean Re/Im | mean Re/Im |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| base | no_fb | 106.94 | 1069.4 | 0.4390 | 880 | 880 | 0.954 / 0.400 | 0.159435 / 0.052948 |
| base | fb_norefine | 282.38 | 2823.8 | 0.4366 | 15 | 15 | 0.517 / 1.087 | 0.073014 / 0.113468 |
| s320 | no_fb | 67.28 | 672.8 | 0.4288 | 714 | 1524 | -0.692 / -0.076 | -0.124125 / -0.005780 |
| s320 | fb_norefine | 86.80 | 868.0 | 0.4292 | 703 | 1520 | -0.597 / 0.010 | -0.106228 / 0.000773 |
| s240 | no_fb | 61.52 | 615.2 | 0.4200 | 514 | 2586 | -1.576 / -0.576 | -0.385437 / -0.083326 |
| s240 | fb_norefine | 78.39 | 783.9 | 0.4196 | 519 | 2587 | -1.516 / -0.503 | -0.353469 / -0.072479 |
| s160 | no_fb | 52.83 | 528.3 | 0.3780 | 414 | 4952 | -3.182 / -1.366 | -0.668498 / -0.163056 |
| s160 | fb_norefine | 64.19 | 641.9 | 0.3780 | 413 | 4950 | -3.180 / -1.302 | -0.667970 / -0.156159 |

The `s100` jobs were cancelled after they became pathological, and
`s160_h1e8_e4_c4_i2` behaved like the too-aggressive `s160` branch.  Only
`s320` had a runtime projection worth a 10k check, but even at 1k it already
showed suspicious acceptance and observable drift.

The selected 10k extension was:

```text
campaign: cvode_failfast_s320_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260516T000908_1d750409cf3e
jobs:     15496.anode01 no_fb, 15497.anode01 fb_norefine
backend:  TLTM_ODE_BACKEND=sundials_cvode
knobs:    TLTM_CVODE_FIXEDPOINT_M=0, TLTM_CVODE_MAX_STEPS=320
result:   both jobs Exit_status=0
walltime: no_fb 00:11:56, fb_norefine 00:12:46
```

10k readback against the strict CVODE comparison and the ODEX baseline:

| label | method | runtime | unresolved | proposal failures | pair0 accept | Zmean Re/Im | mean Re/Im |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ODEX baseline | no_fb | 586.99 | 8390 | 8388 | 0.44036 | 0.269 / -0.816 | 0.015219 / -0.034490 |
| strict CVODE | no_fb | 854.68 | 8295 | 8295 | 0.44012 | 0.072 / -0.686 | 0.004167 / -0.030939 |
| s320 fail-fast | no_fb | 696.20 | 6983 | 14941 | 0.43248 | -3.892 / -0.781 | -0.173019 / -0.030689 |
| ODEX baseline | fb_norefine | 983.94 | 173 | 173 | 0.44040 | 0.326 / 0.043 | 0.018126 / 0.001527 |
| strict CVODE | fb_norefine | 2101.61 | 165 | 165 | 0.44134 | -0.085 / -0.271 | -0.004616 / -0.009260 |
| s320 fail-fast | fb_norefine | 734.52 | 6742 | 14833 | 0.43254 | -4.220 / -1.032 | -0.178249 / -0.039115 |

Conclusion:

- The new CVODE fail-fast controls work technically and fail through the normal
  TLTM rejection/RG path.
- `TLTM_CVODE_MAX_STEPS=320` is not an acceptable production or canonical
  candidate.  It is faster, especially for `fb_norefine`, but it changes the
  proposal/failure surface and gives large observable drift at 10seed/10k.
- Do not scale `s100`, `s160`, `s240`, `s160_h1e8_e4_c4_i2`, or `s320`
  max-step fail-fast settings further.
- Keep strict CVODE as a disabled-by-default comparison backend only.  If F18
  continues, the next question should be an explicitly different package route
  or a non-kernel-changing performance path, not a looser max-step fail-fast
  budget.

## CVODE Non-Max-Step Fail-Fast Sweep

The remaining fail-fast knobs were tested in isolated 10seed/1k screens, using
the same official DFO-LS `npt5_r0055`, true Stage2 RNG v2, assist-off,
`TLTM_CVODE_FIXEDPOINT_M=0`, strict tolerance, and reverse-gate policy:

```text
round 1 stamp: 20260516T003745
labels: h1e8, h1e6, err4, conv4, iter2
jobs:   15498-15507.anode01

round 2 stamp: 20260516T004754
labels: conv2, conv6, conv4_iter2, err2, h1e9
jobs:   15508-15517.anode01

round 3 stamp: 20260516T005611
label:  conv1
jobs:   15518-15519.anode01
```

The compact 1k readback, compared with the same 1k base row:

| label | method | runtime ratio vs base | surface result | readback |
| --- | --- | ---: | --- | --- |
| h1e6 | both | n/a | hard fail | Stage2 initialization failed with CVODE `hmin` / repeated error-test failures at `t=0, h=1e-6` |
| h1e8 | no_fb | 0.690 | near base | unresolved `879` vs base `880`, mean Re `0.132587` vs `0.159435` |
| h1e8 | fb_norefine | 0.330 | rejected | unresolved/proposal failures `870` vs base `15`, mean Re `0.157700` vs `0.073014` |
| h1e9 | no_fb | 0.733 | small drift | unresolved `882` vs base `880`, mean Re `0.166942` vs `0.159435` |
| h1e9 | fb_norefine | 0.603 | rejected | unresolved/proposal failures `405` vs base `15`, mean Re `0.139013` vs `0.073014` |
| err4 | both | 1.031 / 1.016 | no effect | aggregate identical to base but slightly slower |
| err2 | no_fb | 0.754 | near base | unresolved `879` vs base `880`, aggregate means unchanged |
| err2 | fb_norefine | 0.342 | rejected | unresolved/proposal failures `878` vs base `15`, mean Re `0.157700` vs `0.073014` |
| iter2 | no_fb | 1.010 | no useful gain | aggregate identical but slower |
| iter2 | fb_norefine | 0.943 | not clean | unresolved/proposal failures `16` vs base `15`, mean Im shifted by about `-0.0108` |
| conv6 | both | 1.010 / 0.992 | no useful gain | aggregate identical to base |
| conv4_iter2 | no_fb | 0.933 | clean | aggregate identical to base |
| conv4_iter2 | fb_norefine | 0.928 | not clean | unresolved/proposal failures `16` vs base `15`, mean Im shifted by about `-0.0108` |
| conv4 | both | 0.922 / 0.920 | clean at 1k | aggregate identical to base |
| conv2 | both | 0.928 / 0.918 | clean at 1k | aggregate identical to base |
| conv1 | both | 0.856 / 0.880 | clean at 1k | aggregate identical to base |

Only the convergence-failure limit family was worth a 10k check.  The selected
extension was the strongest clean 1k candidate:

```text
campaign: cvode_failfast_conv1_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260516T010335_d24acef0e890
jobs:     15520.anode01 no_fb, 15521.anode01 fb_norefine
knobs:    TLTM_CVODE_FIXEDPOINT_M=0, TLTM_CVODE_MAX_CONV_FAILS=1
result:   both jobs Exit_status=0
walltime: no_fb 00:16:04, fb_norefine 00:41:15
```

10k readback:

| label | method | runtime | unresolved | proposal failures | pair0 accept | Zmean Re/Im | mean Re/Im |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| strict CVODE | no_fb | 854.68 | 8295 | 8295 | 0.44012 | 0.072 / -0.686 | 0.004167 / -0.030939 |
| conv1 | no_fb | 927.57 | 8295 | 8295 | 0.44012 | 0.072 / -0.686 | 0.004167 / -0.030939 |
| strict CVODE | fb_norefine | 2101.61 | 165 | 165 | 0.44134 | -0.085 / -0.271 | -0.004616 / -0.009260 |
| conv1 | fb_norefine | 2353.62 | 165 | 165 | 0.44134 | -0.085 / -0.271 | -0.004616 / -0.009260 |

Conclusion:

- `TLTM_CVODE_MAX_CONV_FAILS=1` is output-surface preserving at 10seed/10k
  relative to strict CVODE, but it is slower (`1.085x` no_fb and `1.120x`
  fb_norefine).  It is not a performance candidate.
- `TLTM_CVODE_MIN_STEP` and aggressive `TLTM_CVODE_MAX_ERR_TEST_FAILS` settings
  are rejected because they change `fb_norefine` proposal/failure behavior or
  fail initialization.
- `TLTM_CVODE_MAX_NONLIN_ITERS=2` and mixed convergence/nonlinear-iteration
  settings do not give a clean enough payoff.
- All tested CVODE fail-fast knobs are now rejected as canonical/performance
  routes.  Keep strict CVODE as disabled-by-default comparison-only unless F18
  switches to an explicitly different mature package path or a
  non-kernel-changing performance strategy.
