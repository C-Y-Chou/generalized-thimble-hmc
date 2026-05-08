# ODEX 10k Validation Result: QN-Clean Baseline

Updated: 2026-05-09 JST
Status: active 10k ODEX validation baseline for the next 50k gate; not final physics signoff.

## Run Identity

- Source branch: `codex/qn-error-handling-validation`
- Trajectory source commit: `64cc22c89b90c3d98e600d0958ccb7e8b93ae5af`
- Documentation/workflow commit after evaluation recovery: `667a5dc`
- Route: `fb_norefine`
- Core settings: p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`
- Original run output: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/tests/qn_error_handling/20260509_10seed_10k_fb_norefine_ct1e13_qn1e13`
- Canonical ODEX baseline copy: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`

This result supersedes `ODEX_10K_VALIDATION_RESULT_20260508.md` for forward decisions because the 2026-05-08 ODEX 10k run predates the QN invalid-evaluation handling cleanup.

## Aggregate Physical Readout

| quantity | QN-clean ODEX 10k |
|---|---:|
| mean Re<O> | -0.0386029170 |
| mean Im<O> | 0.0183377376 |
| std Re<O> | 0.248251963 |
| std Im<O> | 0.100655126 |
| Zmean Re<O> | -0.491730824 |
| Zmean Im<O> | 0.576115891 |
| mean Zp | 1.628874689 |
| median abs Zp | 1.597723886 |

Interpretation:

- The 10seed/10k aggregate remains compatible with the target `Re<O>=0`, `Im<O>=0` at this gate.
- These physical-observable values match the prior 2026-05-08 ODEX 10k aggregate to the recorded precision, but the prior result is no longer the governing baseline because it used the old QN error-handling semantics.

## Operational Diagnostics

| quantity | QN-clean ODEX 10k |
|---|---:|
| unresolved failures | 2521 |
| mean projection failures / seed | 408.5 |
| mean unresolved failures / seed | 252.1 |
| mean quasi probe success / seed | 863.8 |
| reverse-gate rejects | 1564 |
| mean pair0 accept rate | 0.44008 |
| mean total round trip | 2199.4 |
| mean hot-end hits / seed | 4997.6 |
| mean runtime / seed | 605.29 s |

Difference from the superseded 2026-05-08 ODEX 10k aggregate:

- `unresolved failures`: `2521` vs `2519`
- `reverse-gate rejects`: `1564` vs `1566`
- `mean pair0 accept rate`: unchanged at `0.44008` to reported precision
- Physical observables: unchanged to reported precision

## Judgment

The QN-clean 10k gate replaces the older ODEX 10k gate and can be used as the starting point for refreshed 50k validation, provided no further Fortran source changes are made before submission.

This remains provisional because:

- 10 seeds at 10k are only a first physical-observable gate.
- ODEX-only policy changes trajectories, so exact trajectory equality is not the criterion.
- Projection/unresolved failures remain the main watch item for 50k and 100k.

## Next Step

Refresh the ODEX 50k/100k PBS workflow before submission:

- Use the dedicated QN-clean worktree `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`.
- Do not rely on `git` inside compute-node PBS scripts.
- Build both `run_tltm_stage2` and `evaluate_expectations` inside the job or preflight explicitly.
- Use new `20260509`/`qnclean` output paths so the superseded 2026-05-08 outputs cannot be confused with the active baseline.
