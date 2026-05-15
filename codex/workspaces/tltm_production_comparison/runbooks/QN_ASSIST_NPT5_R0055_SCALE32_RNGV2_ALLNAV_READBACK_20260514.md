# QN Assist npt5_r0055_m500 RNG v2 All-Navigation Readback

Date: 2026-05-14 JST
Status: completed negative diagnostic; not an active production path

## Provenance

- Worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Branch: `codex/tltm-production-comparison-official-dfols`
- Commit: `ae777294814955f7f7935fc386a6172bcd30651f`
- Campaign: `qn_assist_npt5_r0055_scale32_20260514_ae77729_32seed_50000cyc_t035_L2_nstep20_rngv2_allnav_nofb_withfb`
- Output root: `output/production_comparison/pre_redo/qn_assist_npt5_r0055_scale32_20260514_ae77729_32seed_50000cyc_t035_L2_nstep20_rngv2_allnav_nofb_withfb`
- Log root: `output/logs/production_comparison/pre_redo/qn_assist_npt5_r0055_scale32_20260514_ae77729_32seed_50000cyc_t035_L2_nstep20_rngv2_allnav_nofb_withfb`
- Stage2 RNG stream contract: `stage2_kernel_rng_v2`
- Assist policy: method-level `INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic`
- DFO-LS settings: `QN_OFFICIAL_DFOLS_NPT=5`, `QN_OFFICIAL_DFOLS_RHOBEG=0.055`, `QN_OFFICIAL_DFOLS_MAXFUN=500`, `QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE=1`, `QN_OFFICIAL_DFOLS_RHOEND=1e-16`, `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-30`, `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`

## PBS Completion

| Job | Role | Status |
|---|---|---|
| `15205.anode01` | preflight | `Exit_status=0` |
| `15206.anode01`-`15209.anode01` | nofb chunks | `Exit_status=0` |
| `15210.anode01`-`15213.anode01` | withfb chunks | `Exit_status=0` |
| `15214.anode01` | merge/report | `Exit_status=0` |

All eight chunk manifests recorded:

- `TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2`
- `ASSIST_POLICY=all_navigation_diagnostic`
- `METHOD_LEVEL_ASSIST_POLICY=all_navigation_diagnostic`

## Readback

| canonical | raw | n_seeds | mean Re | mean Im | Zmean Re | Zmean Im | failures | RG rejects | runtime |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `nofb` | `no_fb` | 32 | `0.13954536290095745` | `-0.0040736603523942455` | `11.400630197163373` | `-0.41528281214525525` | `245006` | `15661` | `3823.84403809375` |
| `withfb` | `fb_norefine` | 32 | `0.03420261820536729` | `0.0051942853774203206` | `2.449403290483088` | `0.6431657290510379` | `25881` | `19407` | `6184.575801937501` |

## Failure-Only Comparison

Matched 32seed/50k failure counts:

| run | nofb failures | withfb failures | withfb RG rejects |
|---|---:|---:|---:|
| RNG v2 default policy | `268647` | `25982` | `19421` |
| RNG v0 default policy | `265332` | `26413` | `19522` |
| RNG v2 all-navigation diagnostic | `245006` | `25881` | `19407` |
| old same-scale assist-on reference | n/a | `19579` | n/a |
| assist-off tuned reference | n/a | `33872` | n/a |

All-navigation changed `no_fb` substantially but did not recover `fb_norefine`
to the old assist-on failure scale.

Per-seed failure delta for RNG v2 all-navigation versus RNG v2 default:

- `no_fb`: total `-23641`, improved `32/32`, min/max per-seed delta `-876/-571`.
- `fb_norefine`: total `-101`, improved `15/32`, worsened `16/32`, unchanged `1/32`, min/max per-seed delta `-51/+22`.

## Verdict

This is a negative recovery result for `TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2` plus method-level `all_navigation_diagnostic` at `32 seeds x 50k`.

The failure count for `fb_norefine` is essentially unchanged relative to the RNG v2 default-policy redo (`25982 -> 25881`) and remains `+6302` above the old same-scale assist-on reference (`19579`).  The result does not support `all_navigation_diagnostic` as the missing recovery knob for the 50k production-comparison failure scale.
