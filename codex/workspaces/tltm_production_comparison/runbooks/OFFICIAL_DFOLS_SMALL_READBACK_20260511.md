# Official DFO-LS Small Readback 2026-05-11

Scope: read back the first small `tltm_production_comparison` redo executed from the production-comparison worktree with the official DFO-LS backend, and compare against the preserved in-house solver 10seed/10k baseline.

## Campaign

- Campaign: `official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb`
- Worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Branch: `codex/tltm-production-comparison-official-dfols`
- Pinned run commit: `81b0784473073a6bc3ec1604f3f2e5930e70e252`
- Output report: `output/production_comparison/provisional/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb/REPORT.md`
- Physical point: `t=0.35,L=2,nstep=20`
- Scale: `10 seeds x 10000 cycles`
- Gate/solver: RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`
- Mapping: `no_fb -> nofb`, `fb_norefine -> withfb`

## Official DFO-LS Result

| canonical | raw | n | P68 Re | P95 Re | P68 Im | P95 Im | mean Re | mean Im | std Re | std Im | Zmean Re | Zmean Im | unresolved failures | RG rejects | mean runtime s |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | 10 | 0.6 | 0.9 | 0.7 | 1.0 | 0.0265222881 | 0.0247701103 | 0.1886771381 | 0.0926561653 | 0.4445204125 | 0.8453832101 | 7502 | 1252 | 715.5420136 |
| withfb | fb_norefine | 10 | 0.8 | 1.0 | 0.6 | 0.9 | -0.0290740001 | 0.0347713206 | 0.1039176303 | 0.0969095801 | -0.8847397764 | 1.1346305510 | 1179 | 996 | 1105.0365717 |

Within official DFO-LS small run, `withfb - nofb`:

- Mean shift: Re `-0.0555963`, Im `+0.0100012`
- Zmean shift: Re `-1.32926`, Im `+0.289247`
- Unresolved failures: `-6323`
- RG rejects: `-256`
- Runtime: `+389.495 s`

## In-House Baseline Used For Comparison

The old raw output was cleaned, so this comparison uses preserved aggregate readback in the control-plane logs:

- `no_fb`: from `codex/state/session_log.md`
- `fb_norefine`: from `codex/workspaces/tltm_production_comparison/state/session_log.md`

For `no_fb`, only mean and Zmean were preserved; `std` below is inferred from `std = |mean| sqrt(n) / |Zmean|` with `n=10`.

| canonical | raw | solver | n | mean Re | mean Im | std Re | std Im | Zmean Re | Zmean Im | unresolved failures | RG rejects | mean runtime s |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | in-house | 10 | 0.06561 | -0.02009 | 0.1831218334 | 0.1069531283 | 1.133 | -0.594 | 7451 | 1132 | 817.5 |
| withfb | fb_norefine | in-house | 10 | -0.0157643 | 0.0471401 | 0.147663 | 0.0861727 | -0.337600 | 1.729899 | 1769 | 1585 | 961.7 |

## Official DFO-LS Minus In-House

| canonical | raw | d mean Re | d mean Im | d std Re | d std Im | d Zmean Re | d Zmean Im | d failures | d RG rejects | d runtime s |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | -0.0390877119 | +0.0448601103 | +0.0055553046 | -0.0142969630 | -0.6884795875 | +1.4393832101 | +51 | +120 | -101.9579864 |
| withfb | fb_norefine | -0.0133097001 | -0.0123687794 | -0.0437453697 | +0.0107368801 | -0.5471397764 | -0.5952684490 | -590 | -589 | +143.3365717 |

## Initial Reading

- Official DFO-LS `withfb` still strongly reduces unresolved failures versus `nofb` at the same 10seed/10k scale: `7502 -> 1179`.
- Official DFO-LS `withfb` also has fewer RG rejects than official `nofb`: `1252 -> 996`.
- Compared with in-house `fb_norefine`, official DFO-LS `withfb` has fewer unresolved failures and fewer RG rejects, but is slower in this small run.
- `Zmean` remains small-sample noisy at 10 seeds. Official DFO-LS improves `withfb` Im Zmean versus in-house `fb_norefine`, but worsens Re Zmean magnitude. This is not enough to conclude production-level bias; it is a calibration gate result.
