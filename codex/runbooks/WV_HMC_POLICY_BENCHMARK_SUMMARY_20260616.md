# WV-HMC Boundary Policy Benchmark Summary

Updated: 2026-06-16 JST

Scope: Stephanov model, `n=6`, dense explicit-J WV-HMC, 64 seeds
`9510001..9510064`, 90k cycles per policy.  Estimates use the production
`weight_re/weight_im` history fields, pooled complex ratio estimator, and
ratio-preserving seed jackknife.

## Decision

- Main policy: `normal_reflect` / `normal_reflection`.
- Optional benchmark policy: `full_bounce` / `paper_full_flip`.
- Diagnostic/historical policies: `stay_reject`, `paper_bounce_reject`.

This is a boundary-policy routing decision, not a final high-dimensional
production-performance claim.

## Evidence Artifacts

- `codex/runbooks/generated/wv_hmc_n6_4policy_all_available_20260611/wv_hmc_n6_4policy_all_available_summary.csv`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/WV_HMC_N6_4POLICY_BURN_MIDDLE_GRID_20260616.md`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/wv_hmc_n6_4policy_burn_middle_grid_summary.csv`

## All-Available 90k Four-z

| policy | samples | C | chiral Re z | chiral Im z | density Re z | density Im z | max abs(z) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `stay_reject` | 4,938,691 | 0.077586 | -3.42 | 1.36 | -0.75 | 0.42 | 3.42 |
| `full_bounce` | 4,934,680 | 0.073380 | -1.37 | 1.64 | -1.44 | -1.22 | 1.64 |
| `normal_reflection` | 4,936,837 | 0.075398 | -2.30 | 1.18 | -0.20 | -0.43 | 2.30 |
| `paper_bounce_reject` | 4,936,119 | 0.076709 | -2.67 | 0.06 | -1.20 | -0.15 | 2.67 |

All-available alone favors `full_bounce`, but it is not the decisive cut
because startup and boundary-window effects are visible.

## Burn/Middle-Window Grid

Best max `|four z|` by policy over the scanned small-burn and symmetric
middle-window grid:

| policy | best cut | max abs(z) |
|---|---|---:|
| `stay_reject` | `burn15k_mid010_020` | 1.97 |
| `full_bounce` | `burn10k_mid003_027` | 1.45 |
| `normal_reflection` | `burn15k_mid008_022` | 1.24 |
| `paper_bounce_reject` | `burn15k_mid004_026` | 1.76 |

`normal_reflection` has the clearest middle-window plateau:

| burn | best middle window | max abs(z) |
|---|---|---:|
| `burn0` | `mid008_022` | 1.60 |
| `burn2k` | `mid008_022` | 1.35 |
| `burn5k` | `mid008_022` | 1.45 |
| `burn10k` | `mid008_022` | 1.31 |
| `burn15k` | `mid008_022` | 1.24 |

`full_bounce` is retained as the optional benchmark because its best windows
are close but less stable across burn/window cuts:

| burn | best middle window | max abs(z) |
|---|---|---:|
| `burn0` | `mid003_027` | 1.55 |
| `burn5k` | `mid003_027` | 1.74 |
| `burn10k` | `mid003_027` | 1.45 |
| `burn15k` | `mid003_027` | 1.78 |

## Operational Consequences

- Default WV-HMC policy should be `normal_reflect`.
- Product and cluster wrappers should only use `full_bounce` when explicitly
  benchmarking the optional bounce policy.
- Rejection-heavy boundary handling should not be promoted to the default from
  the current evidence.
- Measurement-window cuts remain diagnostics; they must not feed back into the
  transition kernel.
