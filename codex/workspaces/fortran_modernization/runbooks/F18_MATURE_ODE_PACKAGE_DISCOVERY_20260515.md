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
