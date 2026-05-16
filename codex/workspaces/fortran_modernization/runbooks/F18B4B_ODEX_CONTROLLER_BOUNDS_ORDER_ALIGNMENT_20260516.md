# F18b.4b ODEX Controller Bounds And Order Alignment

Date: 2026-05-16 JST
Scope: first behavior-changing source patch under HWM-ODEX-001.
Status: accepted for the current modernization tree after focused tests, local
10seed/1k and 10seed/10k screens, post-B anchor update, and full M4.

## F8 Statement

This patch intentionally changes ODEX endpoint-controller behavior.  It is not a
behavior-preserving cleanup.

Reference intent:

- keep the TLTM product boundary as endpoint-only ODEX, not dense-output or
  general-purpose Hairer ODEX;
- align the adaptive step-size and final-order controller with Hairer-style
  ODEX constants rather than the previous TLTM-specific partial controller;
- keep SUNDIALS CVODE as disabled-by-default comparison evidence, not the
  canonical route.

Allowed behavior changes:

- accepted/rejected ODEX step counts may change;
- candidate endpoint step sizes may change;
- final accepted ODEX order may change;
- downstream HMC/QN proposal outcomes may change if the endpoint flow changes.

Explicit non-goals:

- no RATTLE failure-policy change;
- no Metropolis reject-output reset in this patch;
- no QN/official DFO-LS route change;
- no production-comparison promotion from this patch without the paired screen
  and later frozen-commit contract.

## Reference Mapping

The implementation uses the Hairer ODEX controller constants surfaced in
`odex_options`:

| Field | Default | Role |
| --- | --- | --- |
| `step_size_bound_fac1` | `0.02` | Hairer `FAC1 = 1/50`; contributes to the order-dependent scale bound |
| `step_size_bound_fac2` | `4.0` | Hairer `FAC2`; contributes to the order-dependent shrink bound |
| `order_decrease_factor` | `0.8` | Hairer-style decrease/order demotion factor |
| `order_increase_factor` | `0.9` | Hairer-style increase/order promotion factor |

The bounded step scale is:

```text
raw_scale = SAFE2 * (SAFE1 / max(error, error_floor)) ** (1 / (2*k - 1))
facmin    = FAC1 ** (1 / (2*k - 1))
scale     = clamp(raw_scale, facmin / FAC2, 1 / facmin)
```

with `SAFE1=0.65`, `SAFE2=0.94`, and the existing TLTM error floor retained.
The reference source for the constants is Hairer's public ODEX implementation:
`https://www.unige.ch/~hairer/prog/nonstiff/odex.f`.

## Source Changes

- `src/physics/odex_backend.f90`
  - adds the controller option fields and normalization;
  - routes `calculate_hk` and `calculate_wk` through `odex_step_scale`;
  - applies the bounded scale to both endpoint integration and observation
    helpers;
  - changes the old final demotion predicate from the single `0.9` rule to
    separate `0.8` demotion and `0.9` promotion factors.

- `tests/test_odex_controller_alignment_spec.f90`
  - changes expected current gaps from four to two;
  - verifies growth and shrink bounds directly;
  - verifies keep/demote/promote order probes against the new factors.

- `tests/test_odex_controller_observation_contract.f90`
  - updates controller-estimate expectations to include the same bounds while
    preserving signed intervals, positive work estimates, and failure
    classification surfaces.

## Focused Verification

Passed locally:

```bash
make -C build test_odex_controller_alignment_spec test_odex_controller_observation_contract
```

Observed focused readback:

- `growth_ratio=1.7487E+00` for the zero-error order-4 probe;
- `shrink_ratio=1.4297E-01` for the large-error order-4 probe;
- expected ODEX controller gaps are now `2`, not `4`;
- signed endpoint interval, max-step failure, h-min failure, and conservative
  stability observation still pass.

## M4 And Affected-Baseline Readback

Initial full M4 correctly tripped the deterministic post-B anchor after the
controller behavior change:

```text
post-B stage2_summary expected b3c3b9192018337e633b9183e5ed74c62358109058b75d8484d589d682f70dfd
post-B stage2_summary actual   ecd5973ff2f578af962a62b2fb8dd94b183158726b88f0674de4986dfbd668d2
```

The anchor repeat check was stable: `run_a` and `run_b` produced the same new
normalized hash.  After the 1k and 10k screens below showed the change stayed on
the accepted output surface, `POST_B_RNG_REFERENCE_ANCHOR_V1.json` was updated to
the new Stage2 summary hash.

Full M4 then passed:

```bash
make -C build modernization_guardrails
```

## 10seed/1k Screen

Local current-worktree screen:

```text
output/tests/f18b4b_odex_bounds_order_10seed_1k_20260516T063826
```

Compared with the previous 1k base readback row, the failure and observable
surface was close enough to scale:

| method | unresolved | pair0 accept | mean Re | mean Im | Zmean Re | Zmean Im |
| --- | ---:| ---:| ---:| ---:| ---:| ---:|
| no_fb | 890 | 0.4402 | 0.16354890732706878 | 0.06437810403082284 | 0.9845781042229088 | 0.5004894509419484 |
| fb_norefine | 16 | 0.4356 | 0.08685769128586888 | 0.07669041196034852 | 0.6878077177692228 | 0.8893065742668113 |

No max-step, invalid-state, or reverse-replay failure surface appeared.

## 10seed/10k Screen

Local current-worktree screen:

```text
output/tests/f18b4b_odex_bounds_order_10seed_10k_20260516T064256
```

Compact readback:

| method | mean Re | mean Im | Zmean Re | Zmean Im | failures | RG rejects |
| --- | ---:| ---:| ---:| ---:| ---:| ---:|
| no_fb | 0.0019528482220934804 | -0.02786044660484825 | 0.03382818583627952 | -0.6644160270087625 | 8300 | 1076 |
| fb_norefine | 0.02311080440482635 | 0.004007786293613718 | 0.4197458251236253 | 0.10935044927261645 | 166 | 1274 |

Comparison to the accepted npt5_r0055 assist-off 10seed/10k baseline:

| method | baseline failures | F18b.4b failures | baseline mean Re | F18b.4b mean Re | baseline mean Im | F18b.4b mean Im | baseline RG rejects | F18b.4b RG rejects |
| --- | ---:| ---:| ---:| ---:| ---:| ---:| ---:| ---:|
| no_fb | 8340 | 8300 | -0.002818340294982019 | 0.0019528482220934804 | -0.02465681851224433 | -0.02786044660484825 | 1150 | 1076 |
| fb_norefine | 167 | 166 | 0.02974362444598664 | 0.02311080440482635 | -0.002988766099182953 | 0.004007786293613718 | 1324 | 1274 |

Interpretation: this controller patch changes deterministic trajectories, as
expected, but the 10seed/10k failure, reverse-gate, and observable surface stays
inside the accepted npt5_r0055 assist-off baseline neighborhood.  The patch is
therefore accepted for the current modernization tree, not as a final production
redo.

## Remaining Controller Gaps

This patch does not close all HWM-ODEX-001 surfaces.

Still open:

- first-step `h0` estimator: current default remains `0.01*t`;
- h-min/rejected-step policy and failure classification: current TLTM floor and
  status mapping are retained;
- default stability policy: conservative stability rejection remains opt-in;
- large-error rejection threshold and strict-double error floor remain current
  TLTM behavior unless later evidence requires a separate patch.

## Remaining Gates And Scope Boundary

This acceptance is local-modernization evidence.  Before using this patch for
production-comparison regeneration, freeze a clean commit and rerun or explicitly
waive the remote PBS/provenance wrapper gate.

The next F18b.4 ODEX controller decision is h0 policy.  F18b.4c attempted an
isolated Hairer-style initial `H`/initial `K` transplant and blocked it with
1k/timing evidence, so the remaining controller families are not "just apply the
next Hairer line" edits:

1. first-step `h0` estimator;
2. h-min/rejected-step policy and failure classification;
3. default stability policy.
