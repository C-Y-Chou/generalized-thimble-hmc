# F20 Loose ODEX Attribution Readback 2026-05-19

## Scope

Canonical workspace: `/Users/ccy/Documents/TLTM_qn_error_handling`

Remote evidence was read from:

- strict/current-head diagnosis:
  `output/tests/f20_tolerance_diagnosis/f20_strict_double_r2_10seed_10k_3364d783e4d5`
- loose/current-head diagnosis:
  `output/tests/f20_tolerance_diagnosis/f20_single_feasible1e6_rg1e4_r2_10seed_10k_3364d783e4d5`
- failed tolerance attribution:
  `output/logs/f20_tolerance_attribution/f20_odex_tol_only1e6_r2_10seed_10k_1ff1e7f2ed33`

No parent-side real `qsub` was performed for this readback.

## Immediate Findings

The old tolerance-attribution run already isolates one hard failure:

- `odex_only` with `TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-6` and
  `TLTM_STAGE2_REL_TOL_OVERRIDE=1e-6` failed Stage2 slot initialization at
  `flow_time=0.3500` for all logged seeds in both methods.
- Therefore ODEX tolerance `1e-6` alone is not a valid profile under strict
  Newton/QN/constraint settings. It is not merely slower.
- The old `constraint_only` result is not clean evidence because that pre-repair
  launcher also loosened quasi tolerance under the `constraint_only` label.

## Call-Site Cost Attribution

The successful strict-vs-loose diagnosis run already wrote raw Stage2 summary
lines for:

- `# odex_context_flowz`
- `# odex_context_flowzr`
- `# odex_context_flow`

These were parsed directly from per-seed Stage2 summaries.

### no_fb

| context | strict calls | strict rhs | loose calls | loose rhs | loose-strict rhs |
|---|---:|---:|---:|---:|---:|
| flowz | 52,574,705 | 10,167,287,466 | 22,906,209 | 16,717,641,089 | +6,550,353,623 |
| flow | 7,949,740 | 1,481,214,753 | 7,862,760 | 387,588,283 | -1,093,626,470 |

Net loose RHS increase is dominated by `flowz`.

### fb_norefine

| context | strict calls | strict rhs | loose calls | loose rhs | loose-strict rhs |
|---|---:|---:|---:|---:|---:|
| flowz | 54,862,388 | 11,088,523,056 | 23,182,901 | 21,461,297,113 | +10,372,774,057 |
| flowzr | 1,520,141 | 1,124,369,692 | 640,540 | 78,785,296 | -1,045,584,396 |
| flow | 8,102,821 | 1,543,728,568 | 7,881,834 | 391,945,957 | -1,151,782,611 |

Net loose RHS increase is again dominated by `flowz`, not `flowzr`.

## Interpretation

The full loose run is slower because `flowz` calls become much more expensive
per call even while the number of `flowz` calls drops.

This explains the apparent paradox:

- fixed-input replay showed some captured loose-trajectory `flowz` inputs are
  cheap under loose tolerance;
- full-run call-site attribution shows the aggregate loose run spends far more
  RHS work in `flowz`.

So the problem is not a Python/PBS artifact, and it is not primarily the
`flowzr` Newton residual path in this 10seed/10k evidence. The leading suspect is
ODEX controller behavior on the `flowz` input distribution visited by the full
loose run, plus the fact that pure `odex_only=1e-6` cannot initialize Stage2.

## Code Follow-Up

`scripts/run_stage3_3_multiseed.py` and
`scripts/merge_stage3_multiseed_chunks.py` now preserve ODEX context columns in
future per-seed and aggregate tables:

- `odex_context_flowz_*`
- `odex_context_flowzr_*`
- `odex_context_flow_*`
- `odex_context_unknown_*`

This makes future attribution readback direct instead of requiring ad hoc raw
summary parsing.

## Next Step

Do not promote `single_feasible1e6_rg1e4` or `odex_only1e6` as a speedup path.

The next meaningful experiment should search for an ODEX tolerance that is still
single-precision-feasible but does not trigger Stage2 initialization failure or
`flowz` RHS inflation, for example a ladder such as:

- `1e-8`
- `3e-8`
- `1e-7`
- `3e-7`
- `1e-6`

Run this first on a small `flowz`/Stage2-init diagnostic, then only promote
passing candidates to 10seed/10k physics comparison.
