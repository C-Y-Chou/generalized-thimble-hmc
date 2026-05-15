# TLTM Production Comparison State Brief

Updated: 2026-05-14 JST

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
- On 2026-05-12, modernization-head pre-redo campaign `official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb` completed from production worktree commit `a22de1c19633793cf9c3ff7037b7cbc399e1b568` with solver assist off. Jobs `14951`, `14952`, and `14953` all exited `0`; `REPORT.md` and `combined_summary_table.csv` are present.
- On 2026-05-12, modernization-head pre-redo scaling campaign `official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb` completed from the same production worktree commit with solver assist off. Jobs `14954`-`14963` all exited `0`; `REPORT.md` and `combined_summary_table.csv` are present.
- On 2026-05-12, DFO-LS assist-off tuning Phase A/B job `14984.anode01` completed Stage3 capture and all 100 coarse replay CSVs. PBS exit was `1` only because the first aggregate parser did not handle blank `dfols_nf` error rows; robust aggregate recovery wrote `REPORT.md` and `coarse_summary.csv`.
- Phase A/B selected `rho050_m500` as the best coarse candidate: `45/50` residual successes versus baseline `stable_gate77` `40/50`, with no embedded-converged regressions and `4` error rows versus baseline `3`.
- On 2026-05-12, Phase C embedded Stage3 holdout job `15005.anode01` completed for candidate `rho050_m500`.
- On 2026-05-13, Phase D 32seed/50k confirmation jobs `15006`-`15014` completed with `Exit_status=0`.  Under the corrected hard gate, the candidate is improved but not sufficient: assist-off tuned failures are `33872`, while same-scale assist-on `fb_norefine` is `19579`.
- On 2026-05-13, Phase E focused full replay job `15095.anode01` completed on `C12`.  Best candidate `rho050_m1000` reached `1726/1994` replay successes, only `+20` over `rho050_m500`; parameter-only assist-off DFO-LS tuning is not plausibly enough to reach assist-on failure parity.
- On 2026-05-13, after the user synced the production worktree to commit `6f98b5bfce60678293c163764e1cefe8307736ba`, remote production outputs/logs were cleaned for the next rerun.  The remote `output` tree now only has empty containers: `output/production_comparison`, `output/tests`, `output/logs/production_comparison`, and `output/logs/dfols_assist_off_tuning`; disk usage was `24K`.
- On 2026-05-13, the formalized assist bridge 32seed/50k gate completed from commit `6f98b5bfce60678293c163764e1cefe8307736ba` on `C8`.  Jobs `15097`-`15106` all exited `0`.  Readback is negative for the current formalized policy: `fb_norefine` resolved to `qn_navigation` and has nonzero QN assist counters, but failures are `67159`, still far above assist-on `19579` and assist-off tuned `33872`.  See `runbooks/FORMALIZED_ASSIST_BRIDGE_32SEED_50K_READBACK_20260513.md`.
- On 2026-05-14, the assist/root-cause diagnostic branch was closed by user decision.  Do not continue the ODEX, NT-assist, parameter-tuning, or `npt5` diagnostic scale-up tree as active production work.  Current production-comparison state is hold-for-modernization-fix: after the fixed modernization commit is selected, sync this tree and regenerate production from a clean namespace.  See `runbooks/TREE_CONVERGENCE_AFTER_ASSIST_RESOLUTION_20260514.md`.
- On 2026-05-14, the RNG-v2 plus method-level `all_navigation_diagnostic` npt5_r0055 32seed/50k diagnostic completed from commit `ae777294814955f7f7935fc386a6172bcd30651f`.  It was negative as a recovery path: `withfb` failures `25881`, mean Re `0.03420261820536729`, still above the old assist-on failure reference `19579`.  This result stays diagnostic only; the modernization line now uses assist-off as the starting baseline and keeps solver assist on the deletion schedule.  See `runbooks/QN_ASSIST_NPT5_R0055_SCALE32_RNGV2_ALLNAV_READBACK_20260514.md`.

## Important Correction

- `runbooks/QUEUE_OPTIMIZATION.md` is superseded for current queue decisions.
- Use the shared cluster02 scheduler policy instead of the old Stage3_4 queue playbook.

## Decoupled Worktree Model

- Production comparison execution target: `tltm_production_comparison`.
- Production comparison execution branch: `codex/tltm-production-comparison-official-dfols`.
- Production comparison execution worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Official DFO-LS source branch to sync from: `codex/fortran-modernization`.
- Current redo execution must happen from the production-comparison worktree after it is synced to the chosen official-DFO-LS commit.
- Modernization remote target: `fortran_modernization`.
- Modernization branch: `codex/fortran-modernization`.
- Modernization remote worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.

## Next Action

Current production-comparison action:

1. Do not submit new production-comparison jobs from the current formalized-assist or diagnostic branches.
2. Wait for the modernization fixed commit.
3. Refresh remote worktree/job state before sync.
4. Fast-forward/sync the production-comparison branch/worktree to the chosen modernization commit.
5. Rebuild and rerun production from a clean post-fix namespace.

Closed diagnostic evidence:

- Formalized assist bridge dataset id: `prodcomp_formalized_assist_bridge_6f98b5b_32seed_50k_20260513`; `fb_norefine` failures `67159`.
- NT+QN assist control dataset id: `qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`; failures `3394` at 10seed/10k.
- ODEX legacy-sequence control dataset id: `odex_legacy_sequence_ntqn_control_20260513_10s10k_v1`; failures `3364` at 10seed/10k.
- RNG-v2 all-navigation diagnostic dataset id: `qn_assist_npt5_r0055_rngv2_allnav_32s50k_20260514`; `withfb` failures `25881` at 32seed/50k.
- QN+assist preset/refinement matrix and `npt5` scale-up remain diagnostic history, not the next production path.

Current assist-off tuning campaign:

1. Campaign plan: `runbooks/DFOLS_ASSIST_OFF_TUNING_CAMPAIGN_20260512.md`.
2. Completed Phase A/B dataset id: `dfols_assist_off_tuning_phaseAB_20260512`.
3. Completed Phase A/B output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseAB_10s10k_c200s10_m5`.
4. Coarse result: `rho050_m500` (`npt=4,maxfun=500,noise=true,rhobeg=0.050,rhoend=1e-16,model.abs_tol=1e-30,model.rel_tol=0`) had `45/50` replay successes, `0` embedded-converged regressions, `5` hard successes, and nf mean/p95/max `85.5/262.75/500`.
5. Baseline replay: `stable_gate77` had `40/50` successes, `0` embedded-converged regressions, `0` hard successes, and nf mean/p95/max `91.2128/250/250`.
6. Phase C job `15005.anode01` completed with `Exit_status=0`.
7. Phase C output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseC_rho050_m500_10s10k`.
8. Phase C readback: `no_fb` control unchanged; `fb_norefine` unresolved failures `4004 -> 2171`, reverse-gate rejects `909 -> 1550`, mean runtime `+22.35s`, Zmean Re `1.2826 -> -0.5002`, Zmean Im `2.5434 -> 3.9564`.
9. Phase C decision: promote to scale confirmation because embedded solver-local improvement is real but the observable shift needs larger-scale adjudication.
10. Completed Phase D dataset id: `dfols_assist_off_tuning_phaseD_rho050_m500_32s50k_20260512`.
11. Completed Phase D output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseD_rho050_m500_32s50k`.
12. Phase D jobs `15006`-`15014` all exited `0`; rows are `32/32` for both methods.
13. Phase D readback: `no_fb` is an exact solver/observable control match; `fb_norefine` unresolved failures improve `67061 -> 33872`, and mean Re/Im improves `0.0607926/0.0112710 -> 0.0434491/0.00824623`.
14. Corrected verdict: reverse-gate rejects and P68/P95 are diagnostics, not blockers.  The no-assist problem is not solved unless tuned assist-off failures reach the assist-on scale or lower while `mean_Ohat_re` and `mean_Ohat_im` do not regress.
15. Phase E completed: `15095.anode01`, output root `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260513_a22de1c_phaseE_fullreplay_focus`.  Clear negative for continuing parameter-only assist-off tuning; next work is assist/proposal semantics and audit.
16. Remote output cleanup completed on 2026-05-13 before rerun preparation.  Historical readbacks remain in runbooks/state, but raw output/log roots under production comparison and DFO-LS assist-off tuning were removed from `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison/output`.
