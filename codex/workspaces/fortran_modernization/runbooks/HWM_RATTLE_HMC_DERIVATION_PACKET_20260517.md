# HWM-RATTLE/HMC Derivation Packet

Date: 2026-05-17 JST

Status: derivation/provenance packet.  No source edits are authorized or made by
this packet.

## Purpose

This packet answers the immediate question raised after the RATTLE/HMC line
audit, but it is not limited to the two phrases that triggered the discussion
(`momentum update` and symplectic structure).  It is the pre-source-change
derivation/readback packet for the whole handwritten RATTLE/HMC internal
proposal path:

- action/gradient convention;
- real/complex packing;
- tangent projection and Hamiltonian helpers;
- initial momentum generation/projection;
- one-step RATTLE position projection;
- simplified Newton residual and tangent/normal split;
- official DFO-LS/QN fallback boundary inside the RATTLE step;
- strict final-flow certification;
- final momentum reconstruction and projection;
- multi-step proposal composition;
- reverse-gate replay;
- Metropolis accept/reject boundary;
- status/counter accounting;
- warmup/legacy routes and test-only triggers;
- finite-precision symplectic/reversibility claim boundary.

The answer is:

- The successful one-step update order, action-gradient convention, momentum
  update signs, half-force factor, Newton residual sign, and tangent projection
  convention match the reference-backed TLTM/GT-HMC RATTLE core under the
  current real/complex packing convention.
- The code therefore has a `matched-core` RATTLE structure for successful,
  certified proposals through the Newton/QN-converged, strict-final-flow,
  reverse-gate-accepted path.
- The product-level claim is still not "the finite-precision implementation is
  a proven exact symplectic map."  Exact symplectic/volume-preserving claims
  require exact solves and exact projections.  The implemented route uses
  finite ODE solves, simplified Newton or official DFO-LS solves, tolerances,
  strict final-flow checks, and reverse-gate certification.  Failures are the
  project-selected rejection-as-stay-put policy.

## References Used

- `codex/workspaces/fortran_modernization/references/REFERENCES_INDEX.md`
  records the stable local reference bundle, including:
  - `1912.13303_TLTM_HMC.pdf` for the TLTM HMC framework;
  - `2311.10663v4.pdf` for simplified Newton and constrained RATTLE/GT-HMC;
  - `new_algorithm__Copy_.pdf` for project-specific projection/QN boundaries.
- `M2_REFERENCE_BACKED_CORE_AUDIT.md` records the reference equation map:
  - GT-HMC Eq. (3.37): `zt(x+u) = zt(x) + Delta z - lambda`;
  - GT-HMC Eq. (3.40): `B = z + Delta z - lambda - znew`;
  - GT-HMC Eq. (3.41): fixed-base simplified Newton
    `E Delta u + Delta lambda = B`;
  - GT-HMC Eqs. (3.42)-(3.44): split `B` into tangent/base and normal/Lagrange
    components;
  - TLTM complex RATTLE formula:
    `ztilde = z + Delta s*pi - Delta s**2/2*conjg(dS(z))`;
  - final half-momentum and tangent projection:
    `pi_half=(z'-z)/Delta s`,
    `pi_tilde'=pi_half - Delta s/2*conjg(dS(z'))`.
- Direct PDF text extraction was not available in this local environment
  (`pdftotext`, `pypdf`, `PyPDF2`, and `pdfplumber` were unavailable), so this
  packet relies on the already-written reference-backed audit summaries and the
  current source readback rather than re-extracting PDF text.

## Full Internal Coverage Inventory

This packet covers every RATTLE/HMC internal-algorithm surface identified by
the line audit.  The classification separates equation-level matched core from
project policy, direct-API caveat, or separate packet boundary.

| Internal algorithm surface | Source surface | Derivation/readback status | Claim boundary |
| --- | --- | --- | --- |
| Action and gradient input | `src/physics/model.f90`, `src/physics/model_generated.f90`, `src/sampler/hmc_integrator_core.f90:331-334`, `568-573` | `ds` supplies the holomorphic action derivative used as `conjg(ds)` before real packing. | Matched for the RATTLE force convention here; broader action/branch provenance remains a separate model/action packet. |
| Real/complex packing | `src/core/utils.f90`; used by `hmc_kernels` and `hmc_constraints` | Complex vectors are packed as interleaved real coordinates; complex Jacobians become the real block matrix used by the projection solves. | Matched packing convention; tests should protect it because sign/factor conclusions depend on it. |
| Tangent projection helper | `src/sampler/hmc_kernels.f90:34-95` | `decompose2` computes `P_T(b)=J Re(J^{-1}b)` and `P_N(b)=b-P_T(b)`. | Matched tangent projection; output names are confusing but mathematically consistent. |
| Hamiltonian helper | `src/sampler/hmc_kernels.f90:97-111` | Computes `0.5*norm2(p)**2 + Re S(z)`. | Formula matched; direct helper only warns on shape mismatch, so caller-owned shape guard remains an API caveat. |
| Initial momentum and projection | `src/sampler/hmc.f90:188-233` | Draws or accepts momentum, projects to tangent space, publishes initial projected momentum, and computes initial Hamiltonian. | Matched proposal setup; `istest/testmom` overriding explicit `momentum_in` is a legacy trigger caveat. |
| Multi-step proposal wrapper | `src/sampler/hmc.f90:239-278`, `515-521` | Composes `num_steps` one-step RATTLE calls and aborts/reset live public outputs on proposal failure. | Live Metropolis-facing stay-put route is protected; direct core failure outputs still need hardening. |
| First half-force and trial displacement | `src/sampler/hmc_integrator_core.f90:331-342` | Uses `dV=1/2 R(conjg(dS))`, then `del_z=h*p-h**2*dV`. | Matched RATTLE position formula under packing convention. |
| Simplified Newton residual | `src/sampler/hmc_constraints.f90:247-394` and `396-441` | Residual is `B=z+Delta z-lambda-flowz(x+u)`; projected step is fixed-base `E Delta u + Delta lambda=B`. | Matched core residual and sign; controller thresholds/failure predicates are project policy. |
| Official DFO-LS/QN bridge inside step | `src/sampler/hmc_integrator_core.f90:358-540` | If Newton fails, active source performs one official package attempt plus TLTM trace/residual classification. | Separate HWM-QN packet boundary; this RATTLE packet does not certify wrapper policy as paper-given. |
| Strict final flow | `src/sampler/hmc_integrator_core.f90:550-565` | Reflows endpoint and requires strict success before momentum reconstruction. | Project certification gate; failure exits need direct-core output hardening. |
| Final momentum reconstruction/projection | `src/sampler/hmc_integrator_core.f90:568-589` | Reconstructs `pi_half=(z'-z)/h`, applies final half-force, then projects tangent. | Matched successful-core RATTLE momentum update. |
| Reverse-gate replay | `src/sampler/hmc_integrator_core.f90:591-626`, `646-711` | Replays one reverse step with `-final_momentum` and checks `x`, `z`, `J`, and momentum against tolerance. | Project numerical certification; not a formal exact-arithmetic proof by itself. |
| Metropolis boundary | `src/sampler/markovchain_metropolis.f90:66-187` | Valid proposal uses `min(1, exp(-Delta H))`; proposal failures, invalid Hamiltonians, invalid Delta-H, reverse-gate rejection, and finite ordinary rejection leave public outputs at the current state. | Correct MCMC rejection-as-stay-put policy if proposal certification boundary is accepted; status collapse is deliberate but needs mapping coverage. |
| Local transition counters | `src/sampler/tltm_types.f90:133-197` | Typed local transition events distinguish several outcomes while legacy aggregate names remain. | Accounting boundary; do not interpret legacy `projection_failure_count` as literal projection-only physics evidence. |
| Warmup `rattle2` / `integrate_hmc_warmup` | `src/sampler/hmc.f90:525-714` | Zero-momentum/warmup route shares some RATTLE machinery but has weaker failure-output semantics than the proposal wrapper. | Not part of the accepted Markov proposal proof; needs hardening or explicit partial-progress semantics. |
| Diagnostic reverse probe | `src/sampler/hmc.f90:282-431` | Runs a diagnostic propagation/reversibility readback after a proposal. | Diagnostic only; not an acceptance gate. |
| Test-only/global triggers | `src/sampler/hmc.f90:219`, warmup `eo` route | Legacy triggers can alter deterministic paths. | F9/W11 cleanup candidate; not a proof source. |

Therefore, after this packet, the RATTLE/HMC audit boundary is:

```text
matched successful core + project rejection/certification policy + explicit
direct-API/legacy/status/QN/model boundaries
```

not:

```text
all RATTLE/HMC source is now paper-correct in every branch
```

## Notation And Packing

Let:

- `z` be the complex flowed point on the thimble.
- `x` be the real coordinate state; in source, `x(1)` is the flow time and
  `x(2:)` are physical seed coordinates.
- `J = dz/dx_seed` be the complex Jacobian returned by `flow`.
- `E = real(J)` be the real block matrix constructed by
  `utils:map_to_real_mat`.
- `R(c)` be `utils:complex_to_real(c)`, i.e.
  `[Re c1, Im c1, Re c2, Im c2, ...]`.
- `real_vec(v)` zeroes the imaginary slots in a real-packed coordinate vector,
  leaving only the real seed-coordinate component.

`decompose2(b, x, au, av, J)` implements the projection split:

```text
q_full = E^{-1} b
q_real = real_vec(q_full)
P_T(b) = E q_real
P_N(b) = b - P_T(b)
```

In the actual subroutine return names:

- the second argument receives `q_full`;
- the third argument receives `P_T(b)`;
- the fourth argument receives `P_N(b)`.

Therefore a call such as:

```fortran
call decompose2(momentum, full_coord, tangent_part, normal_part, jac, ierr)
```

returns `tangent_part = P_T(momentum)`.

This is the intended tangent projection `J Re(J^{-1} b)` in real-packed form.

## Force Convention

For holomorphic action `S(z)`, the real gradient of `Re S` in real-packed
complex coordinates is:

```text
grad_R Re S(z) = R(conjg(dS/dz)).
```

The source convention is:

```fortran
call ds(state_z, ws%ds_val)
ws%E0 = conjg(ws%ds_val)
call complex_to_real(ws%E0, ws%E0_real)
call calculate_dV(n_state, ws%E0_real, ws%E0_perp, ws%dV, has_error)
```

and `calculate_dV` is:

```fortran
dV = E0_real/2.0_dp
```

So `dV` is not the full potential gradient.  It is the half-gradient used by
the RATTLE position and final force formulas:

```text
dV = 1/2 R(conjg(dS/dz)).
```

The unused `E0_perp` argument is a naming/API caveat, not evidence of a missing
projection step in the successful RATTLE core.  The normal/tangent projection is
performed explicitly through `decompose2`.

## Position Projection Derivation

The reference TLTM/GT-HMC one-step trial displacement is:

```text
Delta z = h*pi - h**2/2 * conjg(dS(z)).
```

The code computes:

```fortran
ws%del_z = step_size*momentum - step_size**2*ws%dV
```

Using `dV = 1/2 R(conjg(dS))`, this is exactly the real-packed version of:

```text
Delta z = h*pi - h**2/2 * conjg(dS(z)).
```

The constraint target is:

```text
z_new = z + Delta z - lambda.
```

Equivalently, the residual is:

```text
B = z + Delta z - lambda - z_new.
```

The source implements this as:

```fortran
z_new = z - flowz(xtu) - ld
call complex_to_real(z_new, B)
B = B + del_z
```

which is:

```text
B = R(z + Delta z - lambda - flowz(x+u)).
```

The simplified Newton linearized step is:

```text
E Delta u + Delta lambda = B.
```

The source `solve_projected_step` performs:

```fortran
dxi = B
call dgetrs('N', ..., jacr_lu, ..., dxi, ...)
au = dxi
call real_vec(au)
call dgemv('N', ..., jacr, ..., au, ..., av)
au = av
av = B - au
```

which is:

```text
q_full = E^{-1} B
Delta u = real_vec(q_full)
E Delta u = E real_vec(E^{-1}B)
Delta lambda = B - E Delta u
```

The Newton update then does:

```fortran
u(i)  = u(i)  + dxi(2*i - 1)
ld(i) = ld(i) + cmplx(av(2*i - 1), av(2*i), dp)
```

Thus the residual sign, `lambda` sign, fixed-base Jacobian use, and
tangent/normal split match the reference-backed simplified Newton mapping.

## Momentum Update Derivation

After the projected coordinate solve, the source strictly reflows:

```fortran
call flow(final_x, final_z, ws%temp_jac, has_error, final_flow_status, ...)
```

Then it reconstructs the half-step momentum:

```fortran
call complex_to_real((final_z - ws%temp_z)/step_size, momentum)
```

This is the real-packed version of:

```text
pi_half = (z' - z)/h.
```

Then the code evaluates the final half-gradient:

```fortran
call ds(final_z, ws%ds_val)
ws%E0 = conjg(ws%ds_val)
call complex_to_real(ws%E0, ws%E0_real)
call calculate_dV(n_state, ws%E0_real, ws%E0_perp, ws%dV, has_error)
```

and applies:

```fortran
momentum = momentum - step_size*ws%dV
```

Since `dV = 1/2 R(conjg(dS(final_z)))`, this is:

```text
pi_tilde' = pi_half - h/2 * conjg(dS(z')).
```

Finally it projects this momentum to the tangent space at the final point:

```fortran
call decompose2(momentum, ws%E0_perp, ws%del_z, ws%Jl, ws%temp_jac, has_error, ws%decompose_ws)
momentum = ws%del_z
```

Because the third `decompose2` output is `P_T(momentum)`, this sets:

```text
pi' = P_T^{z'}(pi_tilde').
```

This matches the RATTLE final momentum projection structure.  The signs are
consistent with the same force convention used in the position update.

## Proposal Wrapper And Multi-Step Composition

`rattle` is the public HMC proposal constructor used by the Metropolis path.
Its proposal semantics are:

```text
initialize final outputs to current state
obtain momentum from explicit input, local RNG state, or global RNG
project initial momentum to the tangent space
compute initial Hamiltonian
repeat num_steps one-step RATTLE updates with h = total_step_size/num_steps
project final momentum and compute final Hamiltonian
return proposal_ok only if every step and final projection succeeded
```

The successful multi-step map is therefore a composition of the one-step
RATTLE map described above.  The wrapper also protects the live Markov-chain
state on failed proposals: if a step fails, it maps the step status to an HMC
proposal status and calls the local failure abort, which resets public
`final_x/final_z/jacf` to `state_x/state_z/jaci`.

This is a different claim from the direct `rattle_step_core` API.  The direct
core initializes failed outputs to the input state before the solve, but after
late failures such as final-flow or reverse-gate failure it can return with
candidate values while `method_converged=.false.`.  That is why
`HWM-RATTLE-API-001` remains an API-hardening item even though the
Metropolis-facing wrapper is currently stay-put protected.

The momentum source precedence is also not fully clean:

```text
explicit momentum_in
else local momentum_rng_state
else global RNG
then legacy istest/testmom override
```

The final `istest/testmom` override is not a paper algorithm.  It is a legacy
test trigger and should be treated as an F9/W11 cleanup boundary.

## Reverse-Gate Replay Boundary

The reverse gate is a TLTM project certification layer around the successful
RATTLE core.  It does not appear here as a proof that finite-precision RATTLE
is exactly reversible; it is an explicit numerical gate:

```text
reverse_momentum = -final_momentum
run one rattle_step_core from the final state
compare replayed x, z, J, and momentum against the initial state/momentum
accept only if all norms are within qn_reverse_gate_tol
```

The replay suppresses normal constraint-solver accounting while recording a
reverse-gate replay status.  If the replay fails, the proposal is rejected by
policy (`hmc_step_status_reverse_gate_rejected`) rather than continued by the
paper momentum-reflection route.  That is the already-confirmed
HWM-RATTLE-001 decision.

This makes the accepted proposal claim:

```text
successful RATTLE update + strict final-flow replay + reverse replay within
tolerance
```

not:

```text
all finite-precision branches have an independently proven exact inverse
```

## Metropolis And Rejection Boundary

`metropolis_step` is the Markov-state boundary.  After valid output-buffer
shape checks, it initializes `x_new/z_new/j_new` to the current state before
constructing a proposal.  The accepted-proposal probability is:

```text
alpha = 1                         if Delta H <= 0
alpha = exp(-Delta H)             if Delta H > 0
```

This is the usual HMC Metropolis rule for a reversible/volume-preserving
proposal kernel, with TLTM's extra certification gates deciding which proposals
are eligible for the energy test.  The stay-put branches are:

- HMC proposal construction failure;
- reverse-gate rejection;
- invalid initial/final Hamiltonian;
- invalid `Delta H`;
- finite ordinary Metropolis rejection.

After HWM-MET-001, the finite ordinary rejection branch also resets public
`x_new/z_new/j_new` to the current state, matching the already-existing failure
branches.  This is legal MCMC rejection-as-stay-put behavior.  It is not the
paper's momentum-reflection continuation route, and it should not be described
as such.

## Status And Counter Accounting

The code intentionally has two status layers:

- HMC proposal statuses distinguish initial projection failure, step failure,
  final projection failure, reverse-gate rejection, and output-size mismatch.
- Metropolis transition statuses preserve accepted/rejected, reverse-gate
  rejection, invalid Hamiltonian/Delta-H, output-size mismatch, and a collapsed
  proposal-failed bucket.

The status collapse is an engineering/product-schema decision, not an equation
from the RATTLE paper.  It is acceptable for MCMC correctness because all these
non-accepted proposal-construction branches are stay-put transitions, but it is
not acceptable to cite the collapsed public status as if it proved a specific
physical mechanism.  The next proof-test packet should include a status mapping
test/table so this boundary is mechanically visible.

The same rule applies to counters.  Typed local-transition events distinguish
specific statuses, while legacy aggregates such as `projection_failure_count`
remain compatibility fields.  They must be interpreted as compatibility
aggregates, not literal projection-only evidence.

## Warmup, Diagnostic, And Legacy Routes

`rattle2` / `integrate_hmc_warmup` is a warmup/relaxation route, not the
accepted Metropolis proposal proof route.  It shares some RATTLE machinery, but
its failure abort currently resets `final_hamiltonian` and `jacf` without the
same complete `final_x/final_z` stay-put guarantee as `rattle`.  This remains
`HWM-RATTLE-WARMUP-001`.

The diagnostic reverse probe in `hmc.f90` is also not an acceptance gate.  It
records reversibility/readback diagnostics after proposal construction; the
actual acceptability gate is the reverse-gate replay inside
`rattle_step_core`, followed by Metropolis.

Legacy switches such as `istest/testmom` and the warmup `eo` branch are
behavior surfaces, but not paper derivations.  They belong in the cleanup and
state/productization queue after the RATTLE proof-test/API-hardening packet.

## Symplectic / Reversibility Claim Boundary

The code has the correct constrained leapfrog/RATTLE structure in the successful
core:

```text
project initial momentum to tangent
Delta z = h*pi - h**2/2 grad V
solve constrained position projection
strictly reflow endpoint and Jacobian
pi_half = (z' - z)/h
pi_tilde' = pi_half - h/2 grad V(z')
project final momentum to tangent
```

In exact arithmetic, with exact flow/Jacobian values and exact constraint
solves, this is the expected constrained-HMC RATTLE structure and is the right
structure for the usual reversibility/volume-preservation argument.

The current Fortran implementation is finite precision and implementation
certified rather than mathematically exact:

- flow/Jacobian evaluation is numerical ODEX endpoint integration;
- the constraint solve is simplified Newton or official DFO-LS plus TLTM
  residual/certification policy;
- success requires strict final `flow(...)`;
- reverse gate replays the reverse step and checks `x`, `z`, `J`, and momentum;
- failures follow the confirmed TLTM project policy: reject/stay-put instead of
  paper momentum reflection.

Therefore the correct strong statement is:

```text
The successful RATTLE core update order, force half-step signs, Newton residual,
momentum reconstruction, and tangent projection match the reference-backed
RATTLE structure under the current packing convention.  Accepted proposals are
then numerically certified by strict final flow and reverse gate.  This is not a
standalone proof that every finite-precision branch is an exact symplectic,
volume-preserving paper map.
```

## Existing Evidence

Current retained-core tests support the matched-core claim:

- `test_retained_core_newton_contract` replays accepted simplified Newton
  solutions for step sizes `0.002`, `0.003`, and `0.004`; it checks residual
  replay and `lambda = O(h**2)` scaling.
- `test_retained_core_rattle_rg_contract` covers one successful one-step RATTLE
  proposal: final endpoint/Jacobian replay, final momentum tangent projection,
  reverse-gate replay success, and replay diagnostics context isolation.
- `test_retained_core_rg_reject_identity` covers reverse-gate rejected
  HMC/Metropolis stay-put outputs and, after HWM-MET-001, ordinary finite
  Metropolis rejection output reset.

## Remaining Boundaries Before Paper-Correctness Claim

This derivation packet closes the immediate momentum-update/sign/factor question
for the successful RATTLE core.  It does not close:

- direct `rattle_step_core` failure-output API semantics;
- warmup `rattle2` failure-output API semantics;
- legacy `istest/testmom` overriding explicit momentum input;
- HMC proposal-status to Metropolis-status/counter mapping;
- Newton controller constants and failure predicates;
- official DFO-LS wrapper/certification choices inside the RATTLE step;
- full formal proof that the finite-precision accepted proposal kernel is
  symplectic/volume-preserving beyond reverse-gate numerical certification;
- model/action branch-convention derivation beyond the use of `ds=dS/dz` and
  `conjg(ds)` here.

## Recommended Next Step

Proceed with the previously proposed RATTLE/HMC API-hardening/proof-test patch,
but keep its claim narrow:

1. Reset failed direct `rattle_step_core` outputs to stay-put after valid shape
   checks.
2. Reset failed warmup `rattle2` outputs to stay-put unless the user explicitly
   wants partial-progress warmup semantics.
3. Add focused direct-core/warmup failure-output tests.
4. Add HMC status to Metropolis status/counter mapping coverage.
5. Keep separate packets for Newton controller policy and QN wrapper
   certification.
