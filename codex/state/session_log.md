# Session Log

Use this file to append per-session notes.

## Template
- Date:
- Goal:
- Config:
- Seeds:
- Env vars:
- Output dir:
- Logs dir:
- Key findings:
- Next action:

## 2026-04-30 14:31 JST
- Goal: run no_fb_ref_reverse_gate 1024-seed with unified nofb/withfb->RG->Metropolis flow; accelerate queue throughput.
- Code change: /home/cychou/TLTM/src/sampler/hmc_integrator_core.f90
  - reverse-gate condition changed from quasi_solved_ok&&RG_enabled to RG_enabled (unified gate).
- Rebuild: run_tltm_stage2 and evaluate_expectations rebuilt with compiler/mpi/mkl modules.
- Cleanup: stage3_4 pruned to keep only 4 legacy groups + no_fb_ref_reverse_gate group and related PBS.
- Current active jobs: 13438[], 13445[], 13449[], 13453[], 13455[]; merge hold job 13456.
- Queue optimization actions: moved tail from C16 to C17; added C17-LONG; added repack16 split to consume fragmented resources.

## 2026-04-30 14:39:37 JST
- Governance update: added runbooks/STATUS.md and state/job_tracker.tsv for ordered live tracking.

## $(date "+%Y-%m-%d %H:%M:%S %Z")
- Context policy refinement: added compression-resistant context stack (L0-L3) for robust handoff across truncated chats.

## 2026-04-30 14:57:10 JST
- Queue optimization pass: replaced blocked C17-LONG odd repack array (13455[]) with C17 odd repack array (13461[]).
- Merge dependency refreshed to 13462 after replacing 13456.
- Observed queue reason for new odd array: temporary C17 ncpus insufficiency; expected to start as C17 slots free.

## 2026-04-30 15:15 JST
- Queue strategy formalized in `/home/cychou/TLTM/codex/runbooks/QUEUE_OPTIMIZATION_STAGE3_4.md`.
- Re-optimized wave2 placement to reduce C17 contention:
  - Kept running chunk_07 on `13465[0]` (C17).
  - Cancelled queued `13465[1-16]` to avoid C17 starvation wait.
  - Submitted `13472[]` on C12 for chunk_08..15.
  - Submitted `13473[]` on C12-LONG for chunk_16..23.
- Merge dependency refreshed to `13474` with:
  - `afterany:13438[]:13445[]:13449[]:13465[]:13472[]:13473[]`
- Observed scheduler comment for queued wave2 jobs:
  - `Not Running: Insufficient amount of resource: Qlist`
- Governance update:
  - Status and queue runbook now include explicit monitoring times and escalation threshold.

## 2026-04-30 21:58 JST
- Global queue optimization executed after full queue audit.
- Verified by 32-core probes:
  - `C17` immediate run
  - `C17-LONG` immediate run
  - `C12-LONG` remained queued with `Qlist` shortage
- Optimization actions:
  - Cancelled stalled `13472[]` (C12, chunk_08..15).
  - Cancelled `13473[5-7]` (C12-LONG tail, chunk_21..23).
  - Submitted `13500[]` on C17 for chunk_08..15.
  - Submitted `13501[]` on C17-LONG for chunk_21..23.
  - Refreshed merge dependency to `13502` on `afterany:13473[]:13500[]:13501[]`.
- Result: all remaining chunks transitioned from queued to running (global parallel fill achieved).

## 2026-05-01 10:28 JST
- Codex control-plane upgraded to live multi-task management mode.
- Added `tasks/refresh_live_board.sh` to synchronize:
  - `runbooks/LIVE_BOARD.md`
  - `state/job_tracker.tsv`
  - `state/run_manifest_latest.env`
  - per-workspace `state/job_tracker.tsv` + `context/LAST_REFRESH.txt`
- Registered and activated workspaces:
  - `stage3_3_rg_redo`
  - `ngport_rg_single_replica_t03_nstep_grid`
- Updated bootstrap/handoff/workflow/readme to require live-board refresh at session start.

## 2026-05-02 11:15 JST
- Goal: verify post-QN refine entry residual (first loss-function norm) in current p28+RG+refine code path.
- Code instrumentation: `/home/cychou/TLTM/src/sampler/hmc_constraints.f90`
  - Added env-gated log `QN_POST_NEWTON_REFINE_LOG_FIRST` printing `[POST_QN_REFINE_INIT_NORM]` at rescue/newton-seeded entry.
- Build note: parallel `make -j` on this build tree produced transient `.mod` read/EOF races; successful rebuild done with serial `make`.
- Test run A (fb smoke, 500 cycles):
  - Config: `docs/stage_3_4_t035_smoke_post_newton_refine_500.json`
  - Env: `QN_POST_NEWTON_REFINE_ENABLED=1`, `QN_POST_NEWTON_REFINE_MAX_ITER=20`, `QN_POST_NEWTON_REFINE_LOG_FIRST=20`
  - Log: `/home/cychou/TLTM/output/logs/tltm_smoke_postqn_initnorm500_fb_seed20260421.log`
- Test run B (same smoke + production p28+RG env):
  - Added envs: `QN_S1_PROBE_MAX_ITER=28`, `QN_S1_NEAR_RESCUE_ENABLED=0`, `QN_S1_NONNEAR_RESCUE_ENABLED=0`, `QN_QUASI_GLOBAL_FALLBACK_ENABLED=0`, `QN_REVERSE_GATE_ENABLED=1`, `QN_REVERSE_GATE_TOL=1e-8`
  - Log: `/home/cychou/TLTM/output/logs/tltm_smoke_postqn_initnorm500_rgenv_fb_seed20260421.log`
- Key finding:
  - first entry norm = `7.1926421418326207E-14` with tol=`1.0E-13` (ratio `0.719`), seed_is_zero=F.
  - In first 20 entries, max init norm observed `1.4079175166687319E-12` (ratio `14.08`), showing refine is not always starting below tol.

## 2026-05-03 10:17:12 JST
- New stage3_4 launch prepared with separated tolerances + force-best-proposal path.
- Code updates deployed:
  - /home/cychou/TLTM/src/sampler/hmc_integrator_core.f90: added `QN_QUASI_TOL_OVERRIDE` (separate QN tol from NT/constraint tol).
  - /home/cychou/TLTM/src/sampler/quasi_newton_solver.f90: added `QN_FORCE_BEST_PROPOSAL_ENABLED` + `QN_FORCE_BEST_PROPOSAL_TOL`.
  - /home/cychou/TLTM/scripts/run_stage3_3_multiseed.py: added `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE` to write isolated `constraint_tol/cttol`.
- Queue probe (short queue, 32-core shape) results:
  - immediate start: C8, C12, C16, C17
  - sustained concurrency observed after full launch: C16~8, C17~8, C8~4, C12~1 (dynamic).
- Submitted main arrays:
  - 13673[] (C8, chunks 0-7)
  - 13674[] (C12, chunks 8-15)
  - 13675[] (C16, chunks 16-23)
  - 13676[] (C17, chunks 24-31)
- Rebalance step:
  - cancelled delayed queued subjobs: 13673[5-7], 13674[2-7]
  - submitted replacement chunk jobs on C16/C17: 13690-13698 for chunks 5,6,7,10,11,12,13,14,15
- Rebalance finalized: all 32 chunks now active concurrently (running state) via C8/C12/C16/C17 + rebalance jobs 13690-13699.
- Final rebalance correction: chunk_04 was inadvertently cancelled during queue drain; resubmitted as 13700 (C16).
- Current status: 32/32 target chunks are running concurrently.

## 2026-05-03 10:29 JST
- User-requested fix applied: when QN does not converge, force-best proposal may enter RG/Metropolis only if best_res < force_tol (strict <, not <=).
- Source update:
  - /home/cychou/TLTM/src/sampler/quasi_newton_solver.f90
    - changed gate at route_code=91 from tolerance helper (<=) to strict check:
      - ieee_is_finite(best_res_global) .and. best_res_global < best_accept_tol
- PBS env harmonized for this run:
  - QN_FORCE_BEST_PROPOSAL_TOL=1e-14 (updated in all stage3_4 withfb_rg_nt1e13_qn1e14_norefine scripts, including rebalance generic script).
- Rebuilt binaries on remote:
  - /home/cychou/TLTM/bin/run_tltm_stage2
  - /home/cychou/TLTM/bin/evaluate_expectations
- Prevented mixed results with old threshold:
  - removed stale outputs/logs under
    - /home/cychou/TLTM/output/tests/stage3_4/reverse_gate_p28_withfb_rg_nt1e13_qn1e14_norefine_1024seed_200k_t035
    - /home/cychou/TLTM/output/logs/stage3_4_reverse_gate_p28_withfb_rg_nt1e13_qn1e14_norefine_1024seed_200k_t035
- Requeue strategy (fastest completion priority):
  - submitted 32 one-off chunk jobs via run_stage3_4_t035_reverse_gate_p28_withfb_rg_nt1e13_qn1e14_norefine_rebalance_chunk_generic.pbs
  - initial placement: chunks 0-15 on C16 (13701-13716), chunks 16-31 on C17 (13717-13732)
  - queue rebalance: C17 queued chunk29-31 (13730-13732) moved to C8 as 13733-13735
- Verification:
  - all target chunks 0..31 present and currently R.
  - active run set: 13701-13729, 13733-13735.

## 2026-05-04 JST
- Ran post_refine_fail_replay_capture 10-seed x 1k replay batch with NT/post-refine tol and QN tol updated per user request.
- Run label/output:
  - output/tests/stage3_4/post_refine_fail_replay_capture/seed_batch10_1k_nt10e13_qn10e14
  - output/logs/stage3_4_post_refine_fail_replay_capture/seed_batch10_1k_nt10e13_qn10e14
- Environment used:
  - TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=10e-13
  - QN_QUASI_TOL_OVERRIDE=10e-14
  - QN_POST_NEWTON_REFINE_ENABLED=1
  - QN_POST_NEWTON_REFINE_MAX_ITER=20
  - QN_REVERSE_GATE_ENABLED=1
  - QN_REVERSE_GATE_TOL=1e-8
  - QN_S1_NEAR_RESCUE_ENABLED=0
  - QN_S1_NONNEAR_RESCUE_ENABLED=0
  - QN_QUASI_GLOBAL_FALLBACK_ENABLED=0
- Compared vs baseline seed_batch10_1k:
  - P68/P95 unchanged.
  - mean/std/Zmean nearly identical (float-level differences only).
  - unresolved failures: 300 -> 292.
  - reverse-gate rejects: 574 -> 582.
  - post-refine success/fail: 585/152 -> 593/144.
  - mean runtime_total increased: 105.489173 -> 123.2075744.
## 2026-05-04 JST (qsub 20-core rerun)
- Cleaned failed rerun artifacts and logs under:
  - output/tests/stage3_4/post_refine_fail_replay_capture/*(rerun|v2clean|startup_smoke)*
  - output/logs/stage3_4_post_refine_fail_replay_capture/*(rerun|v2clean|startup_smoke)*
- Killed leftover local multiseed processes and cleared user queue jobs before resubmit.
- Submitted direct qsub 20-core jobs:
  - 13828.anode01: run_stage3_4_postrefine_seedbatch10_nt1e13_qn1e13_qsub20.pbs
  - 13829.anode01: run_stage3_4_postrefine_seedbatch10_nt1e13_qn1e14_qsub20.pbs
- Both currently queued on C8.

## 2026-05-06 02:19:58 JST
- Added stage3_4 replay-capture 10k/10seed config:
  - /home/cychou/TLTM/docs/stage_3_4_t035_paired_10k_10seed.json
- Updated multiseed runner to prevent refine override for no-refine method:
  - /home/cychou/TLTM/scripts/run_stage3_3_multiseed.py
  - added method `fb_norefine` with env override `QN_POST_NEWTON_REFINE_ENABLED=0`.
- Submitted 4 production jobs (all with RG, cttol=1e-13, 10k cycles, 10 seeds):
  - 13948.anode01 | C8  | nofb
  - 13949.anode01 | C12 | withfb p28 norefine (QN tol 1e-13)
  - 13950.anode01 | C16 | withfb p28 refine (QN tol 1e-13)
  - 13951.anode01 | C17 | withfb p28 refine (QN tol 1e-14)
- Queue strategy: one queue per group (C8/C12/C16/C17) to maximize immediate parallel start and avoid queue-local contention.
- Current state at submit check: all four jobs are R.

## 2026-05-06 02:22:18 JST
- Added 5th replay-capture group per user request:
  - withfb p28 norefine QN 1e-14
- Queue/PBS re-optimization notes:
  - C24 submission rejected because queue requires large nodect jobs (resources_min.nodect=17).
  - C36 similarly requires resources_min.nodect=25.
  - switched 5th group to C8-LONG single-node lane for immediate start.
- Submitted:
  - 13954.anode01 | C8-LONG | s34r10k_fbnr14 | R
- Active five-group set now:
  - 13948, 13949, 13950, 13951, 13954 (all R).

## 2026-05-06 09:36:29 JST
- Investigated missing report.md for 5-group replay capture.
- Root cause confirmed via qstat -fx:
  - nofb job 13948 Exit_status=-29 (walltime hit at 04:00:37)
  - withfb p28 norefine qn1e14 job 13954 Exit_status=-29 (walltime hit at 04:00:17)
- Action:
  - increased walltime from 04:00:00 to 08:00:00 for two affected PBS scripts:
    - /home/cychou/TLTM/run_stage3_4_replay_10k_10seed_nofb_rg_ct1e13.pbs
    - /home/cychou/TLTM/run_stage3_4_replay_10k_10seed_withfb_p28_norefine_rg_ct1e13_qn1e14.pbs
  - resubmitted:
    - 13961.anode01 (C8) s34r10k_nofb
    - 13962.anode01 (C8-LONG) s34r10k_fbnr14
- Current: both reruns are R.

## 2026-05-07 JST
- Completed git bootstrap on `/home/cychou/TLTM`.
- Added `.gitignore` with heavy/runtime artifact exclusions (`output/`, `build/`, `bin/`, PBS runtime dumps).
- Created baseline commit: `0057dec`.
- Established local bare origin: `/home/cychou/git/TLTM.git`.
- Added runbook: `codex/runbooks/GIT_WORKFLOW.md`.

## 2026-05-07 JST
- User requested stage3_4 reset to 10k baseline only.
- Cleaned `/home/cychou/TLTM/output/tests/stage3_4` and kept only:
  - `post_refine_fail_replay_capture/*10k*` (6 groups)
- Cleaned `/home/cychou/TLTM/output/logs` stage3_4 groups and kept only:
  - `stage3_4_post_refine_fail_replay_capture/*10k*` (6 groups)
- Result footprint:
  - tests/stage3_4: ~173M
  - logs/stage3_4_post_refine_fail_replay_capture: ~4.4M

## 2026-05-07 JST
- Built source-audit bootstrap layer to reduce dependence on compressed chat context:
  - `codex/runbooks/SOURCE_AUDIT_BOOTSTRAP.md`
  - `codex/knowledge/CODEBASE_SCAN_MANIFEST.md`
  - `codex/knowledge/FULL_PROGRAM_MAP_CHECK.md`
- Updated `codex/context/CORE.md`, `codex/context/HANDOFF_MIN.txt`, and `codex/README.md` so new conversations read the audit docs before source-level work.
- Verified remote `/home/cychou/TLTM` is reachable and remote/local source-code file lists match for `src/`, `scripts/`, and `tests` over `*.f90`, `*.inc`, `*.py`, and `*.sh`.
- Scan baseline:
  - code files: 83
  - code lines: 36677
  - deep-read path: Stage3 driver/config/Stage2/HMC/RATTLE/Newton/QN/post-refine/RG/flow/model/evaluation.

## 2026-05-07 JST
- Created `codex/workspaces/kernel_correctness_audit` for correctness-condition probes independent of stage3_4 live ops.
- Before record for Probe 1 added in workspace session log.
- Probe 1 scope: deterministic/single-valued repeatability only; volume and reversibility are explicitly out of scope for this first probe.

## 2026-05-07 JST
- Ran Kernel Correctness Audit Probe 1 via PBS job `14115.anode01`.
- Result: PASS for deterministic/single-valued repeatability on:
  - one short full-run repeatability probe (`seed=20260421`, 500 cycles, withfb/RG/p28/post-refine).
  - one captured-case replay repeatability probe from existing 10k `withfb_p28_refine_rg_ct1e13_qn1e13`.
- Output report:
  - `output/tests/kernel_correctness_audit/single_valued_probe_20260507/single_valued_probe_report.md`
- Caveat:
  - PBS job ended with `Exit_status=1` after producing planned outputs; report was generated afterward by file-only post-processing.
  - This probe does not prove reversibility or volume preservation.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 2.
- Probe 2 target: captured-case local reversibility condition `R(F(y)) = y`.
- Before record added in:
  - `codex/workspaces/kernel_correctness_audit/state/session_log.md`
- PBS script:
  - `codex/workspaces/kernel_correctness_audit/tasks/pbs/reversibility_probe_20260507.pbs`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 2a completed:
  - PBS job: `14116.anode01`
  - Report: `output/tests/kernel_correctness_audit/reversibility_probe_20260507/reversibility_probe_report.md`
  - Status in report: `FAIL`
- Interpretation:
  - The captured-case replay source is not a valid successful-proposal reversibility audit.
  - Rows came from `constraint_solver_fail_*` difficult/failure captures, so `rev_ok=0` with `NaN` reverse metrics does not prove accepted proposal non-reversibility.
- Next action:
  - Probe 2b will use the main HMC successful-proposal `[REVCHK]` hook with `HMC_REVERSIBILITY_PROBE_LIMIT=100` and `HMC_REVERSIBILITY_PROBE_FALLBACK_ONLY=0`.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 2b:
  - PBS job: `14117.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/successful_reversibility_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/successful_reversibility_probe_20260507/successful_reversibility_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 2b completed:
  - PBS job: `14117.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/successful_reversibility_probe_20260507/successful_reversibility_probe_report.md`
  - Status in report: `PASS`
- Summary:
  - `[REVCHK]` records: 100
  - fallback_used records: 4
  - nonfallback records: 96
  - bad records: 0
  - max `dx_inf`: `9.89786e-12`
  - max `dz_inf`: `1.028899e-11`
  - max `dj_inf`: `5.921639e-12`
  - max `dp_inf`: `9.163892e-12`
- Next correctness audit:
  - Probe 3 local volume preservation, `log|det dF/dy| = 0`.

## 2026-05-07 JST
- Reordered next correctness audit after user asked whether `REVCHK` covers RG rejects.
- Finding:
  - `REVCHK` covers successful proposals after forward RG pass, and its reverse leg also runs RG.
  - It does not cover forward RG-reject proposals because they abort before `[REVCHK]`.
- Prepared Probe 2c:
  - target: RG-reject identity handling in full Stage2/Metropolis path.
  - added env-gated Stage2 CSV diagnostic `TLTM_RG_REJECT_AUDIT_FILE`.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/rg_reject_identity_probe_20260507.pbs`
  - planned run: one 10k-cycle `withfb` p28 RG seed with production `QN_REVERSE_GATE_TOL=1e-8`.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 2c:
  - PBS job: `14119.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/rg_reject_identity_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/rg_reject_identity_probe_20260507/rg_reject_identity_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 2c completed:
  - PBS job: `14119.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/rg_reject_identity_probe_20260507/rg_reject_identity_probe_report.md`
  - Status in report: `PASS`
- Summary:
  - audit CSV rows: 372
  - proposal_failed rows: 372
  - RG reject rows: 188
  - sum CSV `rg_reject_delta`: 188
  - Stage2 summary `reverse_gate_route_reject total`: 188
  - bad rows: 0
  - max RG-reject slot `dx/dz/dj`: all `0.0`
- Interpretation:
  - Forward RG-reject updates are identity rejects in the full Stage2/Metropolis path for this sampled 10k withfb/RG/p28/post-refine seed.
  - Next correctness audit returns to Probe 3 local volume preservation, `log|det dF/dy| = 0`.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 3:
  - target: local phase-space volume preservation for successful proposal map.
  - added standalone diagnostic app: `src/apps/probe_hmc_volume.f90`
  - added build target: `bin/probe_hmc_volume`
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/volume_probe_20260507.pbs`
- Coordinate design:
  - 1D local chart `(q, c)` with `q=x(2)` and tangent momentum `p = J(q)c`.
  - report raw `log|det d(q',c')/d(q,c)|`.
  - primary diagnostic is metric-corrected `log|det| + 2log|J_out| - 2log|J_in|`.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 3:
  - PBS job: `14121.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/volume_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/volume_probe_20260507/volume_probe_report.md`

## 2026-05-07 JST
- Probe 3 job `14121.anode01` failed during build before scientific execution.
- Cause:
  - Intel `ifx` rejected nested internal cleanup procedures in `src/apps/probe_hmc_volume.f90`.
- Fix prepared:
  - rewrote the cleanup logic without nested `contains` blocks.
- Next:
  - resubmit Probe 3 after syncing the fixed app.

## 2026-05-07 JST
- Resubmitted Kernel Correctness Audit Probe 3:
  - PBS job: `14122.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/volume_probe_20260507.pbs`

## 2026-05-07 JST
- Probe 3 job `14122.anode01` built and ran, but report status was `FAIL`.
- Key observation:
  - `eps=1e-4` had one row at metric-corrected log-volume `7.266e-4`.
  - smaller eps values looked convergent and acceptable: `3e-5` max `6.542e-5`, `1e-5` max `7.314e-6`.
- Interpretation:
  - Treat the first failure as finite-difference truncation from too-large `eps`, not a volume conclusion.
- Adjusted Probe 3:
  - eps grid changed to `3e-5`, `1e-5`, `3e-6`.
  - pass/fail remains based on metric-corrected log-volume tolerance `1e-4`.

## 2026-05-07 JST
- Resubmitted adjusted Probe 3:
  - PBS job: `14123.anode01`
  - Queue: `C8`
  - eps grid: `3e-5`, `1e-5`, `3e-6`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 3 completed:
  - PBS job: `14123.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/volume_probe_20260507/volume_probe_report.md`
  - Status in report: `PASS`
- Summary:
  - eps `3e-5`: 16 stable rows, 2 QN-used stable rows, max metric-corrected log-volume `6.542e-5`.
  - eps `1e-5`: 16 stable rows, 2 QN-used stable rows, max metric-corrected log-volume `7.314e-6`.
  - eps `3e-6`: 16 stable rows, 2 QN-used stable rows, max metric-corrected log-volume `6.683e-7`.
- Interpretation:
  - sampled branch-stable successful proposal points pass the local metric-corrected volume check.
  - raw `(q,c)` determinant is not expected to be 1 and was about `exp(0.997)` in log scale before metric correction.
  - next risk area is not local smooth-map volume at sampled points, but branch coverage and branch-measure symmetry.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 4a:
  - target: fallback/QN branch coverage expansion for successful-proposal reversibility.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/fallback_only_reversibility_probe_20260507.pbs`
  - settings: withfb p28 RG, `cttol=1e-13`, `QN tol=1e-13`, post-refine enabled.
  - `HMC_REVERSIBILITY_PROBE_FALLBACK_ONLY=1`, `HMC_REVERSIBILITY_PROBE_LIMIT=50`.
  - planned run: one 2500-cycle seed derived from the Stage3_4 5000-cycle config.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 4a:
  - PBS job: `14124.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/fallback_only_reversibility_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/fallback_only_reversibility_probe_20260507/fallback_only_reversibility_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 4a completed:
  - PBS job: `14124.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/fallback_only_reversibility_probe_20260507/fallback_only_reversibility_probe_report.md`
  - Status in report: `PASS`
- Summary:
  - `[REVCHK]` records: 50
  - fallback_used records: 50
  - nonfallback records: 0
  - bad records: 0
  - max `dx_inf`: `2.599654e-10`
  - max `dz_inf`: `5.165368e-10`
  - max `dj_inf`: `5.309526e-10`
  - max `dp_inf`: `1.090525e-9`
- Next:
  - QN-enriched local volume coverage.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 4b:
  - target: QN/fallback branch-enriched local volume coverage.
  - added `HMC_VOLUME_REQUIRE_QUASI_STABLE` to `src/apps/probe_hmc_volume.f90`.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/qn_enriched_volume_probe_20260507.pbs`
  - eps grid: `3e-5`, `1e-5`, `3e-6`.
  - target: at least 20 QN-used branch-stable rows per eps.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 4b:
  - PBS job: `14125.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/qn_enriched_volume_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/qn_enriched_volume_probe_20260507/qn_enriched_volume_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 4b completed with report status `FAIL`.
- Report: `output/tests/kernel_correctness_audit/qn_enriched_volume_probe_20260507/qn_enriched_volume_probe_report.md`
- Summary:
  - all three eps values had 20 QN-used branch-stable rows.
  - max metric-corrected log-volume was `1.097e+00` at `3e-5`, `1.998e-01` at `1e-5`, and `1.970e-02` at `3e-6`.
  - same bad attempts dominate and errors decrease with eps, so the next step is a smaller-eps ladder before concluding actual volume violation.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 4c:
  - target: smaller-eps ladder for QN-enriched local-volume bad rows.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/qn_volume_eps_ladder_20260507.pbs`
  - eps grid: `1e-6`, `3e-7`, `1e-7`.
  - same QN-used branch-stable filter as Probe 4b.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 4c:
  - PBS job: `14126.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/qn_volume_eps_ladder_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/qn_volume_eps_ladder_20260507/qn_volume_eps_ladder_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 4c completed:
  - PBS job: `14126.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/qn_volume_eps_ladder_20260507/qn_volume_eps_ladder_report.md`
  - Report status: `TREND_FAIL`
- Summary:
  - all three smaller eps values had 20 QN-used branch-stable rows.
  - max metric-corrected log-volume was `2.213e-03` at `1e-6`, `2.011e-04` at `3e-7`, and `3.008e-05` at `1e-7`.
  - dominant bad attempt `200` converged below `1e-4` at `1e-7`, so Probe 4b's larger-eps failure is best treated as finite-difference/high-curvature until contradicted.
- Next:
  - branch-measure symmetry / branch-boundary audit for the piecewise solver path.

## 2026-05-07 JST
- Added Probe 5 design runbook:
  - `codex/workspaces/kernel_correctness_audit/runbooks/PROBE5_BRANCH_SYMMETRY_DESIGN.md`
- Main recommendation:
  - run strong branch-stability census first, then forward/reverse route signature audit.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 5a:
  - target: strong branch-stability census.
  - code: `src/apps/probe_hmc_volume.f90` now emits `strong_branch_stable` and aggregate route counters.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/branch_stability_probe_20260507.pbs`
  - eps grid: `1e-5`, `1e-6`, `1e-7`.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 5a:
  - PBS job: `14127.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/branch_stability_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/branch_stability_probe_20260507/branch_stability_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 5a completed:
  - PBS job: `14127.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/branch_stability_probe_20260507/branch_stability_probe_report.md`
  - Report status: `DIAGNOSTIC`
- Summary:
  - weak branch stability was 200/200 at all eps.
  - NT subset was fully strong-stable: 173/173 at all eps.
  - QN subset had aggregate-route-counter instability: 21/27, 23/27, 22/27 strong-stable for eps `1e-5`, `1e-6`, `1e-7`.
  - current evidence points to QN internal route-counter sensitivity, not a clear finite-measure weak branch boundary.
- Next:
  - detail capture for strong-unstable QN rows, including perturbation-side counters.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 5a2:
  - target: strong-unstable QN detail capture.
  - code: `src/apps/probe_hmc_volume.f90` now supports optional `HMC_VOLUME_DETAIL_CSV`.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/branch_stability_detail_probe_20260507.pbs`
  - eps grid: `1e-5`, `1e-6`, `1e-7`.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 5a2:
  - PBS job: `14128.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/branch_stability_detail_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/branch_stability_detail_probe_20260507/branch_stability_detail_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 5a2 completed:
  - PBS job: `14128.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/branch_stability_detail_probe_20260507/branch_stability_detail_probe_report.md`
  - Report status: `DIAGNOSTIC`
- Summary:
  - QN weak-stable rows remained weak-stable; strong instability was solely due to post-refine route counters.
  - changed counters were only `post_refine_attempt_delta`, `post_refine_skip_delta`, and `post_refine_success_delta`.
  - no NT/QN/failure/RG counter changes were implicated.
  - at `eps=1e-7`, max metric error among QN unstable rows was `1.609e-05`.
- Next:
  - verify post-refine skip-vs-attempt route equivalence with an env-gated skip-disable diagnostic.

## 2026-05-07 JST
- Prepared Kernel Correctness Audit Probe 5b0:
  - target: post-refine skip-vs-attempt route equivalence.
  - code: added diagnostic `QN_POST_NEWTON_REFINE_SKIP_ENABLED`, default enabled.
  - code: added `HMC_VOLUME_DETAIL_ALL` for full detail output in `probe_hmc_volume`.
  - PBS script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/post_refine_skip_equivalence_probe_20260507.pbs`
  - comparison tolerance: `1e-8` on `q_out`, `c_out`, and `jac_out_abs`.

## 2026-05-07 JST
- Submitted Kernel Correctness Audit Probe 5b0:
  - PBS job: `14129.anode01`
  - Queue: `C8`
  - Script: `codex/workspaces/kernel_correctness_audit/tasks/pbs/post_refine_skip_equivalence_probe_20260507.pbs`
  - Report target: `output/tests/kernel_correctness_audit/post_refine_skip_equivalence_probe_20260507/post_refine_skip_equivalence_probe_report.md`

## 2026-05-07 JST
- Kernel Correctness Audit Probe 5b0 completed:
  - PBS job: `14129.anode01`
  - Exit status: `0`
  - Report: `output/tests/kernel_correctness_audit/post_refine_skip_equivalence_probe_20260507/post_refine_skip_equivalence_probe_report.md`
  - Report status: `PASS`
- Summary:
  - compared 185 QN detail rows between skip-on and skip-off.
  - max state difference over `q_out`, `c_out`, `jac_out_abs` was exactly `0.000e+00`.
  - max `|dmetric_logvol|` was exactly `0.000e+00`.
  - counter changes were only post-refine skip replaced by attempt+success.
- Interpretation:
  - post-refine skip/attempt route sensitivity is proposal-equivalent in this sample.
  - current kernel audit has no identified blocker for the withfb p28 RG post-refine kernel.

## 2026-05-07 JST
- Pre-production hardening pass started before restarting 3_4 production.
- Code fixes:
  - `src/sampler/constraint_solver_stats.f90`: added suppression depth and push/pop guard.
  - `src/sampler/hmc_integrator_core.f90`: reverse-gate internal replay now suppresses solver/failure/post-refine stats; RG accept check now includes `jac`.
  - `src/sampler/hmc.f90`: HMC proposal path now returns explicit `proposal_ok`.
  - `src/sampler/markovchain_metropolis.f90`: Metropolis now rejects failed/non-finite proposals via `proposal_ok` and finite Hamiltonian checks, not `h_final == 0`.
  - `scripts/run_stage3_3_multiseed.py`: production `fb` env explicitly enables post-refine skip; nonzero warmup now fails fast; per-seed/method `run_manifest.json` is written.
  - `scripts/merge_stage3_multiseed_chunks.py`: merged CSVs now retain post-refine count/ratio columns.
- Verification:
  - `python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/merge_stage3_multiseed_chunks.py` passed.
  - `git diff --check` passed on changed production files.
  - `make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2` passed locally.
  - `make -C build FC=gfortran LDFLAGS= ../bin/evaluate_expectations` passed locally.
  - `make -C build FC=gfortran LDFLAGS= ../bin/test_program` passed locally.
  - local `./bin/test_program` passed.
  - local RG-on Stage2 smoke passed with `constraint_stats total=20` and `reverse_gate_route_candidates total=20` for `nstep=20`, confirming reverse replay did not double solver counters.
  - remote source and `codex/` were synced to `/home/cychou/TLTM`.
  - remote Intel-module build passed for production binaries `bin/run_tltm_stage2` and `bin/evaluate_expectations`.
  - remote stale `.obj/tests/test_hamiltonian_conservation.o` was removed and `bin/test_program` rebuilt with ifx successfully.
  - remote `./bin/test_program` passed.
  - remote RG-on Stage2 smoke passed with `constraint_stats total=20` and `reverse_gate_route_candidates total=20` for `nstep=20`.

## 2026-05-07 JST
- Git workflow hardening after user noticed unpushed/uncommitted changes:
  - `codex/runbooks/GIT_WORKFLOW.md` now makes push a mandatory validation/production gate.
  - `codex/runbooks/WORKFLOW.md` now has a dedicated git gate before PBS submission.
  - `codex/runbooks/SOURCE_AUDIT_BOOTSTRAP.md` now says validation/production jobs must not run from dirty or unpushed branches.
  - `codex/README.md` policy now explicitly requires commit and push before validation or production submission.
- Production next-step decision:
  - do not go directly to full production after kernel-adjacent code changes.
  - next step should be a small pushed-commit validation run, then full production if Zmean/rev_rej/runtime are stable.
