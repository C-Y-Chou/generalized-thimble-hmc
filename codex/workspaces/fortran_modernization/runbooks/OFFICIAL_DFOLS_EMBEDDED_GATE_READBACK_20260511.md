# Official DFO-LS Embedded Backend Gate Readback

Updated: 2026-05-11 JST

Scope: small remote embedded-backend gate for the official DFO-LS replacement.
This is not a final representative production gate. It verifies that the
embedded official backend can run the Stage2 path, capture QN attempts, and
replay those captured residual cases through the official package without
regressing attempts that the embedded path already accepted by the TLTM
residual gate.

## Run

- PBS job: `14803.anode01`
- queue: `C8`
- host: `cnode18`
- PBS exit status: `0`
- worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- branch: `codex/fortran-modernization`
- commit: `5ebb85c45e956bcd5d511718a6cad49df8e11386`
- label: `official_dfols_embedded_gate_20260511_5ebb85c`
- output root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/fortran_modernization/official_dfols_embedded_gate_20260511_5ebb85c`

Submission command:

```bash
qsub -v TLTM_EXPECTED_GIT_COMMIT=5ebb85c45e956bcd5d511718a6cad49df8e11386,TLTM_DFOLS_GATE_LABEL=official_dfols_embedded_gate_20260511_5ebb85c codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_backend_gate_20260511.pbs
```

## Embedded Backend Provenance

- `ENABLE_OFFICIAL_DFOLS=1`
- `QN_SOLVER_BACKEND=official_dfols`
- `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`
- `QN_OFFICIAL_DFOLS_NPT=4`
- `QN_OFFICIAL_DFOLS_MAXFUN=250`
- `QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE=1`
- `QN_OFFICIAL_DFOLS_RHOBEG=0.018`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-16`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-30`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`
- `TLTM_OFFICIAL_DFOLS_PYTHONPATH=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/.venv-dfols/lib64/python3.11/site-packages:/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/.venv-dfols/lib/python3.11/site-packages`
- Python executable: `/bin/python3.11`
- DFO-LS version printed by job: `1.6.5`
- NumPy version printed by job: `2.4.4`

## Gate Summary

```text
attempt_count=100
official_result_count=100
embedded_captured_converged_count=93
official_residual_success_count=93
float64_fail_count=0
missing_result_count=0
embedded_captured_converged_regression_count=0
max_official_final_residual_norm=1.91272610598863316e-02
missing_samples=
float64_fail_samples=
residual_fail_samples=26,40,41,74,87,90,99
embedded_captured_converged_regression_samples=
```

## Interpretation

The small embedded gate passes. The embedded official backend ran Stage2 under
the intended preset, captured 100 QN attempts, and the official package replay
produced one row for every captured attempt with no float64 failures.

All seven replay residual failures correspond to attempts that were not
accepted by the embedded TLTM residual gate; there were zero regressions among
the 93 embedded-converged captured attempts.

This closes the small embedded-backend smoke/readback subtask for `CV-008`.
It does not close `CV-008` as a final replacement claim. Remaining work is a
representative-scale embedded-backend readback beyond this 1seed x 500-cycle
gate and explicit promotion criteria for production regeneration.
