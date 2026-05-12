# Official DFO-LS Provisional Production-Comparison Readback

Updated: 2026-05-12 JST

Scope: readback of the provisional production-comparison artifact generated in
`/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` for the
official DFO-LS backend line. This is real official-DFO-LS production-comparison
evidence. It is not the final publication regeneration gate.

Important boundary: this artifact was generated under production-comparison
commit `c0e40218e6abe2706f4b9b4c66067dbcea74eeff`. It is not a rerun after the
latest modernization HEAD, and it does not mean modernization has reached the
stage where production can be updated and formally redone. That gate remains
blocked by F3/CV-009, F4/CV-010, CV-001/CV-002, and final schema/wrapper/naming
decisions unless those limits are explicitly accepted.

## Provenance

- Campaign: `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`.
- Pinned production-comparison commit: `c0e40218e6abe2706f4b9b4c66067dbcea74eeff`.
- Readback time: 2026-05-12 13:33 JST after PBS jobs were no longer active.
- Remote report:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison/output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb/REPORT.md`.
- Summary table:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison/output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb/combined_summary_table.csv`.
- Backend/preset: `QN_SOLVER_BACKEND=official_dfols`,
  `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Physical point: `t=0.35,L=2,nstep=20`.
- Gate: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Scale: `256 seeds x 200000 cycles` per method.
- Canonical method mapping: `no_fb -> nofb`, `fb_norefine -> withfb`.

## Aggregate Readback

| method | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | Zmean Re<O> | Zmean Im<O> | unresolved failures | reverse-gate rejects | mean runtime s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nofb | 256 | 0.671875 | 0.97265625 | 0.7421875 | 0.94921875 | 0.0025128804602197745 | -0.0008980638575030018 | 1.0465518987029727 | -0.6679884160043988 | 3846795 | 607777 | 14588.093013816413 |
| withfb | 256 | 0.6796875 | 0.9453125 | 0.71875 | 0.96484375 | 0.004020561055771586 | -0.0008372428375762778 | 1.9729537196453188 | -0.6779881307435225 | 618706 | 510906 | 22284.544315070314 |

Direct comparison `withfb - nofb`:

- Mean shift: Re `+0.00150768`, Im `+6.0821e-05`.
- Zmean shift: Re `+0.926402`, Im `-0.00999971`.
- Unresolved failures: `-3228089`.
- Reverse-gate rejects: `-96871`.
- Mean runtime: `+7696.45` seconds.
- Per-seed rows: `nofb=256`, `withfb=256`.

## Interpretation

This production-comparison artifact has been run and merged. It should no
longer be described as "not submitted" or "still waiting on active PBS jobs".
It also should not be described as "current modernization is ready for production
update and rerun".

At the official DFO-LS 256seed/200k scale, `withfb` remains the more robust
official-line production route by a large unresolved-failure margin, while
costing additional runtime. The physical mean/Zmean shifts are not a final
publication claim; they are provisional production-comparison evidence under
the current method/schema/counter conventions.

Final publication regeneration remains a later gate because CV-001/CV-002,
CV-009, CV-010, and final wrapper/schema/naming decisions still control what
counts as the frozen production artifact.
