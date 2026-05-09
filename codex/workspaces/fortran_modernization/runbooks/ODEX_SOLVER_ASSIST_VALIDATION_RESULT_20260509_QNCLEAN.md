# ODEX Solver-Internal Assist Validation Result - 2026-05-09 QN-Clean

Status: staged 10k -> 50k -> 100k validation supports the revised canonical flow policy: ODEX primary integration, solver-internal ODE assist for NT/QN residual evaluation, and strict final proposal flow.

## Source And Protocol

- Production worktree: `/lustre1/home/cychou/TLTM`
- Branch: `codex/preprod-hardening`
- Commit: `704e2aafa650dc7ea5a404f60c9e37d7c841f49d`
- Flow policy label: `odex_primary_solver_internal_assist_final_flow_strict`
- Route: canonical p28 `fb_norefine`
- Reverse gate: enabled, `tol=1e-8`
- Constraint/QN tolerances: `ct=1e-13`, `QN=1e-13`

## Output Artifacts

- 10seed x 10k:
  `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_10seed_10k_qnclean_solverassist_fb_norefine_ct1e13_qn1e13`
- 32seed x 50k:
  `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_32seed_50k_qnclean_solverassist_fb_norefine_ct1e13_qn1e13`
- 128seed x 100k:
  `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_128seed_100k_qnclean_solverassist_fb_norefine_ct1e13_qn1e13`

## Physical Observable Summary

| run | n_seeds | cycles/seed | mean Re<O> | mean Im<O> | Zmean Re | Zmean Im | P95 Re | P95 Im |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| solver-assist 10k | 10 | 10000 | -0.0174339924 | 0.0469555722 | -0.377116 | 1.759907 | 0.9000 | 1.0000 |
| solver-assist 50k | 32 | 50000 | 0.0010218698 | 0.0005344565 | 0.079698 | 0.077923 | 0.9375 | 0.9688 |
| solver-assist 100k | 128 | 100000 | -0.0013054876 | 0.0005283082 | -0.315388 | 0.214810 | 0.9688 | 0.9688 |

The 50k and 100k physical observables remain compatible with the target `Re<virial>=0`, `Im<virial>=0`.

## Robustness Comparison

| run | unresolved | mean projection failures | mean unresolved failures | mean QN probe successes | RG rejects | pair0 accept | mean runtime |
|---|---:|---:|---:|---:|---:|---:|---:|
| ODEX-only 50k | 40715 | 2053.15625 | 1272.34375 | 4294.1875 | 24986 | 0.438705 | 3605.528 |
| solver-assist 50k | 28206 | 1660.40625 | 881.4375 | 4133.65625 | 24927 | 0.438588 | 4130.746 |
| ODEX-only 100k | 326569 | 4133.6015625 | 2551.3203125 | 8606.46875 | 202530 | 0.438907 | 7127.015 |
| solver-assist 100k | 224580 | 3321.1875 | 1754.53125 | 8252.265625 | 200530 | 0.438762 | 8170.916 |

Compared with ODEX-only, solver-internal assist reduces 100k unresolved failures by `101989` while keeping reverse-gate rejects and pair0 acceptance stable.

The solver-assist 100k unresolved count `224580` is essentially back to the earlier pre-ODEX `fb_norefine` characterization level `224439`. This indicates that the ODEX-only robustness loss was mostly caused by removing solver-internal progress assistance, not by a physics-relevant change in the final proposal distribution.

## ODE Assist Counter Summary

| run | files | attempts | success | failure | max_steps | invalid | h_min | success rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| solver-assist 10k | 10 | 670077 | 665034 | 5043 | 2 | 0 | 670075 | 0.992474 |
| solver-assist 50k | 32 | 10768368 | 10688182 | 80186 | 31 | 0 | 10768337 | 0.992554 |
| solver-assist 100k | 128 | 85813922 | 85176297 | 637625 | 236 | 0 | 85813686 | 0.992570 |
| ODEX-only 50k | 32 | 354554 | 0 | 354554 | 40 | 0 | 354514 | 0.000000 |
| ODEX-only 100k | 128 | 2862514 | 0 | 2862514 | 346 | 0 | 2862168 | 0.000000 |

The assist path is heavily used and succeeds at about `99.26%`, almost entirely on h-min boundary cases. Invalid RHS remains zero in these aggregate counters.

## Interpretation

Pure ODEX-only passed the physical-observable gate but introduced a large and unnecessary solver robustness loss. Restoring assist only inside NT/QN residual evaluation recovers the pre-ODEX `fb_norefine` robustness level without allowing hidden rescue to finalize the physical proposal.

The revised canonical target is therefore:

- ODEX remains the primary flow integrator.
- Solver-internal ODE assist is allowed only as a residual-evaluation progress aid inside Newton/QN contexts.
- Final proposal construction must remain strict: final `flow(...)` cannot be completed by assist.
- Legacy terminology such as "final resort" should be renamed during the state/status propagation refactor to avoid implying final proposal acceptance.

## Decision

Do not promote pure ODEX-only as the final production policy.

Promote `ODEX primary + solver-internal assist + strict final proposal` as the current canonical flow-policy candidate for further modernization and official baseline preparation.

## Follow-Up

- Update roadmap wording from "ODEX-only" to "ODEX primary with solver-internal assist" where it refers to the current canonical candidate.
- Keep the pure ODEX-only validation result as a comparison artifact, not as the final decision.
- Do not delete assist-related code until state/status propagation is redesigned and tests prove final proposal strictness.
- Treat assist counters, reverse-gate replay counters, proposal failure, and rejected stay-put transitions as part of the upcoming state/information propagation refactor.
