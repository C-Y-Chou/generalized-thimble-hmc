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

## 2026-05-11 17:04 JST
- Goal: read back official DFO-LS `32 seeds x 50k cycles` production-comparison gate.
- Campaign: `official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb`.
- Remote worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Config: `docs/production_comparison_official_dfols_20260511_32seed_50k_nofb_withfb.json`.
- Methods: `no_fb` canonical `nofb`; `fb_norefine` canonical `withfb`.
- Env vars: official DFO-LS backend, `stable_gate77`, RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Completion: `64/64` run manifests, `32/32` per method, final `REPORT.md` and `combined_summary_table.csv` generated.
- Key findings:
  - `nofb`: mean Re `0.020188792134396484`, mean Im `-0.004985872843091379`, Zmean Re `1.333466646990749`, Zmean Im `-0.5536498965991518`, failures `120858`, RG rejects `19197`, runtime `3708.3135403125007s`.
  - `withfb`: mean Re `-0.0019937714302690254`, mean Im `0.004999952129493637`, Zmean Re `-0.20153214684082096`, Zmean Im `0.6400123564653849`, failures `19579`, RG rejects `15987`, runtime `5586.39629015625s`.
  - `withfb - nofb`: mean shift Re `-0.0221826`, Im `+0.00998582`; unresolved failures `-101279`; RG rejects `-3210`; runtime `+1878.08s`.
- Next action: choose next scale for `nofb` vs `withfb/fb_norefine` official DFO-LS before production-scale run.

## 2026-05-11 17:20 JST
- Correction: the proper same-scale in-house/reference comparison for the official DFO-LS `32 seeds x 50k` gate is M6 R3 `m6_r3_32seed_50k`, not the older `judgment_20260508_32seed_50k_p28_rg` dataset.
- M6 R3 source: `codex/workspaces/fortran_modernization/state/M6_REFERENCE_COMPARISON_SUMMARY.tsv`.
- Corrected readback:
  - `nofb` is unchanged at the observable/counter level: mean Re differs by `+3.44e-11`, mean Im by `-4.31e-11`, unresolved failures by `0`, RG rejects by `0`.
  - Therefore official DFO-LS does not materially affect `nofb`; `no_fb` has `enable_quasi_fallback=false` and should not enter the QN solver path.
  - `withfb/fb_norefine` is the affected method: official DFO-LS shifts mean Re by `-0.00216217`, mean Im by `+0.00349921`, reduces unresolved failures by `8627`, and reduces RG rejects by `8940` relative to M6 R3.
- Next action: use M6 R3/R4 as the baseline family for future official DFO-LS production-comparison scaling decisions.

## 2026-05-11 17:25 JST
- Goal: submit next official DFO-LS production-comparison gate.
- Campaign: `official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4`.
- Config: `docs/production_comparison_official_dfols_20260511_128seed_100k_withfb_r4.json`.
- Method: `fb_norefine` only, canonical `withfb`.
- Baseline policy: compare against accepted M6 R4 `nofb` and `withfb/fb_norefine`; do not rerun `nofb` because the 32seed gate showed no observable/counter difference for `nofb`.
- Execution commit: `1edbbd465663640e711d1935f8d2fa5b47bf8510`.
- Remote worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`, branch `codex/tltm-production-comparison-official-dfols`.
- Queue plan:
  - Preflight build: `14775.anode01` on `C8`.
  - Chunks `00..07`: `14776..14783` on `C8`, offsets `0,8,16,24,32,40,48,56`.
  - Chunks `08..15`: `14784..14791` on `C12`, offsets `64,72,80,88,96,104,112,120`.
  - Merge/report: `14792.anode01` on `C8`, afterok all chunks.
- Scale: `128 seeds x 100000 cycles`, `16 chunks x 8 seeds`, `8 workers/chunk`.
- Expected runtime: if preflight and all chunks start promptly, chunk compute is about `3.1h` from 32seed/50k scaling; report expected roughly `21:00-21:40 JST`.
- Initial status: preflight running; chunks and merge held by dependencies.
- 2026-05-11 17:29 JST status refresh: preflight `14775` finished with `Exit_status=0`; all chunks `14776..14791` are running; merge `14792` remains held until all chunks finish.
- 2026-05-11 20:46 JST readback: report generated at `output/production_comparison/provisional/official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4/REPORT.md`.
- Result: `withfb/fb_norefine`, 128 seeds, mean Re `0.003434163621430383`, mean Im `-0.0012225229577123272`, Zmean Re `0.8633923978986243`, Zmean Im `-0.422893731201389`, failures `155321`, RG rejects `128255`, runtime `10879.63379652343s`.
- Compared to M6 R4 withfb: unresolved failures `-69259` (`-30.84%`), RG rejects `-72275` (`-36.04%`), runtime `+2393.05s` (`+28.20%`).
- Interpretation: statistically acceptable Zmean/coverage and better failure/RG behavior than M6 R4 withfb, with a significant runtime cost and a positive Re mean shift relative to M6 R4 withfb.

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

## 2026-05-08 16:55 JST
- Prepared the next intermediate scale-up for submission.
- Added protocol:
  - `docs/stage_3_4_t035_paired_128seed_100k_rg_nofb_fbnorefine.json`
- Added reusable PBS templates:
  - `codex/workspaces/stage3_4/tasks/pbs/judgment_20260508_128seed_100k_p28_rg_chunk.pbs`
  - `codex/workspaces/stage3_4/tasks/pbs/judgment_20260508_128seed_100k_p28_rg_merge.pbs`
- Submission plan:
  - methods: `no_fb`, `fb_norefine`.
  - queue check found C24/C36 are multi-node queues with `resources_min.nodect`, unsuitable for this non-MPI runner.
  - final chunk plan: 8 chunks per method, 16 seeds/chunk, 16 workers/chunk.
  - queue distribution across both methods: `C8 x6`, `C12 x6`, `G x3`, `F x1`.
  - compute jobs will be submitted with `TLTM_EXPECTED_GIT_COMMIT` pinned to the commit containing this protocol and PBS setup.
  - merge job will run after all compute chunks finish and will produce `REPORT.md` under the campaign output root.

## 2026-05-08 16:45 JST
- Submitted Stage3_4 128seed/100k compute chunks.
- First C12 submissions remained queued with `Qlist`, so they were cancelled and replaced.
- Valid running compute jobs:
  - `no_fb`: `14250`, `14251`, `14252`, `14266`, `14267`, `14255`, `14256`, `14268`.
  - `fb_norefine`: `14258`, `14259`, `14260`, `14269`, `14270`, `14263`, `14264`, `14271`.
- Cancelled/replaced C12 jobs:
  - `14253`, `14254`, `14257`, `14261`, `14262`, `14265`.
- Actual running queue distribution:
  - `C8 x8`, `G x4`, `C8-LONG x3`, `F x1`.
- All valid compute chunks are in `R`, so they have passed the git gate at commit `f5fd391`.
- Next step:
  - update this status to git/remote, then submit merge/report job with dependency on the 16 valid compute jobs.
## 2026-05-11 JST - Production redo switched to official DFO-LS backend
- Production redo should use the synchronized `codex/fortran-modernization` branch/commit, not the older `codex/tltm-production-comparison` solver state.
- Updated the 128seed/100k chunk and merge PBS guards to default to `TLTM_EXPECTED_GIT_BRANCH=codex/fortran-modernization` and `TLTM_WORKTREE=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
- Chunk jobs now require the preflight-created `.venv-dfols`, set `QN_SOLVER_BACKEND=official_dfols`, set `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`, and export `TLTM_OFFICIAL_DFOLS_PYTHONPATH` from the venv site-packages.
- Added `tasks/pbs/official_dfols_preflight_build.pbs` to create/update `.venv-dfols`, verify `DFO-LS==1.6.5`, prepare local Python 3.11 headers under `.deps/` when the system devel package is missing, and build `run_tltm_stage2` plus `evaluate_expectations` with `ENABLE_OFFICIAL_DFOLS=1`.
- New production order: sync the remote production tree to the official-DFO-LS commit, submit the preflight build, then submit chunks pinned to the same commit after preflight succeeds.

## 2026-05-11 JST - Official DFO-LS small production-comparison redo submitted
- Campaign:
  - `official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb`
- Purpose:
  - Restart `tltm_production_comparison` from a small seed/cycle gate using the new official DFO-LS backend before scaling.
- Execution line:
  - local/remote branch: `codex/fortran-modernization`
  - remote worktree: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
  - pinned commit: `b72d5602c81ada436742cc7aef87a9b6fb2262da`
- Protocol:
  - `docs/production_comparison_official_dfols_20260511_10seed_10k_nofb_withfb.json`
  - scale: `10 seeds x 10000 cycles`
  - physical point: `t=0.35,L=2,nstep=20`
  - raw/canonical mapping: `no_fb -> nofb`, `fb_norefine -> withfb`
  - backend: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`
  - gate/tolerance: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
- PBS:
  - preflight build: `14756.anode01`
  - small redo afterok dependency: `14757.anode01`
- Output target:
  - `output/production_comparison/provisional/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb/REPORT.md`

## 2026-05-11 JST - Corrected production-comparison execution worktree
- Correction:
  - Production-comparison jobs must execute from `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`, not from `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
  - `fortran_modernization` is the official DFO-LS source/code line; production worktree is synced to the chosen commit before production output generation.
- Action:
  - Cancelled misrouted small redo job `14757.anode01`; any partial output under the modernization worktree is not a valid production-comparison artifact.
  - Updated production-comparison PBS defaults and route documentation to use the production-comparison worktree and branch `codex/tltm-production-comparison-official-dfols`.
- Correct resubmission:
  - Synced `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` to commit `fdf76ee92eccf921d5c79d5d15d708eede5afdcc`.
  - Branch at submission: `codex/tltm-production-comparison-official-dfols`.
  - Preflight build job: `14758.anode01`.
  - Small redo job: `14759.anode01`, with `afterok:14758.anode01`.
  - Output target remains `output/production_comparison/provisional/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb/REPORT.md` inside the production-comparison worktree.

## 2026-05-11 JST - Small redo resource split corrected
- Issue:
  - Job `14759.anode01` used only one 8-core PBS job and ran `no_fb` then `fb_norefine` sequentially, so the 10seed/10k gate underused available cluster resources.
- Correction:
  - Cancel `14759.anode01`.
  - Use method-split jobs: one `no_fb` PBS and one `fb_norefine` PBS, each with 10 workers.
  - Add a dependency merge job that writes the combined production-comparison report after both method jobs finish.
- Corrected submission:
  - Synced production-comparison worktree to commit `81b0784473073a6bc3ec1604f3f2e5930e70e252`.
  - Preflight build: `14760.anode01`.
  - `no_fb` method job: `14761.anode01`.
  - `fb_norefine` / canonical `withfb` method job: `14762.anode01`.
  - Merge/report job: `14763.anode01`.

## 2026-05-11 JST - Official DFO-LS small redo readback
- Result report:
  - `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison/output/production_comparison/provisional/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb/REPORT.md`
- Official DFO-LS aggregate:
  - `nofb/no_fb`: mean Re `0.0265222881`, mean Im `0.0247701103`, std Re `0.1886771381`, std Im `0.0926561653`, Zmean Re `0.4445204125`, Zmean Im `0.8453832101`, failures `7502`, RG rejects `1252`, runtime `715.5420136s`.
  - `withfb/fb_norefine`: mean Re `-0.0290740001`, mean Im `0.0347713206`, std Re `0.1039176303`, std Im `0.0969095801`, Zmean Re `-0.8847397764`, Zmean Im `1.1346305510`, failures `1179`, RG rejects `996`, runtime `1105.0365717s`.
- In-house comparison:
  - Readback written to `codex/workspaces/tltm_production_comparison/runbooks/OFFICIAL_DFOLS_SMALL_READBACK_20260511.md`.
  - Main preserved-baseline comparison uses `no_fb` and `fb_norefine -> withfb`; old raw reports were cleaned, so `no_fb` std is inferred from preserved mean and Zmean.

## 2026-05-11 JST - Planned next official DFO-LS comparison gate
- Next scale after `10 seeds x 10k cycles`:
  - `32 seeds x 50k cycles` per method.
  - Methods: `no_fb -> nofb`, `fb_norefine -> withfb`.
  - Physical point: `t=0.35,L=2,nstep=20`.
  - Backend/gate: official DFO-LS `stable_gate77`, RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Queue/chunk strategy from live queue check:
  - C8 was empty; C16 was saturated; C12 and C12-LONG had running jobs; F was empty but only one node.
  - Use C8 as the fastest clean one-wave option.
  - Submit 8 chunks total: 4 chunks for `no_fb`, 4 chunks for `fb_norefine`.
  - Each chunk has 8 seeds and 8 workers.
  - Preflight build runs first; all chunks depend on preflight; one merge/report job depends on all 8 chunks.
- Expected walltime if C8 admits all chunks promptly:
  - about `1.5-2h` compute plus merge overhead.

## 2026-05-11 JST - Submitted official DFO-LS 32seed/50k comparison gate
- Campaign:
  - `official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb`
- Production worktree:
  - `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
  - branch `codex/tltm-production-comparison-official-dfols`
  - pinned commit `d3f133d1fd7de2ec6a5b7ac27840c01287be5be7`
- Queue/chunk plan:
  - `C8` one-wave plan because live `C8` was empty at submission time.
  - `no_fb`: chunks `00..03`, offsets `0,8,16,24`, 8 seeds/chunk, 8 workers/chunk.
  - `fb_norefine`: chunks `00..03`, offsets `0,8,16,24`, 8 seeds/chunk, 8 workers/chunk.
- PBS jobs:
  - preflight build: `14765.anode01`
  - `no_fb`: `14766.anode01`, `14767.anode01`, `14768.anode01`, `14769.anode01`
  - `fb_norefine`: `14770.anode01`, `14771.anode01`, `14772.anode01`, `14773.anode01`
  - merge/report: `14774.anode01`
- Note:
  - Initial shell helper hit a dependency-string quoting error after submitting all chunks; merge was submitted immediately afterward with explicit dependency on `14766..14773`.

## 2026-05-11 JST - Archived non-official legacy production output

- User correction:
  - The confusing extra production output was not an `official_dfols` output.
- Action:
  - Restored `official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4` to active `provisional/` after an overly quick initial archive attempt.
  - Archived the non-official legacy gate `gate_20260511_128seed_200k_p28_rg_nofb_fbnorefine`.
- Remote archive:
  - Output: `output/production_comparison/archive/non_official_legacy_20260511/gate_20260511_128seed_200k_p28_rg_nofb_fbnorefine`
  - Logs: `output/logs/production_comparison/archive/non_official_legacy_20260511/gate_20260511_128seed_200k_p28_rg_nofb_fbnorefine`
- Active provisional outputs after cleanup:
  - `official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb`
  - `official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb`
  - `official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4`

## 2026-05-11 JST - Submitted official DFO-LS 256seed/200k comparison gate

- Campaign:
  - `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`
- Purpose:
  - Next matched `nofb` vs `withfb/fb_norefine` production-comparison scale.
- Production worktree:
  - `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
  - branch `codex/tltm-production-comparison-official-dfols`
  - pinned commit `c0e40218e6abe2706f4b9b4c66067dbcea74eeff`
- Setup:
  - `256 seeds x 200000 cycles` per method.
  - `t=0.35,L=2,nstep=20`.
  - RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
  - Backend `QN_SOLVER_BACKEND=official_dfols`, preset `stable_gate77`.
  - Raw/canonical mapping: `no_fb -> nofb`, `fb_norefine -> withfb`.
- PBS:
  - preflight build: `14814.anode01`.
  - `no_fb` chunks: `14815..14846`.
  - `fb_norefine` chunks: `14847..14878`.
  - merge/report: `14879.anode01`.
- Chunk/queue plan:
  - `32` chunks per method, `8` seeds/chunk, `8` workers/chunk.
  - Queue split: `C8 x24`, `C12 x24`, `C8-LONG x8`, `G x6`, `F x2`.
  - Avoided C16 because saturated, and avoided C24/C36/C17/C17-LONG/GPU queues for current workflow hygiene.
- Output:
  - `output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`
  - `output/logs/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`
- Submission status:
  - Initial submission check: preflight was running and all chunk/merge jobs were in dependency hold.
  - First release check after preflight `Exit_status=0`: `58` chunks running, `6` chunks queued, merge held.
  - Expected report window tightened to roughly `2026-05-12 05:30-08:30 JST`, assuming no walltime overruns or queue interruptions.

## 2026-05-12 JST - Official DFO-LS 256seed/200k readback

- Status:
  - `qstat -u cychou` showed no active jobs at readback.
  - `REPORT.md` and `combined_summary_table.csv` are available.
  - Per-seed row counts: `nofb=256`, `withfb=256`.
- Result:
  - `nofb/no_fb`: mean Re `0.0025128804602197745`, mean Im `-0.0008980638575030018`, std Re `0.03841767179759089`, std Im `0.021510884583892855`, Zmean Re `1.0465518987029727`, Zmean Im `-0.6679884160043988`, failures `3846795`, RG rejects `607777`, runtime `14588.093013816413`.
  - `withfb/fb_norefine`: mean Re `0.004020561055771586`, mean Im `-0.0008372428375762778`, std Re `0.032605416058066425`, std Im `0.01975828896374589`, Zmean Re `1.9729537196453188`, Zmean Im `-0.6779881307435225`, failures `618706`, RG rejects `510906`, runtime `22284.544315070314`.
- Direct comparison:
  - `withfb - nofb`: mean Re `+0.0015076805955518115`, mean Im `+0.000060821019926724`, Zmean Re `+0.9264018209423461`, Zmean Im `-0.0099997147391237`.
  - `withfb` reduces unresolved failures by `3228089` and RG rejects by `96871`.
  - `withfb` mean runtime is higher by about `7696.45s`.
- Interpretation:
  - This gate confirms the expected solver-quality improvement in unresolved failures and RG rejects.
  - The Re observable is not clearly better: `withfb` has a larger positive Re Zmean than `nofb` at this 256seed/200k scale, so this result needs discussion before declaring the current scale a final production endpoint.

## 2026-05-12 JST - Reframed QN issue and added event-level route audit

- User correction:
  - The issue is not caused by official DFO-LS alone; old in-house p28 already showed the same qualitative `withfb`/QN concern.
- Code reading:
  - Newton solves the RATTLE projection first.
  - QN fallback then solves BTN/backflow residual `[Im(flowzr(z + del_z - J*(a+i*b))); a]`.
  - RG replay checks `x/z/jac/p`, but RG alone does not prove volume preservation or proposal-density symmetry.
  - Metropolis uses only `exp(-(H_final-H_initial))`.
- Diagnostic added:
  - `TLTM_LOCAL_TRANSITION_AUDIT_FILE`
  - `TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS`
  - `TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR` support in `scripts/run_stage3_3_multiseed.py`.
  - Records per local update route counter deltas plus `h_initial/h_final/delta_h/accept_probability`.
- Validation:
  - `make -C build tltm_stage2` passed.
  - Local smoke run completed at `output/tests/qn_transition_audit_local_1seed_1k`.
- First smoke evidence:
  - Method `fb_norefine`, seed `20260421`, `1000 cycles`, internal p28, RG on, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`.
  - QN events occurred only in the hot slot.
  - Hot-slot accepted Newton-only: `904` rows, mean `delta_h=+9.751148437639863e-4`, negative count `464/904`.
  - Hot-slot accepted QN: `38` rows, mean `delta_h=-2.385424146627109e-2`, negative count `27/38`.
- Current hypothesis:
  - The suspicious gap is QN/fallback route balance, branch selection, local volume, or proposal-density symmetry, not official backend tuning.
  - Next test should be a short multi-seed route-conditioned `delta_h` audit before further production.

## 2026-05-12 JST - Modernization boundary instruction for production Codex

- User flagged `src/apps/probe_hmc_volume.f90` as an adjacent production Codex artifact, not intentional modernization source.
- Added `runbooks/MODERNIZATION_BOUNDARY_AND_QN_ROUTE_NEXT_INSTRUCTIONS_20260512.md`.
- Instruction to production Codex: finish the active `qn_route_bias_exact_event_capture_1seed_2k` local run, read it back, and do not submit more large production gates until exact accepted-QN events are analyzed.
- Boundary instruction: keep production diagnostics out of the modernization source/build graph unless there is a separate reviewed modernization task.
- Follow-up check: the local `qn_route_bias_exact_event_capture_1seed_2k` run completed, but the output appears to contain local transition audit/history/summary files only, not replayable accepted-QN event-state files. The instruction file now says to treat it as a single-seed audit replay and to add production-comparison-only accepted-QN event-state capture before claiming exact-event replay evidence.

## 2026-05-12 JST - Promoted production/modernization boundary to hard blocker

- Added `state/OPEN_ITEMS.tsv` with `PCB-001` as `active_blocker`.
- Added `state/CAVEATS.tsv` with `PCV-001` documenting source-boundary contamination.
- Updated `context/TASK.md`, `context/STATE_BRIEF.md`, and `runbooks/MODERNIZATION_BOUNDARY_AND_QN_ROUTE_NEXT_INSTRUCTIONS_20260512.md` so production Codex must resolve `src/apps/probe_hmc_volume.f90` boundary cleanup before any next local run, PBS submission, commit, evidence promotion, modernization M4, or production sync.
- Current live local run may finish, but the next action after it finishes must be boundary cleanup.

## 2026-05-12 JST - Resolved production/modernization source boundary

- Moved `src/apps/probe_hmc_volume.f90` to `codex/workspaces/tltm_production_comparison/diagnostics/probe_hmc_volume.f90`.
- Verified the modernization `build/makefile` no longer contains a `probe_hmc_volume` target/source entry.
- Marked `PCB-001` and `PCV-001` resolved.
- Production diagnostics must remain in production-comparison-only paths; do not re-add them to modernization source/build roots.
## 2026-05-12 QN Route Bias Deep Diagnostics

- Added local transition audit diagnostics for exact event replay:
  - optional HMC momentum outputs in `hmc.f90` / `markovchain_metropolis.f90`;
  - stage2 audit chart columns `q_initial,c_initial,q_proposal,c_proposal,q_after`.
- Restored a diagnostic-only `src/apps/probe_hmc_volume.f90` for local testing, but kept it out of the persistent modernization build graph per workspace boundary.
- Completed 10seed/2k two-slot route audit:
  - accepted QN retained negative conditional `delta_h` profile;
  - method-level paired Re difference was statistically insignificant at this small scale.
- Completed fallback-only REVCHK:
  - 100/100 fallback probes passed; max reverse coordinate/momentum errors were `O(1e-9)`.
- Completed local volume/branch checks:
  - generic QN stable branches showed metric log-volume near zero;
  - exact production-captured accepted-QN events showed max abs metric log-volume `O(1e-6)`;
  - reverse exact replay returned to original chart coordinates at `O(1e-11)`.
- Completed 10seed/2k single-slot t=0.35 no-effective-swap check:
  - small-window Zmean remains noisy; do not infer a robust method shift from this scale.
- Quantified remote 256seed/200k paired production difference:
  - `fb_norefine - no_fb = +0.001507680595551813 +/- 0.002768615480051937` using paired SE over 256 seeds;
  - paired t-statistic `0.5446`;
  - positive/negative seed differences `131/125`;
  - conclusion: separate Zmeans made `withfb` look worse, but direct paired method comparison does not show significant degradation.
- Current conclusion:
  - direct QN/RATTLE detailed-balance bug is lower priority;
  - next work should inspect block/window stability and autocorrelation/effective-sample behavior before deciding whether more production statistics are needed.

## 2026-05-12 Window/Block Bias Diagnostic

- Added `codex/workspaces/tltm_production_comparison/diagnostics/window_bias_analysis.py`.
- Ran it remotely against `output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`.
- Output synced locally under `codex/workspaces/tltm_production_comparison/diagnostics/window_bias_256seed_200k_20260512`.
- Recomputed per-seed full-run ratios from `sum(O*phi)/sum(phi)` agree with existing summaries to `O(1e-15)`.
- Four 50k windows:
  - `fb_norefine` Re means/Zmeans: `0.00138/0.343`, `0.00737/1.762`, `0.00560/1.375`, `-0.000143/-0.035`.
  - `no_fb` Re means/Zmeans: `0.00290/0.576`, `0.00190/0.371`, `-0.000457/-0.091`, `0.00387/0.797`.
  - paired fb-nofb Re differences by window: `-0.00152`, `+0.00546`, `+0.00606`, `-0.00402`; none significant.
- Twenty 10k-window sign check:
  - `fb_norefine` positive mean Re in `12/20`;
  - `no_fb` positive mean Re in `9/20`;
  - paired mean differences positive/negative `10/10`.
- Counter stratification:
  - `fb_norefine` Re correlates with fallback trigger count (`r=0.6600`) and unresolved failures (`r=0.5398`).
  - `no_fb` Re also correlates strongly with unresolved failures (`r=0.7251`).
  - Quartiles show a hard-region ladder in both methods, so counters are not direct proof of QN route bias.
- Current interpretation:
  - The apparent large-ensemble issue is better explained as hard-region/long-autocorrelation finite-window sampling than as a clean fb-only route bug.
  - More seeds alone may shrink SE around the same finite-window offset; the next decisive test should use longer-cycle/windowed continuation.

## 2026-05-12 Output Namespace Freeze Before Modernization-Head Redo

- User paused further old-code production diagnostics because modernization reached the pre-redo decision point.
- Added `runbooks/OUTPUT_NAMESPACE_FREEZE_20260512.md` and `state/OUTPUT_INVENTORY_20260512.tsv`.
- Registered current remote official DFO-LS provisional roots as `frozen_pre_redo_provisional`:
  - `official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb`
  - `official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb`
  - `official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4`
  - `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`
- Updated `codex/state/DATASETS.tsv` with the frozen pre-redo provisional rows.
- Naming rule for next modernization-head redo:
  - campaign pattern `official_dfols_preredo_YYYYMMDD_<shortsha>_<N>seed_<C>cyc_t035_L2_nstep20_rg_nofb_withfb`
  - output root `output/production_comparison/pre_redo/<campaign>`
  - log root `output/logs/production_comparison/pre_redo/<campaign>`
- Do not extend old `provisional/official_dfols_*` roots in place and do not combine frozen pre-redo data with modernization-head redo data in one estimator.
