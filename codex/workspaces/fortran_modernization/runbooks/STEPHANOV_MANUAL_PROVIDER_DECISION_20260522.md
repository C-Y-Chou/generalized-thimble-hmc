# Stephanov Manual Provider Decision - 2026-05-22

Decision: Stephanov production model evaluation must be hand-written analytic
code. Generic AD-generated derivatives are not an allowed production path for
the sampler/flow code.

## Scope

Applies to the staged Stephanov finite-density chiral random matrix model under:

- `model_specs/high_dimensional/`

The production provider must supply:

- action
- `ds`
- `hessian_vec`
- observable evaluation

using the holomorphic complexification:

```text
X      = Zx + i Zy
Xsharp = transpose(Zx) - i transpose(Zy)
```

`conjg(transpose(X))` is invalid in the action, force, and HVP path after
complexification.

## Rationale

The action is scalar, so AD is mathematically valid. The repo's current generic
tape/generator path, however, does not provide dense matrix primitives for the
Stephanov `log det M`, solve, inverse-action, or HVP operations. A production
tape expansion of dense logdet/HVP would be slower and harder to control near
determinant zeros.

The production path should use dense linear algebra identities, including:

```text
d log det M = tr(M^{-1} dM)
d(M^{-1}) = -M^{-1} (dM) M^{-1}
```

## Validation Requirement

AD and finite differences remain required as validation oracles, not as the
production path. The required derivative/HVP validation gate is random
genuinely complexified `Zx,Zy` seeds with independent complex components.

Real seeds are a lower-dimensional special case. Flowed-like complex points and
near-singular but finite points are useful diagnostics after the basic oracle
passes, but they are not required for the first correctness gate.

Compare:

- action values up to branch-aware expectations;
- `ds`;
- `hessian_vec`.

Any mismatch must be classified as branch convention, determinant-zero
conditioning, anti-holomorphic complexification, analytic formula error, or
oracle implementation error before changing production code.
