# Worktree and Dataset Index

Recorded: 2026-06-02 17:50 JST

Purpose: make the current WV-HMC/TLTM worktree readable before further source
work.  This is a cleanup/index file, not a physics conclusion.

## Cleanup Action Already Applied

The repo `.gitignore` now excludes raw generated run artifacts:

```text
codex/workspaces/*/runbooks/generated/**/chunks/
codex/workspaces/*/runbooks/generated/**/raw_*/*
codex/workspaces/*/runbooks/generated/**/remote_artifacts/
```

This keeps per-seed/chunk raw outputs on disk while removing them from normal
`git status`.  Compact runbooks, readbacks, CSV summaries, scheduler state, PBS
templates, and analysis scripts remain visible.

## Current Git Status Shape

Visible dirty status after raw-artifact ignore:

```text
tracked modified: 24
visible untracked status rows: 70
visible untracked files: 209
```

Tracked modified groups:

| group | count | content |
|---|---:|---|
| repo hygiene | 1 | `.gitignore` raw-artifact rules |
| WV-HMC source/tests | 9 | app common, constraints, driver, kernels, measurement, trajectory, tests |
| runbooks/SOP docs | 6 | modernization, TLTM SOP, WV-HMC implementation/math/bank docs, scheduler doc |
| scheduler state | 3 | queue observations, request ledger, scheduler knowledge |
| scripts/PBS | 5 | scheduler agent, WV-HMC validation/readback scripts and PBS |

Visible untracked groups:

| group | count | content |
|---|---:|---|
| generated readbacks/tables | 160 files/status entries | compact WV-HMC/TLTM generated summaries, not raw chunks |
| new scripts | 23 | WV-HMC bank, scan, history, flow-bin, weight-variant, submit helpers |
| new PBS templates | 12 | WV-HMC debug/build/validation/analysis PBS wrappers |
| scheduler state | 10 | cluster inventory, queue rankings, source pin metadata, worktree index JSON |
| new SOP runbooks | 4 | parameter tuning and initial-bank SOP files |

## Dataset / Generated Directory Routing

Use these generated directories as the current routing map:

| directory | role | keep visible? |
|---|---|---|
| `wv_hmc_t0_long_validation_20260602` | active old-boundary n=6 T0=0 long-validation readback and settled no-W offline fact | yes |
| `wv_hmc_n2_t001_clean_20260602` | clean n=2 bank-init WV-HMC validation after full-flip boundary policy | yes |
| `wv_hmc_n6_correctness_diagnostics_20260602` | n=6 debugging packet and current measurement-factor suspicion | yes |
| `wv_hmc_fast_audit_20260602` | fast boundary/reflection and high-flow diagnostic packet | yes |
| `wv_hmc_n6_prod15k_20260601` | older n=6 production diagnostics, useful as historical evidence | yes |
| `wv_hmc_t0_retune_20260601` | older T0 retune and window/cut diagnostics | yes |
| `wv_hmc_n6_t003_tuning_20260531` | parameter tuning evidence | yes |
| `wv_hmc_n6_t003_retune_20260531` | retune / solver cap / validation smoke evidence | yes |
| `cluster02_inventory_20260531` | cluster inventory and queue optimization evidence | yes |

Raw child directories named `chunks/`, `raw_*`, and `remote_artifacts/` are
diagnostic storage only and are now hidden from normal status.

## Current Blocking Source State

The worktree is intentionally not marked production-ready.

The no-W source/test/doc convention fix has been applied locally:

```text
WV-HMC measurement factor:
  wv_factor = phase / alpha
```

The tests now enforce that a supplied nonzero `W` is recorded for diagnostics
but does not change `wv_factor`.  The active math/implementation/SOP docs have
been updated to the same convention.

The cluster deterministic build/test gate and n=6 alpha/measure oracle are now
closed by job `18806.anode01`:

```text
test_wv_hmc_math_kernels: PASS
n=6 alpha/measure oracle: ok=T, alpha_rel=1.1275e-15, logabs_identity=0
test_wv_hmc_constraint_kernels: PASS
WV_HMC_GITLESS_BUILD_GATE_COMPLETE
```

Therefore do not commit a production-ready WV-HMC claim before:

1. short current-source n=6 validation with a pre-declared measurement window;
2. if the short gate passes, longer production-scale n=6 validation.

## Suggested Commit / Cleanup Groups

If committing in stages, use this order:

1. **Hygiene and index**
   - `.gitignore`
   - `WORKTREE_DATASET_INDEX_20260602.md`
   - `wv_hmc_t0_long_validation_20260602/*status/audit/readback*`

2. **Scheduler and gitless cluster control plane**
   - `CLUSTER02_SCHEDULING_AGENT.md`
   - `cluster02_scheduler_agent.py`
   - `CLUSTER02_*` state/inventory/source-pin files
   - scheduler request/observation ledgers

3. **WV-HMC implementation and deterministic tests**
   - `src/apps/wv_hmc_app_common.f90`
   - `src/sampler/wv_hmc_*.f90`
   - `tests/test_wv_hmc_*`
   - cluster deterministic verification and n=6 alpha/measure oracle are
     closed; defer final production-readiness claim until current-source n=6
     validation passes

4. **WV-HMC analysis/submission tooling**
   - new WV-HMC analysis scripts
   - PBS wrappers
   - source-pin/build-gate helpers

5. **Generated compact evidence packets**
   - generated readbacks and compact CSV/JSON summaries
   - keep raw chunks excluded unless a specific raw file is needed for a
     reproducibility claim

## Immediate Engineering State

Current next step remains:

```text
Run a short current-source n=6 validation with a pre-declared measurement
window before claiming production validation.
```

The deterministic/oracle gate job submitted after this cleanup was
`18806.anode01`; it completed with exit status 0.
