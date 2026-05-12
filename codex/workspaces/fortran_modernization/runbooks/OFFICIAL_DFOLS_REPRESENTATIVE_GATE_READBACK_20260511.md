# Official DFO-LS Representative Gate Readback

Updated: 2026-05-11 JST

## Scope

This readback records the representative embedded official DFO-LS backend gate
for the current canonical `fb_norefine` route.

This is the F2 / CV-008 backend-replacement gate. It is not a final publication
production-regeneration approval by itself; final production still depends on
the remaining kernel-correctness, retained-core, diagnostics/accounting, and
schema/wrapper caveats.

## Execution

- Remote target: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- Branch: `codex/fortran-modernization`.
- Stage2/data generation commit: `9d6f9fcad21df5e8833dceb0aab90e1c93d69355`.
- Replay discovery repair commit for future runs: `248777d6ff683407d4bceb9d9ad29830d67fdfff`.
- Stage2 PBS job: `14804.anode01`.
- Replay recovery PBS job: `14805.anode01`.
- Label: `official_dfols_repr_gate_20260511_9d6f9fc`.
- Config: `docs/stage_3_4_t035_paired_10k_10seed.json`.
- Method: `fb_norefine`.
- Seed/cycle shape: 10 seeds x 10000 cycles.
- Capture shape: 100 QN attempts per seed, 1000 total captured attempts.
- Backend/preset: `QN_SOLVER_BACKEND=official_dfols`,
  `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.

The representative run uses per-seed capture directories through
`QN_ATTEMPT_CAPTURE_BASE_DIR`. This avoids the overwrite hazard from sharing one
`QN_ATTEMPT_CAPTURE_DIR` across multiple seeds when capture files are opened
with replacement semantics.

## Stage Aggregate

Remote artifact:

```text
output/tests/fortran_modernization/official_dfols_repr_gate_20260511_9d6f9fc/stage3/aggregated_summary_table.csv
```

Readback highlights:

```text
method=fb_norefine
n_seeds=10
total_unresolved_failure_count=1179
mean_projection_failure_count=217.5
mean_unresolved_failure_count=117.9
mean_quasi_probe_success_count=905.6
mean_pair0_accept_rate=0.4383
total_qn_eval_flow_success_count=1476550
total_qn_eval_flow_solver_assist_count=1858
total_reverse_gate_total_candidate_count=4006229
total_reverse_gate_total_pass_count=4005233
total_reverse_gate_total_reject_count=996
total_local_metropolis_reject_count=2690
total_local_reverse_gate_reject_count=996
total_local_proposal_failure_count=1179
```

The 10 per-seed Stage3 summary files, 10 eval metadata files, and 10 per-seed
capture bundles were present. Each per-seed `qn_attempt_meta.csv` had 101 lines
(header plus 100 captured attempts). Per-seed protocol audits passed.

## Official Replay Summary

Remote artifact:

```text
output/tests/fortran_modernization/official_dfols_repr_gate_20260511_9d6f9fc/gate_summary.txt
```

Readback:

```text
case_count=10
attempt_count=1000
official_result_count=1000
embedded_captured_converged_count=923
official_residual_success_count=923
float64_fail_count=0
missing_result_count=0
embedded_captured_converged_regression_count=0
max_official_final_residual_norm=4.02143661297323859e-02
missing_samples=
float64_fail_samples=
embedded_captured_converged_regression_samples=
```

The 77 residual failures were all captured attempts that had not converged under
the embedded TLTM residual gate. They are not regressions of embedded-converged
attempts.

## Verdict

Representative embedded official DFO-LS backend replacement passes under the
current scoped contract:

- Official package/preset provenance is present.
- The embedded official backend produces representative Stage2 output.
- Per-seed capture is isolated and replayable.
- Official replay preserves all embedded-converged captured attempts.
- There are 0 float64 contract failures, 0 missing replay rows, and 0
  embedded-converged regressions.

`CV-008` is accepted for representative backend replacement under
`DFO-LS==1.6.5`, `stable_gate77`, and the current TLTM residual-gate contract.
Reopen this row if the DFO-LS package version, preset, residual callback,
acceptance gate, bridge/runtime policy, or QN route changes.

This does not make final publication production complete. After the 2026-05-12
F14 completion pass, `CV-009` and `CV-010` are closed for the pre-redo gate, but
final production redo still needs the remaining `CV-001`/`CV-002`/`CV-006`
promotion boundary plus exact redo scope/scale and target commit/worktree.
