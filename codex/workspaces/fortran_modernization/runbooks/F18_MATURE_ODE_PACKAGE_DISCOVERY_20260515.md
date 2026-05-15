# F18 Mature ODE Package Discovery - 2026-05-15

## Scope

This records the first F18 dependency spike after F19 official DFO-LS thin
bridge cleanup and F15b solver-assist deletion.

This packet does not switch the TLTM ODE backend. The current handwritten
endpoint-only ODEX backend remains the behavior baseline until a package
backend passes endpoint, retained-core, Stage2, M4, and F8 affected-baseline
gates.

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

The remote modernization worktree is pinned by these jobs and must not be
fast-forwarded or cleaned until they finish or are explicitly abandoned.

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

The next implementation slice is a disabled-by-default endpoint shim:

1. add a reproducible SUNDIALS dependency/setup helper or manifest using
   `SUNDIALS_ENABLE_*` CMake options;
2. add build flags for an optional backend, e.g. `TLTM_ODE_BACKEND=odex` by
   default and `TLTM_ODE_BACKEND=sundials_cvode` for the spike;
3. add a small C/Fortran boundary that maps TLTM endpoint integration onto
   CVODE with explicit status and failure translation;
4. start with standalone scalar/vector endpoint tests against known analytic
   ODEs before wiring `solve_flow`;
5. only then run `flowz`, `flowzr`, `flow`, retained-core, Stage2, M4, and F8
   affected-baseline gates.

Items 2-4 are now implemented for the first serial double-precision CVODE
candidate. Item 1 remains a reproducibility/documentation helper. Item 5 is
the active gate sequence before any canonical backend switch.

Blocked claims remain blocked:

- this does not prove the handwritten ODEX controller is full Hairer ODEX;
- this does not prove SUNDIALS preserves TLTM outputs;
- this does not switch the canonical backend.
