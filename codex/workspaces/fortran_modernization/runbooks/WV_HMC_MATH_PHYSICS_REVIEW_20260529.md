# WV-HMC Math And Physics Review

Date: 2026-05-29

Purpose: close the pre-implementation math/physics review for adding WV-HMC as
a sibling sampler.  This review assumes the paper formulas can contain typos or
notation omissions, so each formula below is checked against the geometry,
Hamiltonian mechanics, and the existing TLTM/GT-HMC convention rather than
copied literally.

Primary references:

- `references/2311.10663v4.pdf`: simplified GT-HMC/WV-HMC algorithm.
- `references/1912.13303_TLTM_HMC.pdf`: current TLTM/GT-HMC background.
- Fukuma and Matsumoto, "Worldvolume approach to the tempered Lefschetz thimble
  method", arXiv:2012.08468 / PTEP 2021, 023B08.
- Existing pre-implementation contract:
  `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`.

## Review Verdict

The simplified WV-HMC algorithm is mathematically consistent if the formulas are
read with the anti-holomorphic-flow conjugation convention and with the paper's
`partial V` convention.  Literal PDF/OCR text can be misleading: the flow,
tangent-flow, and normal-flow equations often appear without visible overbars or
stars in extracted text.  The implementation must therefore encode the
mathematical convention, not the raw extracted characters.

The current TLTM code contains a fixed-flow GT-HMC-style RATTLE/Newton kernel.
It is useful as the fixed-surface part of WV-HMC, but it is not a WV-HMC kernel.
WV-HMC requires a new sampler layer for `(t, x, z, pi)`, worldvolume projection,
the `(h, u, lambda)` RATTLE solve, the `W(t)` force term, boundary handling, and
the `alpha^{-1}` measurement weight.

Implementation should start with dense small-N oracles and formula tests.  The
matrix-free BiCGStab backend can then be certified against those oracles before
being used for high-dimensional production.

## Future Formula Recovery Rule

If a later implementation step finds that a formula, coefficient, sign, or
definition was not copied into this review, do not paste it directly from the
paper into source or into the algorithm contract.  Treat the paper expression as
a candidate formula and rerun the same math/physics review rule:

1. Record the source paper, equation number, page, and local meaning of every
   symbol.
2. Translate the expression into this repo's conventions:
   `xi = conj(partial S)`, real target-space inner product, target-space force
   vector, carried `(t,x,z)` state, and manual derivative provider.
3. Re-derive the formula from the geometry, Hamiltonian/RATTLE update, or
   measurement ratio, rather than relying only on visual transcription.
4. Check invariants that the formula must satisfy, such as `Im S` conservation,
   tangent-normal orthogonality, WV projection orthogonality, `alpha^{-1}`
   measure correction, reversibility, and energy-error scaling.
5. Add or name the validation test that would fail if the transcription had the
   wrong sign, conjugation, or factor of two.

No newly recovered formula is implementation-ready until this process is
recorded.  If the paper expression and the independent derivation disagree, keep
the item in the typo/convention risk register and do not use it in production
code until the conflict is resolved.

## Core Conventions

Use the real target-space inner product

```text
<u, v> = Re(u^dagger v).
```

The anti-holomorphic flow is

```text
dot z = xi(z),       xi(z) = conj(partial S(z)).
```

This is not optional.  Without the conjugation,

```text
dS/dt = partial S . dot z
```

would not equal `|partial S|^2` and `Im S` would not be constant along the
flow.  The conjugated form gives

```text
dS/dt = sum_i partial_i S * conj(partial_i S) = |partial S|^2,
```

so `Re S` increases and `Im S` is conserved.  Any paper/OCR expression that
looks like `dot z = partial S` must be treated as a notation/extraction risk
unless the star/overbar convention is explicitly restored.

For implementation, define one explicit vector:

```text
force(z) = target-space vector corresponding to paper partial V(z).
```

For GT-HMC,

```text
force_GT(z) = 1/2 * xi(z).
```

For WV-HMC,

```text
force_WV(z, t) = 1/2 * [ xi(z) + W'(t)/<xi_n, xi_n> * xi_n ].
```

This is the vector that appears in

```text
Delta z = Delta s * pi - (Delta s)^2 * force(z).
```

Do not implement a raw holomorphic `partial V` vector in the real-coordinate
RATTLE update.

## Anti-Holomorphic Flow, Tangent Flow, Normal Flow

Let `g(z) = partial S(z)` and `H(z) = partial_i partial_j S(z)`.  With

```text
dot z = conj(g(z)),
```

a real tangent perturbation `v` obeys

```text
dot v = conj(H(z) * v).
```

Reason: vary `z -> z + eps v` with real `eps`, differentiate the
anti-holomorphic flow, and then set `eps = 0`.

The normal-flow companion must preserve real orthogonality between transported
tangent and normal spaces.  With symmetric holomorphic Hessian `H = H^T`, the
choice

```text
dot n = -conj(H(z) * n)
```

gives

```text
d/dt <v, n> = 0
```

for every tangent-flow vector `v` and normal-flow vector `n`.  This fixes the
sign and conjugation.  A paper/OCR formula that lacks the conjugation is not
safe to use directly.

## Fixed-Surface GT-HMC Check

For a fixed flowed surface

```text
Sigma_t = { z_t(x) | x in R^N },
E_a = partial z_t / partial x_a,
gamma_ab = <E_a, E_b>,
```

the positive measure is

```text
|dz_t| = sqrt(det gamma) dx = |det E| dx.
```

The fixed-surface reweighting factor is

```text
F_GT(z) = det(E)/|det(E)| * exp(-i Im S(z)).
```

The target-space Hamiltonian is

```text
H_GT(z, pi) = 1/2 <pi, pi> + Re S(z),     pi in T_z Sigma_t.
```

The paper's RATTLE normalization is internally consistent:

```text
pi_half = pi - Delta s * force(z) - lambda/Delta s
z'      = z + Delta s * pi_half
pi'     = pi_half - Delta s * force(z') - lambda'/Delta s
```

Because Hamilton's equation is written as `dot pi = -2 partial V`, the
`-Delta s * partial V` term is the usual half step.  There is no missing factor
of `1/2` in

```text
Delta z = Delta s * pi - (Delta s)^2 * force(z).
```

The existing TLTM code's `del_z = step_size * momentum - step_size**2 * dV`
therefore matches the simplified GT-HMC convention if `dV` is interpreted as
the target-space `force(z)` above.

## Fixed-Surface Projection

For `w in T_z C^N`, the fixed-surface split is

```text
w = w_v + w_n,     w_v in T_z Sigma_t,     w_n in N_z Sigma_t.
```

The simplified algorithm represents this split by the real-linear map

```text
A w0 = E v0 + F n0,
v0 = (w0 + conj(w0))/2,
n0 = (w0 - conj(w0))/2.
```

The dense small-N oracle may build the real matrix for `E`, factor it, and
recover `w_v`, `w_n`, and `w0_v`.  The high-dimensional backend should solve
`A w0 = w` with a matrix-free iterative method using flow, tangent-flow, and
normal-flow actions.  Both paths must expose the same logical result:

```text
w_v, w_n, w0_v, residual, status.
```

The sampler should never branch on "dense versus BiCGStab" in its physics
logic.  That choice belongs to the projection backend.

## Worldvolume Geometry

WV-HMC samples the worldvolume

```text
R = { z_t(x) | t in interval, x in R^N }.
```

Coordinates are `xhat = (t, x)`, and

```text
dz = xi dt + E_a dx_a.
```

Split the flow vector by fixed-surface projection:

```text
xi = xi_v + xi_n,
xi_v in T_z Sigma_t,
xi_n in N_z Sigma_t.
```

Then the induced metric has ADM form with

```text
gamma_ab = <E_a, E_b>,
beta^a   = gamma^{ab} <xi, E_b>,
alpha^2  = <xi_n, xi_n>.
```

The worldvolume positive measure is

```text
|dz|_R = alpha * |dz_t| * dt.
```

If the sampler Hamiltonian is
`H = 0.5 ||pi||^2 + Re S(z) + W(t)`, the positive worldvolume density contains
`exp[-Re S(z)-W(t)]`.  The complex worldvolume integral carries the same
`exp[-W(t)]` weight, so `W(t)` cancels in the reweighting factor.  Therefore
the WV-HMC measurement factor is

```text
F_WV(z) = alpha^{-1} * det(E)/|det(E)| * exp(-i Im S(z)).
```

The `alpha^{-1}` factor is mandatory.  `W(t)` belongs to the sampling potential
and to the W-weighted target integral, but it must not be multiplied into
`F_WV`; doing so measures a different ratio except in the special `W(t)=0`
case.

Degeneracy condition:

```text
alpha^2 = <xi_n, xi_n> > 0
```

is required for a valid local worldvolume coordinate.  Near-zero `alpha^2`
should be a typed sampler/projection failure, not silently regularized.

## WV Projection

First perform the fixed-surface split:

```text
w  = w_v  + w_n,
xi = xi_v + xi_n.
```

Since `T_z R = T_z Sigma_t + span(xi_n)`, the worldvolume projection is

```text
c          = <xi_n, w_n> / <xi_n, xi_n>
w_parallel = w_v + c * xi_n
w_perp     = w_n - c * xi_n.
```

Then

```text
w_parallel in T_z R,
w_perp     in N_z R,
<w_parallel, w_perp> = 0.
```

This is a mathematical wrapper around the fixed-surface projection.  Reusing
the current fixed-surface projector without the `xi_n` correction would project
onto `T_z Sigma_t`, not `T_z R`.

## WV Force

The WV potential is

```text
V(z) = Re S(z) + W(t(z)).
```

On the worldvolume, `partial t` has no component along `T_z Sigma_t` and has
worldvolume-tangent component

```text
(partial t)_parallel = [1 / (2 <xi_n, xi_n>)] * xi_n,
```

up to a worldvolume-normal component that is absorbed into the RATTLE Lagrange
multiplier.  Therefore the target-space force vector used by the RATTLE update
is

```text
force_WV = 1/2 * [ xi + W'(t)/<xi_n, xi_n> * xi_n ].
```

This is the most likely place to introduce a factor-of-two bug.  Validation must
check it by finite differences of `V(z_t(x)) = Re S(z_t(x)) + W(t)` along random
worldvolume tangent directions.

## WV Simplified RATTLE

For one RATTLE position update, solve for `(h, u, lambda)`:

```text
z_{t+h}(x + u) = z_t(x) + Delta z - lambda,
Delta z = Delta s * pi - (Delta s)^2 * force_WV(z, t),
lambda in N_z R     (frozen at the substep base point).
```

Define

```text
z_new = z_{t+h}(x + u),
B     = z + Delta z - lambda - z_new.
```

The full Newton equation is

```text
xi_new * Delta h + E_new * Delta u + Delta lambda = B.
```

The simplified Newton equation freezes the linearization at the start of the
substep:

```text
xi * Delta h + E * Delta u + Delta lambda = B.
```

Use the fixed-surface decompositions

```text
xi = E * xi0_v + xi_n,
B  = E * B0_v  + B_n,
cB = <B, xi_n> / <xi_n, xi_n>.
```

Then the update is

```text
Delta h      = cB
Delta u      = B0_v - cB * xi0_v
Delta lambda = B_n - cB * xi_n
```

followed by

```text
h      <- h + Delta h
u      <- u + Delta u
lambda <- lambda + Delta lambda.
```

After convergence:

```text
z' = z_new,
pi_tilde' = pi - Delta s * [force_WV(z, t) + force_WV(z', t')] - lambda/Delta s,
pi' = worldvolume_project(pi_tilde').
```

The final momentum projection must be the WV projection, not the fixed-surface
projection.

## Boundary Handling And W(t)

`W(t)` is a sampler component, not a model observable and not a paper constant.
It should be represented by a provider with both value and derivative:

```text
W(t), W'(t).
```

The piecewise example in the simplified paper should not be typed into source
without a rendered-equation check and a finite-difference derivative test.  PDF
text extraction around the exponential walls is ambiguous.  The implementation
should support a configurable `W(t)` first, then add a tested example wall
profile.

The simplified paper presents a terse boundary step for a trial outside the
extended interval `[T0 - d0, T1 + d1]` as

```text
z'  = z
pi' = -pi.
```

The production simplified-WV kernel uses this literal full momentum flip for
boundary exits.  A 2026-06-02 fast audit first separated this paper policy from
the earlier normal/component-reflection variant.  That was necessary but not
the final bug: the decisive exact positive-target invariant gate later showed
that the no-boundary Newton/RATTLE solve must not use the measurement/wall
interval as an iterative fail-fast bound.

Correct construction rule:

- the no-boundary Newton solve may guard only the physical ODE domain, currently
  nonnegative flow time `t >= 0`;
- the extended interval `[T0-d0,T1+d1]` is a post-trial boundary rule applied to
  a converged no-boundary RATTLE trial;
- treating a temporary Newton iterate outside the measurement/wall interval as
  a boundary exit can produce an over-accepting, biased kernel even when local
  RATTLE/Newton/force/order/reverse identities pass.

The 2026-06-02 boundary/Newton readback records the A/B evidence:
pre-fix high-boundary-stress positive-target gates failed at large z-score,
while the fixed source pin `4597ced50bd8-e99b1c4b19b1` passed the same exact
target gates.

Normal/component reflection is not the default simplified-WV production rule.
It may only be revisited as a separately named geometry variant with its own
detailed-balance and observable validation.  Only numerical construction
failures that cannot be classified as boundary exits remain diagnostic rejected
proposals.

## Measurement And Physics Interpretation

WV-HMC has a different measurement ratio from TLTM:

```text
<O> = <F_WV O>_R / <F_WV>_R.
```

The Markov chain may sample the whole effective worldvolume interval, but
measurements can be restricted to a chosen subinterval
`[Ttilde0, Ttilde1]`.  That restriction is a measurement policy after
worldvolume equilibrium, not a rejection rule and not a second sampler.

Physics expectation:

- small `t` regions improve global communication between modes;
- large `t` regions improve the sign problem;
- `W(t)` is used to prevent precipitation toward small `t` and to tune useful
  flow-time visitation;
- the method avoids computing the Jacobian during proposal generation, but the
  Jacobian phase and `alpha` are still needed at measurement time.

## Typo And Convention Risk Register

| ID | Risk | Required treatment |
| --- | --- | --- |
| WV-MATH-001 | Flow equation appears in extracted text without conjugation. | Implement `xi = conj(partial S)`. Verify `Re S` monotonic and `Im S` constant on random complex seeds. |
| WV-MATH-002 | Tangent/normal flow equations can appear without conjugation. | Implement `dot v = conj(H v)` and `dot n = -conj(H n)`. Verify transported tangent-normal orthogonality. |
| WV-MATH-003 | `partial V` notation can be confused with raw holomorphic derivative. | In code expose `force_GT` and `force_WV` as target-space update vectors. Test by directional finite differences. |
| WV-MATH-004 | Factor-of-two ambiguity in WV force. | Test `force_WV = 1/2[xi + W'/alpha^2 xi_n]` against finite differences of `Re S + W(t)`. |
| WV-MATH-005 | Metric formula may be copied without the real inner product. | Use `<u,v> = Re(u^dagger v)` everywhere. Test metric symmetry and positive definiteness. |
| WV-MATH-006 | `alpha^{-1}` measurement weight can be omitted. | Add estimator tests where dense `E` and `alpha` are explicit; compare to direct integration or exact small-N reference. |
| WV-MATH-007 | Simplified Newton may accidentally use moving `E_new, xi_new` but simplified updates. | Freeze `E, xi, xi_n, xi0_v` per RATTLE substep. If full Newton is added later, make it a separate backend. |
| WV-MATH-008 | `Delta lambda` must be normal to `R`, not merely normal to `Sigma_t`. | Verify `<Delta lambda, T_z R> = 0` after each update. |
| WV-MATH-009 | Boundary handling differs between geometry variants and the simplified paper, and wall handling can be accidentally inserted into Newton iteration instead of post-trial boundary handling. | Default simplified-WV production uses the paper full flip `pi -> -pi` for boundary exits. The no-boundary solve may use only the physical flow-domain guard `t >= 0`; apply `[T0-d0,T1+d1]` only to the converged trial. Test with exact positive-target invariant gates, not only one-step reversibility. Treat normal/component reflection only as a separately validated nondefault variant. |
| WV-MATH-010 | Example `W(t)` wall formula is vulnerable to transcription error. | Implement configurable `W(t)`. Add rendered-source note and FD derivative tests before adding a paper-example profile. |
| WV-MATH-011 | `alpha^2` near zero makes the worldvolume coordinate singular. | Fail closed with typed diagnostics; do not divide by a clipped value in production. |
| WV-MATH-012 | Dense and matrix-free projection backends can drift numerically. | Certify BiCGStab against dense small-N oracle on the same seeds/residuals before enabling high-dimensional production. |

## Required Validation Before Scientific Runs

1. Gradient/Hessian validation:
   - random complex seeds;
   - manual `partial S` and Hessian/Hv versus AD/FD validation;
   - complexified perturbations, not only real seeds.

2. Flow validation:
   - `dot z = xi`;
   - `Re S` nondecreasing;
   - `Im S` conserved within ODE tolerance;
   - tangent-flow and normal-flow orthogonality preserved.

3. Fixed-surface projection validation:
   - reconstruction `||w - (w_v + w_n)||`;
   - orthogonality `<w_v, w_n>`;
   - dense backend against matrix-free backend for small N.

4. WV projection validation:
   - reconstruction `||w - (w_parallel + w_perp)||`;
   - orthogonality `<w_parallel, w_perp>`;
   - `w_parallel` lies in `span(T Sigma_t, xi_n)`;
   - `w_perp` is orthogonal to both `T Sigma_t` and `xi_n`.

5. WV force validation:
   - directional finite differences of `V = Re S + W(t)` along random WV
     tangent vectors;
   - explicit factor-of-two check;
   - `alpha^2` positivity diagnostics.

6. Simplified Newton/RATTLE validation:
   - one-step residual convergence for `(h,u,lambda)`;
   - `Delta h`, `Delta u`, `Delta lambda` against dense small-N oracle;
   - final momentum tangent to `R`;
   - reverse step returns to the starting point within tolerance;
   - energy error scales as expected when `Delta s` is reduced.

   Production WV-HMC uses the same reversibility check as a reverse-gate guard:
   after a forward proposal is constructed, replay the trajectory from
   `(z', -pi')`.  If the replay does not return to `(z, -pi)` within the
   configured state and momentum tolerances, the proposal is rejected as a
   reverse-gate rejection.  This is a WV-specific guarded kernel, not a reuse of
   TLTM Stage2 swap/proposal code.

7. Boundary validation:
   - inside interval: trial accepted into ordinary Metropolis decision;
   - outside extended interval: simplified-WV default restores the current
     state and applies the paper full flip `pi -> -pi`;
   - the measurement/wall interval is not passed as a Newton-iterate fail-fast
     bound; only the physical ODE domain guard is allowed inside the no-boundary
     solve;
   - boundary map is reversible and volume-preserving in the tested discrete
     proposal sense;
   - exact positive-target invariant gates pass under high boundary stress.

8. Measurement validation:
   - dense small-N `F_WV = alpha^{-1} det(E)/|det(E)| exp(-i Im S)`;
   - subinterval measurement does not alter the Markov transition;
   - exact/reference observables pass on small Stephanov cases before any
     high-dimensional claim.

## Implementation Consequences

The first source slice should not be a production WV-HMC driver.  It should add
math kernels and tests in this order:

1. model-provider derivative/Hv validation hook for random complex seeds;
2. fixed-surface projection result object with dense oracle fields;
3. WV projection wrapper using `xi_n`;
4. configurable `W(t)` provider and `force_WV`;
5. single-step dense WV RATTLE oracle;
6. reversibility/energy/boundary tests;
7. matrix-free projection backend certification against the dense oracle;
8. only then a WV-HMC sampler driver.

No TLTM Stage2 proposal, swap, or measurement code should be changed to make
WV-HMC fit.  WV-HMC should enter as a sibling sampler sharing model, ODE,
derivative, observable, IO, scheduler, and readback infrastructure.  Its
production reverse gate belongs inside the WV transition kernel and must be
diagnosed separately from TLTM reverse-gate counters.
