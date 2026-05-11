# Official DFO-LS 32seed/50k Gate Readback

Date: 2026-05-11 JST

Campaign: `official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb`

Remote worktree:
`/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`

Remote output:
`output/production_comparison/provisional/official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb`

Report:
`output/production_comparison/provisional/official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb/REPORT.md`

## Setup

- Physical point: `t=0.35,L=2,nstep=20`.
- Scale: `32 seeds x 50000 cycles` per method.
- Methods: `no_fb -> nofb`, `fb_norefine -> withfb`.
- Backend: `QN_SOLVER_BACKEND=official_dfols`.
- Official DFO-LS preset: `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Post-refine: off for both reported methods (`post-refine = 0/0`).

## Completion

- `run_manifest.json`: 64/64 present.
- Per-method seed rows: 32/32 for `nofb`, 32/32 for `withfb`.
- All 8 chunk-level `aggregated_summary_table.csv` files were generated.
- Final merged `REPORT.md` and `combined_summary_table.csv` were generated at about 17:04 JST.

## Main Result

| canonical | raw | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej | runtime |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | 32 | 0.6875 | 0.96875 | 0.6875 | 0.90625 | 0.020188792134396484 | -0.004985872843091379 | 0.08564522767427822 | 0.05094258330601725 | 1.333466646990749 | -0.5536498965991518 | 120858 | 19197 | 3708.3135403125007 |
| withfb | fb_norefine | 32 | 0.71875 | 1.0 | 0.6875 | 0.9375 | -0.0019937714302690254 | 0.004999952129493637 | 0.055963649296814556 | 0.04419289747340104 | -0.20153214684082096 | 0.6400123564653849 | 19579 | 15987 | 5586.39629015625 |

## Direct Comparison

`withfb - nofb`:

- Mean shift: Re `-0.0221826`, Im `+0.00998582`.
- Zmean shift: Re `-1.535`, Im `+1.19366`.
- Unresolved failures: `-101279`.
- Reverse-gate rejects: `-3210`.
- Mean runtime: `+1878.08` seconds.

## Comparison To M6 R3 Modernization Reference

Use `m6_r3_32seed_50k` as the correct same-scale in-house/reference anchor, not the older
`judgment_20260508_32seed_50k_p28_rg` dataset.

M6 R3 source:
`codex/workspaces/fortran_modernization/state/M6_REFERENCE_COMPARISON_SUMMARY.tsv`

| canonical | metric | M6 R3 reference | official DFO-LS gate | official - reference |
|---|---|---:|---:|---:|
| nofb | mean Re<O> | 0.0201887921 | 0.020188792134396484 | +3.44e-11 |
| nofb | mean Im<O> | -0.0049858728 | -0.004985872843091379 | -4.31e-11 |
| nofb | unresolved failures | 120858 | 120858 | 0 |
| nofb | RG rejects | 19197 | 19197 | 0 |
| nofb | pair0 accept | 0.438043 | 0.4380425 | -5.0e-7 |
| withfb | mean Re<O> | 0.000168402 | -0.0019937714302690254 | -0.00216217 |
| withfb | mean Im<O> | 0.0015007415 | 0.004999952129493637 | +0.00349921 |
| withfb | unresolved failures | 28206 | 19579 | -8627 |
| withfb | RG rejects | 24927 | 15987 | -8940 |
| withfb | pair0 accept | 0.438588 | 0.43846875 | -0.00011925 |

Interpretation:

- `nofb` is unchanged by the official DFO-LS gate at the observable/counter level.
- This is expected because `no_fb` renders `enable_quasi_fallback=false`; the QN backend env is present in the PBS environment but the QN solve path is not used.
- The official DFO-LS change affects `withfb/fb_norefine`, where the quasi fallback path is active.
- Official DFO-LS reduces both unresolved failures and RG rejects for `withfb` at this scale, while shifting the mean observables modestly relative to M6 R3.
- Runtime columns should be compared carefully because the M6 summary and official gate report may not be identical instrumentation slices; use raw per-seed tables before making a runtime-only claim.

## Interpretation

- This gate is healthier than the earlier 10seed/10k official small gate for `withfb`: the `withfb` aggregate Re Zmean is close to zero and Im Zmean is moderate.
- `withfb` strongly reduces unresolved failures relative to `nofb`, from `120858` to `19579`.
- `withfb` also has fewer total RG rejects than `nofb` in this gate, from `19197` to `15987`.
- Runtime cost remains substantial: `withfb` is about `+1878s` mean runtime per seed versus `nofb` at this scale.
- This is still a gate-scale dataset, not a final production claim. The next decision should be based on whether these Zmean magnitudes and failure reductions are stable enough to scale further.

## Current Recommendation

For the next scale-up toward production, keep the comparison focused on:

- `nofb`
- `withfb` = `fb_norefine`

Do not reintroduce post-refine unless a later diagnostic shows official DFO-LS `fb_norefine` has a systematic bias or unacceptable reversibility/failure behavior at larger seed/cycle windows.
