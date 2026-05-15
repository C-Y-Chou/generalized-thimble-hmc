# F19 Official DFO-LS Certification Rename - 2026-05-15

Status: implemented locally.

## Scope

This is F19.1 from `OFFICIAL_DFOLS_THIN_BRIDGE_BRANCH_MAP_20260515.md`.
It is a source-level naming cleanup only:

- `src/sampler/quasi_newton_solver.f90`
  - renamed `rescue_attempt_from_best` to
    `certify_candidate_if_within_tol`;
  - updated all call sites in the official and internal QN paths;
  - did not change tolerances, candidate checks, certification residual checks,
    final-state recovery, route codes, package parameters, final-flow policy,
    reverse-gate policy, or Metropolis behavior.

## F8 Statement

Behavior intent: no numerical behavior change.

Reason: the helper was named like a rescue/best-candidate policy, but its
implementation is a strict certification gate:

- it returns unless the candidate residual is finite and within the active
  tolerance;
- it re-evaluates the TLTM certification residual;
- it returns unless the certification residual is also within tolerance;
- it recovers the flowed state only after those strict checks pass.

Affected surface: QN candidate certification in both official and internal QN
paths.  The official DFO-LS package route remains one package attempt plus TLTM
strict certification gates.

## Verification

Passed locally on 2026-05-15 JST with:

```sh
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_official_dfols_preset_contract \
  test_retained_core_qn_route_contract \
  test_retained_core_rg_reject_identity

TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
  make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_odex_assist_policy
```

Observed checkpoints:

- official DFO-LS preset contract completed;
- retained-core QN route contract completed with `route10_cases=3`,
  `success_cases=3`, `accepted_cases=3`;
- retained-core RG reject identity contract completed with stay-put checks;
- ODEX assist policy contract completed for default, off, diagnostic, and legacy
  env compatibility modes.

## Next Slice

F19.2 should isolate the official route policy:

- official DFO-LS route cannot enter internal DFO-like retry logic;
- near/far rescue env knobs cannot trigger extra official attempts;
- force-best proposal acceptance cannot affect the official route;
- solver-assist watchdog control cannot terminate official package
  certification flow;
- package failure remains proposal rejection without internal fallback.

