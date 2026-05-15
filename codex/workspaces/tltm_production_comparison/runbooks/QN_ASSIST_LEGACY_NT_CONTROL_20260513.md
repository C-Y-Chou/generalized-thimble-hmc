# QN Assist Legacy NT Control

Date: 2026-05-13 JST

Status: completed_readback_pass

## Purpose

Run one explicit sanity control for the current production-comparison tree:

- QN backend: official DFO-LS `stable_gate77`
- method: `fb_norefine`
- assist mode: legacy NT+QN navigation assist allowed
- scale: 10 seeds x 10000 cycles

This checks whether the poor formalized QN-navigation starting point is caused
by the stricter assist policy itself, or by another code/protocol change in the
current tree.

## Fixed Contract

- Remote worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Expected branch: `codex/tltm-production-comparison-official-dfols`
- Expected commit: `6f98b5bfce60678293c163764e1cefe8307736ba`
- Method: `fb_norefine` only.
- Scale: 10 seeds x 10000 cycles.
- Physical point: `t=0.35,L=2,nstep=20`.
- QN preset: `stable_gate77`, explicitly set as `npt=4`, `rhobeg=0.018`,
  `maxfun=250`, `objfun_has_noise=1`.
- Assist policy: `INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic` plus
  `INTODE_SOLVER_ASSIST_ENABLED=1`.

## Interpretation

Compare against the completed QN navigation-only stable anchor:

- `stable_gate77_npt4_r0018_m250` under `qn_navigation`: failures `4055`
  per 10seed/10k.

If this legacy NT+QN control falls near the old assist-on density, the strict
formalized policy was too restrictive as a starting point. If it remains close
to `4055`, then another production-tree or protocol difference is likely.

## Output

- Label: `qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`
- Output root:
  `output/tests/qn_assist_legacy_nt_control/qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`
- Log root:
  `output/logs/qn_assist_legacy_nt_control/qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`

## Submission

Submitted from `ithems_fe02.intra.riken.jp` at 2026-05-13T21:47:29+09:00.

- Active job: `15134.anode01`
- Queue: `C8`
- State at verification: running on `cnode24/0*10`
- Resource shape: 10 cores, 20gb, walltime 4h

Two earlier starts used the `v1` label and failed before any scientific run:

- `15132.anode01`: wrapper precheck rejected the pre-created output root.
- `15133.anode01`: wrapper argv still contained an unexpanded `--jobs` token.

Those failed prechecks produced no aggregate/per-seed scientific result and are
not part of the baseline readback.

## Readback

Completed 2026-05-13 JST. Active job `15134.anode01` exited with status 0.

- Rows: `10/10` per-seed rows.
- Policy manifest:
  - `INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic`
  - `INTODE_SOLVER_ASSIST_ENABLED=1`
- DFO-LS bridge warning audit: 4 residual-callback warnings, no job failure.

Summary:

| control | failures | projected 32s50k | RG rejects | mean Re | mean Im | Zmean Re | Zmean Im | NT assist count | QN assist count |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `stable_gate77_legacy_nt_qn_assist` | 3394 | 54304 | 988 | +0.083040 | +0.006599 | +3.58 | +0.29 | 663829 | 2043 |

Comparison to current stable QN-navigation anchor:

| control | failures | projected 32s50k | mean Re | mean Im | NT assist count | QN assist count |
|---|---:|---:|---:|---:|---:|---:|
| `stable_gate77_qn_navigation` | 4055 | 64880 | +0.037370 | -0.020443 | 0 | 3735 |
| `stable_gate77_legacy_nt_qn_assist` | 3394 | 54304 | +0.083040 | +0.006599 | 663829 | 2043 |

Interpretation:

- The control confirms NT solver assist was heavily exercised in the current
  code path.
- It improves failures relative to strict QN-navigation stable_gate77, but not
  nearly enough to reproduce old assist-on density.
- Therefore the old assist-on advantage is not explained by simply enabling NT
  assist in the current stable_gate77 backend.
