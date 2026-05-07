# Probe 5 Branch Symmetry Design

Updated: 2026-05-07 JST

## Purpose

Probe 5 targets the remaining correctness risk after the completed checks:

- deterministic/single-valued repeatability.
- successful-proposal reversibility.
- RG-reject identity handling.
- local metric-corrected volume preservation away from detected branch boundaries.

The remaining risk is the piecewise solver route:

```text
NT -> QN fallback -> post-refine -> RG -> Metropolis
```

Even if each smooth region is locally volume-preserving and RG-pass proposals are reversible, branch selection could still be dangerous if branch boundaries have non-negligible numerical measure or if accepted proposal routing is asymmetric in a way not caught by RG.

## Necessary Conditions

For the current deterministic proposal kernel to be safe enough for MCMC/HMC correctness, we need evidence for:

- Involution/reversibility on accepted proposals:
  - already covered by successful-proposal `REVCHK`, including fallback-only coverage.
- Identity on rejected proposals:
  - already covered for RG rejects by the RG-reject identity probe.
- Local volume preservation inside smooth branch regions:
  - covered for generic branch-stable rows and QN-enriched rows after using sufficiently small finite-difference eps.
- Branch-boundary measure is negligible:
  - not yet covered.
  - if tiny perturbations cross solver branches with a finite, non-vanishing rate as eps decreases, local-volume probes can miss a finite-measure discontinuity.
- Proposal route asymmetry does not create an uncaught accepted/rejected mismatch:
  - not yet covered beyond aggregate reversibility.

## Important Non-Requirement

Forward and reverse proposals do not necessarily need to take the exact same internal solver branch.

What is required is:

- the accepted proposal map is reversible under momentum flip within tolerance.
- the map is volume-preserving almost everywhere on the accepted region.
- rejected proposals leave the Markov state unchanged.
- any branch-boundary discontinuity has negligible measure or is safely rejected.

Therefore, branch-signature mismatch is a diagnostic warning, not automatically a proof of incorrectness.

## Probe 5a: Strong Branch-Stability Census

Goal: estimate whether solver branch boundaries shrink with perturbation size.

Method:

- Extend or add a probe app that evaluates the same local tangent-bundle map used by `probe_hmc_volume`.
- For each base point `(q, c)`, evaluate perturbations in `q` and `c` at eps ladder values.
- Record a stronger branch signature, not only `used_quasi`:
  - number of NT successes.
  - number of QN successes.
  - post-refine skip/attempt/success/fail deltas.
  - RG candidate/pass/reject deltas.
  - solver failure count delta.
  - optionally per-step route signature if inexpensive.
- For each eps, report:
  - accepted base points.
  - perturbation success rate.
  - fraction with exactly same strong signature.
  - fraction with only weak same signature (`used_quasi` same).
  - fraction with RG reject / solver reject in perturbations.

Pass-style interpretation:

- Good:
  - strong branch-instability fraction decreases toward zero as eps decreases.
  - weak branch-stable local-volume rows pass with small eps.
- Risk:
  - strong or weak branch-instability fraction plateaus above zero as eps decreases.
  - plateau is especially concerning if base proposals are accepted and perturbations remain accepted but route changes non-negligibly.

## Probe 5b: Forward-Reverse Route Signature Audit

Goal: check if accepted forward proposals and explicit reverse replay exhibit systematic route asymmetry.

Method:

- Reuse the successful-proposal `REVCHK` framework.
- Add route-signature deltas for the forward proposal and the reverse replay:
  - NT/QN counts.
  - post-refine skip/attempt/success/fail counts.
  - RG counts.
  - failure count.
- Report:
  - total REVCHK accepted proposals.
  - reversibility pass/fail as before.
  - forward/reverse route signature exact-match fraction.
  - mismatch examples with dx/dz/dp and route deltas.

Interpretation:

- Exact route match is reassuring but not required.
- Route mismatch with excellent reversibility is a diagnostic for branch-boundary/local-volume follow-up, not a standalone failure.
- Route mismatch plus degraded reversibility or local-volume instability is a serious issue.

## Recommended Next Execution Order

1. Implement Probe 5a first because it directly targets branch-boundary measure.
2. If 5a looks clean, implement 5b for route-asymmetry documentation.
3. If 5a shows a plateau, capture and replay representative boundary cases before any new 1024-seed production run.

## Current Inputs From Completed Probes

- Probe 4b initially failed at eps `3e-5`, `1e-5`, `3e-6`.
- Probe 4c showed the dominant QN bad row converged below tolerance at eps `1e-7`.
- This means the current evidence favors finite-difference/high-curvature behavior rather than a demonstrated local-volume defect.
- Probe 5 should therefore focus on branch-boundary measure rather than rerunning the same local-volume test unchanged.

## Probe 5a/5a2 Result

- Probe 5a found:
  - weak branch stability (`used_quasi`) was clean in the sampled rows.
  - NT rows were fully strong-stable.
  - QN rows had aggregate route-counter sensitivity.
- Probe 5a2 identified the changing counters:
  - only `post_refine_attempt_delta`, `post_refine_skip_delta`, and `post_refine_success_delta` changed.
  - NT/QN/failure/RG counters were not the source of the strong-instability flag.
- Current interpretation:
  - the remaining signal is post-refine skip-vs-attempt sensitivity.
  - this may be benign if both routes produce the same proposal within tolerance.
- Recommended next diagnostic:
  - verify post-refine route equivalence by disabling skip in an env-gated diagnostic run and comparing representative points.

## Probe 5b0 Design

- Add `QN_POST_NEWTON_REFINE_SKIP_ENABLED`, default enabled.
- In diagnostic mode only, set it to `0` so post-refine always runs DFOLS instead of returning at the initial-loss skip check.
- Run the same deterministic local-map sample twice:
  - skip-on: default route.
  - skip-off: forced post-refine attempt route.
- Use full detail rows for base and finite-difference perturbation points.
- Compare common QN detail rows in local chart coordinates:
  - `q_out`
  - `c_out`
  - `jac_out_abs`
- Treat max state difference <= `1e-8` as evidence that post-refine skip vs attempt is a benign computational route choice.

## Probe 5b0 Result

- Status: PASS.
- Compared 185 QN detail rows between skip-on and skip-off.
- Max state difference over `q_out`, `c_out`, and `jac_out_abs`: `0.000e+00`.
- Max `|dmetric_logvol|`: `0.000e+00`.
- Counter transitions showed only post-refine skip counts being replaced by matching attempt+success counts.
- Conclusion:
  - post-refine skip-vs-attempt sensitivity is proposal-equivalent in this sample.
  - the strong branch-instability signal from Probe 5a/5a2 is benign for the proposal map under this diagnostic.
