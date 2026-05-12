# TLTM Production Comparison State Brief

Updated: 2026-05-12 JST

## Current Position

- `tltm_production_comparison` is the canonical workspace for TLTM `nofb` vs `withfb` production-comparison work.
- Legacy name: `stage3_4`. Treat old `stage3_4` paths, configs, and output roots as historical/provisional artifacts, not the long-term workspace identity.
- This workstream is logically separate from `fortran_modernization`. Modernization supplies the official-DFO-LS code commit; production-comparison runs execute from the synchronized production worktree.
- Current production-comparison status is provisional-discussion, not final publication data. It may be used for collaborator discussion, workflow rehearsal, queue scaling, and physical trend checks; final datasets should be regenerated after modernization converges.
- Existing long `runbooks/STATUS.md` contains historical production and validation details. Read `runbooks/SOFT_DECOUPLING_AND_PROVISIONAL_CONTRACT.md` for the current boundary.
- Cleanup of legacy production-comparison outputs/logs is allowed only after dataset/job/worktree registry refresh and summary/archive decisions.
- Legacy Stage1 to Stage3_4 raw outputs/logs were cleared on 2026-05-10 after preserving key summaries. See `runbooks/LEGACY_STAGE_OUTPUT_CLEANUP_20260510.md`.
- Obsolete ODEX validation raw data was also cleared because accepted M6 modernization reference datasets now own the modernization baseline.
- Accepted M6 reference datasets are also production-calibration aliases for the same `t=0.35,L=2,nstep=20` `nofb`/`withfb` point. Read `runbooks/M6_REFERENCE_AS_PRODUCTION_CALIBRATION_PLAN.md` before choosing the next seed/cycle scale.
- On 2026-05-11, the non-official legacy production output `gate_20260511_128seed_200k_p28_rg_nofb_fbnorefine` was archived out of active `provisional/` to avoid confusion with the current official DFO-LS comparison line. Its output/logs now live under `output/production_comparison/archive/non_official_legacy_20260511/` and `output/logs/production_comparison/archive/non_official_legacy_20260511/`.
- On 2026-05-12, `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` had no active PBS jobs remaining and had a merged `REPORT.md` plus `combined_summary_table.csv`. Treat it as completed provisional production-comparison evidence, not final publication data.

## Important Correction

- `runbooks/QUEUE_OPTIMIZATION.md` is superseded for current queue decisions.
- Use the shared cluster02 scheduler policy instead of the old Stage3_4 queue playbook.

## Decoupled Worktree Model

- Production comparison execution target: `tltm_production_comparison_provisional`.
- Production comparison execution branch: `codex/tltm-production-comparison-official-dfols`.
- Production comparison execution worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Official DFO-LS source branch to sync from: `codex/fortran-modernization`.
- Current redo execution must happen from the production-comparison worktree after it is synced to the chosen official-DFO-LS commit.
- Modernization remote target: `fortran_modernization`.
- Modernization branch: `codex/fortran-modernization`.
- Modernization remote worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.

## Next Action

Current live campaign:

1. `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` completed with report available.
2. Report target: `output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb/REPORT.md`.
3. Readback: `nofb` Zmean Re `1.0466`, Zmean Im `-0.6680`; `withfb` Zmean Re `1.9730`, Zmean Im `-0.6780`.
4. Solver counters favor `withfb`: unresolved failures `618706` vs `3846795`; RG rejects `510906` vs `607777`.
5. Interpretation: `withfb` strongly improves failure counters but has larger positive Re Zmean than `nofb`, so discuss whether to extend statistics or diagnose residual systematic shift before calling this final production.
6. Before any new production submission, confirm no active pinned jobs depend on `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
