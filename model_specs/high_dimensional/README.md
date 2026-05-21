# Stephanov High-Dimensional Model Draft

This folder stages the Stephanov chiral random matrix model as the first
high-dimensional GTM/TLTM benchmark. Nothing here is compiled.

Primary benchmark:

- Model: Stephanov finite-density chiral random matrix model.
- Baseline parameters: `N_f = 1`, `m = 0.004`, `tau = 0`.
- Scale ladder: `n = 2, 4, 6, 8, 10`; the literature target is `n = 10`.
- First chemical potentials: `mu = 0.4, 0.6, 0.8`.
- Full literature sweep: `mu = 0.4, 0.45, 0.5, 0.55, 0.575, 0.6,
  0.625, 0.65, 0.7, 0.75, 0.8`.

The most important implementation rule is the complexification convention.
The original model contains `X dagger`, but GTM complexifies the real and
imaginary parts of `X` independently. Therefore `X dagger` must be promoted to
the holomorphic continuation

```text
X      = X_re + i X_im
Xsharp = transpose(X_re) - i transpose(X_im)
```

Do not use `conjg(transpose(X))` after complexification. That would make the
action non-holomorphic and would define a different model.

Provider decision:

- Stephanov production code must use a hand-written analytic dense provider for
  `action`, `ds`, and `hessian_vec`.
- The active sampler/flow path must not use generic AD-generated Stephanov
  derivatives.
- AD/finite-difference code is a validation oracle only, and must validate the
  holomorphic complexified action at random genuinely complex `Zx,Zy`.

File map:

1. `MODEL_PLAN.md`: model definition, action, exact formulas, observables,
   sign-problem controls, and references.
2. `PARAMETERS_AND_LAYOUT.md`: state-vector layout, runtime parameters, and
   scale-up plan.
3. `ACTION_BODY.inc`: inert hand-written provider sketch.
4. `OBSERVABLE_REGISTRY.inc`: inert observable-name registry sketch.
5. `OBSERVABLE_BODY.inc`: inert observable-body promotion sketch.
6. `VALIDATION_PLAN.md`: derivative checks, exact-answer checks, and
   acceptance gates.
7. `exact_reference_values_n10_m0004_tau0.csv`: finite-`n` exact values for
   the baseline literature sweep.

Only after review should these drafts be promoted into `src/physics/` and
`src/config/`.
