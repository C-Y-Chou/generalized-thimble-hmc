# nofb_diagnostics State Brief

Date: 2026-05-21 JST

## Purpose

This workspace owns the F20F no-fallback diagnostics line.  Its job is to
decide whether no-fallback failures are only an efficiency/mobility problem or
whether they create an actual sampling/observable bias, and whether TLTM/fallback
replicas repair that bias.

## Current Canonical Evidence

The current main F20F diagnostic dataset is the fixed-flow `t=0.3` paired
dataset:

- scale: `512 seeds x 200000 cycles`
- methods: `no_fb`, `fb_norefine`
- composition: initial 128-seed block plus 384-seed extension
- interpretation: failures/rejections are large in `no_fb`, but raw `Re z`
  support/mixing and the measured observables do not show a meaningful
  no_fb-vs-fb difference at this flow time.

The current threshold/pathology evidence is the fixed-flow `t=0.5` no-fallback
dataset:

- scale: `128 seeds x 200000 cycles`
- method: `no_fb`
- interpretation: every seed is locked in a single `Re z` sign sector, and
  `Ohat_re` shifts to about `-0.241256`.  Balancing positive/negative sectors
  would cancel the odd imaginary component but would not repair this real
  observable shift.

## Boundary

- This workspace does not own source modernization or PBS launcher
  productization.  Those remain in `fortran_modernization`.
- This workspace does not own final production-facing publication output.  That
  remains in `tltm_production_comparison`.
- Raw `z_history.dat` and `phi_history.dat` payloads stay in remote output
  roots.  This workspace stores only registries, readbacks, compact diagnostics,
  and stable paths to raw evidence.

## Next Gate

The nofb-only two-replica TLTM short scan selected `low005 = [0.05, 0.5]`.
This ladder repaired the fixed-flow `t=0.5` sign-sector lock in short TLTM
tests.

The current interpretation is provisional:

- TLTM repairs the fixed-flow `t=0.5` undercoverage pathology.
- `fb_norefine` strongly reduces failures, but the one-dimensional toy model has
  not yet demonstrated that fallback is required for unbiased TLTM observables.
- The active paired top-up from 32 to 128 seeds at 200k cycles is the gate for
  the remaining Im candidate signal.

Current closure and cleanup planning live in:

```text
codex/workspaces/nofb_diagnostics/runbooks/F20F_1D_TOY_TLTM_CLOSURE_AND_CLEANUP_PLAN_20260521.md
```

Do not rebuild the file library, move output roots, or delete datasets until
the paired top-up finishes and the combined 128seed readback is registered.
