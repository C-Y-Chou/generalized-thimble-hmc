# nofb_diagnostics State Brief

Date: 2026-05-21 JST

## Purpose

This workspace owns the F20F no-fallback diagnostics line.  Its job is to
decide whether no-fallback failures are only an efficiency/mobility problem or
whether they create an actual sampling/observable bias, and whether TLTM/fallback
replicas repair that bias.

## Current Canonical Evidence

The F20F 1D toy evidence is now grouped by physical scenario:

| bucket | canonical role |
| --- | --- |
| `TLTM_t030` | F20F double-preset validation at TLTM `t=0.3`; F20F remains the unique active double preset |
| `fixed_flow_t030` | paired `512 seeds x 200000 cycles` negative control; failures/rejections are large in `no_fb`, but support and observables remain compatible with `fb_norefine` |
| `fixed_flow_t050` | nofb `128 seeds x 200000 cycles` threshold pathology; every seed is locked in one high-flow `Re z` sign sector and `Ohat_re ~= -0.241256` |
| `TLTM_t050` | low005 paired `128 seeds x 200000 cycles` repair dataset; TLTM repairs the fixed-flow pathology, while fallback only has a solver-health advantage in this 1D evidence |

## Boundary

- This workspace does not own source modernization or PBS launcher
  productization.  Those remain in `fortran_modernization`.
- This workspace does not own final production-facing publication output.  That
  remains in `tltm_production_comparison`.
- Raw `z_history.dat` and `phi_history.dat` payloads stay in remote output
  roots.  This workspace stores only registries, readbacks, compact diagnostics,
  and stable paths to raw evidence.

## Current Closure

The nofb-only two-replica TLTM short scan selected `low005 = [0.05, 0.5]`.
The final paired TLTM `t=0.5` evidence combines the base32 and topup96 raw
components into `128 seeds x 200000 cycles`.

The current interpretation is frozen for cleanup planning:

- TLTM repairs the fixed-flow `t=0.5` undercoverage pathology.
- `fb_norefine` strongly reduces failures, but this one-dimensional toy model
  does not demonstrate that fallback is required for unbiased TLTM observables.
- The base32 Im candidate did not survive independent topup96 validation:
  combined128 paired `no_fb - fb_norefine` is `Re Z = -0.772`,
  `Im Z = 1.933`.

Current closure and cleanup planning live in:

```text
codex/workspaces/nofb_diagnostics/runbooks/F20F_1D_TOY_TLTM_CLOSURE_AND_CLEANUP_PLAN_20260521.md
codex/workspaces/nofb_diagnostics/runbooks/F20F_1D_TOY_FINAL_SUMMARY_20260521.md
codex/workspaces/nofb_diagnostics/runbooks/F20F_COMPACT_PACKETS_20260521.md
```

The cleanup dry-run manifest and physics grouping are prepared.  Do not rebuild
the file library, move output roots, or delete datasets until a concrete
deletion command list is reviewed and explicitly approved.
