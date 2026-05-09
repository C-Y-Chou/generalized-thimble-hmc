# ODEX 50k/100k Validation Result: QN-Clean Baseline

Updated: 2026-05-09 JST
Status: historical comparison artifact. Staged ODEX-only validation passed for physical observables, but the later solver-internal assist validation showed the ODEX-only robustness loss is avoidable. Do not use this file to promote pure ODEX-only as the final production policy.

Superseding result:

- `ODEX_SOLVER_ASSIST_VALIDATION_RESULT_20260509_QNCLEAN.md`

## Run Identity

- Source branch: `codex/preprod-hardening`
- Validation source commit: `5b93aaa80f1f8cfe19de0cbd3c324acf138d2034`
- Route: `fb_norefine`
- Core settings: p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`
- 50k job: `14324.anode01`
- 100k chunk jobs: `14325.anode01` through `14332.anode01`
- 100k merge job: `14333.anode01`

Artifacts:

- 10k active baseline: `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`
- 50k output: `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_32seed_50k_qnclean_fb_norefine_ct1e13_qn1e13`
- 100k output: `/lustre1/home/cychou/TLTM/output/tests/odex_validation/20260509_128seed_100k_qnclean_fb_norefine_ct1e13_qn1e13`

## Aggregate Physical Readout

| run | n_seeds | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re | Zmean Im | mean Zp | median abs Zp |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10k QN-clean | 10 | -0.0386029170 | 0.0183377376 | 0.248251963 | 0.100655126 | -0.491731 | 0.576116 | 1.628875 | 1.597724 |
| 50k QN-clean | 32 | -0.0190826825 | 0.0037547361 | 0.074414258 | 0.037456248 | -1.450635 | 0.567061 | 1.134692 | 0.971677 |
| 100k QN-clean | 128 | 0.0017729074 | -0.0005999719 | 0.052066844 | 0.033771030 | 0.385239 | -0.200998 | 1.203462 | 1.144326 |

Interpretation:

- The 100k physical observables are compatible with the target `Re<O>=0`, `Im<O>=0`.
- The 50k real-part Zmean is the largest aggregate deviation in the staged sequence, but it does not persist at 100k.
- Seed-level spread remains present, including a largest 100k per-seed `Zp_abs_max=3.49`, but the aggregate mean does not show a physics-significant bias.

## Operational Diagnostics

| run | unresolved failures | projection failures | reverse-gate rejects | mean pair0 accept | mean runtime / seed |
|---|---:|---:|---:|---:|---:|
| 10k QN-clean | 2521 | 4085 | 1564 | 0.440080 | 605.29 s |
| 50k QN-clean | 40715 | 65701 | 24986 | 0.438705 | 3605.53 s |
| 100k QN-clean | 326569 | 529101 | 202530 | 0.438907 | 7127.02 s |

Relative to the pre-ODEX 128seed/100k `fb_norefine` characterization:

| metric | pre-ODEX fb_norefine | ODEX-only QN-clean | delta |
|---|---:|---:|---:|
| mean Re<O> | -0.0013410966 | 0.0017729074 | +0.0031140040 |
| mean Im<O> | 0.0000429799 | -0.0005999719 | -0.0006429518 |
| Zmean Re | -0.325057 | 0.385239 | +0.710295 |
| Zmean Im | 0.017403 | -0.200998 | -0.218401 |
| unresolved failures | 224439 | 326569 | +102130 |
| projection failures | 424888 | 529101 | +104213 |
| reverse-gate rejects | 200447 | 202530 | +2083 |
| mean pair0 accept | 0.438754 | 0.438907 | +0.000153 |
| mean runtime / seed | 11405.41 s | 7127.02 s | -4278.40 s |

Interpretation:

- ODEX-only increases projection/unresolved failures, as expected after removing hidden rescue success paths.
- The increase does not produce a visible bias in the 128seed/100k physical observables.
- Reverse-gate rejects and pair0 acceptance remain stable.
- Runtime improves substantially in this campaign.

## ODE Failure Boundary

| run | fallback attempts | success | failure | invalid | h_min | max_steps |
|---|---:|---:|---:|---:|---:|---:|
| 10k QN-clean | 21649 | 0 | 21649 | 0 | 21648 | 1 |
| 50k QN-clean | 354554 | 0 | 354554 | 0 | 354514 | 40 |
| 100k QN-clean | 2862514 | 0 | 2862514 | 0 | 2862168 | 346 |

Interpretation:

- `success=0` is expected under the ODEX-only policy; legacy rescue is not silently active.
- `invalid=0` across all staged runs is an important pass condition.
- Max-step failures remain rare relative to total fallback/failure-boundary events.

## Judgment

The QN-clean ODEX-only staged validation passes the 10k -> 50k -> 100k physical-observable gate.

This supports keeping ODEX-only as a physically acceptable comparison point, but not as the final production flow policy.

Later solver-internal assist validation on commit `704e2aafa650dc7ea5a404f60c9e37d7c841f49d` reduced 100k unresolved failures from `326569` to `224580`, essentially matching the earlier pre-ODEX `fb_norefine` level `224439`, while keeping physical observables compatible with zero.

Revised canonical candidate:

- ODEX primary integration.
- Solver-internal ODE assist for NT/QN residual evaluation.
- Strict final proposal flow.

Remaining caution:

- Failure counters are higher than the pre-ODEX characterization and were later shown to be avoidable with solver-internal assist.
- Do not delete assist/final-resort-related source solely based on this file; deletion requires preserving explicit residual-assist semantics and proving final proposal strictness.
