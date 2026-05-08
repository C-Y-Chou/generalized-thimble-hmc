# Stage3_4 Task Status

Updated: 2026-05-08 12:54 JST

## Active objective
- Run minimal 32seed/50k judgment experiment for three sets before choosing production seed/cycle counts.

## Live jobs (current)
- `14180.anode01`: `fb_refine`, queue `G`, state `R`, 20 workers, started 2026-05-08 12:53 JST.
- `14181.anode01`: `fb_norefine`, queue `C8`, state `R`, 20 workers, started 2026-05-08 12:49 JST.
- `14182.anode01`: `no_fb`, queue `F`, state `R`, 20 workers, started 2026-05-08 12:53 JST.
- `14188.anode01`: merge/report job, queue `C8`, state `H`, dependency `afterok:14180:14181:14182`.
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
- ETA:
  - Based on 10seed/10k measured runtime scaled to 50k and two waves, expected compute finish is around 2026-05-08 15:50-16:20 JST.
  - Merge/report should finish a few minutes after all three compute jobs exit successfully.

## Protocol
- Validation label: `preprod_validation_20260507_10seed_10k_p28_rg`
- Pushed branch: `codex/preprod-hardening`
- Pushed commit: `fe82bc433784991065db35b900325b1c87e096f0`
- Config: `docs/stage_3_4_t035_paired_10k_10seed.json`
- Methods: `both` (`no_fb` + `fb`)
- Key settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, post-refine enabled by `fb` method spec.
- PBS: `codex/workspaces/stage3_4/tasks/pbs/preprod_validation_20260507_10seed_10k_p28_rg.pbs`
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
- PBS: `codex/workspaces/stage3_4/tasks/pbs/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine.pbs`
- Output root: `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- Logs root: `output/logs/stage3_4_preprod_validation/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
