# Stephanov Model Plan

## Goal

- Model name: Stephanov finite-density chiral random matrix model.
- Physics target: QCD-like finite-density sign problem with exact finite-`n`
  references for `N_f = 1`.
- Primary references:
  - M. A. Stephanov, "Random matrix model of QCD at finite density and the
    nature of the quenched limit", arXiv:hep-lat/9604003.
  - Fukuma and Matsumoto, "Worldvolume approach to the tempered Lefschetz
    thimble method", arXiv:2012.08468, Sec. 4.
- Expected dimension: `N = 2 n^2` real physical coordinates.
- Literature target: `n = 10`, so `N = 200` real coordinates and a `20 x 20`
  Dirac matrix.

## Model Definition

The integration variable is an `n x n` complex matrix

```text
X_ij = x_ij + i y_ij,       x_ij, y_ij real.
```

The partition function is

```text
Z_n^{N_f} = exp(n mu^2) int d^2X exp(-S_pq_core) det(D + m)^{N_f}
```

with

```text
S_pq_core = n tr(X dagger X)

D + m = [ m I_n        i (X + C)       ]
        [ i (X dagger + C)   m I_n     ]

i C = diag((mu + i tau) I_{n/2}, (mu - i tau) I_{n/2}).
```

Equivalently,

```text
C = diag((tau - i mu) I_{n/2}, (-tau - i mu) I_{n/2}).
```

The paper uses the same `C` in both off-diagonal blocks. The lower block is
`X dagger + C`, not `(X + C) dagger`.

The sampling action, dropping the constant prefactor `exp(n mu^2)`, is

```text
S = n tr(X dagger X) - N_f log det(D + m).
```

The constant `-n mu^2` may be added to `S` only if absolute partition-function
normalization is needed. It does not affect forces, HMC acceptance ratios at
fixed `mu`, or observables.

## GTM Complexification Contract

GTM complexifies the real and imaginary parts independently:

```text
x_ij -> z_x,ij complex
y_ij -> z_y,ij complex
```

Use the holomorphic continuation

```text
X      = Zx + i Zy
Xsharp = transpose(Zx) - i transpose(Zy)
```

Then

```text
tr(X dagger X) -> tr(Xsharp X)
                = sum_ij (Zx_ij^2 + Zy_ij^2)

A = X + C
B = Xsharp + C
M = [ m I_n   i A ]
    [ i B     m I_n ]

S(z) = n sum_ij (Zx_ij^2 + Zy_ij^2) - N_f log det M(z).
```

Hard rule: do not use `conjg(transpose(X))` after complexification. That is an
anti-holomorphic operation and invalidates the GTM flow and force.

## Provider Decision

Stephanov production evaluation must be hand-written analytic code, not generic
AD-generated code. The promoted provider must supply:

- `calculate_action`
- `ds`
- `hessian_vec`
- model observable evaluation

The implementation should use dense matrix identities and reusable linear
algebra helpers for `log det`, solves, and inverse-action products. AD and
finite differences are validation oracles only.

Required validation scope:

- compare hand-written derivatives against AD/FD at small `n`;
- use random genuinely complexified `Zx,Zy` seeds with independent complex
  components;
- classify mismatches as branch convention, near-singular conditioning,
  complexification error, or analytic-formula error.

## Branch And Singularity Conventions

- `log det M` should use one branch consistently for action evaluation.
- The force is branch-independent away from determinant zeros:

```text
d log det M = tr(M^{-1} dM).
```

- The determinant-zero set `det M = 0` creates force poles. For the standard
  benchmark these zeros are a stiffness and phase-winding issue, not a reason
  to assume the original `t = 0` real manifold is disconnected.

## Flow And Sampling Requirements

- Standard benchmark: `N_f = 1`, `m = 0.004`, `tau = 0`.
- Literature flow window for `n = 10` is `T1` in the approximate range
  `0.025` to `0.068`, depending on `mu`.
- For original parallel-tempering TLTM at `mu = 0.6`, the literature reports:

| `n` | `T` | approximate replicas |
| ---: | ---: | ---: |
| 4 | 0.0 | 1 |
| 6 | 0.02 | 4 |
| 8 | 0.06 | 33 |
| 10 | 0.068 | 70 |

- The first port should not start at `n = 10`. Use `n = 2, 4, 6, 8, 10`.
- The first `mu` set should be `0.4, 0.6, 0.8`; `mu = 0.6` is the main
  sign-problem diagnostic point.

## Observables

Define

```text
A = X + C
B = Xsharp + C
K = (B A + m^2 I_n)^{-1}.
```

The two required physics observables are

| Name | Analytic form | Normalization | Notes |
| --- | --- | --- | --- |
| `chiral_condensate` | `(m / n) tr K` | per `n` | Equals `(1 / 2n) d log Z / dm` for `N_f = 1`. |
| `number_density` | `mu - (i / 2n) tr K (A + B)` | per `n` | Equals `(1 / 2n) d log Z / dmu` for `N_f = 1`. |
| `logdet_dirac` | `log det M` | raw diagnostic | Useful for branch, phase, and force-pole diagnostics. |
| `phase_factor` | `exp(-i Im S)` | raw diagnostic | Use only as a diagnostic stream; final estimates need the TLTM/GTM reweighting factor. |
| `min_singular_ba_m2` | `min singular value(B A + m^2 I)` | raw diagnostic | Tracks proximity to determinant zeros. |

Observable estimates on flowed manifolds must include the existing GTM/TLTM
Jacobian and residual-phase reweighting. The formulas above are pointwise model
observables, not final unweighted averages.

## Finite-`n` Exact Formulas For `N_f = 1`

For validation, the `N_f = 1` finite-`n` partition function reduces to one
real integral. Define

```text
Q(rho) = (rho - mu^2 + tau^2)^2 + (2 mu tau)^2.
```

Then

```text
Z_n^1 =
  n exp(n (mu^2 - m^2))
  int_0^infty d rho exp(-n rho) I_0(2 n m sqrt(rho)) Q(rho)^(n/2).
```

The exact observables are

```text
<psibar psi> =
  -m +
  [int_0^infty d rho exp(-n rho) I_1(2 n m sqrt(rho))
     sqrt(rho) Q(rho)^(n/2)]
  /
  [int_0^infty d rho exp(-n rho) I_0(2 n m sqrt(rho))
     Q(rho)^(n/2)]

<psi_dag psi> =
  mu - mu
  [int_0^infty d rho exp(-n rho) I_0(2 n m sqrt(rho))
     Q(rho)^(n/2 - 1) (rho - mu^2 - tau^2)]
  /
  [int_0^infty d rho exp(-n rho) I_0(2 n m sqrt(rho))
     Q(rho)^(n/2)].
```

The baseline exact table for `n = 10`, `m = 0.004`, `tau = 0` is staged in
`exact_reference_values_n10_m0004_tau0.csv`.

## Parameter Controls For The Sign Problem

| Parameter | Role |
| --- | --- |
| `mu` | Main finite-density sign-problem control. The hard region in the benchmark is near `mu = 0.6`. |
| `n` | Volume/matrix-size control. Real DOF grows as `2 n^2`; reweighting difficulty grows rapidly. |
| `m` | Smaller mass brings determinant zeros closer to important regions. Use `m = 0.004` for the benchmark; smaller `m` is stress testing. |
| `tau` | Temperature-like deformation. Keep `tau = 0` until the baseline is reproduced. |
| `N_f` | Multiplies the determinant phase. Keep `N_f = 1` for the first benchmark. |
| flow time `t` | Algorithmic sign-problem control, not a model parameter. Larger `t` can reduce phase noise but can create multimodality and reversibility stress. |

## Dataset And I/O

- Need full configuration snapshots: yes for initial porting at `n <= 6`, to
  diagnose determinant-zero proximity, phase winding, and `Xsharp` mistakes.
- Preferred observable stream stride: every accepted sample for `n <= 6`; tune
  down after the stream schema and exact-reference checks are stable.
- Checkpoint frequency target: every run segment for `n >= 8`.
- Maximum local storage target: keep `n = 10` exploratory local runs short;
  production-scale sweeps should run on the cluster output path.

## Open Questions Before Promotion

- Whether the model layer should expose a reusable dense complex LU/logdet
  helper before promotion.
- Whether `min_singular_ba_m2` should be computed in production or only in
  diagnostic builds.
