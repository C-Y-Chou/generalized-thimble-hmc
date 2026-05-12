# ODEX Official Assist Observable-Degeneracy Readback

Updated: 2026-05-12 JST

Scope: paired per-seed observable readback for the existing official
DFO-LS ODEX solver-internal assist on/off evidence. Both variants use
`fb_norefine`; the only intended difference is
`INTODE_SOLVER_ASSIST_ENABLED=1` versus `0`.

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
observable degeneracy. A larger paired assist-on/off observable gate is
needed if F14 requires an observable-level decision rather than a solver
health decision.
