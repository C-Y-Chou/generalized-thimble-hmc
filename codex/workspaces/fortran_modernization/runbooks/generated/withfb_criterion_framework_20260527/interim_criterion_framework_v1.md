# Interim Criterion Framework v1: `withfb` vs `nofb`

Date: 2026-05-27

Scope: Stephanov `n=6`, TLTM `t_high = 0.03`, current `nofb` vs `withfb` production comparison.

This framework freezes the final decision gates before the completed `withfb` data are available. After `withfb` finishes, new data should be inserted into these gates; the gates and thresholds should not be redefined in response to the outcome.

## 1. Current Interim Status

Current status:

- Transport warning flag; no production switch yet.
- Lower failure count itself is not a criterion.
- Current positive non-circular evidence is failure-mediated ladder transport only.
- Denominator-stability and observable-bias gates currently do not support `withfb` necessity.
- Wall-clock efficiency is unavailable.
- Final `withfb` failure, swap, runtime, and solver summaries are unavailable.

Current interpretation:

`nofb` failures are not obviously harmless because they correlate with degraded ladder transport. However, current evidence is insufficient to adopt `withfb` as production default because the transport signal has not yet been shown to propagate to observable correctness, ratio-estimator stability, high-flow ergodicity failure, or wall-clock-normalized efficiency.

## 2. Gate Hierarchy

### Hard Gates

Hard gates are allowed to decide the final production method.

1. Observable correctness
   - `Re(chiral_condensate)` vs exact `0.0244771983`
   - `Im(chiral_condensate)` vs zero
   - `Re(number_density)` vs exact `0.5661155667`
   - `Im(number_density)` vs zero

2. Wall-clock efficiency
   - phase ESS per wall-clock hour
   - round trips per wall-clock hour
   - `1 / SE_Re(chiral_condensate)^2` per wall-clock hour
   - `1 / SE_Re(number_density)^2` per wall-clock hour
   - runtime and solver-cost decomposition

### Mechanistic Gates

Mechanistic gates explain why one method should be trusted, but they do not by themselves justify a production switch unless they connect to a hard gate or severe ergodicity risk.

1. Ratio-estimator stability
   - global pooled phase coherence `C`
   - block-level `C`
   - phase ESS
   - denominator magnitude `|D|`
   - denominator phase `arg(D)`
   - denominator outlier rate
   - leave-one-seed influence

2. Ladder transport / high-flow return
   - label MSD
   - round trips
   - zero-round-trip seeds
   - high-flow first passage
   - high-flow return time
   - high-flow residence
   - high-flow consecutive-stay length

3. Failure-mediated repair
   - matched seed/block `delta_failure_rate`
   - matched seed/block transport changes
   - matched seed/block ratio-stability changes
   - matched seed/block observable-error changes
   - whether high-failure `nofb` seeds/blocks are exactly where `withfb` improves downstream metrics

4. Edge-localized bottleneck
   - failure rate by ladder edge
   - swap acceptance by edge
   - accepted flux by edge
   - bottleneck rank
   - whether `withfb` repairs the same edges that bottleneck `nofb`

## 3. Final Decision Rules

### Adopt `withfb` Only If

Adopt `withfb` only if at least one of the following conditions is met:

1. Observable correctness rescue:
   - `nofb` fails observable correctness under robust seed/block uncertainty; and
   - `withfb` fixes or materially reduces the same failure under matched or equal-cost comparison.

2. Ratio-estimator stability rescue:
   - `nofb` has ratio-estimator instability, such as denominator collapse, phase-ESS degradation, denominator-angle drift, or ratio outlier concentration; and
   - `withfb` repairs the same instability in matched seeds/blocks.

3. Transport degradation propagates downstream:
   - `nofb` transport degradation propagates to estimator quality or high-flow ergodicity risk; and
   - `withfb` repairs that transport degradation in the same seeds/blocks/edges.

4. Wall-clock productivity:
   - `withfb` is competitive or better in primary information rate per wall-clock hour:
     - `1 / SE_Re(chiral_condensate)^2 / hour`, or
     - `1 / SE_Re(number_density)^2 / hour`; and
   - `withfb` does not materially degrade the other primary observable.

### Keep `nofb` If

Keep `nofb` if all of the following hold:

1. Observable correctness passes:
   - chiral and density real parts are statistically compatible with exact values;
   - imaginary parts are statistically compatible with zero;
   - no stable same-direction drift appears across prefixes, blocks, or seeds.

2. Denominator stability passes:
   - failure does not predict denominator instability;
   - no severe denominator outlier or seed-influence problem appears;
   - global and block phase diagnostics are stable enough for the target analysis.

3. Transport warning does not propagate downstream:
   - transport degradation does not produce observable bias, ratio instability, high-flow non-return, or reduced wall-clock-normalized precision.

4. Wall-clock efficiency favors or ties `nofb`:
   - `nofb` wins or ties `withfb` in primary `1 / SE^2 / hour` metrics.

5. Robustness checks pass:
   - conclusions survive seed bootstrap;
   - conclusions survive block-size variation;
   - conclusions survive matched-seed common-prefix comparison;
   - conclusions survive equal-wall-clock comparison.

## 4. Transport-Only Rule

Transport-only improvement is not enough for a production switch unless it indicates severe ergodicity risk.

Severe ergodicity risk includes:

- nonzero zero-round-trip seed fraction;
- high-flow non-return;
- high-flow trapping;
- edge bottleneck trapping;
- failure-mediated transport collapse that prevents adequate exchange across the ladder.

Otherwise, transport improvement is secondary evidence. It must connect to at least one of:

- observable quality;
- ratio-estimator stability;
- high-flow endpoint correctness;
- wall-clock productivity.

## 5. Cut Hierarchy

Use cuts in the following order of interpretive priority:

1. Matched-seed equal-prefix
   - Best for algorithmic comparison before final runtimes are available.
   - Must preserve paired seed IDs where possible.

2. Equal-wall-clock
   - Required for final production decision.
   - Primary cut for cost-adjusted efficiency.

3. Equal-cycle
   - Useful for per-cycle algorithmic behavior.
   - Not sufficient if runtime differs strongly.

4. All-available
   - Operationally useful.
   - Not algorithm-intrinsic if sample counts, cycle counts, or wall-clock budgets differ.

## 6. Deferred Items Requiring Finalized `withfb` Summaries

The following must wait for finalized `withfb` outputs:

- true `withfb` failure counts;
- swap acceptance by ladder edge;
- local acceptance by flow-time slot;
- fallback calls;
- DFO-LS objective evaluations;
- ODE calls;
- ODE step counts;
- per-record wall-clock timing;
- production timing breakdown;
- equal-wall-clock cuts;
- true paired `delta_failure_rate`;
- edge-localized bottleneck repair;
- cost-adjusted rescued-failure value.

## 7. Final Rerun Checklist

When `withfb` finishes, this workspace should rerun the full failure-impact analysis with finalized `withfb` summaries.

### 7.1 Observable Correctness

Compute:

- chiral/density Re/Im against exact/zero;
- robust seed/block jackknife or bootstrap;
- matched-seed common-prefix cuts;
- all-available cuts;
- equal-cycle cuts;
- equal-wall-clock cuts.

Classify as:

- favors `withfb`;
- favors `nofb`;
- inconclusive;
- unavailable.

### 7.2 Ratio-Estimator Stability

Compute:

- global pooled `C`;
- block-level `C`;
- phase ESS;
- `|D|`;
- `arg(D)`;
- denominator outlier rate;
- leave-one-seed influence;
- failure-conditioned denominator instability.

### 7.3 Ladder Transport / High-Flow Return

Compute:

- label MSD;
- round trips;
- high-flow first passage;
- high-flow return time;
- zero-round-trip fraction;
- high-flow residence;
- high-flow consecutive-stay length.

### 7.4 Failure-Mediated Repair

Compute matched seed/block:

- `delta_failure_rate`;
- `delta_transport`;
- `delta_ratio_stability`;
- `delta_observable_error`;
- directional consistency across seeds;
- whether high-failure `nofb` seeds/blocks are where `withfb` improves.

### 7.5 Edge-Localized Bottleneck

Compute:

- failure rate by edge;
- swap acceptance by edge;
- accepted flux by edge;
- bottleneck rank;
- whether `withfb` fixes `nofb` bottleneck edges.

### 7.6 Wall-Clock Efficiency

Compute:

- phase ESS/hour;
- round trips/hour;
- `1 / SE_Re(chiral_condensate)^2 / hour`;
- `1 / SE_Re(number_density)^2 / hour`;
- DFO-LS cost breakdown;
- ODE cost breakdown.

### 7.7 Non-Circularity Requirement

Do not use lower failure count as proof. Failure can support a decision only if it predicts or repairs downstream non-failure degradation.

Allowed downstream metrics:

- observable correctness;
- ratio-estimator stability;
- ladder transport;
- high-flow return;
- seed robustness;
- wall-clock-normalized information rate.

## 8. Frozen Interpretation

Current frozen interim label:

`transport warning flag; no production switch yet`.

This framework is now fixed as criterion framework v1. The completed `withfb` data should be inserted into these gates without changing the gate hierarchy or the decision rules.
