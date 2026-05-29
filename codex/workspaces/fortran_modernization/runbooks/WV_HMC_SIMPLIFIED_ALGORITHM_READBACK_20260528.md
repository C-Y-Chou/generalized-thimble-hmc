# WV-HMC Simplified Algorithm Readback

Date: 2026-05-28

Primary reference:

- Masafumi Fukuma, "Simplified Algorithm for the Worldvolume HMC and the
  Generalized Thimble HMC", arXiv:2311.10663 / PTEP 2024, 053B02.
- Local PDF:
  `codex/workspaces/fortran_modernization/references/2311.10663v4.pdf`
- arXiv:
  `https://arxiv.org/abs/2311.10663`

Purpose: fix the WV-HMC pre-implementation boundary. WV-HMC must not be
implemented as a thin mode inside the current TLTM Stage2 driver. The current
repo contains a fixed-flow GT-HMC/TLTM local RATTLE kernel. WV-HMC changes the
sampled manifold, projection, force, first RATTLE constraint solve, boundary
treatment, measurement weight, and diagnostics.

This file is intentionally an algorithm contract, not an implementation plan.

## Paper-Level State And Target

GT-HMC samples one fixed deformed surface:

```text
Sigma_t = { z_t(x) | x in Sigma_0 }
state: z = z_t(x), pi in T_z Sigma_t
potential: V(z) = Re S(z)
```

WV-HMC samples the worldvolume:

```text
R = { z_t(x) in Sigma_t | t in R }
xhat = (t, x)
state: z = z_t(x), pi in T_z R
potential: V(z) = Re S(z) + W(t(z))
```

`W(t)` is part of the sampler definition. It shapes the flow-time
distribution, prevents precipitation toward small flow time, and implements the
effective finite interval `[T0, T1]`.

The WV-HMC observable ratio is not the TLTM fixed-flow ratio. Its reweighting
factor is

```text
F(z) = alpha^{-1} * det(E) / |det(E)| * exp(-i Im S(z))
alpha^2 = <xi_n, xi_n>
xi = conj(partial S(z))
```

where `xi_n` is the component of the flow vector normal to `Sigma_t`.
Measurements should be taken from a chosen subinterval
`[Ttilde0, Ttilde1]` only after worldvolume equilibrium is established.

## Required Model And Flow Primitives

A WV-HMC-capable model provider must expose, directly or through validated
adapters:

- holomorphic scalar action `S(z)`;
- manual `partial S(z)` and `xi = conj(partial S(z))`;
- manual Hessian-vector product for tangent/normal flow;
- anti-holomorphic flow `z_t(x)`;
- tangent-flow action `E v0`;
- normal-flow action `F n0`;
- fixed-surface decomposition on `Sigma_t`;
- worldvolume projection using `xi_n`;
- `W(t)` and `W'(t)`;
- measurement-time Jacobian phase or stochastic estimator policy;
- exact/benchmark observables for small validation cases.

For small Stephanov smoke tests an explicit dense Jacobian path can be used, but
the public interface must be written in terms of decomposition/projection
operations. High-dimensional WV-HMC cannot rely on dense explicit `E` as the
canonical path.

## GT-HMC Simplified Projection

For a fixed surface `Sigma_t`, a vector `w in T_z C^N` is decomposed as

```text
w = w_v + w_n
w_v in T_z Sigma_t
w_n in N_z Sigma_t
```

The paper defines a real-linear map

```text
A w0 = E v0 + F n0,  w0 = v0 + n0
v0 = (w0 + conj(w0)) / 2
n0 = (w0 - conj(w0)) / 2
```

where `E v0` is obtained from tangent flow and `F n0` from normal flow. In a
large system, the decomposition should solve `A w0 = w` with an iterative
method such as BiCGStab, using flow/tangent-flow/normal-flow actions instead of
building the dense Jacobian.

The current repo's explicit mode is the small-system dense analogue of this
operation:

```text
solve jacr * x = b
tangent = jacr * real_part(x)
normal = b - tangent
```

Code path:

- `src/sampler/hmc_kernels.f90`, `decompose_tangent_projection_with_workspace`;
- `src/sampler/hmc_kernels.f90`, `prepare_real_jacobian_cache`.

This is a fixed-`Sigma_t` decomposition, not a worldvolume projection.

## GT-HMC Simplified RATTLE Update

For GT-HMC, the first RATTLE constraint solve finds `(u, lambda)` such that

```text
z_t(x + u) = z_t(x) + Delta z - lambda
Delta z = Delta s * pi - (Delta s)^2 * conj(partial V(z))
B = z + Delta z - lambda - z_new
z_new = z_t(x + u)
```

The original Newton equation uses the moving linearization:

```text
E_new * Delta u + Delta lambda = B
E_new = partial z_t(x+u) / partial u
```

The simplified Newton equation freezes the linearization at the start of the
RATTLE substep:

```text
E * Delta u + Delta lambda = B
```

With fixed-surface decomposition

```text
B = E * B0_v + B_n
```

the update is

```text
Delta u      = B0_v
Delta lambda = B_n
u            <- u + Delta u
lambda       <- lambda + Delta lambda
```

After convergence, set `z' = z_new`, compute

```text
pi_tilde' = pi - Delta s * [conj(partial V(z)) + conj(partial V(z'))]
            - lambda / Delta s
```

and project `pi_tilde'` onto `T_z' Sigma_t`.

## Current TLTM NT Solver Audit

The current first constraint solver is a fixed-flow GT-HMC-style simplified
Newton/projection solver, not WV-HMC:

- `src/sampler/hmc_integrator_core.f90` computes
  `del_z = step_size * momentum - step_size**2 * dV`.
- `src/sampler/hmc_constraints.f90` prepares one real Jacobian/LU at the base
  point before the iteration.
- `solve_constraint_newton_seeded` repeatedly evaluates
  `B = z + del_z - lambda - z_t(x+u)`.
- `solve_projected_step` solves with the same base `jacr_lu` every iteration,
  extracts the real/tangent update, and assigns the residual complement to the
  Lagrange update.
- The final momentum projection calls the same fixed-`Sigma_t`
  `decompose_tangent_projection`.

So the existing NT solver is already close to the paper's simplified GT-HMC
Newton update in explicit-Jacobian form. It is not the WV-HMC update because it
has no `h`, no `xi_n`, no worldvolume projection, no `W(t)` force, no
worldvolume boundary bounce, and no `alpha^{-1}` measurement weight.

This is the key implementation boundary:

```text
Current NT solver:  fixed Sigma_t, solve/update (u, lambda).
WV-HMC solver:      worldvolume R, solve/update (h, u, lambda).
```

## WV-HMC Projection

WV-HMC first uses the fixed-surface decomposition on `Sigma_t`.

For any `w in T_z C^N`, decompose

```text
w  = w_v  + w_n
xi = xi_v + xi_n
```

where the `v` components are tangent to `Sigma_t` and the `n` components are
normal to `Sigma_t`.

The worldvolume tangent/normal decomposition is then

```text
c          = <xi_n, w_n> / <xi_n, xi_n>
w_parallel = w_v + c * xi_n
w_perp     = w_n - c * xi_n
```

with

```text
w_parallel in T_z R
w_perp     in N_z R
```

This is not the current repo's fixed-surface projection. The current projection
returns `(w_v, w_n)` for `Sigma_t`; WV-HMC must wrap that result with the
`xi_n` correction to obtain `(w_parallel, w_perp)` for `R`.

## Projection Backend Choices

The sampler should not branch on dense versus iterative projection logic. It
should call one fixed-surface projection interface and one WV wrapper:

```text
sigma_project(z, t, x, w, backend) -> sigma_projection_result
wv_project(z, t, x, w, backend)    -> wv_projection_result
```

The fixed-surface result must include enough information for the WV simplified
Newton update:

```text
sigma_projection_result:
    w_v       tangent component in T_z Sigma_t
    w_n       normal component in N_z Sigma_t
    w0_v      base-space tangent coefficient satisfying w_v = E * w0_v
    w0_n      optional base-space normal coefficient satisfying w_n = F * w0_n
    residual  reconstruction/linear-solve residual
    status
```

The WV wrapper then uses the same formula for every backend:

```text
sigma_project(w)  -> (w_v,  w_n,  w0_v,  w0_n)
sigma_project(xi) -> (xi_v, xi_n, xi0_v, xi0_n)

c          = <xi_n, w_n> / <xi_n, xi_n>
w_parallel = w_v + c * xi_n
w_perp     = w_n - c * xi_n
```

For the WV first-constraint solve, `xi0_v` and `xi_n` are fixed for the
RATTLE substep. Each nonlinear iteration only needs a fresh projection of the
current residual `B`.

### Backend A: Explicit Dense `E/J`

This backend is the right first implementation for `n=2`, small Stephanov
checks, and exact cross-validation.

Implementation:

```text
given base (t, x, z) and vector w:
    integrate flow with tangent Jacobian E = partial z_t(x) / partial x
    map E to the 2N x 2N real matrix E_R
    LU-factor E_R once for this base point
    solve E_R * q = w_R
    q_v = real_part_only(q)
    w_v = E_R * q_v
    w_n = w_R - w_v
    w0_v = q_v
    w0_n = q - q_v
```

Current repo analogue:

- `map_to_real_mat` builds `E_R`;
- `prepare_real_jacobian_cache` performs the LU;
- `real_vec` zeroes the interleaved imaginary slots to get the base tangent
  part;
- `decompose_tangent_projection_with_workspace` computes
  `w_v = E_R * real_part_only(q)` and `w_n = w_R - w_v`.

Cost and role:

```text
factorization: O(N^3)
storage:       O(N^2)
best use:      correctness oracle, small-N validation, explicit-vs-iterative tests
not canonical: high-dimensional production
```

Failure semantics:

- singular or ill-conditioned dense factorization is a projection failure;
- large reconstruction residual is a projection failure;
- this failure should be reported as backend/projection failure, not hidden as a
  model or sampler decision.

### Backend B: Matrix-Free BiCGStab

This is the high-dimensional canonical direction. It implements the paper's
`A w0 = w` decomposition without building the dense Jacobian.

Define the operator action:

```text
apply_A(w0):
    v0 = (w0 + conj(w0)) / 2
    n0 = (w0 - conj(w0)) / 2
    integrate base flow z_s from x to z_t(x)
    integrate tangent flow for v0: dot v = conj(H(z_s) * v)
    integrate normal flow  for n0: dot n = -conj(H(z_s) * n)
    return E * v0 + F * n0
```

Then solve:

```text
given base (t, x, z) and vector w:
    solve apply_A(w0) = w with BiCGStab
    split converged w0 into v0 and n0
    compute or reuse v = E * v0 and n = F * n0
    return w_v = v, w_n = n, w0_v = v0, w0_n = n0
```

Implementation boundary:

- BiCGStab owns only the linear decomposition `A w0 = w`;
- the nonlinear WV RATTLE loop still owns `B`, `h`, `u`, and `lambda`;
- each BiCGStab matrix-vector action must use the same base flow path for the
  current `(t, x, z)` so that the linear operator is fixed during the solve;
- base-flow/dense-output caching is allowed inside one projection call or one
  RATTLE substep if it is trajectory-equivalent and included in diagnostics.

Cost and role:

```text
factorization: none
storage:       O(N) plus ODE workspaces, model dependent
dominant cost: repeated tangent/normal-flow actions
best use:      high-dimensional production path
```

Failure semantics:

- BiCGStab nonconvergence, invalid ODE status, or failed reconstruction is a
  projection failure;
- tolerance and maximum-iteration choices belong to projection backend config;
- fallback to dense `E/J` is allowed only for validation/small-N debugging, not
  as hidden high-dimensional production behavior.

### Backend Equivalence Tests

For small dimensions where dense `E/J` is available, both backends must be run on
the same random complex seeds and residuals:

```text
fixed-surface:
    ||w - (w_v + w_n)||
    <w_v, w_n>
    ||w_v_dense - w_v_bicg||
    ||w_n_dense - w_n_bicg||
    ||w0_v_dense - w0_v_bicg||

worldvolume:
    ||w - (w_parallel + w_perp)||
    <w_parallel, w_perp>
    ||w_parallel_dense - w_parallel_bicg||
    ||w_perp_dense - w_perp_bicg||

RATTLE:
    one-step WV constraint residual
    one-step Delta h, Delta u, Delta lambda
    reversibility residual
    energy error scaling
```

The first implementation should make `explicit_dense` the validation backend
and `bicgstab_matrix_free` the backend under certification. The sampler API must
be stable before the iterative backend replaces the dense internals.

## WV-HMC Force

The WV-HMC potential is

```text
V(z) = Re S(z) + W(t(z))
```

The force used by RATTLE is

```text
conj(partial V(z))
  = 1/2 * [ xi + W'(t) / <xi_n, xi_n> * xi_n ]
```

up to a worldvolume-normal component that is absorbed into the Lagrange
multiplier in the paper's derivation.

The current `calculate_dV` uses the fixed-flow GT force only. WV-HMC needs a
new force routine because `W'(t)` and `xi_n` are sampler-level inputs.

## WV-HMC Simplified RATTLE Update

For WV-HMC, the first RATTLE constraint solve finds `(h, u, lambda)` such that

```text
z_{t+h}(x + u) = z_t(x) + Delta z - lambda
Delta z = Delta s * pi - (Delta s)^2 * conj(partial V(z))
B = z + Delta z - lambda - z_new
z_new = z_{t+h}(x + u)
```

The original Newton equation uses moving data at `z_new`:

```text
xi_new * Delta h + E_new * Delta u + Delta lambda = B
```

The simplified Newton equation freezes the data at the start of the RATTLE
substep:

```text
xi * Delta h + E * Delta u + Delta lambda = B
```

where `xi = conj(partial S(z))` and `E` is the tangent map at `z = z_t(x)`.

To solve it, first decompose at fixed `Sigma_t`:

```text
xi = E * xi0_v + xi_n
B  = E * B0_v  + B_n
cB = <B, xi_n> / <xi_n, xi_n>
```

Then update:

```text
Delta h      = cB
Delta u      = B0_v - cB * xi0_v
Delta lambda = B_n - cB * xi_n

h      <- h + Delta h
u      <- u + Delta u
lambda <- lambda + Delta lambda
```

With a zero initial guess, the first iteration gives

```text
h      = c_Delta_z
u      = (Delta z)0_v - c_Delta_z * xi0_v
lambda = (Delta z)_n - c_Delta_z * xi_n
c_Delta_z = <Delta z, xi_n> / <xi_n, xi_n>
```

After convergence, set `z' = z_new`, compute

```text
pi_tilde' = pi - Delta s * [conj(partial V(z)) + conj(partial V(z'))]
            - lambda / Delta s
```

and project `pi_tilde'` onto `T_z' R` using the WV projection, not the
fixed-surface projection.

This update is the part that cannot be borrowed from the current NT solver by
renaming variables.

## Boundary Step

WV-HMC has an explicit flow-time boundary rule. The paper uses an effective
interval `[T0, T1]` with penetration depths `d0`, `d1`.

For each MD step:

```text
trial: (z, pi) -> (z_tilde, pi_tilde), z_tilde = z_{t_tilde}(x_tilde)

if t_tilde < T0 - d0 or t_tilde > T1 + d1:
    z'  = z
    pi' = -pi
else:
    z'  = z_tilde
    pi' = pi_tilde
```

This bounce rule is part of the transition kernel. It should not be hidden in
flow-bank initialization, TLTM preflow, or scheduler scripts.

## WV-HMC HMC Step

One WV-HMC trajectory has this sampler-level structure:

```text
given z in R with carried coordinates (t, x):
    draw Gaussian pi_tilde in T_z C^N
    project pi_tilde -> pi in T_z R
    repeat WV-RATTLE plus boundary handling for N_step
    compute Delta H = H(z', pi') - H(z, pi)
    accept with min(1, exp(-Delta H))
```

The state must carry enough coordinate provenance to evaluate `z_t(x)`,
`z_{t+h}(x+u)`, `W(t)`, `W'(t)`, and the measurement subinterval.
Reconstructing `t` from `z` should not be the primary state representation.

## Consequences For Repo Architecture

Shared infrastructure:

- model provider API for action, gradient, Hessian/Hv;
- complexification and derivative validation;
- ODE backend and flow diagnostics;
- fixed-surface decomposition primitive;
- observable registry and complex ratio-estimator readback;
- scheduler/run manifest discipline;
- small Stephanov exact-reference tests.

Must be WV-HMC-specific:

- state type `(t, x, z, pi)`;
- `W(t)` / `W'(t)` / boundary parameter schema;
- WV force routine;
- WV projection `T_z C^N -> T_z R + N_z R`;
- WV simplified Newton solver for `(h, u, lambda)`;
- WV RATTLE and boundary bounce kernel;
- WV acceptance and trajectory diagnostics;
- measurement subinterval and `alpha^{-1}` weight handling;
- flow-time visitation, bounce, and subinterval-stability readbacks.

Must not be reused as-is:

- TLTM replica ladder;
- TLTM swap/reflow kernel;
- TLTM fixed-target flow-bank semantics;
- TLTM label round-trip diagnostics;
- TLTM nofb/withfb fallback policy;
- TLTM fixed-flow HMC parameter gates without a WV-specific retune;
- current fixed-surface final projection as the final WV projection.

## Implementation Boundary For First WV-HMC Version

Acceptable for first low-dimensional Stephanov validation:

```text
explicit dense E/J for fixed-surface decomposition
explicit WV wrapper using xi_n correction
n=2 exact-reference validation
short reversibility/energy tests
```

Not acceptable as the canonical high-dimensional design:

```text
dense explicit E/J as the only projection path
copying TLTM Stage2 and inserting a dynamic flow-time label
using current solve_constraint_newton as the WV constraint solver
omitting alpha^{-1} from measurement weights
omitting boundary bounce tests
```

The canonical interface should be decomposition-oriented:

```text
sigma_project(z, t, x, w) -> (w_v, w_n, w0_v, w0_n)
wv_project(z, t, x, w)    -> (w_parallel, w_perp)
wv_force(z, t, x)         -> conj(partial V)
wv_constraint_step(...)   -> (h, u, lambda, z_new)
wv_rattle_step(...)       -> (t', x', z', pi')
```

The explicit dense path can implement these interfaces first. The iterative
`A w0 = w` path can then replace the internals without changing sampler
semantics.

## Validation Checklist Before Production Claims

Derivative/model:

- manual gradient vs AD/FD for random complex seeds;
- manual Hessian/Hv vs AD/FD for random complex seeds;
- flow/tangent-flow/normal-flow consistency.

Projection:

- fixed-surface reconstruction `w = w_v + w_n`;
- fixed-surface orthogonality `<w_v, w_n> = 0`;
- WV reconstruction `w = w_parallel + w_perp`;
- WV orthogonality `<w_parallel, w_perp> = 0`;
- `xi_n` normalization and `alpha^2 = <xi_n, xi_n>` positivity.

RATTLE:

- first-constraint residual decreases for GT and WV cases;
- WV `(h,u,lambda)` update matches finite-difference linearization at small
  `Delta s`;
- final momentum lies in `T_z' R`;
- reversibility under momentum flip;
- energy error scales with step size as expected.

Boundary:

- bounce triggers exactly when `t_trial` leaves `[T0-d0, T1+d1]`;
- bounce maps `(z,pi)` to `(z,-pi)`;
- boundary path remains reversible.

Physics/readback:

- n=2 Stephanov exact observable check;
- flow-time histogram responds to `W(t)`;
- measurement subinterval stability;
- phase/ratio stability with `alpha^{-1}` included;
- comparison to fixed-flow GT/TLTM only as diagnostic, not as shared sampler
  semantics.

## Short Conclusion

The repo can share model, flow, derivative, observable, scheduler, and readback
infrastructure between TLTM and WV-HMC. It should not share TLTM's sampler
state machine. The current NT solver is a fixed-surface GT-HMC simplified
Newton solver in explicit-Jacobian form. WV-HMC needs a new worldvolume
projection and a new simplified Newton update for `(h, u, lambda)`.
