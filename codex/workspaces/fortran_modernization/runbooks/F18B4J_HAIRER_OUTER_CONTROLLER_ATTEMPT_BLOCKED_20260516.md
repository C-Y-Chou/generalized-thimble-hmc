# F18b.4j Hairer Outer Controller Screen Invalidated

Date: 2026-05-16 JST

Status: invalid screen, no ODEX-controller conclusion.  The temporary source
behavior was backed out to the behavior-free `hairer_experimental` gate plus
the accepted F18b.4g/h/i hardening line, but the 10seed/1k readback below is
not valid evidence against the Hairer outer-controller route.

## Question Tested

After HODEX-LB-001/002/003/004 were resolved, the next open ODEX surface was
HODEX-LB-006: whether an opt-in Hairer-style outer controller could be wired
under `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental` without disturbing the
default route.

The temporary implementation kept the existing TLTM initial step policy
(`h = 0.01*t`) and added an opt-in controller state machine around:

- first/last step handling,
- endpoint clipping,
- `KC` / `KOPT`,
- rejected-step history,
- reject-side step/order update,
- accepted-step next-`H` update,
- after-rejected accepted-step clamp.

This was deliberately tested as an opt-in branch.  Default source behavior
remained the accepted F18b.4i route during guardrail checks.

## Focused Package Evidence

The temporary implementation was internally usable on simple direct package
contracts:

```text
[CHECK] package_hairer_experimental ok=T context=T order=8 context_order=8 err=  4.9960E-16 context_err=  4.9960E-16
```

Focused ODEX tests passed in the temporary source:

```text
make -C build test_odex_controller_alignment_spec \
  test_odex_backend_package_contract \
  test_odex_controller_observation_contract \
  test_odex_result_contract \
  test_odex_foundation_contract
```

The default-route modernization guardrails also passed in the temporary source:

```text
make -C build modernization_guardrails
```

This means the temporary branch was compile/API usable and did not disturb the
default route.  It does not validate the 10seed/1k screen below, because the
screen was later found to have a broken official DFO-LS runtime environment.

## 10seed / 1k Screen

Screen directory:

```text
output/tests/f18b4f_hairer_outer_controller_10seed_1k_20260516T150233
```

Command shape:

```text
TLTM_ODE_CONTROLLER_POLICY=hairer_experimental \
python3 scripts/run_stage3_3_multiseed.py \
  --repo-root . \
  --config output/tests/f18b4f_hairer_outer_controller_10seed_1k_20260516T150233/config_10seed_1k.json \
  --max-seeds 10 \
  --methods no_fb_fbnorefine \
  --jobs 10 \
  --stage2-threads 1 \
  --eval-threads 1 \
  --schedule paired \
  --pair-order alternating \
  --output-subdir output/tests/f18b4f_hairer_outer_controller_10seed_1k_20260516T150233 \
  --logs-subdir output/logs/f18b4f_hairer_outer_controller_10seed_1k_20260516T150233 \
  --log-prefix f18b4f_hairer_outer_1k \
  --report-title "F18b.4f Hairer outer-controller 10seed 1k screen" \
  --skip-build
```

Aggregated readback from the invalid run:

| method | failures | reverse-gate rejects | mean Re | mean Im | Zmean Re | Zmean Im | mean runtime |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fb_norefine` | 878 | 0 | 0.12406758222359959 | 0.048830547047550736 | 0.7663972069608074 | 0.37917289850995584 | 22.8112127 |
| `no_fb` | 878 | 0 | 0.12406758222359959 | 0.048830547047550736 | 0.7663972069608074 | 0.37917289850995584 | 22.624688 |

Additional diagnostic readback:

- `total_local_proposal_failure_count=878` for both methods.
- `total_reverse_gate_total_candidate_count=0` for both methods.
- `total_newton_eval_flow_failure_h_min_count=831` for both methods.
- `fb_norefine` recorded `total_qn_eval_flow_success_count=878`, but still
  ended with `total_local_proposal_failure_count=878`.

This looked like the same bad shape as the earlier F18b.4c isolated
initial-H/initial-K attempt.  Follow-up inspection showed the same invalidating
cause in both screens: the `fb_norefine` path was not receiving a working
official DFO-LS bridge.

## Invalidating Evidence

The `fb_norefine` Stage2 log for the invalid run shows the bridge was not able
to import the official DFO-LS package:

```text
ModuleNotFoundError: No module named 'dfols'
[WARN] Official DFO-LS bridge failed: status=12 flag=-999; QN attempt will be rejected without internal fallback.
```

The invalid run manifest for `fb_norefine/seed_20260421` contains only the
minimal method/local-update environment:

```text
INTODE_SOLVER_ASSIST_POLICY = off
TLTM_STAGE2_INIT_MODE = adaptive
```

It does not contain the production-comparison QN/DFO-LS route environment such
as:

```text
TLTM_OFFICIAL_DFOLS_PYTHONPATH
QN_SOLVER_BACKEND
QN_OFFICIAL_DFOLS_PRESET
QN_REVERSE_GATE_ENABLED
QN_REVERSE_GATE_TOL
QN_QUASI_TOL_OVERRIDE
```

For comparison, the accepted F18b.4b 10seed/1k run did have:

```text
TLTM_OFFICIAL_DFOLS_PYTHONPATH=/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/lib/python3.11/site-packages
QN_SOLVER_BACKEND=official_dfols
QN_OFFICIAL_DFOLS_PRESET=stable_gate77
QN_REVERSE_GATE_ENABLED=1
QN_REVERSE_GATE_TOL=1e-8
QN_QUASI_TOL_OVERRIDE=1e-13
```

The equality between `fb_norefine` and `no_fb` is therefore explained by a
broken QN bridge/interface for the screen: `fb_norefine` entered the QN route,
the official DFO-LS import failed, and every QN attempt was rejected without the
internal fallback that F19 deliberately deleted.  The accepted local trajectory
then stayed Newton-only, matching `no_fb`.

Accepted F18b.4b 10seed/1k reference shape for comparison:

```text
fb_norefine failures=16, reverse-gate rejects=116, mean runtime=87.3316924
no_fb failures=890, reverse-gate rejects=116, mean runtime=50.5300101
```

Invalidated F18b.4c shape:

```text
fb_norefine failures=882, reverse-gate rejects=0, mean runtime=26.3112709
no_fb failures=882, reverse-gate rejects=0, mean runtime=26.413063
```

F18b.4j temporary Hairer outer-controller shape:

```text
fb_norefine failures=878, reverse-gate rejects=0, mean runtime=22.8112127
no_fb failures=878, reverse-gate rejects=0, mean runtime=22.624688
```

## Corrected Decision

Do not use this run to accept or reject the Hairer outer-controller transplant.

The 1k result is invalid because the official DFO-LS bridge was not available
to the run.  No 10k extrapolation should be made from it.

## Source Handling

The temporary behavior source was removed after the screen.  The repository
keeps:

- the accepted F18b.4g/h/i hardening,
- the behavior-free `hairer_experimental` policy/parser/observer surface,
- the line-audit records and blocked-attempt evidence.

The repository does not keep:

- the temporary `odex_step_hairer*` implementation,
- the temporary package test that treated the opt-in Hairer branch as a valid
  direct endpoint contract.

Post-backout focused readback passed:

```text
make -C build test_odex_controller_alignment_spec \
  test_odex_backend_package_contract \
  test_odex_controller_observation_contract \
  test_odex_result_contract \
  test_odex_foundation_contract
```

Follow-up interface hardening:

- `scripts/run_stage3_3_multiseed.py` now derives solver-route env defaults
  from the protocol when present: `QN_SOLVER_BACKEND`,
  `QN_OFFICIAL_DFOLS_PRESET`, `QN_QUASI_TOL_OVERRIDE`,
  `QN_REVERSE_GATE_ENABLED`, `QN_REVERSE_GATE_TOL`, rescue toggles, and
  `QN_S1_PROBE_MAX_ITER`.
- On local runs with `.venv-dfols`, the script now infers
  `TLTM_OFFICIAL_DFOLS_PYTHONPATH` from the venv site-packages directory if the
  caller did not set it.
- `python3 -m py_compile scripts/run_stage3_3_multiseed.py` passed, and a
  direct helper check on the invalid screen config now materializes the missing
  DFO-LS/QN env defaults.

## Next Required Step

Recreate the opt-in Hairer outer-controller patch only in a new temporary
screen branch/slice and rerun a short screen with a preflight that proves the
official DFO-LS environment is active.

The corrected screen must include, at minimum:

- `TLTM_OFFICIAL_DFOLS_PYTHONPATH` pointing to the local `.venv-dfols`
  site-packages directory;
- `QN_SOLVER_BACKEND=official_dfols`;
- the intended `QN_OFFICIAL_DFOLS_*` npt/rhobeg/maxfun/tolerance policy for the
  comparison being run;
- `QN_REVERSE_GATE_ENABLED=1` and `QN_REVERSE_GATE_TOL=1e-8`;
- log/manifest preflight checking for absence of `ModuleNotFoundError` and
  presence of the official DFO-LS env keys before interpreting any statistics.

Until a new decision is made, do not claim full Hairer ODEX paper-correctness.
Universal handwritten-algorithm paper-correctness remains blocked by CV-012 and
the all-handwritten line-audit requirement.
