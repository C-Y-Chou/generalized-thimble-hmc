# WV-HMC Measurement Factor Convention Audit

Date: 2026-06-02

Scope: phase / alpha / W(t) convention audit for the current WV-HMC
measurement implementation and the pinned n=6 T0=0 long-validation dataset.

## Status

The complete convention audit had not been completed before this checkpoint.
The current audit finds a concrete W(t) convention mismatch between the paper
formula and the implemented measurement factor.

## Paper Convention

The WV-HMC worldvolume average introduces the arbitrary flow-time weight as

```text
int dt e^{-W(t)} int_{Sigma_t} dz_t e^{-S(z_t)} O(z_t)
```

and samples the positive density proportional to

```text
exp[-Re S(z) - W(t)] Dz
```

where the real worldvolume measure is

```text
Dz = alpha |dz_t| dt.
```

Therefore W(t) cancels between the complex target integrand and the positive
sampling density.  The measurement/reweighting factor should be

```text
A(z) = alpha^{-1} det(E)/|det(E)| exp[-i Im S(z)]
```

with no extra `exp(W(t))` factor.

## Current Code Convention

Before the 2026-06-02 local source fix, production code included W(t) in the
measurement factor:

```text
wv_factor = exp(W(t)) * phase_factor / alpha
phase_factor = exp[i(arg detJ - Im S)]
```

This appears in both dense and operator measurement paths:

```text
src/sampler/wv_hmc_measurement.f90
  wv_dense_measurement_factor
  wv_operator_measurement_factor
```

The driver passed `measurement_w_value` into the measurement-factor routine, so
the extra `exp(W(t))` was active in production output for runs generated before
the fix.

## Test Convention Problem

Before the 2026-06-02 local source fix, existing tests were not an independent
paper-formula oracle for this issue.  They enforced the old implementation
convention:

```text
tilted_factor%wv_factor == exp(nonzero_w_value) * expected_factor
```

This means the old tests could pass while the paper-level W(t) convention was
wrong.

The previous documentation was also internally inconsistent:

- `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md` states the no-W factor.
- `WV_HMC_MATH_PHYSICS_REVIEW_20260529.md` incorrectly states that
  `exp(W(t))` is mandatory, while a later checklist line in the same file again
  lists the no-W factor.

## Pinned Dataset Offline Check

Dataset:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601
```

Broad measurement window `[0.025,0.03]`:

```text
current_wv_factor = exp(W) * phase / alpha
  max |z| = 3.198

phase_over_alpha = phase / alpha
  max |z| = 3.176

phase_only = phase
  max |z| = 1.747

current_times_alpha = exp(W) * phase
  max |z| = 1.753
```

The paper-correct no-W replacement (`phase_over_alpha`) does not dramatically
improve this old-boundary long dataset.  The variants that improve the broad
window remove `alpha^{-1}`; that conflicts with the paper formula and must not
be selected merely because it gives better z-scores on this dataset.

The endpoint-only cut `t >= 0.029` has much better z-scores for the current
factor, but uses only about 21 percent of the measurement samples and is too
post-hoc to rescue the production formula.

## Immediate Consequence

The local source-level correction applied after this audit is:

1. Fix the runbook convention: W(t) is part of the sampling potential, not the
   measurement reweighting factor.
2. Change tests so nonzero W(t) does not change `wv_factor`.
3. Change dense and operator measurement factors to
   `phase_factor / alpha`.
4. Because the old dataset still fails under `phase/alpha`, run current-code
   short n=6 validation and add alpha-specific oracle diagnostics before making
   any production claim.

Cluster deterministic tests and the explicit n=6 alpha/measure oracle passed in
job `18806.anode01`.  This closes the source-level convention gate, but it does
not rescue the old-boundary dataset or replace a current-source n=6 validation.

## Claim Boundary

This audit identifies a real W(t) convention bug that affected old
code/tests/docs and has now been fixed locally.  It does not prove that the n=6
observable discrepancy is fully explained by that bug.  The alpha convention
has since passed an independent n=6 oracle in cluster job `18806.anode01`; see
`../wv_hmc_measure_n6_oracle_gate_20260602/RESULT.md`.  The remaining open
correctness issue is not the pointwise measurement convention, but the full
production kernel's invariant measure and current-source n=6 validation.  Use
`../wv_hmc_verification_workflow_20260602/CURRENT_CODE_VERIFICATION_LEDGER_AND_TODO_WORKFLOW.md`
as the active follow-up workflow.
