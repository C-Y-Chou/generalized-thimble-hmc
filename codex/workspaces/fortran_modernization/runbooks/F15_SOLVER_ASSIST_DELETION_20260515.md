# F15 Solver Assist Deletion

Updated: 2026-05-15 JST

## Scope

This patch deletes the active solver-internal assist path from the canonical
modernization source line. The previous F15 navigation-assist implementation is
now historical/diagnostic evidence only.

The retained runtime contract is:

- ODEX endpoint integration either succeeds through the ODEX backend or reports
  the ODEX failure status.
- The Radau/JFNK secondary rescue stack remains disabled.
- Solver-assist compatibility counters and policy query APIs remain present for
  older diagnostics/output readers, but always report inactive/zero.
- Legacy attempts to enable assist through `INTODE_SOLVER_ASSIST_POLICY`,
  `INTODE_SOLVER_ASSIST_ENABLED`, `TLTM_STAGE3_METHOD_ASSIST_POLICY`, or
  `TLTM_STAGE3_METHOD_ASSIST_ENABLED` no longer activate an assist route.

## Source Changes

- `src/physics/solve_flow.f90`
  - removed `intode_try_solver_assist`;
  - removed active solver-assist policy/env parsing;
  - removed the `qn_navigation` and `all_navigation_diagnostic` policy modes;
  - removed solver-assist success/failure counters from active state;
  - made `get_intode_solver_assist_policy*` return `off`, disabled, max uses
    `0`, and `fast_hmin_assist=.false.`;
  - made `intode_solver_assist_policy_allows(...)` always return `.false.`;
  - kept retired status/diagnostic labels only for compatibility readers.
- `scripts/run_stage3_3_multiseed.py`
  - records `INTODE_SOLVER_ASSIST_POLICY=off` for `no_fb`, `fb`, and
    `fb_norefine`;
  - ignores method-level assist override envs instead of forwarding them.
- `tests/test_odex_assist_policy.f90`
  - converted the old on/off policy gate into a deletion gate; even explicit
    legacy enable envs must observe inactive policy and no allowed routes.
- `tests/test_odex_foundation_contract.f90`
  - updated the ODEX foundation contract to expect inactive policy and zero
    solver-assist success/failure counters.
- `build/makefile`
  - keeps the `test_odex_assist_policy` target but now runs default, explicit
    off, policy-enable-ignored, and legacy-enable-ignored cases.

## F8 Statement

Behavior level: behavior-relevant policy deletion with a deliberately narrower
affected baseline.

Affected baseline:

- `ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md` preserves the exact
  pre-deletion official DFO-LS `npt5_r0055`, true Stage2 RNG v2, 10seed/10k
  assist-off readback.
- Under that baseline the intended contract already has solver assist off and
  `QN assist = 0`.

Expected effect:

- The canonical assist-off route should not gain any solver-assist event.
- Old explicit enable knobs should stop changing route behavior.
- This patch does not certify `withfb` feedback-kernel measure preservation and
  does not replace the separate mature ODE backend evaluation.

Before using this patch as a production-comparison regeneration source, rerun
the direct 10seed/10k PBS wrapper from
`ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md` at the clean selected
commit, or explicitly record a narrower affected-baseline decision.

## Verification

Focused local gate:

```bash
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  test_odex_assist_policy \
  test_odex_foundation_contract \
  test_odex_result_contract \
  test_newton_eval_flow_status_context_contract \
  test_retained_core_qn_route_contract \
  test_retained_core_rg_reject_identity
```

Result: pass. The assist deletion policy gate passed for default, explicit
`INTODE_SOLVER_ASSIST_POLICY=off`, explicit
`INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic`, legacy
`INTODE_SOLVER_ASSIST_ENABLED=0`, and legacy
`INTODE_SOLVER_ASSIST_ENABLED=1` cases. All observed policy states were off,
disabled, `fast_hmin=F`, `max_uses=0`, and every route gate returned false.

Full M4:

```bash
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$PWD/.venv-dfols/lib/python3.11/site-packages" \
make -C build FC=gfortran PYTHON="$PWD/.venv-dfols/bin/python" \
  modernization_guardrails
```

Result: pass. M4 passed Python compile, CV-005 script evidence audit,
`git diff --check`, direct-env guard, Stage2 RNG v2 guard, ODEX/swap tests,
Stage3 sidecar dry-runs, F14 pre-redo gate, CV-001 official-line kernel gate,
post-B RNG anchor, Stage2 RNG v2 anchor, and sidecar merge checks.

## Current Claim Boundary

F15b is complete for active source deletion and local/M4 guardrails.

Remaining separate work:

- production-comparison sync/regeneration must use a clean selected commit and
  rerun or explicitly scope the affected npt5 assist-off baseline;
- `withfb` feedback-kernel correctness is a separate measure-preservation
  audit;
- ODEX-controller risk remains routed through mature package backend evaluation
  with SUNDIALS CVODE primary and ODEPACK fallback.
