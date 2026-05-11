# ODEX Official DFO-LS Assist On/Off Readback

Updated: 2026-05-11 JST

Scope: current-code Stage/TLTM readback for ODEX solver-internal
assist policy under the embedded official DFO-LS backend. This is not
a nofb-vs-withfb production-route comparison; both variants use
`fb_norefine` and differ only by `INTODE_SOLVER_ASSIST_ENABLED`.

## Provenance

- Imported evidence root: `codex/workspaces/fortran_modernization/state/odex_official_dfols_assist_onoff_20260511`.
- PBS script: `codex/workspaces/fortran_modernization/tasks/pbs/odex_official_dfols_assist_onoff_10seed_10k_20260511.pbs`.
- Readback-generation local HEAD before the evidence commit: `61505c307358`.
- Run commit recorded by manifest: `61505c307358323fe81568eeb49cdd177a134496`.
- Backend/preset: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Physical point: `t=0.35,L=2,nstep=20`; scale: `10 seeds x 10000 cycles`; method `fb_norefine`.
- Assist-on variant: `INTODE_SOLVER_ASSIST_ENABLED=1`.
- Assist-off variant: `INTODE_SOLVER_ASSIST_ENABLED=0`.

## Aggregate Comparison

| metric | assist on | assist off | off - on | pct delta | off / on |
| --- | ---: | ---: | ---: | ---: | ---: |
| mean_Re | -0.0290740000958 | -0.0136830848926 | 0.0153909152032 | NA | NA |
| mean_Im | 0.0347713205763 | 0.0332807892011 | -0.00149053137514 | NA | NA |
| Zmean_Re | -0.884739776363 | -0.326722630929 | 0.558017145434 | NA | NA |
| Zmean_Im | 1.13463055101 | 1.16121639412 | 0.0265858431118 | NA | NA |
| unresolved_failures | 1179 | 1542 | 363 | 30.7888041 | 1.30788804 |
| projection_failures_mean | 217.5 | 262.8 | 45.3 | 20.8275862 | 1.20827586 |
| reverse_gate_rejects | 996 | 1086 | 90 | 9.03614458 | 1.09036145 |
| newton_solver_assist | 682682 | 0 | -682682 | -100 | 0 |
| qn_solver_assist | 1858 | 0 | -1858 | -100 | 0 |
| newton_hmin_failures | 0 | 14515 | 14515 | NA | NA |
| qn_hmin_failures | 0 | 118 | 118 | NA | NA |
| pair0_accept | 0.4383 | 0.4397 | 0.0014 | 0.319415925 | 1.00319416 |
| runtime_seconds_mean | 999.2355646 | 916.6339024 | -82.6016622 | -8.26648541 | 0.917335146 |

Key readback:

- Assist-on exercised solver-internal assist: Newton `682682`, QN `1858`.
- Assist-off solver-internal assist counters: Newton `0`, QN `0`.
- Unresolved failures changed from `1179` to `1542`: delta `363`.
- H-min failures changed from Newton/QN `0`/`0` to `14515`/`118`.

## Interpretation

Conclusion tag: `assist_off_increases_unresolved_failures_at_10seed_10k`.

This closes only the representative 10seed x 10k current-code
assist-on/off readback slice for `fb_norefine`. It does not by
itself complete the full ODEX backend design work: result/workspace
status mapping, flow/Jacobian deterministic tests, and any selected
production-scale confirmation remain separate gates.
