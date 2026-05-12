# ODEX Official Assist Observable-Degeneracy Readback

Updated: 2026-05-12 JST

Scope: paired per-seed observable readback for the existing official
DFO-LS ODEX solver-internal assist on/off evidence. Both variants use
`fb_norefine`; the only intended difference is
`INTODE_SOLVER_ASSIST_ENABLED=1` versus `0`.

## Current Readback Status

- The original 10seed x 10k readback proves solver-health degradation when solver assist is disabled, but does not prove observable degeneracy.
- The follow-up 16seed x 10k v2 paired remote gate completed successfully at commit `709a7de721b2d03b10be0a87bd60c223124301fd`:
  - `14947.anode01` assist-on: `Exit_status=0`, walltime `00:23:10`.
  - `14948.anode01` assist-off: `Exit_status=0`, walltime `00:24:46`.
- The 16seed v2 readback strengthens the solver-health conclusion but still does not give a production-grade observable-degeneracy conclusion.
- User decision on 2026-05-12 JST: assist is default-off for the pre-redo canonical line and scheduled for later deletion; the remaining assist-on/off evidence is diagnostic only, not a pre-redo blocker.

## Provenance

- Evidence root: `codex/workspaces/fortran_modernization/state/odex_official_dfols_assist_onoff_20260511`.
- Source aggregate readback: `codex/workspaces/fortran_modernization/runbooks/ODEX_OFFICIAL_ASSIST_ONOFF_READBACK_20260511.md`.
- Run commit recorded by manifest: `61505c307358323fe81568eeb49cdd177a134496`.
- Local HEAD when this readback was generated: `ad91c2d2eabc`.
- Seeds paired: `20260421, 20260518, 20260615, 20260712, 20260809, 20260906, 20261003, 20261100, 20261197, 20261294`.
- Scale: 10 seeds x 10000 cycles, `t=0.35,L=2,nstep=20`, official DFO-LS `stable_gate77`.

## Paired Metrics

| metric | n | assist on mean | assist off mean | off - on mean | SE(delta) | Z(delta) | + / - seed deltas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ohat_Re | 10 | -0.0290740000958 | -0.0136830848926 | 0.0153909152032 | 0.0249052478286 | 0.617978801461 | 6/4 |
| Ohat_Im | 10 | 0.0347713205763 | 0.0332807892011 | -0.00149053137514 | 0.0447452255346 | -0.0333115177616 | 5/5 |
| unresolved_failures | 10 | 117.9 | 154.2 | 36.3 | 4.04158934634 | 8.98161512448 | 10/0 |
| projection_failures | 10 | 217.5 | 262.8 | 45.3 | 4.28187394075 | 10.5794800657 | 10/0 |
| reverse_gate_rejects | 10 | 99.6 | 108.6 | 9 | 3.22834667008 | 2.78780469378 | 7/3 |
| pair0_accept | 10 | 0.4383 | 0.4397 | 0.0014 | 0.00283658636784 | 0.49355098645 | 5/5 |

## Interpretation

- Solver-health degeneracy is present at this scale: unresolved failures increase from `1179` to `1542` (`+363`), and Newton/QN h-min failures change from `0/0` to `14515/118` when assist is disabled.
- Observable readout is not yet a production-grade degeneracy conclusion: paired `Ohat_Re` delta Z is `0.617978801461` and paired `Ohat_Im` delta Z is `-0.0333115177616`.
- Conclusion tag: `no_observable_degeneracy_conclusion_at_10seed_10k`.

Current conclusion: the existing 10seed x 10k evidence proves that
assist-off degrades solver health, but it does not prove an actual
observable degeneracy. After the 2026-05-12 user decision, this remains
diagnostic context only: pre-redo canonical policy is assist default-off and
later deletion, so a larger assist-on/off observable gate is not required
before pre-redo.

## 16seed x 10k v2 Paired Readback

Evidence root on the remote worktree:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/runs/fortran_modernization/odex_official_dfols_assist_onoff_16seed_10k_parallel_v2_20260512`.

Protocol:

- 16 paired seeds, 10000 cycles per seed, `t=0.35,L=2,nstep=20`.
- Official DFO-LS `stable_gate77`.
- Standalone ODEX endpoint package commit `709a7de721b2d03b10be0a87bd60c223124301fd`.
- v1alpha sidecars and protocol audits passed for the paired seed outputs.

Aggregate readback:

| metric | assist on | assist off | off - on |
| --- | ---: | ---: | ---: |
| mean Re<O> | 0.0705266428994 | 0.0997527533318 | 0.0292261104325 |
| mean Im<O> | 0.0502919233894 | 0.00220511583664 | -0.0480868075527 |
| Zmean Re<O> | 2.27748019368 | 2.12852982665 | -0.148950367035 |
| Zmean Im<O> | 2.08317626392 | 0.115668137187 | -1.96750812674 |
| unresolved failures | 24273 | 26787 | 2514 |
| reverse-gate rejects | 1558 | 1497 | -61 |
| mean runtime seconds | 683.562639 | 714.952981312 | 31.3903423125 |

Paired-delta readback using the project `Z_mean = mean / standard_error` convention:

| metric | paired off - on mean | SE(delta) | Z(delta) | seed signs |
| --- | ---: | ---: | ---: | ---: |
| Ohat_Re | 0.0292261104325 | 0.0341421688369 | 0.856012123074 | 10+/6- |
| Ohat_Im | -0.0480868075527 | 0.0277477612907 | -1.73299773805 | 6+/10- |
| unresolved_failure_count | 157.125 | 16.8870944314 | 9.3044425516 | 15+/1- |
| projection_failure_count | 153.3125 | 17.4763456206 | 8.7725719855 | 15+/1- |
| reverse_gate_total_reject_count | -3.8125 | 3.28534466736 | -1.16045662967 | 6+/10- |
| pair0_accept_rate | -0.0016875 | 0.0015174505758 | -1.11206257845 | 5+/11- |
| runtime_total | 31.3903423125 | 3.62126292649 | 8.66834111461 | 16+/0- |

Solver-health mechanism check:

- Assist-on used Newton eval-flow solver assist on average `35992.9375` times per seed.
- Assist-off correctly reduced Newton solver-assist count to `0`.
- Assist-off introduced Newton eval-flow h-min failures with paired mean increase `703.5`, `Z(delta)=97.5970062117`.
- QN solver-assist was negligible at this scale (`0.6875` mean on, `0` off), so the observed health degradation is mainly in the Newton residual-evaluation flow path.

Interpretation:

- Solver-health degradation remains decisive at 16seed x 10k: unresolved and projection failures increase with `Z(delta) > 8`.
- Runtime also increases decisively with assist off.
- Observable readout remains inconclusive at this scale: paired `Ohat_Re` and `Ohat_Im` deltas are below a production-grade threshold, and the signs are mixed across seeds.

Current conclusion tag: `no_observable_degeneracy_conclusion_at_16seed_10k_v2`.

Pre-redo decision:

- The user selected solver-assist default-off and later deletion.
- A larger paired assist-on/off observable gate is no longer required before the pre-redo.
- Assist-on remains available only through explicit `INTODE_SOLVER_ASSIST_ENABLED=1` for diagnostic or historical comparison runs.
