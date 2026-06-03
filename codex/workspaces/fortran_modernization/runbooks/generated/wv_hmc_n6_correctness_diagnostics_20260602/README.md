# WV-HMC n=6 correctness diagnostics, 2026-06-02

This runbook records the completed diagnostic pass after the n=6 WV-HMC validation
kept producing biased observables.  The goal was not to tune parameters or launch
another long production run.  The goal was to finish the short, targeted checks
and leave a hard conclusion about what the current evidence does and does not
support.

## Current conclusion

The current n=6 WV-HMC bias is not explained by a generic "bad initial bank"
story alone.  The strongest concrete evidence points instead to the
measurement-factor convention, especially the alpha/W factor used in the
observable weight.

The deterministic kernel tests pass, and the same-record short trace shows that
the kernel is not completely frozen.  The existing failed 32x1500 run is biased
across the flow-time interval, including high-flow bins.  Offline reweighting of
the same history shows that alpha-multiplied weight variants move the two exact
observables much closer to the n=6 exact references, while the current WV factor
does not.

This does not prove the replacement formula yet.  It fixes the next debugging
target: do a formula/code audit and add an n=6 pointwise measurement-factor
identity/oracle before running more long n=6 validation jobs.

## Source and remote context

- Local workspace: `/Users/ccy/Documents/TLTM_fortran_modernization`
- Runtime snapshot: `/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n2_t001_fullflip_clean_20260602`
- Source pin: `4597ced50bd8-dee0602a51c0`
- Commit: `4597ced50bd89f17796aeb56f3444ebc2a7cb17a`
- Remote output root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_correctness_diagnostics_20260602`
- Local artifact root: `remote_artifacts/`

## Diagnostic ledger

| id | diagnostic | status | conclusion |
|---|---|---|---|
| D0 | Deterministic kernel and build gate | complete | Algebra/contract tests pass. This excludes obvious one-step kernel errors but does not validate ensemble weights. |
| D1 | Offline weight-variant scan on existing n=6 32x1500 history | complete | Current WV factor stays biased; alpha-multiplied variants are much closer to exact references. Measurement-factor convention is the leading suspect. |
| D2 | Flow-time binned observable analysis on existing n=6 32x1500 history | complete | Bias is visible throughout the flow-time interval, including high-flow bins. It is not only a low-flow contamination issue. |
| D3 | Same-bank-record short trace with Newton diagnostics | complete | Kernel moves and Newton mostly converges; not enough samples for physics. This is a transition-health check, not an observable validation. |
| D4 | n=6 pointwise WV measurement-factor identity/oracle | unavailable | Existing independent reweight identity tool is n=2-only. A true n=6 oracle must be added before changing the production formula. |
| D5 | Long n=6 validation after suspected fix | deferred | Deferred intentionally. The current evidence says to audit/fix measurement-factor convention first. |

## D0 deterministic kernel/build gate

Artifacts:

- `remote_artifacts/build_gate/test_wv_hmc_math_kernels.log`
- `remote_artifacts/build_gate/test_wv_hmc_constraint_kernels.log`

Important pass signals:

- `wv_force_contract ok=T`
- `wv_random_complex_force_flow ok=T`
- `wv_nonzero_flow_projection_geometry ok=T`
- `wv_worldvolume_force_fd ok=T`
- `wv_simplified_newton_contract ok=T`
- `wv_dense_simplified_newton_oracle ok=T`
- `wv_dense_rattle_reversibility ok=T`
- `wv_dense_rattle_energy_scaling ok=T`
- `wv_dense_trajectory_energy_order ok=T`
- `wv_dense_trajectory_reverse_energy ok=T`
- `wv_boundary_paper_full_flip ok=T`
- `wv_dense_transition_accept ok=T`
- `wv_nonzero_w_transition_gate ok=T`
- `wv_dense_measurement_factor ok=T`
- `wv_operator_measurement_factor_dense_oracle ok=T`
- `wv_dense_chain_driver ok=T`

Conclusion: the deterministic gates pass.  This supports that the local algebra,
projection, RATTLE reversibility checks, boundary-policy unit tests, and dense
measurement-factor self-consistency tests are internally consistent.  It does
not prove that the implemented measurement factor matches the intended WV-HMC
physics convention.

## D1 offline weight-variant scan

Input run:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_retune_20260601/wv_hmc_n6_t0_retuned_g65e009n10_validation_32x1500_20260601`

Artifacts:

- `remote_artifacts/existing_32x1500_weight_variants.csv`
- `remote_artifacts/existing_32x1500_weight_variants_prefix500.csv`

Exact references used by the analysis:

- chiral condensate: `0.0244771983`
- number density: `0.5661155667`

All-available 32-seed results, 40208 samples:

| variant | chiral Re | chiral z_Re | chiral z_Im | density Re | density z_Re | density z_Im | phase coherence |
|---|---:|---:|---:|---:|---:|---:|---:|
| current_wv_factor | 0.016344778 | -3.654 | -0.222 | 0.790818005 | 2.218 | 0.954 | 0.0926 |
| phase_only | 0.019964401 | -1.539 | -0.233 | 0.748948017 | 1.505 | 0.851 | 0.0894 |
| phase_times_alpha | 0.025933155 | 0.276 | -0.008 | 0.665027016 | 0.537 | 1.228 | 0.0711 |
| current_times_alpha2 | 0.028622970 | 0.477 | 0.256 | 0.564917666 | -0.004 | 1.498 | 0.0597 |

Prefix-500 32-seed results, 13415 samples:

| variant | chiral Re | chiral z_Re | chiral z_Im | density Re | density z_Re | density z_Im | phase coherence |
|---|---:|---:|---:|---:|---:|---:|---:|
| current_wv_factor | 0.013582304 | -3.673 | 0.442 | 0.965842668 | 3.649 | 0.046 | 0.1073 |
| phase_only | 0.015496233 | -2.748 | 0.014 | 0.988137283 | 3.183 | 0.323 | 0.1104 |
| phase_times_alpha | 0.018419344 | -1.190 | 0.625 | 0.963997903 | 2.078 | 0.703 | 0.0923 |
| current_times_alpha2 | 0.014835506 | -1.448 | 1.716 | 0.850954434 | 1.103 | 0.686 | 0.0861 |

Conclusion: this is the strongest diagnostic result in this pass.  The same
sample history behaves very differently under alpha-related measurement-factor
variants.  The current implementation uses the current WV factor in
`src/sampler/wv_hmc_measurement.f90`; the next step is to audit the alpha/W
formula and add an independent n=6 pointwise identity test.

Do not interpret this table as a final replacement formula.  Offline variants
can be noisy, and only an independently derived n=6 oracle can decide which
formula is mathematically correct.

## D2 flow-time binned diagnostics

Artifact:

- `remote_artifacts/existing_32x1500_flow_bins.csv`

The existing 32x1500 run was split into eight flow-time bins over `[0, 0.03]`.
The current WV factor remains biased across the interval:

| bin | flow-time interval | chiral Re | chiral z_Re | density Re | density z_Re | samples |
|---:|---|---:|---:|---:|---:|---:|
| 0 | [0.00000, 0.00375] | 0.016959367 | -1.134 | 0.934431717 | 1.709 | 5056 |
| 1 | [0.00375, 0.00750] | 0.016624728 | -1.579 | 0.689446132 | 0.404 | 4602 |
| 2 | [0.00750, 0.01125] | 0.014208670 | -3.677 | 0.744707530 | 1.278 | 4424 |
| 3 | [0.01125, 0.01500] | 0.016293247 | -2.610 | 0.761902537 | 1.622 | 4553 |
| 4 | [0.01500, 0.01875] | 0.016403256 | -2.881 | 0.792407553 | 2.267 | 4686 |
| 5 | [0.01875, 0.02250] | 0.017052186 | -3.599 | 0.738630090 | 1.764 | 5091 |
| 6 | [0.02250, 0.02625] | 0.016780788 | -3.919 | 0.815087686 | 2.345 | 5409 |
| 7 | [0.02625, 0.03000] | 0.016285322 | -2.745 | 0.814379152 | 1.636 | 6387 |

Conclusion: the failure is not isolated to the low-flow part of the
measurement interval.  A pure thermalization or low-flow contamination story is
not sufficient.

## D3 same-bank-record short trace

Remote run:

`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_correctness_diagnostics_20260602/wv_hmc_n6_same_record_trace_g65_e009_n10_4x20_20260602`

Artifacts:

- `remote_artifacts/same_record_trace_analysis/history/wv_hmc_history_readback.md`
- `remote_artifacts/same_record_trace_analysis/history/wv_hmc_history_metadata.json`
- `remote_artifacts/same_record_trace_analysis/newton/wv_newton_trace_analysis.md`
- `remote_artifacts/same_record_trace_analysis/newton/wv_newton_trace_solve_summary.csv`
- `remote_artifacts/same_record_trace_analysis/newton/wv_newton_trace_iteration_summary.csv`

Run setup:

- fixed bank record: `4009`
- seeds: `9920001` to `9920004`
- cycles per seed: `20`
- total completed cycles: `80`
- total history samples: `62`

Transition summary:

| metric | value |
|---|---:|
| accepted | 57 |
| rejected | 23 |
| acceptance including rejects | 0.7125 |
| transitions_failed | 17 |
| metropolis_rejected | 0 |
| reverse_gate_checked | 63 |
| reverse_gate_failed | 6 |
| reverse_gate_rejected | 6 |
| runtime_sec_sum_over_seeds | 213.790 |

Newton trace summary:

| seed | solves | converged | boundary | max_iter | converged rate | resolved rate | converged iter q50/q90/max |
|---:|---:|---:|---:|---:|---:|---:|---|
| 9920001 | 267 | 246 | 10 | 0 | 0.921 | 0.959 | 8/12/25 |
| 9920002 | 332 | 318 | 10 | 0 | 0.958 | 0.988 | 8/12.3/70 |
| 9920003 | 316 | 305 | 4 | 0 | 0.965 | 0.978 | 9/14.6/191 |
| 9920004 | 381 | 372 | 8 | 0 | 0.976 | 0.997 | 8/11/27 |

Conclusion: this short trace is not a physics run.  The tiny-sample observable
z-scores in the artifact are not meaningful.  The transition-health conclusion
is narrower: the chain is not completely frozen, Newton does not hit max_iter
in this trace, and there are real transition failures/reverse-gate events to
monitor.  This does not explain the persistent all-run observable bias as well
as the weight-variant result.

## D4 missing n=6 measurement-factor oracle

The existing independent pointwise identity tool is
`codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n2_wv_reweight_identity_20260531.py`.
It is currently n=2-only.  Therefore this diagnostic pass cannot directly prove
the n=6 WV measurement factor formula by independent quadrature/oracle.

Required next engineering task:

1. Derive the WV measurement factor from the target convention in one place.
2. Add an n=6-capable pointwise/oracle test for the alpha/W factor.
3. Compare the production implementation in `src/sampler/wv_hmc_measurement.f90`
   against that oracle.
4. Only then change the production weight formula and rerun n=6 validation.

## What this pass rules out

- It does not support continuing long n=6 production just by changing the
  initial bank.
- It does not support treating the previous n=6 bias as only low-flow
  contamination.
- It does not show a max_iter-driven Newton catastrophe in the short trace.
- It does not show a deterministic one-step kernel failure in the current unit
  tests.

## What this pass does not rule out

- A production formula error in the WV measurement factor.
- A sign, alpha power, or W-convention mismatch between the paper derivation and
  `src/sampler/wv_hmc_measurement.f90`.
- A transition problem that affects efficiency or ergodicity but is secondary to
  the measurement-factor evidence.
- A bug in a path not covered by the deterministic tests.

## Next action fixed by this diagnostic pass

Stop running long n=6 WV-HMC validation jobs as the next step.  The next step is
a formula/code audit plus an n=6 measurement-factor identity/oracle.  After that
passes, rerun a short n=6 validation and then a longer validation only if the
short result is consistent with the exact references.
