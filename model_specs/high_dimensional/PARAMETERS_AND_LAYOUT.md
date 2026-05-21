# Stephanov Parameters And Layout

## State Layout

- `physical_state_size`: `2 * n * n`.
- Matrix dimensions: `X` is `n x n`; `n` must be even because `C` has two
  `n/2` blocks.
- Dirac matrix dimension: `2n x 2n`.
- Sites: not a spacetime lattice. This is a dense matrix model.
- Degrees of freedom: two real coordinates per complex matrix element.
- Boundary conditions: none.

Use the canonical physical-only state-vector contract from
`docs/state_vector_convention.md`: `x(:)` contains only physical coordinates;
`flow_time` is separate slot/replica metadata.

Recommended state ordering:

```text
offset_x(i,j) = (j - 1) * n + i
offset_y(i,j) = n*n + (j - 1) * n + i

Zx(i,j) = z(offset_x(i,j))
Zy(i,j) = z(offset_y(i,j))
X(i,j)  = Zx(i,j) + i Zy(i,j)
```

This is Fortran column-major ordering. The holomorphic continuation of
`X dagger` is

```text
Xsharp(i,j) = Zx(j,i) - i Zy(j,i).
```

Do not compute `Xsharp` with `conjg(transpose(X))`.

## Parameter Surface

Parameters promoted to `src/config/param_mod.f90`.

| Parameter | Type | Default | Required? | Description |
| --- | --- | --- | --- | --- |
| `stephanov_n` | integer | `10` | yes | Matrix size. Must be even and `physical_state_size = 2*n*n`. |
| `stephanov_nf` | integer | `1` | yes | Number of degenerate quark flavors. First benchmark uses `1`. |
| `stephanov_mass` | real(dp) | `0.004_dp` | yes | Quark mass `m`. |
| `stephanov_mu` | real(dp) | `0.6_dp` | yes | Chemical potential. Main sign-problem control. |
| `stephanov_tau` | real(dp) | `0.0_dp` | yes | Temperature-like parameter. Keep zero for baseline reproduction. |
| `stephanov_include_mu_prefactor` | logical | `.false.` | no | Add `-n*mu^2` to the action for absolute `Z`; leave false for sampling. |
| `stephanov_emit_diagnostics` | logical | `.false.` | no | Emit logdet/phase/singularity diagnostics when observable slots exist. |

Existing generic parameter:

| Parameter | Required value |
| --- | --- |
| `physical_state_size` | `2 * stephanov_n * stephanov_n` |

## Derived Quantities

| Quantity | Formula | Where it should be computed |
| --- | --- | --- |
| `matrix_dof` | `n*n` | model provider setup |
| `dirac_size` | `2*n` | model provider setup |
| `half_n` | `n/2` | model provider setup; validate `mod(n,2) == 0` |
| `C_diag(i)` | `tau - i*mu` for `i <= n/2`; `-tau - i*mu` otherwise | model provider setup |
| `physical_state_size` | `2*n*n` | config validation |
| `X` | `Zx + i Zy` | action/observable provider |
| `Xsharp` | `transpose(Zx) - i transpose(Zy)` | action/observable provider |
| `A` | `X + C` | action/observable provider |
| `B` | `Xsharp + C` | action/observable provider |
| `M` | block matrix `[mI, iA; iB, mI]` | action provider |
| `K` | `(B A + m^2 I)^{-1}` | observable provider |

## Recommended Scale Ladder

Use this order so implementation errors are separated from real sign-problem
stress:

| Stage | Parameters | Purpose |
| --- | --- | --- |
| unit | `n=2`, `m=0.05`, `tau=0`, `mu=0.4` | Decode layout, action, logdet, and finite-difference derivative checks. |
| debug | `n=4`, `m=0.02`, `tau=0`, `mu=0.4,0.6` | End-to-end GTM smoke with a softened determinant-zero geometry. |
| benchmark-small | `n=4,6`, `m=0.004`, `tau=0`, `mu=0.4,0.6,0.8` | First exact-value comparison at literature mass. |
| benchmark-main | `n=8,10`, `m=0.004`, `tau=0`, full `mu` sweep | Literature reproduction target. |
| stress | `n>10` or `m<0.004` or `tau>0` | Only after `n=10` baseline is stable. |

Do not turn on `tau` scans until the `tau=0`, `m=0.004`, `n=10` baseline is
reproduced.

## Initial Conditions

For smoke tests, draw `x_ij` and `y_ij` independently from a narrow Gaussian,
for example standard deviation `1/sqrt(2n)`, then rely on HMC equilibration.
Do not initialize all coordinates to zero for production statistics; the zero
matrix is useful only for deterministic action/force unit tests.

## Promotion Notes

- Keep `x(:)` physical-only.
- Keep `flow_time` as slot/replica metadata.
- Do not add model-specific formulas to sampler or evaluator code.
- The dense linear algebra needed here is model-layer responsibility.
- Use a hand-written analytic Stephanov provider for production `action`, `ds`,
  and `hessian_vec`; AD/FD is validation only.
- The action and observable providers must share one `Xsharp` implementation.
- Add a config validation error if `physical_state_size` is inconsistent with
  `2*n*n`.
