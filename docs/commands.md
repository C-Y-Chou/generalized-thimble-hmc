# Build and Run Commands

All commands below assume working directory is `build/`.

## Build Targets

```bash
make            # same as: make all
make all
make fast
make OMP=1
```

- `make all`: optimized production build
- `make fast`: debug-friendly build profile
- `make OMP=1`: enables OpenMP and parallel MKL

## Run Targets

```bash
make chain
make expect
make tltm_stage1
make test_tltm_stage1
make tltm_stage2
make test_tltm_stage2
make stage3_1
make stage3_3
make test1
make test2
make test1_fb_on
make test1_fb_off
make test2_fb_on
make test2_fb_off
```

- `make chain`: run Markov chain generation
- `make expect`: run expectation evaluation
- `make tltm_stage1`: run TLTM stage-1 (multi-replica, no swap)
- `make test_tltm_stage1`: stage-1 smoke run (max flow=0.3, `L=2`, `nstep=20`)
- `make tltm_stage2`: run TLTM stage-2 (adjacent swap enabled by default)
- `make tltm_stage2_ref`: run TLTM stage-2 with the frozen stage-2.5 reference ladder
- `make test_tltm_stage2`: stage-2 smoke run (max flow=0.3, `L=2`, `nstep=20`)
- `make stage3_1`: run matched-control compare (fallback OFF vs ON) on frozen reference ladder
- `make stage3_3`: run multiseed matched-control summary (fallback OFF vs ON) with frozen stage-3.3 protocol
- `make test1`: Hamiltonian conservation test
- `make test2`: action derivative test
- `make test1_fb_on`, `make test1_fb_off`: test1 with fallback forced on/off
- `make test2_fb_on`, `make test2_fb_off`: test2 with fallback forced on/off

## Stage-2.5 Ladder Scan (Short)

From repository root:

```bash
python3 scripts/run_stage2p5_ladder_scan.py --cycles 40
```

- Runs a short ladder scan with fixed local-update settings from `data/parameters.dat`.
- Writes per-candidate artifacts to:
  - `output/tests/stage2p5_scan/*_summary.dat`
  - `output/tests/stage2p5_scan/*_label_trace.dat`
  - `output/logs/tltm_stage2_*.log`
- Writes consolidated reports:
  - `output/tests/stage2p5_scan/candidate_ladder_scan_table.csv`
  - `output/tests/stage2p5_scan/candidate_ladder_scan_summary.md`

Long-check on promising ladders (example used for stage-2.5 completion):

```bash
# baseline (broken reference)
CHAIN_RNG_SEED=20260421 \
TLTM_STAGE2_FLOW_TIME_LADDER=0,0.1,0.2,0.3 \
TLTM_STAGE2_NUM_REPLICAS=4 \
TLTM_STAGE2_CYCLES=300 \
make -C build tltm_stage2

# promising reference ladder
CHAIN_RNG_SEED=20260421 \
TLTM_STAGE2_FLOW_TIME_LADDER=0,0.05,0.1,0.2,0.3 \
TLTM_STAGE2_NUM_REPLICAS=5 \
TLTM_STAGE2_CYCLES=300 \
make -C build tltm_stage2
```

Frozen stage-2.5 reference ladder:

- `docs/stage_2p5_reference_ladder.json`
- ladder: `0,0.05,0.1,0.2,0.3`
- global local-update settings: `L=2`, `nstep=20`

## Stage-3.1 Matched-Control Compare

From `build/`:

```bash
make stage3_1
```

Optional overrides:

```bash
STAGE3_1_SEED=20260421 STAGE3_1_CYCLES=120 make stage3_1
```

Outputs:

- `output/tests/stage3_1/no_fb_summary.dat`
- `output/tests/stage3_1/fb_summary.dat`
- `output/tests/stage3_1/s3_1_comparison.csv`
- `output/tests/stage3_1/s3_1_report.md`

## Stage-3.3 Multiseed Summary

From `build/`:

```bash
make stage3_3
```

Optional controls:

```bash
STAGE3_3_MAX_SEEDS=2 make stage3_3
STAGE3_3_JOBS=4 make stage3_3
STAGE3_3_CONFIG=docs/stage_3_3_todo.json make stage3_3
STAGE3_3_CONFIG=docs/stage_3_3_minimal_ladder.json make stage3_3
STAGE3_3_SCHEDULE=paired STAGE3_3_JOBS=4 make stage3_3
STAGE3_3_STAGE2_THREADS=1 STAGE3_3_EVAL_THREADS=1 make stage3_3
```

Resource policy:

- `STAGE3_3_SCHEDULE=paired` runs fallback-off and fallback-on for the same seed on the same worker, alternating method order across seeds by default. This is the preferred mode for fair runtime comparison.
- `STAGE3_3_SCHEDULE=task` restores the legacy flat task queue.
- `STAGE3_3_JOBS * max(STAGE3_3_STAGE2_THREADS, STAGE3_3_EVAL_THREADS)` must fit the PBS CPU allocation unless `STAGE3_3_ALLOW_OVERSUBSCRIBE=1` is set.
- Keep `STAGE3_3_STAGE2_THREADS=1` until the stage-2 replica update path has been made thread-safe or replaced by a process/MPI replica scheduler. The current Fortran path uses module-level RNG/workspaces/stat counters.

Outputs:

- `output/tests/stage3_3/per_seed_summary_table.csv`
- `output/tests/stage3_3/aggregated_summary_table.csv`
- `output/tests/stage3_3/stage3_3_report.md`

## Fallback Controls (Current Policy)

Quasi fallback remains the active improvement path; no-fallback is a reference mode. The current working fallback baseline is bounded probe-only. Near/non-near rescue paths are disabled by default because the tested versions did not improve the Re-virial bias and can introduce route asymmetry not represented in the current Metropolis ratio. The legacy global continuation/restart fallback route has been removed from active source.

Control knobs:

- `constraint_tol` and `enable_quasi_fallback` in `data/parameters.dat`
- optional fallback env vars:
  - `QN_S1_PROBE_MAX_ITER` (default `28`; keep `<=32` outside ablations)
  - `QN_S1_NEAR_RESCUE_ENABLED` (default `0`)
  - `QN_S1_NONNEAR_RESCUE_ENABLED` (default `0`)
- removed legacy vars (no runtime effect):
  - `QN_QUASI_GLOBAL_FALLBACK_ENABLED`
  - `QN_PROGRESSIVE_RESCUE_STAGE`, `QN_BASELINE_STAGE`
  - `QN_ENABLE_LEGACY_RESCUE`, `QN_LEGACY_RESCUE`, `QN_RESCUE_LEVEL`

Example:

```bash
cd build
QN_S1_PROBE_MAX_ITER=32 make chain
```

## Interactive Menu

```bash
make menu
make mn
```

`mn` is an alias for `menu`.

## Cleanup Targets

```bash
make clean
make veryclean
```

- `clean`: removes object files and generated module files
- `veryclean`: `clean` + removes built executables

## Reproducible Benchmark

From repository root:

```bash
./scripts/benchmark_hamiltonian.sh        # default: 5 runs
./scripts/benchmark_hamiltonian.sh 10     # custom run count
```

- Uses fixed benchmark inputs under `build/data/` (does not modify `data/`).
- Runs `test_program` with `HMC_SKIP_PLOT=1` to remove plotting overhead.
- Writes per-run logs to `build/bench/logs/` and summary to `build/bench/benchmark_summary.txt`.

## Direct Binary Execution

After build, executables are available under `../bin/`:

```bash
../bin/generate_markov_chain
../bin/evaluate_expectations
../bin/test_program
../bin/test_program2
```

Evaluate multichain expectations (`<virial>` and `<z>`) from a wrapper run:

```bash
cd build
EVAL_MULTICHAIN_RUN_DIR=../output/multichain_auto/<run_name> ../bin/evaluate_expectations
```

- `<virial>` uses a pole-free virial identity:
  - `virial(z) = -i*(z-i*beta)*(z^2+alpha) - 2` (summed over components).
- `<z>` is computed as `sum(z)` (same quantity previously labeled `tra2`).
- Error bars are leave-one-chain-out jackknife over chain-level ratio estimators.
- Additional robust error bars are reported for multichain runs:
  - `error_robust_<virial>` and `error_robust_<z>`
  - Rule: per Re/Im component `max(chain_jk, stratified_jk_plateau, mcse_mean)`.
- Diagnostics (`Rhat`, `ESS_bulk`, `ESS_tail`, `MCSE`) are computed on weighted tails:
  - `O_z(i) = O_i * phi_i / sum_j(phi_j)`.

## Auto-Terminating Multichain Wrapper

From repository root:

```bash
python3 scripts/run_multichain_auto.py \
  --chains 4 \
  --target-samples-per-chain 50000 \
  --max-wall-seconds 7200
```

- Creates isolated per-chain workdirs under `output/multichain_auto/<run_name>/`.
- Patches per-chain `data/parameters.dat` and writes outputs to each chain-local `output/`.
- Polls stream sizes to estimate samples and terminates all running chains once stop criteria are met.
- Constraint fallback toggle:
  - Keep template behavior: `--quasi-fallback auto` (default).
  - Force ON: `--quasi-fallback on`
  - Force OFF (Newton-only): `--quasi-fallback off`

Direct `parameters.dat` toggle is also supported:

```ini
enable_quasi_fallback = true   # or false
```

Convergence-based auto-stop (`Rhat`/`ESS`) is also supported:

```bash
python3 scripts/run_multichain_auto.py \
  --chains 4 \
  --stop-rhat-max 1.01 \
  --stop-ess-bulk-min 1000 \
  --stop-ess-tail-min 400 \
  --diag-min-samples-per-chain 1000 \
  --diag-window-samples 20000 \
  --max-wall-seconds 21600
```

- Diagnostic observable follows `parameters.dat` and is weight-normalized over the active window:
  - `O_z(i) = O_i * phi_i / sum_j(phi_j)` where `O_i` is `A2` when `tra2=true`, otherwise virial.
- Diagnostics are evaluated on chain tails and can be combined with sample or wall-time limits.
- `--diag-window-mode fixed` uses a constant cap (`--diag-window-samples`).
- `--diag-window-mode adaptive` grows `n_use` with chain length:
  - `n_use = min(min_chain_samples, clamp(floor(fraction * min_chain_samples), window_min, window_max))`
  - use `--diag-window-max 0` for no upper cap.

Adaptive example:

```bash
python3 scripts/run_multichain_auto.py \
  --chains 4 \
  --stop-rhat-max 1.01 \
  --stop-ess-bulk-min 1000 \
  --stop-ess-tail-min 400 \
  --diag-window-mode adaptive \
  --diag-window-fraction 1.0 \
  --diag-window-min 20000 \
  --diag-window-max 0 \
  --diag-min-samples-per-chain 1000 \
  --diag-every 5 \
  --max-wall-seconds 21600
```

Mode-mixing gates (for competing modes):

```bash
python3 scripts/run_multichain_auto.py \
  --chains 4 \
  --stop-rhat-max 1.01 \
  --stop-ess-bulk-min 1000 \
  --stop-ess-tail-min 400 \
  --mode-diag-component re \
  --mode-diag-threshold 0.0 \
  --stop-mode-occupancy-delta-max 0.05 \
  --stop-mode-indicator-rhat-max 1.01 \
  --stop-mode-indicator-ess-min 400 \
  --stop-mode-crossings-min-per-chain 20 \
  --stop-mode-roundtrips-min-per-chain 10 \
  --diag-window-mode adaptive \
  --diag-window-fraction 1.0 \
  --diag-window-min 20000 \
  --diag-window-max 0 \
  --diag-every 5 \
  --max-wall-seconds 21600
```

- `mode-diag-component` / `mode-diag-threshold` define a binary mode indicator from the observable tail.
- Additional diagnostics reported: occupancy range/agreement, mode-indicator `Rhat`/`ESS`, crossings, round trips.

## Virial Zero-Coverage Plot

From repository root:

```bash
python3 scripts/plot_multichain_virial_coverage.py --last 30
```

- Reads `output/multichain_auto/*/multichain_expectations.dat`.
- Plots virial `mean +- error` against 0 for Re/Im.
- Default error source is `auto`:
  - prefer `err_robust_virial_re_im`, fallback to `err_strat_jk_virial_re_im`, then `err_chain_jk_virial_re_im`.
- Writes:
  - `output/multichain_auto/virial_coverage.png`
  - `output/multichain_auto/virial_coverage_summary.csv`
