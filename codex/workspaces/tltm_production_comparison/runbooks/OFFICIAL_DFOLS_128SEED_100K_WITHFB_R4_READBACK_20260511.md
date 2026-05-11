# Official DFO-LS 128seed/100k Withfb R4 Gate Readback

Date: 2026-05-11 JST

Campaign: `official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4`

Remote worktree:
`/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`

Remote output:
`output/production_comparison/provisional/official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4`

Report:
`output/production_comparison/provisional/official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4/REPORT.md`

Execution commit:
`1edbbd465663640e711d1935f8d2fa5b47bf8510`

## Setup

- Physical point: `t=0.35,L=2,nstep=20`.
- Scale: `128 seeds x 100000 cycles`.
- Method: `fb_norefine -> withfb` only.
- Baseline: accepted M6 R4 `nofb` and `withfb/fb_norefine` reference rows.
- Backend: `QN_SOLVER_BACKEND=official_dfols`.
- Official DFO-LS preset: `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Post-refine: off (`post-refine = 0/0`).

## Completion

- Preflight build: `14775.anode01`, `Exit_status=0`.
- Chunk jobs: `14776..14791`, all completed.
- Merge/report job: `14792.anode01`.
- Per-seed rows: `128/128`.
- Final `REPORT.md`, `official_withfb_summary_table.csv`, and per-method aggregate/per-seed tables generated at about 20:46 JST.

## Official DFO-LS Result

| canonical | raw | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej | runtime |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| withfb | fb_norefine | 128 | 0.7265625 | 0.9453125 | 0.703125 | 0.9296875 | 0.003434163621430383 | -0.0012225229577123272 | 0.04500054233190407 | 0.032706250663922146 | 0.8633923978986243 | -0.422893731201389 | 155321 | 128255 | 10879.63379652343 |

## Comparison To M6 R4

M6 R4 source:
`codex/workspaces/fortran_modernization/state/M6_REFERENCE_COMPARISON_SUMMARY.tsv`

| metric | M6 R4 nofb | M6 R4 withfb | official DFO-LS withfb | official withfb - M6 R4 withfb | official withfb - M6 R4 nofb |
|---|---:|---:|---:|---:|---:|
| mean Re<O> | 0.0067843097 | -0.0011736472 | 0.003434163621430383 | +0.00460781 | -0.00335015 |
| mean Im<O> | -0.0026896585 | -0.0012498974 | -0.0012225229577123272 | +2.73744e-05 | +0.00146714 |
| unresolved failures | 962417 | 224580 | 155321 | -69259 | -807096 |
| RG rejects | 152279 | 200530 | 128255 | -72275 | -24024 |
| pair0 accept | 0.438617 | 0.438762 | 0.43840171875 | -0.000360281 | -0.000215281 |
| mean runtime s | 7689.963103 | 8486.587849 | 10879.63379652343 | +2393.05 | +3189.67 |

Percent comparisons:

- Official withfb unresolved failures are `30.84%` lower than M6 R4 withfb and `83.86%` lower than M6 R4 nofb.
- Official withfb RG rejects are `36.04%` lower than M6 R4 withfb and `15.78%` lower than M6 R4 nofb.
- Official withfb mean runtime is `28.20%` higher than M6 R4 withfb and `41.48%` higher than M6 R4 nofb.

## Interpretation

- The R4-scale official DFO-LS withfb gate is statistically acceptable by this report: `Zmean Re=0.863`, `Zmean Im=-0.423`, with P68/P95 near expected coverage.
- The official backend substantially reduces unresolved failures and RG rejects relative to both M6 R4 withfb and M6 R4 nofb.
- Mean Re shifts positive relative to M6 R4 withfb, but remains closer to zero than M6 R4 nofb. Mean Im is essentially unchanged relative to M6 R4 withfb.
- The main cost is runtime: official DFO-LS withfb is about `28%` slower than M6 R4 withfb at this scale.
- This supports scaling official DFO-LS withfb further if runtime budget is acceptable. The next scientific risk to watch is whether the Re mean shift remains bounded at larger seed/cycle scale.

## Current Recommendation

Proceed to a larger production-candidate official DFO-LS withfb run only if the runtime cost is acceptable. If prioritizing quickest evidence before full production, use a matched R4-like or modestly larger window and keep M6 R4 as the nofb baseline; do not rerun nofb unless source changes touch non-QN paths.
