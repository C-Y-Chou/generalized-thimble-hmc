# Modernization Main Status

Updated: 2026-06-16 JST

This is the single active status file for the current modernization workflow.
If another runbook disagrees with this file, treat that runbook as historical
until this file is updated.

## Top Line

- WV-HMC boundary-policy routing is now closed for the current dense explicit-J
  implementation.
- Main WV-HMC boundary policy: `normal_reflect` / `normal_reflection`.
- Optional benchmark policy: `full_bounce` / `paper_full_flip`.
- Diagnostic/historical policies: `stay_reject` and `paper_bounce_reject`.
- Public/product default has been moved to `normal_reflect`.
- No high-dimensional production-performance claim is made yet; matrix-free /
  BiCGStab trajectory work remains deferred.

## Current Evidence

Primary evidence packet:

- `codex/runbooks/WV_HMC_POLICY_BENCHMARK_SUMMARY_20260616.md`

Generated evidence used by that summary:

- `codex/runbooks/generated/wv_hmc_n6_4policy_all_available_20260611/wv_hmc_n6_4policy_all_available_summary.csv`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/WV_HMC_N6_4POLICY_BURN_MIDDLE_GRID_20260616.md`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/wv_hmc_n6_4policy_burn_middle_grid_summary.csv`

Current result:

- `normal_reflection` is the most stable policy under small-burn and
  middle-flow-time window scans.
- A practical diagnostic window is around `[0.006, 0.024]` to `[0.008, 0.022]`
  with burn `2k..15k`.
- The grid does not prove a final production observable gate by itself; it
  selects the boundary policy and measurement-window direction for the next
  validation.

## Active Policy Definitions

`normal_reflect` / `normal_reflection`:

- Main WV-HMC boundary policy.
- On boundary/construction events handled locally by the RATTLE wrapper, keep
  the current state and reflect the flow-normal momentum component using the
  current `xi,J` decomposition.

`full_bounce` / `paper_full_flip`:

- Optional benchmark policy.
- On the same local boundary/construction events, keep the current state and
  perform a full momentum flip `pi -> -pi`.

`stay_reject`:

- Diagnostic/historical.
- Treats construction events as full proposal rejections.  The 90k comparison
  did not support it as the main policy.

`paper_bounce_reject`:

- Diagnostic/historical.
- Bounces successful buffer exits but rejects construction failures.  The 90k
  comparison did not support it as the main policy.

## Current Code State

- `wv_hmc_constraints` defaults to `normal_reflect`.
- `run_wv_hmc` defaults to `normal_reflect` unless
  `WV_HMC_BOUNDARY_POLICY` is set.
- `scripts/run_tltm_product.py wv-hmc` exposes `--boundary-policy`, defaulting
  to `normal_reflect`.
- `full_bounce` is an accepted alias for `paper_full_flip`.

## Current Next Step

Use `normal_reflect` as the main WV-HMC policy for any subsequent dense
explicit-J validation.  If comparing policies, compare only:

1. `normal_reflect` as main.
2. `full_bounce` as optional benchmark.

Do not reopen `stay_reject` or `paper_bounce_reject` unless a new diagnostic
specifically targets rejection semantics.

## Nonblocking / Deferred

- Matrix-free / BiCGStab WV-HMC trajectory wiring.
- High-dimensional performance validation.
- Reentrancy/context cleanup before OpenMP or library-level parallel claims.
- Historical runbook/data archive cleanup.
