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

## 2026-05-12 18:27 JST
- Goal: sync production-comparison worktree to current modernization-head official DFO-LS code and submit the first pre-redo production gate.
- Campaign: `official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Dataset id: `prodcomp_preredo_a22de1c_10seed_10k_20260512`.
- Config: `docs/production_comparison_official_dfols_preredo_10seed_10k_nofb_withfb.json`.
- Remote worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Branch/commit: `codex/tltm-production-comparison-official-dfols` at `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.
- Methods: matched `no_fb` canonical `nofb` and `fb_norefine` canonical `withfb`.
- Env vars: official DFO-LS backend, `stable_gate77`, RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, `INTODE_SOLVER_ASSIST_ENABLED=0`.
- Output dir: `output/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Logs dir: `output/logs/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Submission: preflight `14950`, nofb method job `14951`, withfb method job `14952`, merge/report job `14953`.
- Status at 18:32 JST refresh: preflight no longer live in queue; `14951` and `14952` running on `C8`; `14953` held for dependencies.
- Next action: monitor `14951/14952/14953`, read back merged report, and do not sync/fast-forward the production worktree while these active pinned jobs remain.
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

## 2026-05-12 Modernization-Head Pre-Redo 10seed/10k Readback

- Checked remote PBS at 18:45 JST for campaign `official_dfols_preredo_20260512_a22de1c_10seed_10000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Production worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Branch/commit: `codex/tltm-production-comparison-official-dfols`, `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.
- Jobs:
  - method job `14951`: `Exit_status=0`;
  - method job `14952`: `Exit_status=0`;
  - merge job `14953`: `Exit_status=0`.
- Output root exists with `REPORT.md`, `combined_summary_table.csv`, per-method reports, per-method aggregate tables, and per-method per-seed tables.
- Readback:
  - `nofb/no_fb`: 10 rows, Zmean Re/Im `1.5006/1.2686`, unresolved failures `16821`, RG rejects `889`, mean runtime `651.569s`.
  - `withfb/fb_norefine`: 10 rows, Zmean Re/Im `1.2826/2.5434`, unresolved failures `4004`, RG rejects `909`, mean runtime `1052.808s`.
  - `withfb - nofb`: mean shift Re `-0.0398467`, Im `+0.056344`; Zmean shift Re `-0.2180`, Im `+1.2747`; unresolved failures `-12817`; RG rejects `+20`; mean runtime `+401.239s`.
- Current interpretation: this is a completed pre_redo smoke-scale production readback, not final production evidence. Choose the next scale deliberately before further production sync or extension.

## 2026-05-12 Modernization-Head Pre-Redo 32seed/50k Submission

- Submitted next scaling gate after user approval.
- Campaign: `official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Dataset id: `prodcomp_preredo_a22de1c_32seed_50k_20260512`.
- Production worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Branch/commit: `codex/tltm-production-comparison-official-dfols`, `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.
- Config: `docs/production_comparison_official_dfols_20260511_32seed_50k_nofb_withfb.json`; same-scale config reused, with output/log roots overridden to `pre_redo`.
- Output root: `output/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Log root: `output/logs/production_comparison/pre_redo/official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Queue plan: `C8` for preflight, eight 8-core method chunks, and merge. `qstat -Qf` showed `C8` empty/enabled/started before submission.
- Jobs:
  - preflight `14954`;
  - nofb chunks `14955`, `14956`, `14957`, `14958`;
  - withfb chunks `14959`, `14960`, `14961`, `14962`;
  - merge `14963`.
- Submission check: preflight entered `E` with `Exit_status=0`; chunk and merge jobs remained dependency-held at the 19:02 JST refresh.
- Follow-up at 19:06 JST: preflight `14954` finished with `Exit_status=0`; all eight chunks `14955`-`14962` were running on `C8`; merge `14963` remained held on chunk dependencies.

## 2026-05-12 Modernization-Head Pre-Redo 32seed/50k Readback

- Jobs `14954`-`14963` all exited with `Exit_status=0`; merged `REPORT.md` and `combined_summary_table.csv` are present.
- Per-seed rows: `nofb=32`, `withfb=32`.
- Aggregate readback:
  - `nofb/no_fb`: mean Re/Im `0.09549068827299285/-0.0017842285424940483`, Zmean Re/Im `5.990283893906403/-0.17601025889394464`, failures `265127`, RG rejects `15086`, mean runtime `3389.99086840625`.
  - `withfb/fb_norefine`: mean Re/Im `0.060792566742816925/0.0112710435756147`, Zmean Re/Im `4.946849130584964/1.794977218111019`, failures `67061`, RG rejects `14991`, mean runtime `5271.5809374375`.
- Direct paired method comparison:
  - Re `withfb - nofb = -0.0346981215301759 +/- 0.0173612518833185`, paired t `-1.9986`, positive/negative seeds `11/21`.
  - Im `withfb - nofb = +0.0130552721181087 +/- 0.0104624431584951`, paired t `1.24782`, positive/negative seeds `17/15`.
- Same-seed comparison to frozen 2026-05-11 32seed/50k:
  - `nofb` Re new-minus-frozen `+0.0753018961385964 +/- 0.0168897541897311`, paired t `4.45844`.
  - `withfb` Re new-minus-frozen `+0.0627863381730859 +/- 0.0142766343346361`, paired t `4.39784`.
- Attribution check:
  - frozen 2026-05-11 commit `d3f133d1fd7de2ec6a5b7ac27840c01287be5be7` had solver assist enabled by default in `src/physics/solve_flow.f90`;
  - frozen 32seed/50k PBS did not export `INTODE_SOLVER_ASSIST_ENABLED=0`;
  - a22de1c introduced runtime assist-policy parsing with default off;
  - this pre_redo campaign explicitly recorded `ASSIST_POLICY=INTODE_SOLVER_ASSIST_ENABLED=0`.
- Interpretation: the gate completed cleanly and withfb still reduces unresolved failures. The large positive Re shift in both methods is best attributed to assist-on frozen line vs assist-off pre_redo line, so the next scale-up decision is an assist-policy decision rather than an unexplained production drift.

## 2026-05-12 JST - Assist-Off DFO-LS Tuning Campaign Start

- Wrote `runbooks/DFOLS_ASSIST_OFF_TUNING_CAMPAIGN_20260512.md`.
- Added PBS worker `tasks/pbs/dfols_assist_off_tuning_phase_ab_20260512.pbs`.
- Submitted Phase A/B job `14984.anode01` from production worktree commit `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.
- Job label: `dfols_assist_off_tuning_20260512_a22de1c_phaseAB_10s10k_c200s10_m5`.
- Output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseAB_10s10k_c200s10_m5`.
- Log root: `output/logs/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseAB_10s10k_c200s10_m5`.
- Protocol: assist off, current commit, capture 10 seeds x 10k for `no_fb` and `fb_norefine`, then replay a coarse official DFO-LS parameter matrix. No solver assist, no external rescue wrapper.

## 2026-05-12 JST - Assist-Off DFO-LS Tuning Phase A/B Readback

- Phase A/B job `14984.anode01` exited `1` because the first aggregate parser did not handle blank `dfols_nf` rows from replay errors.
- Stage3 capture and all 100 replay CSVs were complete; robust aggregate recovery wrote `REPORT.md` and `coarse_summary.csv`.
- Captured QN attempt dirs materialized for `fb_norefine` only; `no_fb` produced no QN attempt case dirs in this campaign.
- Stable baseline replay: `stable_gate77` success `40/50`, embedded-converged regressions `0`, error rows `3`, nf mean/p95/max `91.2128/250/250`.
- Best coarse candidate: `rho050_m500` success `45/50`, embedded-converged regressions `0`, error rows `4`, hard successes `5`, nf mean/p95/max `85.5/262.75/500`.
- Submitted Phase C embedded Stage3 holdout job `15005.anode01` for `rho050_m500` at 10 seeds x 10k, assist off, same nofb/withfb protocol.

## 2026-05-12 JST - Assist-Off DFO-LS Tuning Phase C Readback and Phase D Submit

- Phase C job `15005.anode01` completed with `Exit_status=0`.
- Candidate: `rho050_m500` (`npt=4`, `maxfun=500`, `noise=true`, `rhobeg=0.050`, `rhoend=1e-16`, `model.abs_tol=1e-30`, `model.rel_tol=0`).
- Output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseC_rho050_m500_10s10k`.
- `no_fb` was an exact control match vs `stable_gate77`: failures `16821 -> 16821`, RG rejects `889 -> 889`, Zmean unchanged.
- `fb_norefine` improved unresolved failures `4004 -> 2171`, with every seed improved.
- `fb_norefine` costs/caveats: RG rejects `909 -> 1550`, mean runtime `1018.32s -> 1040.68s`, Zmean Re `1.2826 -> -0.5002`, Zmean Im `2.5434 -> 3.9564`.
- Decision: promote to 32seed/50k confirmation because the solver-local improvement transfers to embedded Stage3, but do not call it verified until the larger-scale observable check resolves the Im Zmean caveat.
- Submitted Phase D label `dfols_assist_off_tuning_20260512_a22de1c_phaseD_rho050_m500_32s50k`.
- Phase D jobs: chunks `15006`-`15013` running on `C8`; merge `15014` held on afterok.

## 2026-05-13 JST - Assist-Off DFO-LS Tuning Phase D Readback

- Phase D jobs `15006`-`15014` all completed with `Exit_status=0`.
- Output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseD_rho050_m500_32s50k`.
- `REPORT.md` and `combined_summary_table.csv` are present; per-method seed rows are `32/32`.
- `no_fb` is an exact control match versus stable assist-off baseline for counters and observables: failures `265127 -> 265127`, RG rejects `15086 -> 15086`, Zmean Re/Im unchanged `5.9903/-0.1760`.
- `fb_norefine` solver-local tail improves strongly: unresolved failures `67061 -> 33872`, with all `32/32` seeds improved.
- Observable means also improve: `fb_norefine` mean Re/Im `0.0607926/0.0112710 -> 0.0434491/0.00824623`; Zmean Re/Im `4.9468/1.7950 -> 3.3284/1.2868`.
- Reverse-gate rejects worsen `14991 -> 24280`, all `32/32` seeds increased; P68/P95 worsen; runtime increases `5271.58s -> 5425.29s`.  Per user correction, RG rejects and P68/P95 are diagnostics, not blockers for this campaign.
- Corrected verdict: `rho050_m500` verifies real assist-off official DFO-LS solver-local improvement and is positive under the observable-mean criterion.  The remaining issue is whether the improved mean Re/Im, especially Re with `Zmean_re=3.3284`, persists at the next scale.

## 2026-05-13 JST - Assist-Off Tuning Hard Gate Correction

- User correction: solving the no-assist problem likely requires tuned assist-off failures to reach the same scale as assist-on, ideally equal or lower.
- Same-scale 32seed/50k `fb_norefine` failure references:
  - assist-on/default frozen: `19579`;
  - assist-off stable: `67061`;
  - assist-off `rho050_m500`: `33872`.
- Updated interpretation: `rho050_m500` is a real improvement, but it has not solved the no-assist problem because it remains above assist-on failure parity.
- Next tuning gates should target assist-on-scale failures while preserving the mean Re/Im improvement; RG rejects and P68/P95 remain diagnostics.

## 2026-05-13 JST - Assist-Off Tuning Phase E Focused Replay Submit

- Added PBS script `tasks/pbs/dfols_assist_off_focused_replay_phase_e_20260513.pbs`.
- Submitted job `15095.anode01` to `C12`; it started running on `cnode28`.
- Label: `dfols_assist_off_tuning_20260513_a22de1c_phaseE_fullreplay_focus`.
- Output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260513_a22de1c_phaseE_fullreplay_focus`.
- Log root: `output/logs/dfols_assist_off_tuning/dfols_assist_off_tuning_20260513_a22de1c_phaseE_fullreplay_focus`.
- Scope: reuse all captured Phase A/B `fb_norefine` QN attempts instead of the previous 5-case-per-seed coarse screen.
- Candidate family: focused `rho050_m500` neighborhood over `rhobeg`, `maxfun`, and `npt`; no solver assist, no external wrapper/rescue/backtracking.
- Hard target: find whether a candidate can plausibly reach same-scale assist-on failure parity (`19579`) while preserving mean Re/Im improvement.

## 2026-05-13 JST - Assist-Off Tuning Phase E Readback

- Job `15095.anode01` completed with `Exit_status=0`.
- Output root: `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260513_a22de1c_phaseE_fullreplay_focus`.
- Report artifacts: `REPORT.md` and `focused_summary.csv`.
- Replay scope: all captured Phase A/B `fb_norefine` QN attempts, `1994` attempts across 10 seed directories.
- Stable baseline replay: `1593/1994` successes.
- Anchor `rho050_m500`: `1706/1994` successes.
- Best focused candidate `rho050_m1000`: `1726/1994` successes, only `+20` over `rho050_m500`.
- Conclusion: parameter-only official DFO-LS tuning has saturated before assist-on failure parity.  Do not submit another embedded Stage3 candidate from this focused family; shift to assist/proposal-semantics design and audit.

## 2026-05-13 JST - Production Output Cleanup Before Rerun

- User synced the production worktree before cleanup.
- Verified remote execution worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Branch: `codex/tltm-production-comparison-official-dfols`.
- Commit: `6f98b5bfce60678293c163764e1cefe8307736ba`.
- `qstat -u cychou` returned no active jobs before cleanup.
- Removed raw output/log roots:
  - `output/production_comparison`;
  - `output/tests/dfols_assist_off_tuning`;
  - `output/logs/production_comparison`;
  - `output/logs/dfols_assist_off_tuning`.
- Recreated empty containers:
  - `output/production_comparison`;
  - `output/tests`;
  - `output/logs/production_comparison`;
  - `output/logs/dfols_assist_off_tuning`.
- Post-cleanup `du -sh output`: `24K`.
- Historical readbacks remain in runbooks/state, but the raw production-comparison and DFO-LS tuning artifacts are no longer present in the remote production output tree.

## 2026-05-13 JST - Formalized Assist Bridge 32seed/50k Submit

- Added formalized assist bridge run config: `docs/production_comparison_formalized_assist_bridge_32seed_50k_nofb_withfb.json`.
- Added PBS runtime templates:
  - `tasks/pbs/formalized_assist_bridge_32seed_50k_chunk.pbs`;
  - `tasks/pbs/formalized_assist_bridge_32seed_50k_merge.pbs`.
- Remote staging path: `output/pbs_scripts/formalized_assist_bridge_20260513_6f98b5b_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- Remote worktree stayed clean after staging because `output/` is git-ignored.
- Submitted C8 dependency chain:
  - preflight `15097.anode01`;
  - `no_fb` chunks `15098`-`15101`;
  - `fb_norefine` chunks `15102`-`15105`;
  - merge/report `15106`.
- Follow-up qstat/readback: preflight `15097.anode01` completed with `Exit_status=0`; chunk jobs `15098`-`15105` left dependency hold and are running on `C8`; merge `15106` remains held until all chunks finish.
- Policy: `INTODE_SOLVER_ASSIST_POLICY=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`; legacy `INTODE_SOLVER_ASSIST_ENABLED` is unset in the chunk jobs.
- Exact-gate contract: QN navigation assist may help find guesses, but certification residual, final flow, reverse gate, and Metropolis acceptance remain unassisted/exact.
- Primary readback after merge: mean Re/Im and unresolved failures, with assist-on failure reference `19579` and assist-off tuned Phase D reference `33872`.

## 2026-05-13 JST - Formalized Assist Bridge 32seed/50k Readback

- Jobs `15097`-`15106` all completed with `Exit_status=0`.
- Output root: `output/production_comparison/formalized_assist_bridge/formalized_assist_bridge_20260513_6f98b5b_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`.
- `REPORT.md` and `combined_summary_table.csv` are present; per-method rows are `32/32`.
- Policy audit:
  - chunk manifests set `INTODE_SOLVER_ASSIST_POLICY=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1` and unset legacy `INTODE_SOLVER_ASSIST_ENABLED`;
  - per-seed manifest resolved `no_fb` to `off`;
  - per-seed manifest resolved `fb_norefine` to `qn_navigation`;
  - `fb_norefine` has nonzero QN assist counters.
- Summary:
  - `no_fb`: mean Re/Im `0.12850514911944863/-0.00044150817736475457`, Zmean Re/Im `8.530632030235894/-0.04653856450252538`, failures `267455`, RG rejects `15112`.
  - `fb_norefine`: mean Re/Im `0.07133444361813597/-0.004686085466098856`, Zmean Re/Im `6.7549242962306515/-0.7868762110380288`, failures `67159`, RG rejects `15088`.
- Hard comparison:
  - assist-on/default same-scale `fb_norefine` failure reference: `19579`;
  - assist-off tuned Phase D reference: `33872`;
  - formalized bridge `fb_norefine`: `67159`, or `+47580` vs assist-on and `+33287` vs assist-off tuned.
- Verdict: current formalized `qn_navigation` policy is not enough.  It exercised QN assist, but behaved near the assist-off stable failure scale rather than old assist-on.  Do not scale this policy as-is.

## 2026-05-13 JST - QN Assist Preset Matrix Submit

- Goal: test whether `QN+assist` can replace the effective role of old `NT+assist`
  without assuming assist-off tuning rankings transfer to the assist-on residual landscape.
- Added PBS scripts:
  - `tasks/pbs/qn_assist_preset_matrix_10seed_10k_array_20260513.pbs`;
  - `tasks/pbs/qn_assist_preset_matrix_10seed_10k_merge_20260513.pbs`.
- Added runbook:
  `runbooks/QN_ASSIST_PRESET_MATRIX_20260513.md`.
- Remote execution scripts were copied outside the git worktree under
  `/lustre1/home/cychou/TLTM_job_scripts/qn_assist_preset_matrix_20260513`
  so the production worktree remains clean.
- Dataset label:
  `qn_assist_preset_matrix_20260513_6f98b5b_10s10k_v1`.
- Fixed protocol: `fb_norefine` only, 10 seeds x 10000 cycles,
  `INTODE_SOLVER_ASSIST_POLICY=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`,
  legacy `INTODE_SOLVER_ASSIST_ENABLED` unset, certification/final/RG/Metropolis unassisted.
- Matrix: 28 candidates scanning `npt`, `rhobeg`, `maxfun`, and two no-noise controls.
- Submitted on `C12`:
  - array job `15112[].anode01`;
  - initial merge job `15113.anode01`.
- Startup repair:
  - original array indices `20`-`23` exited immediately with `Exit_status=127`
    before candidate logs opened;
  - canceled old merge `15113.anode01`;
  - replacement jobs `15114`-`15117` cover indices `20`-`23`;
  - replacement merge `15118.anode01` depends on `afterany:15112[]` plus the four replacements.
- Second repair:
  - original array indices `24`-`27` also expired with `Exit_status=127` on `cnode36`;
  - replacements `15114`-`15117` also landed on `cnode36` and exited at startup;
  - canceled merge `15118.anode01`;
  - resubmitted indices `20`-`27` on `C8` as jobs `15119`-`15126`;
  - active merge is `15127.anode01`, depending on original array plus the C8 replacements.

## 2026-05-13 JST - QN Assist Preset Matrix Readback and NPT5 Refinement Submit

- Fixed the QN assist preset matrix readback merge path. The original merge
  looked under `candidate/fb_norefine/aggregated_summary_table.csv`, but
  `run_stage3_3_multiseed.py` writes aggregate/per-seed tables directly under
  the candidate output root.
- Reran the fixed readback on the remote completed outputs:
  - `28/28` candidate directories;
  - `28/28` aggregates;
  - `28/28` per-seed tables;
  - fixed `REPORT.md` now reports `Rows found: 28 / expected 28`.
- Best matrix candidate:
  `npt5_r0050_m500`, failures `1786`, mean Re/Im
  `+0.02644360/-0.00519660`, Zmean Re/Im `+0.5707/-0.2610`.
- Added next-round PBS scripts:
  - `tasks/pbs/qn_assist_npt5_refine_10seed_10k_array_20260513.pbs`;
  - `tasks/pbs/qn_assist_npt5_refine_10seed_10k_merge_20260513.pbs`.
- Added runbook:
  `runbooks/QN_ASSIST_NPT5_REFINE_20260513.md`.
- Dataset label:
  `qn_assist_npt5_refine_20260513_6f98b5b_10s10k_v1`.
- Refinement candidates: 12 local variants around `npt=5`, `rhobeg=0.050`,
  plus `npt=3/7` and `maxfun=750/1000` probes.
- Remote scripts staged under:
  `output/pbs_scripts/qn_assist_npt5_refine_20260513`.
- Submitted on `C8`:
  - array job `15130[].anode01`;
  - merge job `15131.anode01`;
  - dependency `afterany:15130[].anode01`.
- Initial qstat verification: all 12 array elements running on `C8`, merge held
  normally, C8 assigned ncpus `120`.

## 2026-05-13 JST - QN Assist NPT5 Refinement Readback

- Refinement matrix completed and merge job `15131.anode01` exited with status
  0.
- Output root:
  `output/tests/qn_assist_npt5_refine/qn_assist_npt5_refine_20260513_6f98b5b_10s10k_v1`.
- Rows: `12/12`, missing aggregates `0`.
- Best by failure:
  - `npt5_r0050_m1000`: failures `1544`, mean Re/Im
    `+0.106073/-0.058417`, Zmean Re/Im `+2.63/-2.43`, projected 32s50k
    failures `24704`.
  - `npt5_r0055_m500`: failures `1560`, mean Re/Im
    `+0.003135/+0.013989`, Zmean Re/Im `+0.08/+0.94`, projected 32s50k
    failures `24960`.
  - `npt5_r0060_m750`: failures `1565`, mean Re/Im
    `-0.008980/-0.014603`, Zmean Re/Im `-0.21/-0.64`, projected 32s50k
    failures `25040`.
- Interpretation: refinement improved failure density relative to the matrix
  anchor `1786/100k`, but did not reach the rough old-NT-assist parity target
  `~1224/100k`.  The lowest-failure candidate has poor mean Re/Im, while the
  cleaner candidates still project to about `25k` failures at 32seed/50k.

## 2026-05-13 JST - Legacy NT+QN Assist Baseline Control Submit

- Motivation: verify that the current tree is not starting from a wrong
  baseline by running current code with stable_gate77 and legacy-style NT+QN
  assist enabled.
- Added PBS script:
  `tasks/pbs/qn_assist_legacy_nt_control_10seed_10k_20260513.pbs`.
- Added runbook:
  `runbooks/QN_ASSIST_LEGACY_NT_CONTROL_20260513.md`.
- Control contract:
  - current commit `6f98b5bfce60678293c163764e1cefe8307736ba`;
  - method `fb_norefine`, 10 seeds x 10000 cycles;
  - QN preset stable_gate77 (`npt=4`, `rhobeg=0.018`, `maxfun=250`);
  - `INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic`;
  - `INTODE_SOLVER_ASSIST_ENABLED=1`.
- Important implementation detail: `run_stage3_3_multiseed.py` normally
  overrides `fb_norefine` to `INTODE_SOLVER_ASSIST_POLICY=qn_navigation`, so
  the control wrapper monkeypatches the runner method spec before invoking
  `main()`. This is a wrapper-only change to pass the intended env to Stage2.
- Two initial `v1` submissions failed before scientific work:
  - `15132.anode01`: precheck rejected pre-created output root;
  - `15133.anode01`: wrapper argv still had an unexpanded `--jobs` token.
- Active clean label:
  `qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`.
- Active job:
  `15134.anode01`, running on `C8` / `cnode24/0*10`.

## 2026-05-13 JST - Legacy NT+QN Assist Baseline Readback

- Job `15134.anode01` completed with `Exit_status=0`.
- Output root:
  `output/tests/qn_assist_legacy_nt_control/qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`.
- Rows: `10/10` per-seed rows; aggregate/report present.
- Manifest confirms:
  - `INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic`;
  - `INTODE_SOLVER_ASSIST_ENABLED=1`;
  - stable_gate77 (`npt=4`, `rhobeg=0.018`, `maxfun=250`).
- Summary:
  - failures `3394`;
  - projected 32seed/50k failures `54304`;
  - mean Re/Im `+0.0830396450/+0.0065988950`;
  - Zmean Re/Im `+3.5798/+0.2886`;
  - RG rejects `988`;
  - NT assist count `663829`;
  - QN assist count `2043`.
- Comparison: current stable QN-navigation anchor had failures `4055` and
  projected `64880`, with NT assist count `0` and QN assist count `3735`.
- Interpretation: enabling NT assist in current code does improve stable_gate77
  failure density, and NT assist is definitely exercised, but it does not
  reproduce old assist-on density.  The old assist-on advantage is not
  explained by "NT assist on" alone under current stable_gate77.

## 2026-05-13 JST - Split ODEX Sequence Control And NPT5 Scale-Up

- Implemented an ODEX sequence control switch in an independent remote worktree:
  `TLTM_ODEX_STEP_SEQUENCE=legacy` restores `2,4,6,12,18,36,...`; default
  remains the current IWORK3 sequence. Local package-contract tests passed for
  both default and legacy env mode.
- Remote ODEX control worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_odex_legacy_sequence_control`,
  branch `codex/odex-legacy-sequence-control`, commit
  `9fc3b80c9555a3892deb9486b809814292e6d326`.
- Submitted ODEX jobs:
  - preflight `15142.anode01`, completed `Exit_status=0`;
  - control `15143.anode01`, running on `C8`.
- Submitted npt5 scale-up for `npt5_r0055_m500`, 32 seeds x 50000 cycles,
  `fb_norefine` only, current default ODEX sequence:
  - active chunks `15149-15152.anode01`;
  - merge/readback `15153.anode01`, held afterok on chunks.
- Two npt5 wrapper attempts are explicitly discarded:
  - `15137-15140` exited before science and did not capture stdout;
  - `15144-15147` captured FileNotFoundError for unsynced
    `docs/production_comparison_formalized_assist_bridge_32seed_50k_nofb_withfb.json`.
    v3 uses the existing
    `docs/production_comparison_official_dfols_20260511_32seed_50k_nofb_withfb.json`.
- Runbook:
  `runbooks/SPLIT_ODEX_SEQUENCE_AND_NPT5_SCALEUP_20260513.md`.

## 2026-05-13 JST - ODEX Legacy Sequence Control Readback

- Job `15143.anode01` completed with `Exit_status=0`.
- Output root:
  `output/tests/odex_legacy_sequence_control/odex_legacy_sequence_ntqn_control_20260513_10s10k_v1`.
- Rows: `10/10`; aggregate, per-seed table, and report are present.
- Result:
  - failures `3364`;
  - RG rejects `823`;
  - mean Re/Im `+0.0855276962/-0.0200646225`;
  - Zmean Re/Im `+2.465072/-0.681683`;
  - mean runtime `1347.606s`.
- Baseline comparison: current IWORK3 NT+QN assist control had failures `3394`,
  RG rejects `988`, and mean Re/Im `+0.0830396450/+0.0065988950`.
- Interpretation: reverting ODEX nstep/ak sequence to `2,4,6,12,18,36,...`
  does not recover old assist-on density.  It changes details slightly, but is
  not the missing effect.

## 2026-05-14 JST - Production hold after assist resolution

- User reported the assist discrepancy/root-cause problem is solved and selected
  a tree-convergence plan.
- Keep the assist/QN/ODEX/npt5 readbacks as diagnostic evidence, but do not
  continue that diagnostic scale-up tree as the active production path.
- Active production-comparison state is hold-for-modernization-fix.
- Next production action: after modernization is fixed, refresh job/worktree
  state, sync the production-comparison tree to the selected fixed commit, then
  regenerate production from a clean namespace.

## 2026-05-15 JST - Codex State Cleanup After Assist Deletion Baseline

- Remote queue is empty and the production-comparison worktree is clean at
  commit `ae777294814955f7f7935fc386a6172bcd30651f`.
- The old `qn_assist_npt5_r0055_scale32_20260513_6f98b5b_32s50k_v3` row is no
  longer active; it was archived under `pre_rngv2_qn_assist_20260514` and
  superseded by the RNG-v2 diagnostics.
- The RNG-v2 all-navigation npt5_r0055 32seed/50k diagnostic is recorded as
  negative recovery evidence: `withfb` failures `25881`, mean Re
  `0.03420261820536729`, above the old assist-on failure reference `19579`.
- Current source line is modernization assist deletion against the official
  DFO-LS npt5_r0055 assist-off baseline, not continued assist scale-up.
