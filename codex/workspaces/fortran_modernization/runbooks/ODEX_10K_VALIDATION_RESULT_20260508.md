# ODEX 10k Validation Result

Updated: 2026-05-08 JST
Status: superseded for forward validation decisions by the QN-clean 2026-05-09 10k baseline.

Supersession note:

- This run predates the QN invalid-evaluation handling cleanup.
- Keep this file and its raw output as historical evidence only.
- Do not use this result as the active 10k gate for ODEX 50k/100k scale-up.
- Active replacement: `ODEX_10K_VALIDATION_RESULT_20260509_QNCLEAN.md`.

## Run Identity

- Job: `14305.anode01`
- Source branch: `codex/preprod-hardening`
- Source commit: `ae234a29a130c000ad9175b69a844452e09a6ff1`
- Route: `fb_norefine`
- Core settings: p28, reverse gate on, post-refine off, `ct=1e-13`, `QN=1e-13`
- Output directory: `output/tests/odex_validation/20260508_10seed_10k_fb_norefine_ct1e13_qn1e13`
- Report: `output/tests/odex_validation/20260508_10seed_10k_fb_norefine_ct1e13_qn1e13/odex10k_fb_norefine_ct1e13_qn1e13_report.md`

Primary comparison baseline:

- `output/tests/stage3_4/preprod_validation_20260508_10seed_10k_p28_rg_fb_norefine`
- This is the closest matched 10seed/10k p28/RG `fb_norefine` historical baseline before the ODEX canonicalization work.

## Aggregate Physical Readout

| quantity | ODEX-only 10k | primary baseline | delta |
|---|---:|---:|---:|
| mean Re<O> | -0.0386029 | -0.0157643 | -0.0228386 |
| mean Im<O> | 0.0183377 | 0.0471401 | -0.0288024 |
| std Re<O> | 0.248252 | 0.147663 | +0.100589 |
| std Im<O> | 0.100655 | 0.0861727 | +0.0144824 |
| Zmean Re<O> | -0.491731 | -0.337600 | -0.154130 |
| Zmean Im<O> | 0.576116 | 1.729899 | -1.153783 |
| mean Zp | 1.628875 | 1.189155 | +0.439720 |
| median abs Zp | 1.597724 | 1.068689 | +0.529035 |

Interpretation:

- The 10seed aggregate observable remains compatible with the target `Re<O>=0`, `Im<O>=0` at this gate.
- The mean shifts relative to the closest baseline are small compared with the per-seed spread expected at 10k.
- The imaginary aggregate improves relative to the primary baseline by the Zmean diagnostic.
- The seed-level spread and mean/median Zp are larger than the primary baseline; this is not a stop condition at 10k, but it is the main quantity to monitor at 50k.

Largest current per-seed Zp values:

| seed | Re<O> | Im<O> | Zp_abs_max |
|---|---:|---:|---:|
| 20260906 | -0.408664 | -0.0938739 | 3.27361 |
| 20261197 | 0.427445 | 0.0836261 | 2.54746 |
| 20260615 | -0.288793 | -0.163573 | 2.34225 |

## Operational Diagnostics

| quantity | ODEX-only 10k | primary baseline | delta |
|---|---:|---:|---:|
| unresolved failures | 2519 | 1769 | +750 |
| mean projection failures / seed | 408.5 | 335.4 | +73.1 |
| mean unresolved failures / seed | 251.9 | 176.9 | +75.0 |
| mean quasi probe success / seed | 862.5 | 819.1 | +43.4 |
| reverse-gate rejects | 1566 | 1585 | -19 |
| mean pair0 accept rate | 0.44008 | 0.43984 | +0.00024 |
| mean total round trip | 2199.4 | 2198.2 | +1.2 |
| mean hot-end hits / seed | 4997.6 | 5029.0 | -31.4 |
| mean runtime / seed | 739.69 s | 961.74 s | -222.05 s |

Interpretation:

- Acceptance, reverse-gate rejects, round-trip counts, and hot-end reach are stable.
- Runtime is substantially lower than the primary 10k baseline.
- Projection/unresolved failures increased. This is expected to be the sensitive diagnostic after removing legacy ODE rescue behavior, but it must not grow into a physics-significant bias at 50k.

## ODE Fallback / Failure Boundary

ODE fallback counters are not directly comparable as old/new success rates because the ODEX-only policy intentionally disables legacy rescue success paths.

| fallback counter | ODEX-only 10k | primary baseline |
|---|---:|---:|
| calls_total | 63,848,607 | 65,134,727 |
| attempts | 21,762 | 670,214 |
| success | 0 | 665,173 |
| failure | 21,762 | 5,041 |
| max_steps | 1 | 0 |
| invalid | 0 | 0 |
| h_min | 21,761 | 670,214 |

Interpretation:

- `success=0` is expected under ODEX-only failure-as-rejection; it confirms legacy rescue is not silently active.
- Invalid-state fallback count is zero.
- There is one max-step-classified failure across all 10 seeds; all remaining fallback failures are h-min classified.
- The lower attempt count is consistent with no repeated successful legacy rescue path.

## Judgment

The 10k gate passes provisionally and can proceed to the planned 50k validation without code changes.

This is not a final physics approval because:

- 10 seeds at 10k remain statistically small.
- ODEX-only changes proposal trajectories, so trajectory-level equality is not the criterion.
- The current run shows higher projection/unresolved failures and higher seed-level Zp spread than the closest 10k baseline.

Required 50k watch items:

- Aggregate `Re<O>` and `Im<O>` should remain compatible with zero.
- Mean/median Zp and the largest per-seed outliers should shrink or remain explainable.
- Projection/unresolved failure rates must not scale into a visible physics bias.
- Reverse-gate reject rate and pair0 acceptance should remain stable.
- ODE invalid failures should remain zero; max-step failures should remain rare.

## Recommended Next Step

Submit the matching 50k ODEX-only validation using the same route and seed family, with no source changes between the 10k judgment and the 50k submission. Based on the completed 10k walltime of about 12.5 minutes, expected 50k walltime is roughly 60-75 minutes under similar queue/runtime conditions; 100k should be budgeted around 2-2.5 hours.
