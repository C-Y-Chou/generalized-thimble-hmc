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

The next scientific gate is a nofb-only two-replica TLTM short scan to choose a
usable `t=0.5` ladder before any paired nofb-vs-withfb TLTM comparison.  The
current candidate ladders are `[0.05, 0.5]`, `[0.1, 0.5]`, `[0.2, 0.5]`, and
`[0.3, 0.5]`, at `4 seeds x 5000 cycles` per candidate.

After selecting a ladder, run the same `t=0.5` scenario with TLTM/fallback
repair enabled, then check:

- high-flow `Re z` sign changes are restored;
- positive/negative occupancy is near balanced;
- `Ohat_re` is no longer locked near `-0.241`;
- `Ohat_im` remains compatible with zero;
- failure/rejection diagnostics no longer dominate the accepted ensemble.
