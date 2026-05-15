# Solver Assist Problem Diagnosis - 2026-05-13 JST

## Question

Why did the formalized assist bridge fail to recover the old assist-on/default
failure scale, even though `fb_norefine` resolved to `qn_navigation` and QN
assist counters were nonzero?

## Short Answer

The old useful assist behavior was not merely QN navigation assist.  It was
Newton plus QN residual-evaluation assist on h-min failures, enabled globally
by the legacy default.  The current formalized bridge intentionally kept only
QN navigation assist and disabled Newton assist.  That removes the dominant
effective component of the old behavior.

## Evidence

Old 2026-05-11 32seed/50k official DFO-LS gate:

- PBS did not export `INTODE_SOLVER_ASSIST_ENABLED=0`.
- The solver-assist default at that time was enabled.
- `no_fb` had `total_newton_eval_flow_solver_assist_count=6954073`.
- `fb_norefine` had `total_newton_eval_flow_solver_assist_count=10964523`.
- `fb_norefine` had `total_qn_eval_flow_solver_assist_count=41017`.
- `fb_norefine` unresolved failures: `19579`.

Current formalized bridge:

- Chunk manifests set
  `INTODE_SOLVER_ASSIST_POLICY=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`.
- Per-seed manifests resolve:
  - `no_fb` to `off`;
  - `fb_norefine` to `qn_navigation`.
- `fb_norefine` had `total_newton_eval_flow_solver_assist_count=0`.
- `fb_norefine` had `total_qn_eval_flow_solver_assist_count=41823`.
- `fb_norefine` unresolved failures: `67159`.

The QN assist count is almost the same order in both runs (`41017` old versus
`41823` formalized).  The missing term is Newton assist: `10964523` old versus
`0` formalized.

The 10seed assist-on/off slice shows the same shape:

- assist-on had Newton assist `682682`, QN assist `1858`, and failures `1179`;
- assist-off had Newton assist `0`, QN assist `0`, and failures `1542`;
- h-min failures appeared only when assist was disabled.

## Code-Level Difference

Old assist-on behavior, as of the 2026-05-11 gate, allowed solver assist for
both Newton and QN residual-evaluation stages:

```text
stage == intode_stage_newton
stage == intode_stage_quasi
stage == intode_stage_quasi_retry
```

Current formalized `qn_navigation` allows only:

```text
stage == intode_stage_quasi
stage == intode_stage_quasi_retry
role == intode_role_qn_navigation or reverse_replay
```

The method wrapper also changed:

- current `no_fb` sets `INTODE_SOLVER_ASSIST_POLICY=off`;
- current `fb` and `fb_norefine` set `INTODE_SOLVER_ASSIST_POLICY=qn_navigation`;
- old scripts left the solver-assist default in effect.

## What The Assist Actually Does

The solver assist is not a stronger ODEX integration method.  On an allowed
h-min failure, it accepts the current partial ODEX state as a finite residual
evaluation.  This makes it a proposal-navigation device, not an exact flow
evaluation.

That means the old result relied heavily on giving Newton residual solves
quasi-finite values instead of hard failures.  Those finite values changed how
Newton and the subsequent fallback path traversed the target space.  Removing
Newton assist while keeping only QN assist leaves the system close to the
assist-off failure scale.

## Interpretation

There are two separate issues that were previously entangled:

1. The old `no_fb` was not a pure no-assist control.  It had no QN fallback,
   but it still inherited Newton residual assist from the global default.
2. The old `withfb` benefit was not only official DFO-LS/QN strength.  It was
   official DFO-LS plus a large amount of Newton residual assist and a smaller
   amount of QN residual assist.

Therefore the formalized bridge did not fail because assist was not enabled.
It failed because we formalized the wrong subset of the old assist behavior.

## Consequence

Do not scale the current `qn_navigation` policy as-is.  It is a useful strict
certification design, but it does not reproduce the old production behavior.

The next experiment should explicitly separate:

- `strict_off`: no solver assist anywhere;
- `qn_navigation`: current policy;
- `nt_qn_navigation`: Newton plus QN navigation assist, with unassisted
  certification/final/RG/Metropolis;
- optionally `legacy_enabled_diagnostic`: old boolean-compatible behavior for
  direct reference only.

The likely modernization target is `nt_qn_navigation` as a proposal-only
policy, not the current QN-only policy.
