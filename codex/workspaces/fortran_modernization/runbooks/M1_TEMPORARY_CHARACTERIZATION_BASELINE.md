# M1 Temporary Characterization Baseline

Updated: 2026-05-08
Scope: temporary characterization after Stage3_4/TLTM judgment. This is not the official canonical regression baseline.

## Status

Stage3_4 128seed/100k p28 RG judgment report is available and is used as the primary characterization source.

Primary artifact root:

- `/home/cychou/TLTM/output/tests/stage3_4/judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine`

Primary report:

- `/home/cychou/TLTM/output/tests/stage3_4/judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine/REPORT.md`

Config and settings:

- config: `docs/stage_3_4_t035_paired_128seed_100k_rg_nofb_fbnorefine.json`
- seeds: 128 matched seeds
- cycles per seed: 100000
- methods: `no_fb`, `fb_norefine`
- common: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
- near/non-near/global rescue: off
- post-refine: off for `fb_norefine`

## Important Interpretation

This file characterizes the current completed Stage3_4 behavior so we can make core numerical canonicalization decisions. It does not freeze the final modernization target.

Official baseline freeze happens later, after M2 core numerical canonicalization.

## Aggregate Results

| method | n_seeds | mean Re<O> | mean Im<O> | Zmean Re | Zmean Im | unresolved failures | RG rejects | mean runtime sec | post-refine |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| no_fb | 128 | -0.0014091949197912778 | -0.0002987753647124314 | -0.2582757386163032 | -0.10026765888088965 | 946129 | 136997 | 9725.480457179694 | 0/0 |
| fb_norefine | 128 | -0.0013410966099107525 | 4.2979886168221224e-05 | -0.3250566535899634 | 0.017403134759755672 | 224439 | 200447 | 11405.412790874998 | 0/0 |

## Route And Counter Characterization

| metric | no_fb | fb_norefine | fb_norefine - no_fb |
|---|---:|---:|---:|
| projection failures | 1083126 | 424888 | -658238 |
| unresolved failures | 946129 | 224439 | -721690 |
| fallback triggers | 0 | 1265555 | 1265555 |
| quasi probe successes | 0 | 1041116 | 1041116 |
| post-refine attempts | 0 | 0 | 0 |
| RG candidates | 500822594 | 508264091 | 7441497 |
| RG rejects | 136997 | 200447 | 63450 |
| RG reject rate | 0.000273543968745 | 0.000394375686871 | n/a |
| accepted local total | 24380140 | 24908861 | 528721 |
| accepted local quasi | 0 | 407175 | 407175 |
| accepted local probe-only | 0 | 407175 | 407175 |
| quasi watchdog hits | 0 | 0 | 0 |
| far final-resort units | 0 | 0 | 0 |

## Quasi Classification In fb_norefine

| classification/route | total |
|---|---:|
| quasi class local | 889 |
| quasi class mid | 79394 |
| quasi class global | 144156 |
| far route skip | 12936 |
| far route light | 3860 |
| far route anchor | 206754 |
| near rescue candidates | 889 |

Note: near/non-near/global rescue was off, so these route/class counters characterize classification and would not imply rescue execution.

## Paired Differences

Mean paired deltas, `fb_norefine - no_fb`, across 128 matched seeds:

| metric | mean delta | min delta | max delta |
|---|---:|---:|---:|
| Ohat Re | 6.80983098805226e-05 | -0.1720323309508231 | 0.1506834662194659 |
| Ohat Im | 0.00034175525088065225 | -0.1036293066642746 | 0.0902564573166539 |
| unresolved failures | -5638.203125 | -5968.0 | -5298.0 |
| projection failures | -5142.484375 | -5495.0 | -4737.0 |
| RG rejects | 495.703125 | 348.0 | 662.0 |
| runtime sec | 1679.9323336953128 | 618.6053929999998 | 2372.0514789999997 |

## Secondary Evidence: 32seed/50k Three-Set Judgment

The earlier 32seed/50k judgment included `no_fb`, `fb_refine`, and `fb_norefine`.

Recorded interpretation from Stage3_4 status:

- Both fallback variants reduced unresolved failures by about 90k events versus `no_fb`.
- Both fallback variants increased RG rejects by about 7.7k-7.8k versus `no_fb`, with RG reject rate around `3.9e-4`.
- At 32seed/50k, `fb_norefine` had the cleanest aggregate Zmean and was faster than `fb_refine`.
- This reversed the earlier 10seed/10k preference for `fb_refine`, so post-refine should not be retained without further evidence.

## Characterization Conclusions

- `fb_norefine` substantially reduces unresolved failures versus `no_fb` in the 128seed/100k run.
- `fb_norefine` increases RG rejects, but the RG reject rate remains small relative to RG candidates.
- `fb_norefine` increases runtime versus `no_fb` by about 1680 seconds per seed on average in this campaign.
- Post-refine is absent in the 128seed/100k primary characterization and remains a deletion candidate pending final user decision.
- Far final-resort usage recorded through current summary counters is zero in this dataset, but ODEX/Radau/final-resort flow-level counters still need a dedicated ODEX-only characterization before flow backend deletion.

## M2 Decision Queue

Before official baseline freeze:

1. Decide whether `fb_norefine` becomes the canonical p28 production route and post-refine is removed.
2. Generate or identify flow-level rescue counter characterization sufficient for ODEX-only comparison.
3. Decide deletion order for non-p28 quasi legacy routes.
4. Define official canonical baseline configs after these numerical decisions.

## Data Extract

Machine-readable metric extract:

- `/home/cychou/TLTM/codex/workspaces/fortran_modernization/state/M1_CHARACTERIZATION_METRICS_20260508.tsv`
