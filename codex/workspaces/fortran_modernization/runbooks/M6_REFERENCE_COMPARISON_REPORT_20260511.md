# M6 Reference Comparison Report

Updated: 2026-05-11 JST

Scope: read-only comparison anchor for accepted M6 R1-R4 modernization reference packages.

## Caveat Status

- This report is a modernization reference-comparison aid, not a new production dataset.
- Source changes remain gated by `CV-004` and the baseline verification matrix.
- `Zmean` is reported only when raw aggregate CSV fields are available; the accepted readback table itself does not preserve those columns for every level.

## Aggregate Rows

| Level | Canonical | Raw | Seeds | Mean Re | Mean Im | Zmean Re | Zmean Im | Unresolved failures | RG rejects | Pair0 accept | Mean runtime s |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | nofb | no_fb | 4 | 0.2885818242 | 0.0843695367 | NA | NA | 316 | 54 | 0.432 | 73.760435 |
| R1 | withfb | fb_norefine | 4 | -0.0018318526 | 0.058371541 | NA | NA | 77 | 69 | 0.4275 | 74.874499 |
| R2 | nofb | no_fb | 10 | 0.0265222881 | 0.0247701103 | NA | NA | 7502 | 1252 | 0.43862 | 729.547965 |
| R2 | withfb | fb_norefine | 10 | -0.0039843442 | 0.0321239666 | NA | NA | 1770 | 1577 | 0.43986 | 731.171055 |
| R3 | nofb | no_fb | 32 | 0.0201887921 | -0.0049858728 | NA | NA | 120858 | 19197 | 0.438043 | 3433.969112 |
| R3 | withfb | fb_norefine | 32 | 0.000168402 | 0.0015007415 | NA | NA | 28206 | 24927 | 0.438588 | 4066.603039 |
| R4 | nofb | no_fb | 128 | 0.0067843097 | -0.0026896585 | NA | NA | 962417 | 152279 | 0.438617 | 7689.963103 |
| R4 | withfb | fb_norefine | 128 | -0.0011736472 | -0.0012498974 | NA | NA | 224580 | 200530 | 0.438762 | 8486.587849 |

## Withfb Minus Nofb

| Level | dMean Re | dMean Im | Failure reduction | Failure reduction frac | dRG rejects | dRuntime s | Runtime factor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | -0.2904136768 | -0.0259979957 | 239 | 0.75632911 | 15 | 1.114064 | 1.0151038 |
| R2 | -0.0305066323 | 0.0073538563 | 5732 | 0.76406292 | 325 | 1.62309 | 1.0022248 |
| R3 | -0.0200203901 | 0.0064866143 | 92652 | 0.76661868 | 5730 | 632.633927 | 1.1842282 |
| R4 | -0.0079579569 | 0.0014397611 | 737837 | 0.76665001 | 48251 | 796.624746 | 1.1035928 |

## Readback Interpretation

- R4 is the current strongest M6 anchor: 128 matched seeds x 100k cycles.
- At R4, canonical `withfb` reduces unresolved failures by 737837 (0.76665 of `nofb`).
- At R4, canonical `withfb` changes RG rejects by 48251 and runtime factor is 1.10359.
- Mean observables are close to zero at R4 for both canonical roles; use full raw package statistics when deciding source-patch acceptance thresholds.

## Next Use

- Use this report as the F4 comparison anchor in `MODERNIZATION_FORWARD_WORKSTEPS_20260511.md`.
- Before behavior-relevant source patches, add raw-package comparison checks that include route/counter equality and any available `Zmean` fields.
- Do not use this report to make final publication-production claims.
