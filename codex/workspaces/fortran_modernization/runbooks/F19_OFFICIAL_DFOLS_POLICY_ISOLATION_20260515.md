# F19 Official DFO-LS Policy Isolation - 2026-05-15

Status: implemented locally.

## Scope

This is F19.2 from `OFFICIAL_DFOLS_THIN_BRIDGE_BRANCH_MAP_20260515.md`.
It isolates `QN_SOLVER_BACKEND=official_dfols` from legacy in-house solver
control policy.

Changed source:

- `src/sampler/quasi_newton_solver.f90`
  - added `qn_policy_uses_official_dfols`;
  - loads QN backend policy before watchdog setup;
  - does not begin quasi watchdog scope for the official DFO-LS backend;
  - leaves watchdog/force-best policy loading on the internal backend route.
- `src/sampler/hmc_integrator_core.f90`
  - detects whether the active QN route is official DFO-LS;
  - ignores `QN_QUASI_TOL_OVERRIDE` for official DFO-LS certification;
  - records near/far failure diagnostics for official DFO-LS failure without
    running near/far rescue attempts;
  - leaves near/far retry behavior available only for non-official/internal
    routes during the transition.

## F8 Statement

Behavior intent: intentional policy cleanup for the official route.

The canonical official route is:

```text
Newton strict attempt
-> one official DFO-LS package attempt
-> strict TLTM residual/certification gate
-> strict final flow
-> reverse gate when enabled
-> success or proposal reject/stay-put
```

This patch intentionally prevents these legacy controls from affecting the
official route:

- `QN_FORCE_BEST_PROPOSAL_ENABLED`
- `QN_FORCE_BEST_PROPOSAL_TOL`
- `QN_SOLVER_ASSIST_BUDGET`
- `QN_ACCEPTED_ITER_BUDGET`
- `QN_QUASI_TOL_OVERRIDE`
- `QN_S1_NEAR_RESCUE_ENABLED`
- `QN_S1_NONNEAR_RESCUE_ENABLED`

Package failure remains proposal failure/rejection unless the candidate already
passes strict TLTM residual and certification gates.  The internal DFO-like
backend remains available only through explicit legacy/internal backend
selection.

## Verification

Passed locally on 2026-05-15 JST with:

```sh
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_official_dfols_preset_contract \
  test_retained_core_qn_route_contract \
  test_retained_core_rg_reject_identity \
  test_odex_assist_policy
```

Policy-perturbation checks also passed:

```sh
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
QN_SOLVER_BACKEND=official_dfols \
QN_OFFICIAL_DFOLS_PRESET=stable_gate77 \
QN_FORCE_BEST_PROPOSAL_ENABLED=1 \
QN_FORCE_BEST_PROPOSAL_TOL=1.0 \
QN_SOLVER_ASSIST_BUDGET=1 \
QN_ACCEPTED_ITER_BUDGET=1 \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_retained_core_qn_route_contract

TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
QN_SOLVER_BACKEND=official_dfols \
QN_OFFICIAL_DFOLS_PRESET=stable_gate77 \
QN_S1_NEAR_RESCUE_ENABLED=1 \
QN_S1_NONNEAR_RESCUE_ENABLED=1 \
QN_QUASI_TOL_OVERRIDE=1.0e-2 \
QN_REVERSE_GATE_ENABLED=1 \
QN_REVERSE_GATE_TOL=1e-20 \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_retained_core_rg_reject_identity
```

Full M4 guardrail passed:

```sh
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  modernization_guardrails
```

M4 summary: all guardrails passed, including F14 pre-redo gate, CV-001
official-line kernel correctness gate, post-B RNG reference anchor, and Stage2
RNG v2 deterministic anchor.

## Next Slice

F19.3 should clean remaining HMC/QN wrapper vocabulary and diagnostics naming so
the official route reads as one official package attempt rather than a
probe/rescue controller.  F19.4 should then decide how long to retain
`QN_SOLVER_BACKEND=internal` and the internal DFO-like helpers as legacy
comparison code.

