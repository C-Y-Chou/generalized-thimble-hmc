# WV-HMC Validation Packet 2026-06-16

This is the compact public readback for the dense explicit-J WV-HMC
Stephanov `n=6` boundary-policy validation packet.

## Scope

- Model: Stephanov `n=6`, `mu=0.6`.
- Sampler: dense explicit-J WV-HMC.
- Policies in the historical scan: `normal_reflection`, `full_bounce`,
  `stay_reject`, `paper_bounce_reject`.
- Public product route after the scan: `normal_reflect` as the main policy;
  `full_bounce` as the optional benchmark policy.
- Seeds: `9510001..9510064`.
- Cycle budget: 90k cycles per policy.
- Estimator: production `weight_re` / `weight_im`, pooled complex ratio
  estimator, ratio-preserving seed jackknife.

This packet supports boundary-policy routing.  It is not a high-dimensional
production-performance claim.

## Tracked Evidence Artifacts

- `codex/runbooks/WV_HMC_POLICY_BENCHMARK_SUMMARY_20260616.md`
- `codex/runbooks/generated/wv_hmc_n6_4policy_all_available_20260611/wv_hmc_n6_4policy_all_available_summary.csv`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/WV_HMC_N6_4POLICY_BURN_MIDDLE_GRID_20260616.md`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/wv_hmc_n6_4policy_burn_middle_grid_summary.csv`

These are compact summaries.  Raw histories, job-control ledgers, source-pin
manifests, and large generated outputs are not part of this public packet.

## Main Policy Readback

All-available 90k estimates alone favored `full_bounce`, but startup and
measurement-window effects were visible.  The burn/middle-window grid gave the
more stable routing signal.

Best scanned max `|four z|`:

| policy | best cut | max abs(z) |
|---|---|---:|
| `normal_reflection` | `burn15k_mid008_022` | 1.24 |
| `full_bounce` | `burn10k_mid003_027` | 1.45 |

The main policy is therefore `normal_reflect` / `normal_reflection`.
`full_bounce` / `paper_full_flip` remains available only as an optional
benchmark policy.

## Normal-Reflection Best Cut

Cut: `burn15k_mid008_022`.

| observable | samples | C | Re estimate | Re SE | Re z | Im estimate | Im SE | Im z |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 1818520 | 0.072066 | 0.0238843 | 0.0005999 | -0.99 | 0.0006618 | 0.0005346 | 1.24 |
| number_density | 1818520 | 0.072066 | 0.5774330 | 0.0324568 | 0.35 | -0.0197697 | 0.0318210 | -0.62 |

## Optional Full-Bounce Comparison

Cut: `burn10k_mid003_027`.

| observable | samples | C | Re estimate | Re SE | Re z | Im estimate | Im SE | Im z |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 3420574 | 0.071655 | 0.0240847 | 0.0004956 | -0.79 | 0.0008412 | 0.0005816 | 1.45 |
| number_density | 3420574 | 0.071655 | 0.5464004 | 0.0171162 | -1.15 | -0.0241854 | 0.0200566 | -1.21 |

## Stability Readback

Normal-reflection middle-window plateau:

| cut | max abs(z) |
|---|---:|
| `burn15k_mid008_022` | 1.24 |
| `burn10k_mid008_022` | 1.31 |
| `burn2k_mid008_022` | 1.35 |
| `burn15k_mid004_026` | 1.35 |
| `burn15k_mid003_027` | 1.35 |

Full-bounce best cuts:

| cut | max abs(z) |
|---|---:|
| `burn10k_mid003_027` | 1.45 |
| `burn10k_mid001_029` | 1.54 |
| `burn0_mid003_027` | 1.55 |
| `burn10k_fullT` | 1.57 |
| `burn0_mid001_029` | 1.58 |

The compact packet uses seed jackknife and burn/window sensitivity.  It does
not include a separate block-bootstrap artifact; a final production validation
packet should add block-size and bootstrap sensitivity if it is used for a
physics estimate rather than policy routing.

## Reproducibility Metadata

- Public flow backend: DOP853.
- Main boundary policy after this packet: `normal_reflect`.
- Optional benchmark policy after this packet: `full_bounce`.
- Measurement-window cuts are analysis diagnostics only.  They must not feed
  back into the transition kernel.
- Exact references used for the four-z checks:
  - chiral condensate: `0.0244771983`;
  - number density: `0.5661155667`.

## Claim Boundary

This packet closes the dense explicit-J WV-HMC boundary-policy ambiguity for
the public route.  It does not close:

- matrix-free / BiCGStab trajectory implementation;
- high-dimensional WV-HMC performance validation;
- final production physics estimates from WV-HMC;
- historical legacy ODE backend source cleanup.
