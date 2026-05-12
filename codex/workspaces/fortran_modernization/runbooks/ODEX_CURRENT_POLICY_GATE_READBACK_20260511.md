# ODEX Current Policy Gate Readback

Updated: 2026-05-11 JST

Scope: historical current-code deterministic gate for the `intode`
solver-internal assist policy. This is a source-level policy boundary test, not
a production-scale ODEX assist-on/off validation.

Supersession note: this file was one intermediate ODEX policy slice. Later
result/workspace/status, flow/Jacobian, standalone endpoint package, and
representative assist-on/off readbacks accepted `CV-007`/`F1` as reduced scope.
On 2026-05-12, user policy changed the pre-redo default to
`INTODE_SOLVER_ASSIST_ENABLED=0`; this file should not be read as the current
default-policy row by itself.

## Source Change

At the time, this added comparison-only environment control:

```bash
INTODE_SOLVER_ASSIST_ENABLED=0
```

Current behavior after the 2026-05-12 pre-redo policy decision is the opposite:
when the variable is absent or invalid, solver-internal assist remains disabled.
Assist-on requires explicit `INTODE_SOLVER_ASSIST_ENABLED=1`.

The policy remains:

- assist can only accept h-min failures;
- assist can only run in `flowz` or `flowzr` residual contexts;
- assist can only run during Newton/QN/QN-retry stages;
- final `flow(...)` context cannot be completed by assist;
- strict final proposal success remains limited to strict ODEX success and
  zero-time no-op.

## Command

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_assist_policy
```

The make target now runs default-disabled, explicit enabled, and explicit
disabled modes:

```bash
../bin/test_odex_assist_policy disabled
INTODE_SOLVER_ASSIST_ENABLED=1 ../bin/test_odex_assist_policy enabled
INTODE_SOLVER_ASSIST_ENABLED=0 ../bin/test_odex_assist_policy disabled
```

## Result

Pass.

Readback highlights:

- current default mode: policy visibility reports `enabled=F`, `fast_hmin=T`,
  `max_uses=0`;
- explicit enabled mode: h-min in Newton/QN/QN-retry residual contexts is
  allowed;
- disabled mode: policy visibility reports `enabled=F`;
- disabled mode: the same h-min residual contexts are rejected;
- wrong reason, unknown context, final-flow context, unknown stage,
  external stage, and RATTLE-flow stage are rejected in both modes.

## Tiny Stage Smoke

Also ran a tiny current-code Stage3 smoke with assist explicitly disabled:

```bash
INTODE_SOLVER_ASSIST_ENABLED=0 python3 scripts/run_stage3_3_multiseed.py \
  --repo-root . \
  --config output/tests/m4_guardrails/tiny_stage3_guardrail.json \
  --skip-build \
  --max-seeds 1 \
  --methods no_fb \
  --output-subdir output/tests/odex_assist_policy_stage3_disabled \
  --logs-subdir output/logs/odex_assist_policy_stage3_disabled \
  --log-prefix odex_assist_policy_disabled \
  --allow-oversubscribe
```

Result: pass. This tiny smoke produced no h-min assist events
(`newton_solver_assist=0`, `qn_solver_assist=0`) and therefore is only a
no-regression smoke for the env-disabled path, not an assist-degeneracy
measurement.

## Boundary

This historical file closes the deterministic policy-gate gap only. Current
`CV-007` status is tracked in `FULL_HAIRER_ODEX_REOPEN_PLAN_20260512.md` and
`CAVEATS.tsv`.
