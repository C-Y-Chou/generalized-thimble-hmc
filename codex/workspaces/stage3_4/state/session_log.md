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

## 2026-04-30 22:12 JST
- New campaign requested: redo `p28+RG` 1024 seeds with unified RG behavior independent of fallback trigger.
- Code condition verified in `/home/cychou/TLTM/src/sampler/hmc_integrator_core.f90`:
  - RG gate branch guarded by `if (qn_reverse_gate_enabled .and. (.not. qn_reverse_gate_active))` at lines ~408+, not by fallback trigger state.
- New p28 rerun scripts created:
  - `run_stage3_4_t035_reverse_gate_p28_unifiedrg_1024seed_200k_c17_main.pbs`
  - `run_stage3_4_t035_reverse_gate_p28_unifiedrg_1024seed_200k_c17long_tail.pbs`
  - `merge_stage3_4_t035_reverse_gate_p28_unifiedrg_1024seed_200k_chunks.pbs`
- Output root:
  - `output/tests/stage3_4/reverse_gate_p28_unifiedrg_redo_1024seed_200k_t035/reverse_gate_p28_unifiedrg_redo`
- Queue optimization choice:
  - Pre-stage p28 on `C17(24 chunks) + C17-LONG(8 chunks)`.
  - Hold with dependency on current nofb arrays to avoid self-contention:
    `afterany:13473[]:13500[]:13501[]`.
- Submitted jobs:
  - `13503[]` (C17), `13504[]` (C17-LONG), `13505` (merge).

## 2026-05-01 10:14 JST
- User clarification: current task is an RG-enabled redo of prior ngport-style experiment.
- Paper baseline check: fallback-enabled/disabled scan at tau=0.30, L=2, nstep scan does not include reverse gate.
- New experiment root created:
  - /home/cychou/TLTM/output/tests/ngport_rg_single_replica_t03_nstep_grid
- Chosen matched-control budget (xyz):
  - z cycles per chain = 50000
  - x chains per seed = 24
  - y seeds per condition = 10
- Planned conditions:
  - methods: nofb vs withfb (both with RG enabled)
  - nstep grid: 10, 15, 20, 30, 40
- Plan persisted at:
  - /home/cychou/TLTM/output/tests/ngport_rg_single_replica_t03_nstep_grid/summary/PLAN.md

## 2026-05-01 10:23 JST
- Control-plane maintenance upgrade applied.
- Added global live-board refresher: `/home/cychou/TLTM/codex/tasks/refresh_live_board.sh`.
- Stage3_4 workspace now uses live-board refresh in `tasks/refresh_context.sh` and `tasks/queue_snapshot.sh`.
- Stage3_4 status and manifest were updated to current campaign (`reverse_gate_p28_unifiedrg_redo`, jobs 13503/13505).

## 2026-05-01 23:56:34 JST
- Goal: submit Stage3_4 `qn_only_p28_rg` 1024-seed 200k campaign (RG on regardless of fallback trigger path).
- Created PBS set:
  - /home/cychou/TLTM/output/tests/stage3_4/run_stage3_4_t035_qn_only_p28_rg_1024seed_200k_c12_main.pbs
  - /home/cychou/TLTM/output/tests/stage3_4/run_stage3_4_t035_qn_only_p28_rg_1024seed_200k_c17_tail.pbs
  - /home/cychou/TLTM/output/tests/stage3_4/merge_stage3_4_t035_qn_only_p28_rg_1024seed_200k_chunks.pbs
- Queue strategy (coarse optimization): C12 main 24 chunks + C17 tail 8 chunks (32 chunks total, 32 seeds/chunk).
- Submitted jobs:
  - 13610[] (C12)
  - 13611[] (C17)
  - 13612 (merge hold, afterok:13610[]:13611[])
- Method semantics:
  - methods=qn_only_p28
  - QN_SKIP_SIMPLIFIED_NEWTON=1
  - QN_REVERSE_GATE_ENABLED=1



## 2026-05-02 10:47:10 JST
- User decision: abandon all QN-only paths.
- Queue actions:
  - Cancelled 13605[], 13606, 13610[], 13611[], 13612.
- Code actions:
  - Removed QN_SKIP_SIMPLIFIED_NEWTON path from /home/cychou/TLTM/src/sampler/hmc_integrator_core.f90.
  - Removed qn_only_p28/all3 method options from /home/cychou/TLTM/scripts/run_stage3_3_multiseed.py.
- Cleanup actions:
  - Deleted QN-only PBS scripts under output/tests/stage3_3_submit and output/tests/stage3_4.
  - Deleted QN-only output/log trees and codex workspace stage3_3_qn_only_p28_rg.


## 2026-05-02 10:58:50 JST
- New remediation campaign launched for stage3_4 p28 RG issue.
- Rationale: withfb showed worse Re Zmean than nofb and delta correlated with fallback trigger intensity.
- Change applied: run_stage3_3_multiseed fb method now sets QN_POST_NEWTON_REFINE_ENABLED=1 and QN_POST_NEWTON_REFINE_MAX_ITER=20.
- Submitted jobs:
  - 13622[] (C12, chunk_00..23)
  - 13623[] (C17, chunk_24..31)
  - 13624 (merge hold, afterok)
- Output root:
  - /home/cychou/TLTM/output/tests/stage3_4/reverse_gate_p28_unifiedrg_refine_1024seed_200k_t035/reverse_gate_p28_unifiedrg_refine

## 2026-05-06 10:05:22 JST
- Patched post-refine seed mapping in main code: ld0 = -u_qn (from qn_solution_xi first half).
- Rebuilt binaries: ../bin/run_tltm_stage2 and ../bin/replay_quasi_failures.
- 1-failure replay check (seed_20260421, tol=1e-13, iter=28): old_seed_loss=7.9700151303251296e-03, new_seed_loss=7.3173369012385340e-11.
- Output CSV: output/tests/stage3_4/post_refine_fail_replay_capture/withfb_p28_refine_rg_ct1e13_qn1e13_10seed_10k/fb/seed_20260421/output/replay_seedcheck_ld_minus_u_v2.csv

## 2026-05-06 10:06:29 JST
- Cleanup: replay_quasi_failures instrumentation reverted after one-case diagnostic; binary rebuilt clean.

## 2026-05-06 10:09:05 JST
- User requested full redo: cleared 5x capture groups (10k cycles x 10 seeds) under output/tests/stage3_4/post_refine_fail_replay_capture and matching logs subtree.
- Cancelled in-flight old reruns: 13961, 13962.
- Resubmitted 5 jobs for fresh capture:
  - 13963 C8 s34r10k_nofb (nofb, qn tol 1e-13)
  - 13964 C12 s34r10k_fbnr (withfb p28 norefine, qn tol 1e-13)
  - 13965 C8-LONG s34r10k_fbnr14 (withfb p28 norefine, qn tol 1e-14)
  - 13966 C16 s34r10k_fbr13 (withfb p28 refine, qn tol 1e-13)
  - 13967 C17 s34r10k_fbr14 (withfb p28 refine, qn tol 1e-14)
- Status at submission check: all 5 in R.

## 2026-05-07 22:10:44 JST
- Submitted pre-production validation after pushed hardening branch.
- Git gate:
  - branch: `codex/preprod-hardening`
  - pushed commit: `fe82bc433784991065db35b900325b1c87e096f0`
  - remote working tree was clean before submission.
  - PBS receives `TLTM_EXPECTED_GIT_COMMIT=fe82bc433784991065db35b900325b1c87e096f0` and self-checks branch/SHA/dirty state before running.
- Job:
  - `14130.anode01`
  - queue: `C12`
  - state at first check: `R`
  - PBS: `codex/workspaces/stage3_4/tasks/pbs/preprod_validation_20260507_10seed_10k_p28_rg.pbs`
- Validation setup:
  - config: `docs/stage_3_4_t035_paired_10k_10seed.json`
  - methods: `both` (`no_fb` + `fb`)
  - 10 seeds x 10k cycles
  - RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
  - `fb` method uses post-refine enabled, skip enabled, max iter 20.
- Output:
  - `output/tests/stage3_4/preprod_validation_20260507_10seed_10k_p28_rg`
  - logs: `output/logs/stage3_4_preprod_validation/preprod_validation_20260507_10seed_10k_p28_rg`
- Gate for production:
  - inspect report Zmean, rev_rej, unresolved failures, runtime.
  - confirm per-seed `run_manifest.json` exists.
  - only then submit full 1024-seed production.

## 2026-05-08 JST
- Pre-production validation completed and inspected.
- Report:
  - `output/tests/stage3_4/preprod_validation_20260507_10seed_10k_p28_rg/s34_preprod_validation_20260507_p28_rg_report.md`
- Completion artifacts:
  - `aggregated_summary_table.csv`
  - `per_seed_summary_table.csv`
  - 20 per-seed `run_manifest.json` files.
- Aggregated results:
  - `fb`: `Zmean_re=-0.214`, `Zmean_im=1.387`, failures `1787`, RG rejects `1594`, mean runtime `956.9s`.
  - `no_fb`: `Zmean_re=1.133`, `Zmean_im=-0.594`, failures `7451`, RG rejects `1132`, mean runtime `817.5s`.
- Checks:
  - 20 per-seed rows present.
  - 20 run manifests present.
  - required env values present in manifests: RG enabled, p28, `QN_QUASI_TOL_OVERRIDE=1e-13`, `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-13`.
  - `projection_failure_count = unresolved_failure_count + reverse_gate_total_reject_count` for every seed/method row.
- Interpretation:
  - PASS for proceeding to full production planning.
  - Small-sample caveat: 10 seeds x 10k is only a validation gate, not a final scientific claim.
  - `fb` reduces unresolved failures strongly; runtime cost is about 17%; RG rejects are slightly higher but not a blocker.

## 2026-05-08 12:17 JST
- Submitted supplemental `fb_norefine` validation at user's request.
- Git gate:
  - branch: `codex/preprod-hardening`
  - pushed commit: `6b552ffb64e606a919963128e9e55747eb75907b`
  - remote working tree was clean before submission.
  - PBS receives `TLTM_EXPECTED_GIT_COMMIT=6b552ffb64e606a919963128e9e55747eb75907b` and self-checks branch/SHA/dirty state.
- Job:
  - `14175.anode01`
  - queue: `C12`
  - state at first check: `R`
  - PBS: `codex/workspaces/stage3_4/tasks/pbs/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine.pbs`
- Validation setup:
  - config: `docs/stage_3_4_t035_paired_10k_10seed.json`
  - method: `fb_norefine`
  - 10 seeds x 10k cycles
  - RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
  - `QN_POST_NEWTON_REFINE_ENABLED=0`
- Output:
  - `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
  - logs: `output/logs/stage3_4_preprod_validation/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`

## 2026-05-08 12:38 JST
- Supplemental `fb_norefine` validation completed and inspected.
- Job:
  - `14175.anode01`
  - queue: `C12`
  - PBS state at inspection: `E`
  - `Exit_status=0`
- Report:
  - `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine/s34_preprod_validation_20260508_p28_rg_fb_norefine_report.md`
- Aggregated result:
  - `fb_norefine`: `Zmean_re=-0.337600`, `Zmean_im=1.729899`, `mean_Re=-0.0157643`, `mean_Im=0.0471401`, `std_Re=0.147663`, `std_Im=0.0861727`, unresolved failures `1769`, RG rejects `1585`, mean runtime `961.7s`.
- Checks:
  - 10 per-seed rows present.
  - 10 per-seed `run_manifest.json` files present.
  - Manifest env values checked: RG enabled, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, `QN_POST_NEWTON_REFINE_ENABLED=0`.
  - `projection_failure_count = unresolved_failure_count + reverse_gate_total_reject_count` for every row.
- Paired comparison vs previous `fb` refine validation on the same 10 seeds:
  - Mean delta `fb_norefine - fb`: `dRe=-0.00540`, `dIm=+0.00966`, `dRuntime=+4.87s`, `dUnresolved=-1.8`, `dRG=-0.9`.
  - Geometry counters are nearly unchanged/slightly better, but `Zmean_im` worsens from `1.3866` to `1.7299` and runtime does not improve.
- Interim decision:
  - Do not switch production candidate to `fb_norefine`.
  - Keep `fb` with post-refine enabled as current production candidate unless user requests an explicit diagnostic/control production branch.

## 2026-05-08 12:54 JST
- User requested the next minimal judgment experiment before choosing full production seed/cycle count.
- Experiment:
  - label: `judgment_20260508_32seed_50k_p28_rg`
  - config: `docs/stage_3_4_t035_paired_32seed_50k_rg.json`
  - sets: `no_fb`, `fb_refine`, `fb_norefine`
  - budget: 32 matched seeds x 50k cycles per set
  - common settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, near/non-near/global rescue off.
- PBS/config commit:
  - `c04100faea5da0cbad73b6528f2f69e0dcc87d7a`
- Submission / queue notes:
  - Initial `no_fb` submission `14179.anode01` on C17 exited immediately with `Exit_status=127`; it is invalid and excluded.
  - Initial `fb_refine` on C12 queued with `Qlist`; moved away.
  - 20-core probes confirmed immediate starts on C8, C8-LONG, C17-LONG, G, and F.
  - Final running compute jobs:
    - `14180.anode01`: `fb_refine`, queue `G`, state `R`, started 2026-05-08 12:53 JST.
    - `14181.anode01`: `fb_norefine`, queue `C8`, state `R`, started 2026-05-08 12:49 JST.
    - `14182.anode01`: `no_fb`, queue `F`, state `R`, started 2026-05-08 12:53 JST.
  - Merge/report job:
    - First hold job `14188.anode01` was removed before running because tracked status needed a follow-up commit; a replacement merge job is submitted from the latest status commit and is tracked in the live board.
- Output:
  - root: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg`
  - logs: `output/logs/stage3_4_judgment_20260508_32seed_50k_p28_rg`
  - combined report after merge: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg/REPORT.md`
- ETA:
  - Based on 10seed/10k runtime scaled to 50k with two worker waves, expected compute finish is around 2026-05-08 15:50-16:20 JST.
  - Merge/report should complete a few minutes after all compute jobs succeed.

## 2026-05-08 16:30 JST
- Stage3_4 judgment run completed and inspected.
- Jobs:
  - `14180.anode01`: `fb_refine`, completed.
  - `14181.anode01`: `fb_norefine`, completed.
  - `14182.anode01`: `no_fb`, completed.
  - `14189.anode01`: merge/report, completed with `Exit_status=0`.
  - invalid excluded job: `14179.anode01` exited immediately with `Exit_status=127`.
- Output:
  - root: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg`
  - report: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg/REPORT.md`
  - logs: `output/logs/stage3_4_judgment_20260508_32seed_50k_p28_rg`
- Completion checks:
  - `no_fb`: 32 manifests, 32 stage2 summaries.
  - `fb_refine`: 32 manifests, 32 stage2 summaries.
  - `fb_norefine`: 32 manifests, 32 stage2 summaries.
- Aggregated results:
  - `no_fb`: `Zmean_re=0.367395`, `Zmean_im=-0.897098`, mean Re `<O>=0.00454804`, mean Im `<O>=-0.00646140`, std Re `0.0700271`, std Im `0.0407438`, failures `118503`, RG rejects `17228`, mean runtime `5048.5s`.
  - `fb_refine`: `Zmean_re=-0.161417`, `Zmean_im=0.346142`, mean Re `<O>=-0.00201207`, mean Im `<O>=0.00240530`, std Re `0.0705127`, std Im `0.0393088`, failures `28393`, RG rejects `25044`, mean runtime `6059.6s`, post-refine `49321/49634`, skip `80576`.
  - `fb_norefine`: `Zmean_re=0.0697449`, `Zmean_im=-0.0671524`, mean Re `<O>=0.000888348`, mean Im `<O>=-0.000457797`, std Re `0.0720519`, std Im `0.0385644`, failures `28182`, RG rejects `24909`, mean runtime `5535.3s`, post-refine `0/0`.
- Paired seed checks:
  - `fb_refine - no_fb`: paired mean diff `dRe=-0.006560`, `dIm=+0.008867`; closer-to-zero wins `17/32` Re and `16/32` Im.
  - `fb_norefine - no_fb`: paired mean diff `dRe=-0.003660`, `dIm=+0.006004`; closer-to-zero wins `17/32` Re and `18/32` Im.
  - `fb_refine - fb_norefine`: paired mean diff `dRe=-0.002900`, `dIm=+0.002863`; closer-to-zero wins `17/32` Re and `14/32` Im.
- Interim interpretation:
  - Fallback remains useful for reducing unresolved failures: both fallback variants reduce unresolved failures by about `90k` events versus `no_fb`.
  - Fallback increases RG rejects by about `7.7k-7.8k`, but total RG reject rate remains small at about `3.9e-4`.
  - Unlike the earlier 10seed/10k validation, this 32seed/50k judgment run favors `fb_norefine` over `fb_refine` on aggregate Zmean and runtime.
  - Need discuss whether to run a larger intermediate scale or inspect post-refine side effects before full production.

## 2026-05-08 16:45 JST
- User suggested using seed and cycle windows to help choose the next larger scale.
- Created seed/cycle window diagnostics from existing cold-chain histories, without rerunning simulation:
  - `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg/window_diagnostics/REPORT.md`
  - `cycle_window_aggregate.csv`
  - `seed_window_aggregate.csv`
  - `window_seed_estimates.csv`
- Window findings for `no_fb` and `fb_norefine`:
  - Prefix windows show `fb_norefine` Re bias moves from `Zmean_re=-1.420` at 10k to `0.070` at 50k.
  - Non-overlap 10k cycle windows still fluctuate; `fb_norefine` Re window means span about `0.074`.
  - Full-50k seed blocks of 8 still fluctuate; `fb_norefine` Re block means span about `0.048`.
  - Therefore the next scale should increase both seed count and cycle length, not only one axis.
- Recommended next intermediate scale:
  - methods: `no_fb`, `fb_norefine` only.
  - scale: `128 seeds x 100k cycles`.
  - rationale: 4x seeds and 2x cycles versus 32x50k, total 8x information, still much cheaper than full production.
  - expected per-seed runtime from measured 32x50k: `no_fb ~2.8h`, `fb_norefine ~3.1h`.
  - suggested PBS layout: 8 chunks per method, 16 seeds per chunk, one wave per chunk; use 12h queues safely.
