# Official DFO-LS Small Production-Comparison Redo

Campaign: `official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb`

Setup:
- physical point: `t=0.35,L=2,nstep=20`
- scale: `10 seeds x 10000 cycles`
- backend: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`
- gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
- raw/canonical mapping: `no_fb -> nofb`, `fb_norefine -> withfb`

| canonical | raw | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej | runtime | post-refine |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | 10 | 0.6 | 0.9 | 0.7 | 1.0 | 0.026522288126829607 | 0.024770110307204656 | 0.18867713806254421 | 0.09265616530776875 | 0.44452041249544577 | 0.8453832101101665 | 7502 | 1252 | 715.5420136 | 0/0 |
| withfb | fb_norefine | 10 | 0.8 | 1.0 | 0.6 | 0.9 | -0.029074000095812857 | 0.03477132057625035 | 0.10391763030331586 | 0.0969095801049234 | -0.8847397763629393 | 1.1346305510124002 | 1179 | 996 | 1105.0365717 | 0/0 |

Direct comparison `withfb - nofb`:
- mean shift: Re `-0.0555963`, Im `+0.0100012`
- Zmean shift: Re `-1.32926`, Im `+0.289247`
- unresolved failures: `-6323`
- reverse-gate rejects: `-256`
- mean runtime: `+389.495` seconds

Per-seed row counts:
- `nofb`: `10`
- `withfb`: `10`

Artifacts:
- `combined_summary_table.csv`
- per-method `aggregated_summary_table.csv`, `per_seed_summary_table.csv`, and method report files
