# Official DFO-LS Pre-Redo 32seed/50k Readback

Date: 2026-05-12 JST

Campaign: `official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`

Remote worktree:
`/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`

Remote output:
`output/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`

## Setup

- Physical point: `t=0.35,L=2,nstep=20`.
- Scale: `32 seeds x 50000 cycles` per method.
- Methods: `no_fb -> nofb`, `fb_norefine -> withfb`.
- Backend: `QN_SOLVER_BACKEND=official_dfols`.
- Official DFO-LS preset: `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Assist policy: `INTODE_SOLVER_ASSIST_ENABLED=0`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Production worktree commit: `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.

## Completion

- Jobs `14954`-`14963` all exited with `Exit_status=0`.
- Per-method seed rows: 32/32 for `nofb`, 32/32 for `withfb`.
- Final merged `REPORT.md` and `combined_summary_table.csv` are present.
- Same seed list as frozen 2026-05-11 32seed/50k: `20260421` through `20263428`.

## Main Result

| canonical | raw | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej | runtime |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | 32 | 0.34375 | 0.78125 | 0.65625 | 0.9375 | 0.09549068827299285 | -0.0017842285424940483 | 0.09017551009452575 | 0.05734393481436037 | 5.990283893906403 | -0.17601025889394464 | 265127 | 15086 | 3389.99086840625 |
| withfb | fb_norefine | 32 | 0.46875 | 0.8125 | 0.6875 | 0.96875 | 0.060792566742816925 | 0.0112710435756147 | 0.0695179255398047 | 0.03552059051425039 | 4.946849130584964 | 1.794977218111019 | 67061 | 14991 | 5271.5809374375 |

## Direct Paired Comparison

`withfb - nofb`, paired over the same 32 seeds:

- Re mean difference: `-0.0346981215301759 +/- 0.0173612518833185`, paired t `-1.9986`, positive/negative seeds `11/21`.
- Im mean difference: `+0.0130552721181087 +/- 0.0104624431584951`, paired t `1.24782`, positive/negative seeds `17/15`.
- Unresolved failures: `-198066`.
- Reverse-gate rejects: `-95`.
- Mean runtime: `+1881.59` seconds.

## Comparison To Frozen 2026-05-11 32seed/50k

The seed list is unchanged, so old-vs-new comparisons are paired over the same 32 seeds.

Frozen 2026-05-11 paired method difference:

- Re mean difference: `-0.0221825635646655 +/- 0.0177992540223572`, paired t `-1.24626`.
- Im mean difference: `+0.00998582497258502 +/- 0.00919448212828949`, paired t `1.08607`.

New minus frozen, same method and same seeds:

| method | observable | mean shift | paired SE | paired t | pos/neg |
|---|---|---:|---:|---:|---:|
| nofb | Re | +0.0753018961385964 | 0.0168897541897311 | 4.45844 | 25/7 |
| nofb | Im | +0.00320164430059733 | 0.0106002721988882 | 0.302034 | 18/14 |
| withfb | Re | +0.0627863381730859 | 0.0142766343346361 | 4.39784 | 25/7 |
| withfb | Im | +0.00627109144612106 | 0.0096182510181687 | 0.651999 | 11/21 |

## Assist-Policy Attribution

The dominant provenance difference is solver assist:

- Frozen 2026-05-11 source commit `d3f133d1fd7de2ec6a5b7ac27840c01287be5be7` had `intode_enable_solver_assist = .true.` as a compile-time policy in `src/physics/solve_flow.f90`.
- The frozen 32seed/50k PBS chunk did not export `INTODE_SOLVER_ASSIST_ENABLED=0`.
- New pre-redo commit `a22de1c19633793cf9c3ff7037b7cbc399e1b568` changed the policy to `intode_solver_assist_enabled_default = .false.` plus runtime parsing of `INTODE_SOLVER_ASSIST_ENABLED`.
- This pre-redo campaign explicitly recorded `ASSIST_POLICY=INTODE_SOLVER_ASSIST_ENABLED=0` in `submit_manifest.env` and every chunk manifest.

Therefore, compare frozen 2026-05-11 outputs and this pre-redo output as assist-on vs assist-off evidence, not as same-protocol replicas.

## Interpretation

- The gate completed cleanly and `withfb` still sharply reduces unresolved failures relative to `nofb`.
- The important caveat is the large positive Re displacement in both methods at the same seeds relative to the frozen 2026-05-11 32seed/50k output.
- The best current attribution is solver-assist policy: frozen 2026-05-11 was assist-on/default, while this pre-redo run is assist-off.
- Because this affects `nofb` as well as `withfb`, it should be treated as an ODEX/final-flow policy comparison, not only a QN fallback comparison.
- This readback should block blind scale-up to 64seed/200k or 128seed/200k until the user accepts assist-off as the intended production protocol, or until an assist-on/off same-commit bridge run is completed.
