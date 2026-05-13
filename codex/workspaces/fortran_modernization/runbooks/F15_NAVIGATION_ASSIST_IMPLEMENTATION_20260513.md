# F15 Navigation-Assist Strict-Certification Implementation

Status: modernization-local implementation passed; production-tree sync gate open

Date: 2026-05-13 JST

## Summary

F15 implements the solver-assist handoff selected after the production
comparison/tuning readback: `nofb` remains the strict comparison route, while
fallback-on routes use solver assist only as a QN navigation mechanism.
Certification, final proposal flow, reverse-gate acceptance, and Metropolis
remain strict.

Canonical route:

```text
NT strict -> QN navigation assist -> unassisted certification -> strict final flow -> RG -> Metropolis
```

## Source Changes

- `solve_flow.f90`
  - Replaced the boolean solver-assist contract with typed policies:
    `off`, `qn_navigation`, and `all_navigation_diagnostic`.
  - Added residual roles:
    `nt_strict`, `qn_navigation`, `certification`, `final_flow`, and
    `reverse_replay`.
  - Canonical default is `qn_navigation`.
  - Legacy `INTODE_SOLVER_ASSIST_ENABLED=0` maps to `off`; legacy
    `INTODE_SOLVER_ASSIST_ENABLED=1` maps to the diagnostic all-navigation
    mode.

- `hmc_integrator_core.f90`
  - Marks Newton residuals as `nt_strict`.
  - Marks QN fallback residuals as `qn_navigation`.
  - Marks final proposal `flow(...)` as `final_flow`.
  - Preserves `reverse_replay` role during reverse-gate replay.

- `quasi_newton_solver.f90`
  - Splits normal QN residual evaluation from strict certification residual
    evaluation.
  - Recomputes the best QN candidate through strict certification before
    accepting a rescue/best state.
  - Uses the real Jacobian for certification rather than package success or
    any assisted finite value.

- `tltm_stage2_driver.f90`
  - Records
    `flow_policy_id=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`.
  - Records `INTODE_SOLVER_ASSIST_POLICY` in v1 manifest env readback.

- `scripts/run_stage3_3_multiseed.py`
  - Sets `no_fb` policy to `off`.
  - Sets `fb` and `fb_norefine` policy to `qn_navigation`.

- `scripts/run_m4_guardrails.py`
  - Requires Stage2 sidecar manifests to record
    `INTODE_SOLVER_ASSIST_POLICY`.

## Verification

Passed locally on 2026-05-13 JST:

```text
git diff --check
python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/run_m4_guardrails.py
make -C build FC=gfortran LDFLAGS= test_odex_assist_policy
make -C build FC=gfortran LDFLAGS= test_odex_foundation_contract
PYTHON=/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/bin/python \
TLTM_OFFICIAL_DFOLS_PYTHONPATH=/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/lib/python3.11/site-packages \
make -C build FC=gfortran LDFLAGS= test_retained_core_qn_route_contract test_retained_core_rattle_rg_contract post_b_rng_reference_anchor
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

The first retained-core QN route attempt without the official package
`PYTHONPATH` failed with `ModuleNotFoundError: No module named 'dfols'`; rerun
with `.venv-dfols` passed.  The M4 wrapper also inferred the same venv and
passed.

## Production Sync Gate

Production tree sync is allowed only after:

- this modernization-local M4 gate is green;
- remote/job state has been refreshed;
- no active pinned production jobs are present;
- the modernization branch is pushed.

At this checkpoint, the local gate is green.  The next action is to push the
modernization commit and fast-forward the production tree/branch to the pushed
F15 node.
