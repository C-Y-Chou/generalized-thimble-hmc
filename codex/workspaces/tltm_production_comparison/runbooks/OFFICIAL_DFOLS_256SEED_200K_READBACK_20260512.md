# Official DFO-LS 256seed/200k Production Gate Readback

Date: 2026-05-12 JST

Campaign: `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`

Remote worktree:
`/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`

Report:
`output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb/REPORT.md`

Execution commit:
`c0e40218e6abe2706f4b9b4c66067dbcea74eeff`

## Setup

- Physical point: `t=0.35,L=2,nstep=20`.
- Scale: `256 seeds x 200000 cycles` per method.
- Methods: `no_fb -> nofb`, `fb_norefine -> withfb`.
- Backend: `QN_SOLVER_BACKEND=official_dfols`.
- Official DFO-LS preset: `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Post-refine: off (`post-refine = 0/0`).

## Completion

- Preflight build: `14814.anode01`, `Exit_status=0`.
- Chunk jobs: `14815..14878`.
- Merge/report job: `14879.anode01`.
- Per-seed rows: `256/256` for both methods.
- Final `REPORT.md` and `combined_summary_table.csv` are available.

## Result

| canonical | raw | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej | runtime |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | 256 | 0.671875 | 0.97265625 | 0.7421875 | 0.94921875 | 0.0025128804602197745 | -0.0008980638575030018 | 0.03841767179759089 | 0.021510884583892855 | 1.0465518987029727 | -0.6679884160043988 | 3846795 | 607777 | 14588.093013816413 |
| withfb | fb_norefine | 256 | 0.6796875 | 0.9453125 | 0.71875 | 0.96484375 | 0.004020561055771586 | -0.0008372428375762778 | 0.032605416058066425 | 0.01975828896374589 | 1.9729537196453188 | -0.6779881307435225 | 618706 | 510906 | 22284.544315070314 |

## Direct Comparison

- `withfb - nofb` mean shift: Re `+0.0015076805955518115`, Im `+0.000060821019926724`.
- `withfb - nofb` Zmean shift: Re `+0.9264018209423461`, Im `-0.0099997147391237`.
- `withfb` unresolved failures are lower by `3228089`.
- `withfb` RG rejects are lower by `96871`.
- `withfb` mean runtime is higher by about `7696.45s`.

## Interpretation

This gate confirms that official DFO-LS `withfb/fb_norefine` substantially improves solver-quality counters: unresolved failures and RG rejects both decrease relative to `nofb`.

The observable trend is more cautious. The Re Zmean is larger for `withfb` (`1.973`) than for `nofb` (`1.047`), while Im Zmean is essentially the same. This should be discussed before treating this scale as the final production endpoint.
