# F20F 1D Toy Final Summary

Date: 2026-05-21 JST

Status: final readback summary before file cleanup.  This packet freezes the
physics conclusion and the dataset grouping.  It does not authorize deleting
raw output roots.

## Physics Buckets

The evidence is grouped by physical scenario:

| bucket | role |
| --- | --- |
| `TLTM_t030` | F20F double-preset validation at TLTM `t=0.3` |
| `fixed_flow_t030` | fixed-flow `t=0.3` negative control |
| `fixed_flow_t050` | fixed-flow `t=0.5` pathology threshold |
| `TLTM_t050` | TLTM `t=0.5` low005 repair and fallback comparison |

Detailed path ownership is in:

```text
codex/workspaces/nofb_diagnostics/state/F20F_PHYSICS_DATASET_GROUPS_20260521.tsv
codex/workspaces/nofb_diagnostics/state/F20F_CLEANUP_DRY_RUN_INVENTORY_20260521.tsv
```

## TLTM t=0.3

The F20F tolerance-validation run is physically the TLTM `t=0.3` dataset.  It
is not a separate fifth scenario.

- scale: `32 seeds x 50000 cycles`
- methods: `no_fb`, `fb_norefine`
- preset: `f20f_most_conservative_double`
- output root:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35`

Readback:

| method | mean Re | Zmean Re | mean Im | Zmean Im | unresolved | runtime s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | `0.0093236730` | `0.7222` | `-0.0069709609` | `-0.6940` | `133379` | `2409.26` |
| `fb_norefine` | `0.0117964990` | `0.9794` | `-0.0004064170` | `-0.0605` | `26714` | `3595.63` |

Decision: F20F is the unique active double preset.  Single precision and
alternate tolerance presets remain closed unless explicitly reopened.

## Fixed Flow t=0.3

- scale: `512 seeds x 200000 cycles`
- methods: `no_fb`, `fb_norefine`
- raw roots: 128seed base plus 384seed extension

Readback:

| method | rows | mean Re | mean Im | proposal failures | RG rejects | runtime s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | 512 | `-0.0018257699` | `-0.0018512135` | `1260068` | `2868692` | `7768.11` |
| `fb_norefine` | 512 | `-0.0017898159` | `0.0003013731` | `0` | `0` | `8902.78` |

Sign support:

| method | files | only + | only - | both signs | median sign changes |
| --- | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | 512 | 0 | 0 | 512 | `32821.0` |
| `fb_norefine` | 512 | 0 | 0 | 512 | `38341.5` |

Decision: fixed-flow `t=0.3` failures/rejections are an efficiency and mobility
warning, not an observable-bias demonstration.

## Fixed Flow t=0.5

- scale: `128 seeds x 200000 cycles`
- method: `no_fb`
- output root:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1`

Readback:

| method | rows | mean Re | mean Im | proposal failures | RG rejects | runtime s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | 128 | `-0.2412559808` | `-0.0077456212` | `3149862` | `204408` | `10166.46` |

Sign support:

| method | files | only + | only - | both signs | median sign changes |
| --- | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | 128 | 66 | 62 | 0 | `0.0` |

Decision: fixed-flow `t=0.5` is a real pathology in this 1D model.  Equalizing
positive/negative sign sectors would cancel the odd imaginary component, but it
does not repair `Ohat_re`; both sectors sit near `-0.241`.

## TLTM t=0.5

The selected TLTM ladder is `low005 = [0.05, 0.5]`.

Final paired evidence combines:

- base32:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8`
- topup96:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff`

Combined 128seed method summary:

| method | rows | mean Re | Zmean Re | mean Im | Zmean Im | unresolved | runtime s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | 128 | `-0.0012320877` | `-0.3278` | `0.0030541044` | `1.2387` | `4094188` | `11612.75` |
| `fb_norefine` | 128 | `0.0013011465` | `0.5144` | `-0.0012213477` | `-0.6428` | `189662` | `23504.27` |

Direct paired difference `no_fb - fb_norefine`:

| set | n | dRe Z | dIm Z |
| --- | ---: | ---: | ---: |
| base32 | 32 | `-0.900` | `2.995` |
| topup96 | 96 | `-0.307` | `0.864` |
| combined128 | 128 | `-0.772` | `1.933` |

Seed-level distribution checks:

| quantity | KS distance |
| --- | ---: |
| `Ohat_re` | `0.125000` |
| `Ohat_im` | `0.140625` |
| `Zp_re` | `0.093750` |
| `Zp_im` | `0.117188` |

Decision: TLTM repairs the fixed-flow `t=0.5` pathology.  Fallback strongly
improves solver-health counters, but this 1D toy model does not show a robust
TLTM observable-necessity signal.  The earlier base32 Im candidate does not
survive the independent topup96.

## Final Claim Boundary

Use this boundary for manuscript or planning work:

> In the 1D toy model, fixed-flow sampling at large flow time can create a real
> undercoverage and observable-bias pathology.  A two-replica TLTM ladder
> repairs the fixed-flow pathology.  The BTN fallback route substantially
> reduces solver failures, but this 1D evidence does not prove that fallback is
> necessary for unbiased TLTM observables.

Do not claim from this dataset alone:

- solver failures imply sampling bias;
- fallback is required for unbiased TLTM observables;
- `no_fb` and `fb_norefine` have different sampling distributions at TLTM
  `t=0.5`;
- the 1D toy is enough to support the strongest BTN fallback motivation.

## Cleanup Boundary

Raw roots that remain canonical:

- `TLTM_t030`: F20F R3 tolerance validation
- `fixed_flow_t030`: 512seed components
- `fixed_flow_t050`: nofb 128seed pathology root
- `TLTM_t050`: base32 + topup96 components

All other F20F roots are compact-only or deletion candidates after compact
packet review.  No file deletion is authorized by this summary.
