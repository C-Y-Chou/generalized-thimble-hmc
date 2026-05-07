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
