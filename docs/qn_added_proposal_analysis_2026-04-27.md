# QN Added-Proposal Analysis

Date: 2026-04-27

## Question

We need to explain why proposals added beyond the current `p28` QN probe can
damage the Stage-3.4 `t=0.35` Re-virial result, or identify a design that makes
those proposals usable.

The working rule is:

```text
branch switching is allowed
```

The validity question is not branch identity. The validity question is whether
the final transition kernel is correctly represented by the current Metropolis
acceptance rule.

## Seed-Level Evidence

At `1024 seeds x 200k`:

| policy | Re mean | unresolved failures |
|---|---:|---:|
| no_fb_ref | `-0.0208976` | `15131675` |
| probe_only_p28 | `+0.00543094` | `2974657` |

So p28 QN is a real improvement in failure count and coverage, but still leaves
a statistically visible Re-mean offset.

Promotion / screening evidence:

| policy family | behavior |
|---|---|
| `p28` | useful, much fewer failures, still Re offset |
| `p32` | tiny extra failure gain, measurable paired shift |
| `p34/p36/p40` | many more failures rescued, Re coverage/mean degrades badly |
| filter variants | suppress some shift but mostly by not adding many useful proposals |
| zero-start fallback | removed; did not improve correctness |

This pattern is consistent with:

```text
rescuing more proposals is not automatically better
```

but it does not by itself identify the faulty mechanism.

## Minimal Replay Audit

Source:

```text
output/tests/stage3_4/qn_added_audit/min_capture_1seed_1000
```

Setup:

- one seed: `20260421`
- `1000` cycles
- `86` captured Newton failures
- replayed the same failures under QN policies

Replay result:

| policy | success |
|---|---:|
| `p28` | `70/86` |
| `p34` | `70/86` |
| `p40` | `70/86` |
| `p100_noglobal` | `70/86` |
| `global36` | `86/86` |
| `global100` | `86/86` |

In this sample, increasing the single-pass QN iteration budget adds nothing.
The added proposals come from global continuation/restart routes.

The 16 `global36`-added cases:

```text
13, 28, 37, 38, 39, 40, 46, 49, 52, 57, 60, 65, 66, 72, 74, 78
```

Their route sources:

| route | count |
|---|---:|
| continuation scale `1.00` | `10` |
| fine continuation scale `1.00` | `1` |
| restart kick positive | `2` |
| seed sweep zero | `2` |
| seed sweep negative-stage | `1` |

Endpoint diagnostic:

| group | n | mean Re z | mean Re virial |
|---|---:|---:|---:|
| p28/common successes | `70` | `-0.10652` | `-3.07522` |
| global-added successes | `16` | `+0.04323` | `-3.24549` |

The added cases are structured. They are not a random copy of the p28-success
population.

## Reverse Audit Result

Actual-policy local reverse audit:

| group | n | reverse converged | small reverse error |
|---|---:|---:|---:|
| p28/common successes | `70` | `70` | `65` |
| global-added successes | `16` | `16` | `16` |

For the 16 added cases:

```text
median dx = 2.43e-14
median dz = 4.29e-14
median dp = 7.86e-13
max dx    = 1.69e-13
max dz    = 2.51e-13
max dp    = 7.20e-12
```

Therefore this audit does not support:

```text
added proposals are bad because they fail local reversibility
```

The surprise is the opposite: five p28/common successes fail the same reverse
audit with large return errors:

```text
sample 17: endpoint Re z=-0.26514
sample 31: endpoint Re z=-0.26572
sample 42: endpoint Re z=+0.26942
sample 44: endpoint Re z=-0.30507
sample 63: endpoint Re z=-0.26464
```

These cases cluster near `Re z ~= +/-0.265`, and should be treated as a baseline
p28 defect class.

## What This Rules Out

This rules out several weak explanations:

1. `p34/p40` failures are just insufficient iteration budget.
   In the minimal replay, even `p100_noglobal` adds no cases.
2. The first observed `global36` added proposals are not simply non-reversible.
   They pass local reverse better than some p28 successes.
3. Zero-start fallback is not the missing route.
   It was tested earlier and removed because it did not move correctness in the
   right direction.
4. Post-QN refinement with the simplified Newton loss is not enough to recover
   the p28 reverse-bad subset. The sign conversion was handled as
   `ld_seed = -Jl_qn`, because QN uses `z + del_z + Jl_qn` while simplified
   Newton uses `z + del_z - ld_newton`. The Newton `u` seed is the
   inverse-flowed coordinate displacement,
   `u_seed = inverse_flow(z + del_z + Jl_qn) - x0`, not QN's internal `xi`.

Post-QN Newton-refinement replay:

| policy | solved | reverse-bad ids |
|---|---:|---|
| `p28` baseline | `70/86` | `17,31,42,44,63` |
| `p28 + post_newton` | `70/86` | `17,31,42,44,63` |
| `global36` baseline | `86/86` | `17,31,42,44,63` |
| `global36 + post_newton` | `86/86` | `17,31,42,44,63` |

The refinement preserves the clean reverse behavior of the 16 global-added
cases, but it does not fix the baseline p28 reverse-bad cases.

## Current Best Explanation

There are likely two separate effects:

1. Baseline `p28` has a small non-reversible subset near `Re z ~= +/-0.265`.
   This may contribute to the remaining `+0.00543 ± 0.00102` Re-mean offset.
2. Deep rescue routes such as `p34/p36/p40/fullpath` add a structured proposal
   population. The first 16 added cases pass reverse, so if they are still
   invalid under the current acceptance rule, the missing check is probably not
   branch identity but proposal accounting:

```text
full phase-space volume / Jacobian
route-selection support
candidate-selection multiplicity
delayed-rejection proposal ratio
```

In short:

```text
"can solve the constraint" is not sufficient
```

because the current HMC Metropolis rule assumes the deterministic proposal map
has the right reversibility and volume/proposal-density properties.

## How To Make More Proposals Usable

The production design should avoid conditional heuristic escalation:

```text
route A fails -> route B -> route C -> accept first success
```

unless the resulting proposal ratio is explicitly accounted for.

The viable designs are:

| design | rationale |
|---|---|
| fixed route | route chosen before solving; simplest to validate |
| fixed route mixture | route sampled from fixed state-independent weights; route probability cancels |
| multiple-try QN | evaluate a fixed candidate set and use proper multiple-try weights |
| delayed rejection | sequential fallback with the correct delayed-rejection acceptance formula |
| Jacobian-corrected proposal | only if full phase-space `log|det dT|` can be measured or computed |

The most practical next production direction is:

```text
fixed route / fixed route mixture
```

not another post-hoc geometry filter.

## Next Discriminating Tests

The next tests should be diagnostic, not a large seed promotion.

1. Full local phase-space finite-difference `log|det dT|`.
   Compare p28/common, p28 reverse-bad, and global-added cases. This must be
   done in a reduced tangent coordinate chart; a raw determinant in the stored
   `(x, p)` arrays is not meaningful because `x` includes the fixed flow-time
   slot and `p` is stored in a redundant projected representation.
2. Larger capture focused on the bad deep-QN region.
   Minimal replay did not expose p34/p40 additions, but seed-level runs show that
   p34/p36/p40 are the bad regime.
3. Route-specific fixed-route tests.
   Do not let routes conditionally fall through. Run one fixed route per policy
   and compare consistency.

Immediate decision:

```text
keep production default at p28
do not promote fullpath/deep-QN
do not trust reverse-only filtering as the solution
```

The next code-level audit target is full local phase-space Jacobian and
route-specific capture for p34/p36/p40 added cases.
