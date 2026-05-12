# TLTM Production Comparison State Brief

Updated: 2026-05-12 JST

## Boundary Status

- `PCB-001` is resolved as of 2026-05-12 JST.
- `src/apps/probe_hmc_volume.f90` was moved out of the canonical modernization source root to `codex/workspaces/tltm_production_comparison/diagnostics/probe_hmc_volume.f90`.
- Production-comparison diagnostics may continue from their own boundary, but must not be promoted into modernization source/build roots without a separate reviewed task.
- `PCB-002` is resolved as of 2026-05-12 JST: exact accepted-QN replay, local metric-volume replay, reverse replay, window/block diagnostics, and counter-correlation readback completed before the modernization-head pre-redo gate.

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
- On 2026-05-12, `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` had no active PBS jobs remaining and had a merged `REPORT.md` plus `combined_summary_table.csv`. It was generated under production-comparison commit `c0e4021`; treat it as completed provisional production-comparison evidence, not a rerun after the latest modernization HEAD and not final publication data.
- On 2026-05-12, the active official DFO-LS provisional outputs were frozen as pre-redo / old-code evidence. Read `runbooks/OUTPUT_NAMESPACE_FREEZE_20260512.md` and `state/OUTPUT_INVENTORY_20260512.tsv` before creating any new production-comparison output.
- New modernization-head redo outputs must not reuse or extend the old `output/production_comparison/provisional/official_dfols_*` roots. Use `output/production_comparison/pre_redo/<campaign>` and mirror logs under `output/logs/production_comparison/pre_redo/<campaign>`.
- On 2026-05-12, modernization-head pre-redo campaign `official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb` was submitted from production worktree commit `a22de1c19633793cf9c3ff7037b7cbc399e1b568` with solver assist off. At the 18:32 JST refresh, jobs `14951` and `14952` were running and merge job `14953` was held.

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

1. Production prework is complete for this step: `PCB-001` and `PCB-002` are resolved.
2. Submitted campaign: `official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
3. Dataset id: `prodcomp_preredo_a22de1c_10seed_10k_20260512`.
4. Config: `docs/production_comparison_official_dfols_preredo_10seed_10k_nofb_withfb.json`.
5. Output root: `output/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
6. Log root: `output/logs/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
7. Production worktree commit: `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.
8. Assist policy: solver assist default off, `INTODE_SOLVER_ASSIST_ENABLED=0`.
9. Jobs: preflight `14950` completed before the 18:32 JST refresh; `14951` and `14952` are running; merge `14953` is held.
10. The production worktree has active pinned jobs and `safe_to_fast_forward=no`; do not sync or fast-forward it until the pre-redo readback finishes.
11. Next action: monitor jobs `14951/14952/14953`, merge/read back the report, then decide the next production scale-up from the pre_redo result.
