# ODEX solver-internal assist assist_on official DFO-LS 10seed 10k fb_norefine

Protocol freeze:
- ladder: `0.05,0.35`; max_flow_time: `0.35`
- local params: `L=2`, `nstep=20`, `local_updates=1`
- cycles_per_seed: `10000`; seeds: `10`; init: `adaptive`
- observable target: `Re<virial>=0`, `Im<virial>=0`

Key results (Re/Im analyzed separately):

| method | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fb_norefine | 10 | 0.8000 | 1.0000 | 0.6000 | 0.9000 | -0.029074 | 0.0347713 | 0.103918 | 0.0969096 | -0.88474 | 1.13463 | 1179 | 996 |

Failure / reverse-gate reject breakdown:

| method | unresolved failures | reverse-gate rejects (total route) |
|---|---:|---:|
| fb_norefine | 1179 | 996 |

Artifacts:
- `output/tests/fortran_modernization/odex_official_dfols_assist_onoff_20260511/assist_on/per_seed_summary_table.csv`
- `output/tests/fortran_modernization/odex_official_dfols_assist_onoff_20260511/assist_on/aggregated_summary_table.csv`
- `output/tests/fortran_modernization/odex_official_dfols_assist_onoff_20260511/assist_on/odex_official_dfols_assist_onoff_20260511_assist_on_report.md`
- `output/tests/fortran_modernization/odex_official_dfols_assist_onoff_20260511/assist_on/protocol_audit_summary.csv`
