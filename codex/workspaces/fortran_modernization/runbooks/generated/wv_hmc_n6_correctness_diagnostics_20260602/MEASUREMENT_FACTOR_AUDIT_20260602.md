# WV-HMC Measurement-Factor Audit

Date: 2026-06-02

This note records the immediate audit after the n=6 offline weight-variant scan
made the WV measurement factor the leading suspect.  It is intentionally
separate from a code fix: the current evidence identifies a target, but does not
yet prove a replacement formula.

## Accountability

The previous diagnostic pass found that alpha-related offline weight variants
move the n=6 observables closer to exact references.  At that point, the work
should not have stopped at "alpha/W convention may be wrong."  A formula/code
audit should have been opened immediately.  This note starts that audit and
records what is already clear.

## Formula contract currently in the repo

The math/physics review states the worldvolume positive measure as

```text
|dz|_R = alpha * |dz_t| * dt
```

and the sampler Hamiltonian potential as

```text
V(z,t) = Re S(z) + W(t).
```

Therefore the positive sampled density, if the embedded WV-HMC kernel samples
the induced worldvolume measure, is

```text
exp[-Re S(z)-W(t)] * alpha * |det E| * dx * dt.
```

The complex target integrand is

```text
exp[-S(z)] * det(E) * dx * dt.
```

Under that convention the production accumulator should use

```text
weight = exp(W(t)) * exp[-i Im S(z)] * det(E)/|det(E)| / alpha.
```

This is exactly the formula implemented in
`src/sampler/wv_hmc_measurement.f90`:

```text
phase_factor = exp(i * (Im logdetJ - Im S))
wv_factor    = exp(W) * phase_factor / alpha
```

## Important distinction

An earlier algorithm readback wrote the WV-HMC observable ratio as

```text
F(z) = alpha^{-1} * det(E)/|det(E)| * exp(-i Im S(z)).
```

That expression is incomplete unless `W(t)=0` or unless `F` is defined as only
the non-`W` part of the reweighting factor.  The production code and the later
math review include the `exp(W)` correction.  Future docs/tests should avoid
using the ambiguous name `F(z)` without saying whether it includes `exp(W)`.

## What the current deterministic tests prove

The deterministic measurement tests prove internal implementation consistency:

- at `t=0`, `alpha2` matches the test's direct special-case expectation;
- nonzero supplied `W` multiplies the WV factor by `exp(W)`;
- the operator measurement factor matches the dense measurement factor at small
  nonzero flow.

These tests can catch a local coding typo, but they do not independently prove
that the Markov kernel's stationary measure is the induced worldvolume measure
assumed above.

## What the n=2 validation does not prove

The clean n=2 bank-init validation is an observable-level gate at
`T1=0.01`, `gamma=0`.  It does not stress the `W` correction, and the sign
problem is mild enough that an alpha convention error could be hidden by ratio
cancellation or weak correlation with observables.  It is not a sufficient
convention test for n=6.

The n=2 reweight-identity script is also not a fully independent convention
oracle for the current n=6 problem, because it assumes the same
`exp(W) * phase / alpha` structure when defining the "correct" WV weight.

## What the n=6 offline variants imply

For the existing n=6 32x1500 history, the current factor gives biased exact
observables, while alpha-related variants move them closer to the exact
references.  This does not prove that production should multiply by alpha.

It means one of the following must be audited:

1. the measurement factor formula or alpha definition is wrong;
2. the production WV-HMC transition does not sample the induced worldvolume
   measure assumed by the formula;
3. the offline variant analysis is exploiting finite-sample or nonergodic
   behavior rather than identifying a formula error;
4. a different code path, such as projection, momentum refresh, RATTLE volume
   preservation, or boundary/reverse-gate handling, changes the effective
   sampled measure.

## Required next tests before code change

Do not change `wv_factor` solely because `current_times_alpha2` or
`phase_times_alpha` looks better in one offline scan.

Required next tests:

1. Add an n=6-capable pointwise WV identity/oracle that compares:
   - direct contour weight `exp[-S(z_t(x))] det(E)`;
   - assumed WV positive density times production reweight factor;
   - alpha-multiplied alternative hypotheses.
2. Add a sampled-measure diagnostic that tests whether the implemented
   transition is consistent with induced worldvolume volume rather than an
   unintended coordinate measure.
3. Add explicit history columns for `W(t)`, `exp(W)`, `phase`, `alpha`,
   `1/alpha`, and `wv_factor` so offline audits do not have to infer the
   convention from a single combined weight.
4. Only after the identity/oracle and sampled-measure checks identify a specific
   mismatch should the production formula be changed.

## Current actionable conclusion

The current production line `wv_factor = exp(W) * phase / alpha` is not
obviously a typo relative to the repository's math review.  The bug, if present,
is more likely a convention/measure mismatch between the implemented transition
kernel and the measurement factor assumption, or an insufficiently independent
oracle/test suite.
