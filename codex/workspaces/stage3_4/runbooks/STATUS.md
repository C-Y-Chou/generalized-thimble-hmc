# Stage3_4 Task Status

Updated: 2026-05-08 12:17 JST

## Active objective
- Complete supplemental `fb_norefine` pre-production validation before full 1024-seed production planning.

## Live jobs (current)
- 14175.anode01 on C12: `s34_preval_fbnr`, running as of 2026-05-08 12:17 JST.

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

## Next actions
1. Wait for supplemental job `14175.anode01` to finish.
2. Inspect report `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine/s34_preprod_validation_20260508_p28_rg_fb_norefine_report.md`.
3. Compare `fb_norefine` against prior `fb` and `no_fb` validation before full 1024-seed production.
4. If still acceptable, create full production PBS from a pushed clean commit and optimize queues.

## Supplemental validation in progress
- Label: `preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- Pushed branch: `codex/preprod-hardening`
- Pushed commit used by PBS gate: `6b552ffb64e606a919963128e9e55747eb75907b`
- Config: `docs/stage_3_4_t035_paired_10k_10seed.json`
- Method: `fb_norefine`
- Key settings: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, `QN_POST_NEWTON_REFINE_ENABLED=0`.
- PBS: `codex/workspaces/stage3_4/tasks/pbs/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine.pbs`
- Output root: `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- Logs root: `output/logs/stage3_4_preprod_validation/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
