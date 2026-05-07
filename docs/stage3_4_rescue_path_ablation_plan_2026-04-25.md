# Stage 3.4 Rescue Path Ablation Plan

## Purpose

Stage 3.4 at `t=0.35` now shows that quasi fallback can move the Re-virial mean much closer to zero than no-fallback, but adding the old full-S1 rescue paths does not improve the result. Later probe/filter tests superseded the original rescue-search goal: the next task is to design a better rescue path, not to turn fallback off. The older matrices below are retained as ablation history.

The plan is staged:

1. Run a cheap screening matrix at `32 seeds x 50k cycles`.
2. Use the new route/budget diagnostics to reject unsafe paths.
3. Promote only 2-3 candidates to `400 seeds x 200k cycles`.

## Historical Runtime Paths Tested

The old S1 fallback path tested in ablations was:

1. Newton projection, `max_iter=100`.
2. Probe quasi stage: `QN_S1_PROBE_MAX_ITER`, default `28`.
3. If probe fails, classify trace as `NEAR`, `MID`, or `FAR`.
4. `NEAR` path: optional full retry with `QN_S1_NEAR_FULL_MAX_ITER`, default `100`.
5. `NON-NEAR` path: route as `SKIP`, `LIGHT`, or `ANCHOR`; optional cheap retry for `LIGHT/ANCHOR` with `QN_S1_NONNEAR_CHEAP_MAX_ITER`, default `36`.

Default-preserving controls:

- `QN_S1_PROBE_MAX_ITER`
- `QN_S1_NEAR_FULL_MAX_ITER`
- `QN_S1_NEAR_RESCUE_ENABLED`
- `QN_S1_NONNEAR_CHEAP_MAX_ITER`
- `QN_S1_NONNEAR_RESCUE_ENABLED`
- `QUASI_FINAL_RESORT_BUDGET`
- `QN_ACCEPTED_ITER_BUDGET`

## Required Diagnostics

New stage-2 summaries now include:

- `quasi_class_stats`: total local/mid/global classifications.
- `far_route_stats`: total skip/light/anchor routes.
- `near_rescue_stats`: near candidate/attempt/success/unusable counts.
- `quasi_watchdog_stats`: budget hit/used/limit counts.
- `far_investment_stats` and `far_investment_units`: future-proof route-budget accounting.

Existing summaries still include accepted-local route counters, failure counts, error bars, runtime, and Re/Im coverage.

## Screening Matrix

Screening config:

- `docs/stage_3_4_t035_rescue_screening_50k.json`
- `32` paired seeds, `50k` cycles.
- Output root: `output/tests/stage3_4/rescue_ablation/screen_50k`.

Policies:

| id | policy | intent |
|---|---|---|
| `probe_only_p28` | probe 28, near off, nonnear off | isolate probe-only path |
| `nonnear_off_p8` | probe 8, near on, nonnear off | low probe budget |
| `nonnear_off_p16` | probe 16, near on, nonnear off | moderate probe budget |
| `nonnear_off_p28` | probe 28, near on, nonnear off | current best reference |
| `nonnear_off_p40` | probe 40, near on, nonnear off | larger probe budget |
| `nonnear_off_p56` | probe 56, near on, nonnear off | aggressive probe budget |
| `near32_nonnear_off` | probe 28, near iter 32, nonnear off | near budget scan |
| `near64_nonnear_off` | probe 28, near iter 64, nonnear off | near budget scan |
| `near160_nonnear_off` | probe 28, near iter 160, nonnear off | near budget scan |
| `nonnear_on_cheap8` | nonnear on, cheap iter 8 | controlled nonnear retry |
| `nonnear_on_cheap16` | nonnear on, cheap iter 16 | controlled nonnear retry |
| `nonnear_on_cheap24` | nonnear on, cheap iter 24 | controlled nonnear retry |
| `nonnear_on_cheap36` | nonnear on, cheap iter 36 | old full-S1 default |
| `accept_iter8` | accepted iter watchdog 8 | cap accepted quasi trace budget |
| `accept_iter16` | accepted iter watchdog 16 | cap accepted quasi trace budget |
| `accept_iter32` | accepted iter watchdog 32 | cap accepted quasi trace budget |
| `final_budget5000` | final-resort watchdog 5000 | cap expensive internal recovery |
| `final_budget0` | final-resort watchdog disabled | diagnostic only, not production candidate |

## Promotion Criteria

Promote a policy only if all are true:

- Re and Im mean are not worse than `nonnear_off_p28` within screening uncertainty.
- Re P68/P95 do not regress clearly against `nonnear_off_p28`.
- Accepted full-stage/nonnear-route counts are either zero or explainably small.
- Failure reduction remains substantially better than no fallback.
- Runtime does not exceed current nonnear-off by more than roughly 25%.

Reject immediately if:

- Re mean shifts toward the old full-nonnear failure mode.
- `accepted_local_nonnear_route_count` grows materially without clear coverage gain.
- Watchdog hits dominate accepted quasi moves.
- Runtime grows while failure/error metrics do not improve.

## Runnable Files

- Screening config: `docs/stage_3_4_t035_rescue_screening_50k.json`
- Screening PBS: `output/tests/stage3_4/rescue_ablation/run_stage3_4_t035_rescue_screening_50k_matrix.pbs`
- Merge PBS: `output/tests/stage3_4/rescue_ablation/merge_stage3_4_t035_rescue_screening_50k_matrix.pbs`

Do not promote to large runs until the screening matrix has been merged and read.

## Promotion Screen

The first screening matrix found that the useful region is narrow:

- `QN_S1_NONNEAR_RESCUE_ENABLED=0`, `QN_S1_PROBE_MAX_ITER=28` is the current safe reference.
- `QN_S1_PROBE_MAX_ITER=40/56` and `QN_S1_NONNEAR_CHEAP_MAX_ITER=36` show a clear Re coverage failure mode.
- Near rescue and final-resort budget controls have negligible ensemble impact in the 50k screen.

The next step is a single promotion screen designed to pick large-seed candidates:

- Config: `docs/stage_3_4_t035_rescue_promotion_100k.json`
- Output root: `output/tests/stage3_4/rescue_ablation/promote_100k`
- `96` seeds, `100k` cycles.
- `no_fb` is run once as `no_fb_ref`.
- Each fallback policy runs `fb` only to avoid repeating identical no-fallback controls.

Promotion policies:

| policy | intent |
|---|---|
| `probe_only_p28` | minimal probe-only path, no near/nonnear rescue |
| `nonnear_off_p28` | current safe reference |
| `nonnear_off_p32` | moderate probe increase |
| `nonnear_off_p34` | threshold probe scan |
| `nonnear_off_p36` | threshold probe scan |
| `nonnear_off_p40` | known-danger boundary guard |
| `nonnear_on_cheap28` | nonnear cheap-retry threshold scan |
| `nonnear_on_cheap32` | nonnear cheap-retry threshold scan |
| `nonnear_on_cheap36` | known-danger boundary guard |

Runnable files:

- Promotion PBS: `output/tests/stage3_4/rescue_ablation/run_stage3_4_t035_rescue_promotion_100k_matrix.pbs`
- Merge PBS: `output/tests/stage3_4/rescue_ablation/merge_stage3_4_t035_rescue_promotion_100k_matrix.pbs`
- Summary PBS: `output/tests/stage3_4/rescue_ablation/summarize_stage3_4_t035_rescue_promotion_100k_matrix.pbs`
- Summary script: `scripts/compare_rescue_policy_matrix.py`

Promote to large-seed comparison only policies that keep Re P95 acceptable, remain stable against `nonnear_off_p28`, and do not pay a large runtime cost for small failure/error gains.

## Production Policy Update After Probe/Filter Matrix

The `64 seeds x 200k` probe/filter matrix changed the production policy:

- `p32_raw` produced a paired Re shift relative to `p28_filter`:
  `+0.004683 +/- 0.000581`.
- `p32_filter`, `p34_filter`, `p40_filter`, and `full_s1_filter` were all consistent with
  `p28_filter` at the `~2e-4` level.
- `full_s1_filter` did not show measurable improvement over bounded probe-only filter, while the
  raw full-S1 path was too slow and did not complete all seeds inside the walltime.

Updated conclusion:

- Keep quasi fallback as the improvement path and use no-fallback as the reference:
  `enable_quasi_fallback=true` for fallback candidates and `false` for no-fallback controls.
- Use bounded probe-only as the current working baseline.
- Disable quasi internal global fallback by default:
  `QN_QUASI_GLOBAL_FALLBACK_ENABLED=0`.
- Disable S1 near rescue by default:
  `QN_S1_NEAR_RESCUE_ENABLED=0`.
- Disable S1 non-near rescue by default:
  `QN_S1_NONNEAR_RESCUE_ENABLED=0`.
- Keep baseline `QN_S1_PROBE_MAX_ITER <= 32`, with `28` as the conservative default.

Interpretation:

The unsafe path is not branch switching itself. The likely issue is route asymmetry: forward and
reverse proposals can enter different solver paths (`probe`, `near`, `far`, continuation, restart,
seed sweep), while the Metropolis ratio does not include a proposal-route probability correction.
The robust design is therefore not simply "more rescue", but a rescue route whose selection and
reverse availability are controlled.

Candidate designs should start from bounded probe-only and add routes using a fixed-route mixture,
same-route reverse certification, or a proper delayed-rejection correction. Any run enabling global,
near, or non-near rescue must be labeled as a kernel-design test.
