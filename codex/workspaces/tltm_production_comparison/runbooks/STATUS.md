# TLTM Production Comparison Task Status

NOTE: This is a long historical status file from the legacy `stage3_4` workspace. For new conversations, read `context/STATE_BRIEF.md` and `runbooks/SOFT_DECOUPLING_AND_PROVISIONAL_CONTRACT.md` first, then use `codex/state/JOBS.tsv`, `codex/state/DATASETS.tsv`, and `codex/state/WORKTREES.tsv` for current cleanup/scheduling decisions.

Updated: 2026-05-11 JST

## Superseding Current Position

- Canonical workspace name: `tltm_production_comparison`.
- Legacy alias: `stage3_4`.
- This workstream is provisional-discussion production comparison, separate from `fortran_modernization`.
- Current canonical production-comparison roles are `nofb` and `withfb`; the current legacy raw mapping is `nofb == no_fb` and `withfb == fb_norefine`.
- Historical rows below are retained for traceability. They are not a final publication dataset contract.

## Official DFO-LS Redo Position

- Production redo should be launched from the synchronized
  `codex/fortran-modernization` worktree
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`, at the commit
  that contains the embedded official DFO-LS backend.
- Before chunk submission, run
  `codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preflight_build.pbs`
  on the target tree. It creates/updates `.venv-dfols`, verifies official
  `DFO-LS==1.6.5`, prepares local Python headers under `.deps/` if the Rocky
  node lacks `python3.11-devel`, and builds `run_tltm_stage2` plus
  `evaluate_expectations` with `ENABLE_OFFICIAL_DFOLS=1`.
- Chunk jobs now set `QN_SOLVER_BACKEND=official_dfols`,
  `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`, and
  `TLTM_OFFICIAL_DFOLS_PYTHONPATH` from `.venv-dfols`.
- The old live-job list below is historical; check `qstat -u cychou` before
  reusing or fast-forwarding any production tree.

## Active objective
- Redo production comparison from the official DFO-LS backend after tree sync
  and preflight build.

## Live jobs (current)
- 128seed/100k compute chunks are running.
- Valid `no_fb` chunks:
  - `14250.anode01`: chunk `00`, queue `C8`, offset `0`, state `R`.
  - `14251.anode01`: chunk `01`, queue `C8`, offset `16`, state `R`.
  - `14252.anode01`: chunk `02`, queue `C8`, offset `32`, state `R`.
  - `14266.anode01`: chunk `03`, queue `C8`, offset `48`, state `R`.
  - `14267.anode01`: chunk `04`, queue `C8`, offset `64`, state `R`.
  - `14255.anode01`: chunk `05`, queue `G`, offset `80`, state `R`.
  - `14256.anode01`: chunk `06`, queue `F`, offset `96`, state `R`.
  - `14268.anode01`: chunk `07`, queue `G`, offset `112`, state `R`.
- Valid `fb_norefine` chunks:
  - `14258.anode01`: chunk `00`, queue `C8`, offset `0`, state `R`.
  - `14259.anode01`: chunk `01`, queue `C8`, offset `16`, state `R`.
  - `14260.anode01`: chunk `02`, queue `C8`, offset `32`, state `R`.
  - `14269.anode01`: chunk `03`, queue `C8-LONG`, offset `48`, state `R`.
  - `14270.anode01`: chunk `04`, queue `C8-LONG`, offset `64`, state `R`.
  - `14263.anode01`: chunk `05`, queue `G`, offset `80`, state `R`.
  - `14264.anode01`: chunk `06`, queue `G`, offset `96`, state `R`.
  - `14271.anode01`: chunk `07`, queue `C8-LONG`, offset `112`, state `R`.
- Initial C12 attempts were cancelled/replaced because they remained queued with `Qlist`: `14253`, `14254`, `14257`, `14261`, `14262`, `14265`.
- Merge/report job: pending submission after this status update.
- Invalid launch kept for traceability: `14179.anode01` (`no_fb` on C17) exited immediately with `Exit_status=127`; it is not part of the valid dataset.

## Current judgment experiment
- Label: `judgment_20260508_32seed_50k_p28_rg`
- Pushed branch: `codex/preprod-hardening`
- Pushed commit used by compute jobs: `c04100faea5da0cbad73b6528f2f69e0dcc87d7a`
- Config: `docs/stage_3_4_t035_paired_32seed_50k_rg.json`
- Methods/sets:
  - `no_fb`
  - `fb` as `fb_refine`
  - `fb_norefine`
- Common settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, near/non-near/global rescue off.
- Budget: 32 matched seeds x 50k cycles per set.
- Parallelism: 20 workers per set, so 32 seeds run as two waves.
- Output root: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg`
- Logs root: `output/logs/stage3_4_judgment_20260508_32seed_50k_p28_rg`
- Combined report after dependency job: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg/REPORT.md`
- Completion:
  - 32/32 seeds completed for each set.
  - Combined report: `output/tests/stage3_4/judgment_20260508_32seed_50k_p28_rg/REPORT.md`

## Current judgment result
- `no_fb`: `Zmean_re=0.367395`, `Zmean_im=-0.897098`, mean Re `<O>=0.00454804`, mean Im `<O>=-0.00646140`, failures `118503`, RG rejects `17228`, mean runtime `5048.5s`.
- `fb_refine`: `Zmean_re=-0.161417`, `Zmean_im=0.346142`, mean Re `<O>=-0.00201207`, mean Im `<O>=0.00240530`, failures `28393`, RG rejects `25044`, mean runtime `6059.6s`, post-refine `49321/49634`, skip `80576`.
- `fb_norefine`: `Zmean_re=0.0697449`, `Zmean_im=-0.0671524`, mean Re `<O>=0.000888348`, mean Im `<O>=-0.000457797`, failures `28182`, RG rejects `24909`, mean runtime `5535.3s`, post-refine `0/0`.
- Paired seed check:
  - `fb_refine - no_fb`: paired mean diff `dRe=-0.006560`, `dIm=+0.008867`; absolute closer-to-zero wins `17/32` Re and `16/32` Im.
  - `fb_norefine - no_fb`: paired mean diff `dRe=-0.003660`, `dIm=+0.006004`; absolute closer-to-zero wins `17/32` Re and `18/32` Im.
  - `fb_refine - fb_norefine`: paired mean diff `dRe=-0.002900`, `dIm=+0.002863`; absolute closer-to-zero wins `17/32` Re and `14/32` Im.
- Interpretation:
  - Both fallback variants reduce unresolved failures by about `90k` events versus `no_fb`.
  - Both fallback variants increase total RG rejects by about `7.7k-7.8k` versus `no_fb`, but RG reject rate remains about `3.9e-4`.
  - In this 32seed/50k judgment run, `fb_norefine` is the cleanest aggregate Zmean and is faster than `fb_refine`.
  - This reverses the earlier 10seed/10k preference for `fb_refine`; do not commit to full production until we decide whether this is finite-sample noise, post-refine side effect, or expected behavior.

## Next intermediate scale-up
- Label: `judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine`
- Config: `docs/stage_3_4_t035_paired_128seed_100k_rg_nofb_fbnorefine.json`
- Methods: `no_fb`, `fb_norefine`
- Scale: 128 matched seeds x 100k cycles per method.
- Seed generation: `seed_start=20260421`, `seed_stride=97`, `n_seeds=128`.
- Chunking plan: 8 chunks per method, 16 seeds/chunk, 16 workers/chunk.
- Queue plan avoids multi-node C24/C36 queues because this runner is single-node/non-MPI.
- Queue distribution: `C8 x6`, `C12 x6`, `G x3`, `F x1` across both methods.
- Actual running distribution after C12 requeue: `C8 x8`, `G x4`, `C8-LONG x3`, `F x1`.
- Common settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, near/non-near/global rescue off.
- Output root: `output/tests/stage3_4/judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine`
- Logs root: `output/logs/stage3_4_judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine`
- Expected runtime:
  - per chunk: `no_fb ~2.8h`, `fb_norefine ~3.1h` from measured 32seed/50k runtime, because each chunk runs one seed wave.
  - if all chunks start promptly, expected compute completion is about 3.5-4h after launch, plus merge/report.

## Protocol
- Validation label: `preprod_validation_20260507_10seed_10k_p28_rg`
- Pushed branch: `codex/preprod-hardening`
- Pushed commit: `fe82bc433784991065db35b900325b1c87e096f0`
- Config: `docs/stage_3_4_t035_paired_10k_10seed.json`
- Methods: `both` (`no_fb` + `fb`)
- Key settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, post-refine enabled by `fb` method spec.
- PBS: `codex/workspaces/tltm_production_comparison/tasks/pbs/preprod_validation_20260507_10seed_10k_p28_rg.pbs`
- Output root: `output/tests/stage3_4/preprod_validation_20260507_10seed_10k_p28_rg`
- Logs root: `output/logs/stage3_4_preprod_validation/preprod_validation_20260507_10seed_10k_p28_rg`

## Validation result
- Status: PASS for proceeding to production planning, with small-sample caveat.
- Rows: 20 per-seed rows = 10 seeds x 2 methods.
- Manifests: 20 per-seed `run_manifest.json` files present; required RG/p28/tol env values checked.
- Consistency: `projection_failure_count = unresolved_failure_count + reverse_gate_total_reject_count` for all rows.
- Aggregated result:
  - `fb`: `Zmean_re=-0.214`, `Zmean_im=1.387`, failures `1787`, RG rejects `1594`, mean runtime `956.9s`.
  - `no_fb`: `Zmean_re=1.133`, `Zmean_im=-0.594`, failures `7451`, RG rejects `1132`, mean runtime `817.5s`.
- Interpretation:
  - No catastrophic bias or counter/reporting regression from the RG/path hardening.
  - `fb` strongly reduces unresolved failures versus `no_fb`; runtime cost is about `+17%`.
  - `fb` has slightly higher RG rejects but still small relative to RG candidates.

## Supplemental `fb_norefine` result
- Job `14175.anode01` completed on C12 with `Exit_status=0`.
- Output root: `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- Report: `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine/s34_preprod_validation_20260508_p28_rg_fb_norefine_report.md`
- Manifest check: 10 `run_manifest.json` files present; all have RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, `QN_POST_NEWTON_REFINE_ENABLED=0`.
- Consistency: `projection_failure_count = unresolved_failure_count + reverse_gate_total_reject_count` for all rows.
- Aggregated result:
  - `fb_norefine`: `Zmean_re=-0.338`, `Zmean_im=1.730`, failures `1769`, RG rejects `1585`, mean runtime `961.7s`, post-refine `0/0`, skip `0`.
- Paired against previous `fb` refine on the same 10 seeds:
  - Mean delta `fb_norefine - fb`: `dRe=-0.00540`, `dIm=+0.00966`, `dRuntime=+4.87s`, `dUnresolved=-1.8`, `dRG=-0.9`.
  - Geometry counters are nearly unchanged/slightly better, but `Zmean_im` worsens from `1.387` to `1.730` and runtime does not improve.
- Interpretation:
  - Current production candidate remains `fb` with post-refine enabled, not `fb_norefine`.
  - `fb_norefine` is useful as a diagnostic/control, but does not justify disabling post-refine for full production.

## Next actions
1. Discuss whether production should be only `fb` refine, or include `fb_norefine` as a smaller diagnostic/control.
2. If production proceeds, create full 1024-seed PBS from a pushed clean commit and optimize queues.
3. Keep PBS self-checks: branch/SHA/dirty-tree gate must remain enabled.

## Supplemental validation completed
- Label: `preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- Pushed branch: `codex/preprod-hardening`
- Pushed commit used by PBS gate: `6b552ffb64e606a919963128e9e55747eb75907b`
- Config: `docs/stage_3_4_t035_paired_10k_10seed.json`
- Method: `fb_norefine`
- Key settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, `QN_POST_NEWTON_REFINE_ENABLED=0`.
- PBS: `codex/workspaces/tltm_production_comparison/tasks/pbs/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine.pbs`
- Output root: `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- Logs root: `output/logs/stage3_4_preprod_validation/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
