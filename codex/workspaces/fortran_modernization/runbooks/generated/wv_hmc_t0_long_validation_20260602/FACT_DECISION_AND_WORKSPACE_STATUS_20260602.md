# WV-HMC Fact Decision and Workspace Status

Recorded: 2026-06-02 17:35 JST

Scope: settle whether the pinned n=6 long-validation history remains biased
after the paper-correct no-W offline measurement-factor recomputation, then
summarize the current worktree, dataset, and progress state.

## Settled Fact

For the pinned old-boundary n=6 long-validation dataset, the broad measurement
window `[0.025,0.03]` still fails the observable gate after replacing the current
online weight

```text
current_wv_factor = exp(W) * phase / alpha
```

with the paper-correct no-W offline weight

```text
phase_over_alpha = phase / alpha.
```

This fact is confirmed for the same-history offline recomputation of this
dataset:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601
```

It is not a statement about a new current-source production run after fixing the
source/test convention, because that run has not been done.

## Evidence

All rows use:

- 63 usable seeds
- 148397 measurement-history samples
- measurement window `[0.025,0.03]`
- exact references:
  - chiral condensate: `0.0244771983`
  - number density: `0.5661155667`

| variant | C | chiral z Re | chiral z Im | density z Re | density z Im | max abs z | status |
|---|---:|---:|---:|---:|---:|---:|---|
| `current_wv_factor` | 0.11038 | -3.198 | -0.954 | 1.370 | 1.475 | 3.198 | fail |
| `phase_over_alpha` | 0.11083 | -3.176 | -0.781 | 1.294 | 1.348 | 3.176 | fail |
| `phase_only` | 0.09013 | 1.747 | -0.788 | -1.046 | 1.347 | 1.747 | diagnostic only |
| `current_times_alpha` | 0.08972 | 1.753 | -0.953 | -1.004 | 1.472 | 1.753 | diagnostic only |

The key decision row is `phase_over_alpha`: removing the extra `exp(W)` does
not rescue the broad-window estimator for this dataset.  The apparent
improvement in `phase_only` and `current_times_alpha` removes the paper
`alpha^{-1}` factor and must not be used as a production formula choice.

Artifact:

```text
codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_t0_long_validation_20260602/long_validation_weight_variants.csv
```

## Claim Boundary

Confirmed:

- The current online summary for this dataset is contaminated by the extra
  `exp(W)` measurement factor.
- The same-history no-W recomputation `phase/alpha` is still biased in the
  broad measurement window.
- Therefore the remaining n=6 problem is not explained by the extra `exp(W)`
  measurement factor alone.

Not confirmed:

- Current post-fix source production correctness.
- Whether `alpha` is implemented with the correct paper convention.
- Whether the current transition kernel is fully correct for n=6 production.
- Whether a narrower, pre-declared measurement subwindow passes a production
  gate.

## Active Dataset Status

Active label:

```text
n6_t0_long_old_boundary_sourcepin_8ec6dc0d9b87_86f750bba994
```

Remote output:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601
```

Protocol:

- Stephanov n=6, `mu=0.6`, `tau=0`
- sampler interval `[T0,T1]=[0,0.03]`
- measurement interval `[0.025,0.03]`
- measurement start cycle `1001`
- `W(t)=paper_wall`, `gamma=65`
- `epsilon=0.009`, `nstep=10`, `L=0.09`
- `constraint_tol=1e-10`, `constraint_max_iter=192`
- ODE backend `dop853`

Completion:

- requested: 64 seeds x 15000 cycles
- usable summaries/observables/final states: 63
- observable histories: 64
- usable measurement histories: 63
- failed/no-measurement seed: `9630023`
- snapshots: 0

Important source limitation:

```text
TLTM_SOURCE_PIN_COMMIT=8ec6dc0d9b8768c5432e8c9df883a9cd870a82ba
TLTM_SOURCE_PIN_DIRTY_COUNT=51
boundary_policy_status=old implementation before simplified-paper full-flip fix
```

This dataset is useful for same-history measurement-factor diagnosis.  It is
not a current-source validation dataset.

## Active Initial Bank Status

Pinned initial bank:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat
```

Status:

- fixed-tau `T0=0` state bank
- 16064 packed records
- acceptance `0.7716979167`
- proposal failures `0`
- reverse-gate rejects `0`

## Worktree Status

The local worktree is not clean.

Current `git status --short` summary:

```text
modified files: 23
untracked paths: 68
total status rows: 91
```

Modified tracked categories:

- WV-HMC source and tests:
  - `src/sampler/wv_hmc_measurement.f90`
  - `src/sampler/wv_hmc_driver.f90`
  - `src/sampler/wv_hmc_constraints.f90`
  - `src/sampler/wv_hmc_kernels.f90`
  - `src/sampler/wv_hmc_trajectory.f90`
  - `tests/test_wv_hmc_constraint_kernels.f90`
  - `tests/test_wv_hmc_math_kernels.f90`
- WV-HMC app/config surface:
  - `src/apps/wv_hmc_app_common.f90`
  - `src/apps/evaluate_expectations.f90`
- runbooks and scheduler state/scripts:
  - `codex/workspaces/fortran_modernization/runbooks/*`
  - `codex/workspaces/fortran_modernization/state/*`
  - `codex/workspaces/fortran_modernization/tasks/*`

Untracked categories:

- generated WV-HMC readback/status directories
- generated cluster inventory/scheduler state files
- WV-HMC PBS wrappers and analysis/submission scripts
- SOP runbooks added during the WV-HMC phase

No files were reverted or deleted in this status cleanup.

## Current Code Status

Source/test/doc convention fix applied after this fact decision:

```text
src/sampler/wv_hmc_measurement.f90
  factor%wv_factor = phase_factor / alpha
```

The deterministic tests have been updated so nonzero W records
`potential_value` but does not change `wv_factor`:

```text
tests/test_wv_hmc_constraint_kernels.f90
  tilted_factor%wv_factor == expected_factor
```

The active math/implementation/SOP docs have been updated to the same no-W
convention.  Cluster job `18806.anode01` then completed the deterministic
build/test gate on `C17/cnode37` with exit status 0.  The math-kernel log
contains the explicit independent n=6 alpha/measure oracle line:

```text
[CHECK] wv_worldvolume_measure_factor_identity_case ok=T n=6 flow_time=3.0000E-03 alpha_rel=1.1275E-15 logabs_identity=0.0000E+00 logdet_volume=3.1086E-15
```

This closes the source-level measurement-convention and n=6 alpha/measure
oracle gate.  It does not by itself claim current-source n=6 production
observable validation.

## Cluster Status

Checked on `ithems_fe02.intra.riken.jp` at 2026-06-02 17:33 JST:

- `qstat -u cychou` showed no active queue rows in the captured output.
- No new jobs were submitted during this cleanup.

## Progress State

Closed for now:

1. The active long dataset and initial bank are pinned.
2. The no-W same-history recomputation fact is settled for the pinned old
   dataset.
3. The extra `exp(W)` measurement-factor convention bug is identified.
4. The source/test/doc no-W convention fix is applied.
5. Cluster deterministic verification and the independent n=6 alpha/measure
   oracle passed in job `18806.anode01`.

Authoritative follow-up workflow:

```text
codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_verification_workflow_20260602/CURRENT_CODE_VERIFICATION_LEDGER_AND_TODO_WORKFLOW.md
```

Still open and blocking current-source WV-HMC production correctness:

1. Full invariant-measure / detailed-balance gate for the dense explicit-J
   production kernel.
2. Momentum refresh and projected Gaussian base-measure proof.
3. Hamiltonian/base-measure convention decision record.
4. Boundary/RG/Metropolis/construction-failure invariant handling audit.
5. Short current-source n=6 validation with pre-declared measurement window,
   only after the invariant-measure gate passes.
6. Longer production-scale n=6 WV-HMC validation, only after the short gate
   passes.

Nonblocking but important:

- Archive or index the many generated WV-HMC runbook directories after the
  source-level convention fix is complete.
- Decide whether old-boundary datasets should be retained as diagnostics only
  or moved under a dated legacy-diagnostic label.
