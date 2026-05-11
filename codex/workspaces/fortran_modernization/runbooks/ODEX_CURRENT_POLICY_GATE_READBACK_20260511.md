# ODEX Current Policy Gate Readback

Updated: 2026-05-11 JST

Scope: current-code deterministic gate for the `intode` solver-internal assist
policy. This is a source-level policy boundary test, not a production-scale
ODEX assist-on/off validation.

## Source Change

Added comparison-only environment control:

```bash
INTODE_SOLVER_ASSIST_ENABLED=0
```

Default behavior is unchanged: when the variable is absent or invalid,
solver-internal assist remains enabled.

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

The make target runs both:

```bash
../bin/test_odex_assist_policy enabled
INTODE_SOLVER_ASSIST_ENABLED=0 ../bin/test_odex_assist_policy disabled
```

## Result

Pass.

Readback highlights:

- default mode: policy visibility reports `enabled=T`, `fast_hmin=T`,
  `max_uses=0`;
- default mode: h-min in Newton/QN/QN-retry residual contexts is allowed;
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

This closes the current-code deterministic policy-gate gap only. It does not
close `CV-007`/`FG-001`, because the following are still missing:

- source-level ODEX result/workspace/status split;
- endpoint-only/stability-control decision;
- flow-wrapper/Jacobian deterministic tests;
- representative current-code assist-on/off Stage/TLTM validation before a
  production policy conclusion.
