# Stage3_4 Task Status

Updated: 2026-05-07 22:10:44 JST

## Active objective
- Pre-production validation after RG/path hardening before any full 1024-seed production run.

## Live jobs (current)
- 14130.anode01 on C12: `s34_preval_p28rg`, running as of 2026-05-07 22:10 JST.

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

## Next actions
1. Wait for job `14130.anode01` to finish.
2. Inspect report `output/tests/stage3_4/preprod_validation_20260507_10seed_10k_p28_rg/s34_preprod_validation_20260507_p28_rg_report.md`.
3. Gate full production on stable `Zmean`, `rev_rej`, unresolved failures, runtime, and presence of per-seed `run_manifest.json`.
