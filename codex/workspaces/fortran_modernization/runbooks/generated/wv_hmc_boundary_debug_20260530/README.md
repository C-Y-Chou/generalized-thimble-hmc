# WV-HMC Boundary/Newton Debug Readback 2026-05-30

## Scope

This note records the WV-HMC `n=2` correctness debugging sequence after the
dense-oracle trajectory, projection, and measurement path had already been
restored. All executable validation in this note was run on cluster02 through
`codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh`; no local Fortran
simulation was used.

## Exact Reference

For `data/parameters_stephanov_n2_smoke.dat`, the validation target is:

- `chiral_condensate = 0.380047505938398`
- `number_density = 0.0387173396674602`

The earlier values `0.0094567425` and `0.29759133` are not the reference for
this `n=2, mu=0.3, tau=0.1` gate.

## Root Cause Found

The Newton solve inside `wv_rattle_step_dense_no_boundary` could evaluate the
first-constraint residual at a trial target flow time outside the allowed
extended worldvolume interval `[T0-d0,T1+d1]`. Before the fix, this was reported
as a generic residual/ODE failure and caused the whole transition to stay put.

The first attempted repair reflected immediately whenever an intermediate
Newton residual evaluation went outside the interval. That was too aggressive:
an intermediate Newton overshoot is not itself the paper boundary event. It
produced poor reversibility in the trace smoke and was aborted before the full
formal validation completed.

The retained repair damps boundary-crossing Newton updates so the solver first
tries to converge inside the interval. Only repeated/no-progress boundary
approach is classified as `wv_newton_stop_boundary_exit` and mapped to a RATTLE
reflection at the current state.  The current reflection preserves the
fixed-flow-surface tangent momentum and flips only the worldvolume flow-time
component; the earlier full `pi -> -pi` bounce was found to suppress `x`
mobility in small-`T1` runs.

## Code Changes

- `src/sampler/wv_hmc_constraints.f90`
  - Added `wv_newton_stop_boundary_exit = 10`.
  - Added target-flow bounds to the first-constraint residual/solve path.
  - Added damped Newton update scaling when the proposed `h` would leave the
    flow-time interval.
  - Boundary exit now reflects in the boundary wrapper instead of becoming a
    generic transition construction failure.
- `src/sampler/wv_hmc_trajectory.f90`, `src/sampler/wv_hmc_driver.f90`,
  `src/apps/wv_hmc_app_common.f90`
  - Added forward/reverse boundary-exit counters and reverse-gate summary fields.
- `tests/test_wv_hmc_constraint_kernels.f90`
  - Added boundary-exit reflection coverage.
  - Added nonzero-flow dense decomposition vs operator oracle coverage.
  - Added dense-vs-operator measurement factor oracle coverage.

## Cluster Gates

### Boundary Trace Before Damping

Request:
`FMOD-WV-HMC-NEWTON-TRACE-BOUNDARY-DIAG-20260530`

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_newton_trace_boundary_diag_n2_8x1000_eps0015_s3_20260530`

Key result: many Newton terminal residual failures were actually boundary
overshoots.

### Immediate Reflection Attempt

Request:
`FMOD-WV-HMC-BOUNDARY-EXIT-PATCHED-TRACE-SMOKE-20260530`

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_boundary_exit_patched_trace_smoke_n2_8x1000_eps0015_s3_20260530`

Key result: failures shifted into boundary exits, but reverse-gate errors became
large. The follow-up formal run was aborted because this semantics was too
strong.

### Damped Boundary Newton Gate

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-NEWTON-GATE-20260530`

Job:
`18138.anode01`

Log:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_debug_tests_20260530/damped_boundary_newton_gate_20260530/pbs_boot_18138.anode01.log`

Status: deterministic WV math/constraint gates passed.

### Damped Trace Smoke

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-TRACE-SMOKE-20260530`

Job:
`18139.anode01`

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_trace_smoke_n2_8x1000_eps0015_s3_20260530`

Key diagnostics:

- `transitions_failed = 245`
- `bounced_steps = 1070`
- `solver_stop_boundary_exit = 1088`
- reverse-gate mean state/momentum errors:
  `3.1268e-10 / 2.3357e-10`
- reverse-gate max state/momentum errors:
  `1.683e-08 / 1.257e-07`

This fixed the immediate-reflection reversibility problem.

### First Damped Formal Validation

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X8000-VALIDATION-20260530`

Jobs:
`18140.anode01` through `18147.anode01`

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x8000_eps0015_s3_20260530`

Readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x8000_eps0015_s3_20260530/readback_128_damped_boundary`

Summary:

- seeds: `128`
- total cycles: `1024000`
- measurements: `631378`
- phase coherence: `0.9321657932151989`
- transition failures: `26759`
- bounced steps: `119577`
- ODE failures: `5193`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.3765737129 | 0.0010435737 | 0.0063969840 | 0.0050880887 | 0.3800475059 | -0.543 | 0.205 |
| number_density | 0.0564540870 | -0.0139845495 | 0.0110859686 | 0.0142410441 | 0.0387173397 | 1.600 | -0.982 |

This passes the current exact-reference sanity criterion at the `<2 sigma`
level, but an independent same-kernel rerun was launched because density Re is
still the largest remaining finite-sample warning.

### Independent Same-Kernel Rerun

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X8000-INDEPENDENT-RERUN1-20260530`

Jobs:
`18148.anode01` through `18155.anode01`

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x8000_eps0015_s3_rerun1_20260530`

Readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x8000_eps0015_s3_rerun1_20260530/readback_128_damped_boundary_rerun1`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.3770149939 | -0.0076436661 | 0.0047875878 | 0.0051242763 | 0.3800475059 | -0.633 | -1.492 |
| number_density | 0.0490250024 | 0.0065145065 | 0.0092421651 | 0.0139305017 | 0.0387173397 | 1.115 | 0.468 |

### First + Rerun1 Combined

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_256x8000_eps0015_s3_combined_20260530`

Readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_256x8000_eps0015_s3_combined_20260530/readback_256_damped_boundary_combined`

Summary:

- seeds: `256`
- total cycles: `2048000`
- measurements: `1262764`
- phase coherence: `0.9306297594289731`
- transition failures: `52467`
- bounced steps: `237270`
- ODE failures: `10193`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.3768016347 | -0.0032569288 | 0.0039982694 | 0.0036125085 | 0.3800475059 | -0.812 | -0.902 |
| number_density | 0.0527537150 | -0.0038437111 | 0.0072211825 | 0.0099637199 | 0.0387173397 | 1.944 | -0.386 |

The 256-seed combined readback is still below `2 sigma`, but the density Re
shift is same-sign in the first two independent 128-seed batches.  Two more
independent batches were therefore submitted as a finite-statistics versus
remaining invariant-measure discriminator:

- `FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X8000-INDEPENDENT-RERUN2-20260530`
- `FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X8000-INDEPENDENT-RERUN3-20260530`

### Rerun2

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X8000-INDEPENDENT-RERUN2-20260530`

Readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x8000_eps0015_s3_rerun2_20260530/readback_128_damped_boundary_rerun2`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.3730174188 | -0.0057359031 | 0.0048802414 | 0.0057791131 | 0.3800475059 | -1.441 | -0.993 |
| number_density | 0.0424885455 | 0.0085835313 | 0.0103054014 | 0.0153176506 | 0.0387173397 | 0.366 | 0.560 |

### Rerun3

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X8000-INDEPENDENT-RERUN3-20260530`

Readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x8000_eps0015_s3_rerun3_20260530/readback_128_damped_boundary_rerun3`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.3779130157 | 0.0161695840 | 0.0065113516 | 0.0150213334 | 0.3800475059 | -0.328 | 1.076 |
| number_density | 0.0511958009 | -0.0121794113 | 0.0125412980 | 0.0219336845 | 0.0387173397 | 0.995 | -0.555 |

### 512-Seed Combined

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_512x8000_eps0015_s3_combined_20260530`

Readback:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_512x8000_eps0015_s3_combined_20260530/readback_512_damped_boundary_combined`

Summary:

- seeds: `512`
- total cycles: `4096000`
- measurements: `2524811`
- phase coherence: `0.9282882312632617`
- transition failures: `105579`
- bounced steps: `473702`
- ODE failures: `21156`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.3760925251 | 0.0009538636 | 0.0028450437 | 0.0044001736 | 0.3800475059 | -1.390 | 0.217 |
| number_density | 0.0498241164 | -0.0028188918 | 0.0054249996 | 0.0083100414 | 0.0387173397 | 2.047 | -0.339 |

The 512-seed discriminator did not cleanly close the issue: density Re remained
slightly above `2 sigma`.  This is not strong enough by itself to prove a
kernel bug, but it is strong enough to require a burn-in/initial-bank
discriminator before closure.

### Late-Measurement Discriminator

Request:
`FMOD-WV-HMC-DAMPED-BOUNDARY-N2-128X16000-LATE-MEASURE-20260530`

Jobs:
`18172.anode01` through `18179.anode01`

Run:
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x16000_eps0015_s3_late_measure_20260530`

Purpose: keep the same kernel and HMC parameters but delay measurements to
cycle `8001`.  If this passes while the 8000-cycle runs remain density-high,
the likely remaining issue is WV thermalization/initial-bank policy rather than
the dense transition kernel.

Live checkpoint after context compaction:

- checked at `2026-05-30T21:37:05+0900`
- local workspace:
  `/Users/ccy/Documents/TLTM_fortran_modernization`
- remote debug worktree:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_wv_wprime_fd_debug_20260530`
- output root:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_damped_boundary_validation_n2_128x16000_eps0015_s3_late_measure_20260530`
- current cluster jobs:
  `18172.anode01` through `18179.anode01`, all still `R`
- current output count:
  `66` summary files and `66` observable files out of `128`
- no replacement/refill job has been submitted yet for this discriminator

Continuation rule: do not restart this discriminator just because the context
was compacted.  First let these jobs finish or explicitly choose a seed-level
refill strategy for missing seeds.  Any real PBS submission must go through
`codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh` with scheduler
authority and a new row in
`codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_REQUESTS.tsv`.

## Exact Reference Recheck

An independent Gauss-Hermite `k=5` Python re-evaluation of the current
Stephanov `n=2, m=0.2, mu=0.3, tau=0.1, nf=1` observable convention gives:

- `chiral_condensate = 0.38004750593839826`
- `number_density = 0.0387173396674603`

This matches the existing reference table, so the density Re tension cannot be
explained by a stale exact reference or observable-name mismatch.

## E/F Geometry Recheck

The current dense `E/F` implementation was rechecked against the simplified
WV-HMC paper formulas.  In the paper's notation, the real-linear map is
`w = A w0 = E v0 + F n0` with
`v0 = (w0 + conjg(w0))/2` and `n0 = (w0 - conjg(w0))/2`.  With explicit
Jacobian `E`, the simplified Newton footnote gives
`Delta u = Re(E^{-1} B)` and
`Delta lambda = F(i Im(E^{-1} B)) = i E Im(E^{-1} B)`.

The dense code path matches this structure: it solves the real-block
`J_real coords = B`, keeps the real coordinate slots for the `E` tangent
component, and treats the residual as the `F`/normal component.  This does not
look like the current root cause.  The remaining unresolved question is not the
basic dense `E/F` split, but whether the transition/boundary/burn-in policy
samples the intended worldvolume distribution accurately enough.

## Flow-Time Wall Reflection Closure

After the late-measure and small-`T1` checks still left a confusing observable
story, the boundary map itself was re-examined.  The full `pi -> -pi` wall
bounce was identified as the remaining root cause: it reverses the fixed-flow
tangent component of the worldvolume momentum, so the chain bounces in flow time
while artificially suppressing motion in `x`.

The production boundary map was changed to preserve the fixed-flow tangent
momentum and reflect only the flow-time component.  Deterministic math and
constraint gates then passed on cluster02:

- request:
  `FMOD-WV-HMC-BOUNDARY-REFLECTION-FIX-GATE-RERUN1-20260531`
- job:
  `18281.anode01`
- log:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_debug_tests_20260530/boundary_reflection_fix_rerun1_20260531/pbs_boot_18281.anode01.log`
- status:
  `test_wv_hmc_math_kernels` PASS and
  `test_wv_hmc_constraint_kernels` PASS

A small post-fix epsilon scan with bank initialization and
`T0=1e-4`, `T1=1e-3`, `gamma=0`, `nstep=20` showed the expected transition:

| eps | seeds x cycles | effective x jump sq / cycle | strongest exact-reference z |
|---:|---:|---:|---:|
| 0.0005 | 16 x 4000 | `4.75714e-05` | `9.5` |
| 0.0015 | 16 x 4000 | `2.37705e-04` | `2.04` |
| 0.003 | 16 x 4000 | `5.83269e-04` | `1.11` |
| 0.005 | 16 x 4000 | `7.68422e-04` | `2.33` |

The formal post-fix validation used the best short-scan point:

- request family:
  `FMOD-WV-HMC-REFLECTFIX-E003-64X10000-N2-CHUNK00-20260531`
  through `CHUNK03`
- jobs:
  `18286.anode01` through `18289.anode01`
- run:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_reflectfix_e003_n2_64x10000_20260531`
- readback:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_reflectfix_e003_n2_64x10000_20260531/combined_64seed/readback`

Summary:

- seeds: `64`
- total cycles: `640000`
- measurements: `417248`
- phase coherence: `0.864311`
- bounced steps / trajectory steps: `0.732541`
- forward construction failures: `845`
- ODE failures: `325`
- effective x jump sq / cycle: `5.59137e-04`

Observable z scores:

| observable | estimate Re | estimate Im | SE Re | SE Im | target Re | z Re | z Im |
|---|---:|---:|---:|---:|---:|---:|---:|
| chiral_condensate | 0.379826317 | 0.00700051897 | 0.015 | 0.00783 | 0.380047505938398 | -0.0147 | 0.894 |
| number_density | 0.0403096216 | -0.0240821256 | 0.0228 | 0.0258 | 0.0387173396674602 | 0.0698 | -0.934 |

This closes the `n=2` small-`T1` dense WV-HMC correctness blocker for the
current dense explicit-J kernel.  The observed bias was not a sign-problem
effect and not evidence that HMC cannot solve the model.  It was caused by an
incorrect flow-time wall reflection combined with too-small `x`-space motion at
the old epsilon.

## Small Nonzero W Validation

The first nonzero-`W(t)` check exposed that the measurement factor had only been
correct for `W(t)=0`.  For a chain sampled with
`H = K + Re S + W(t)`, the observable reweighting must include `exp(W(t))`.
The dense and operator measurement paths now compute
`wv_factor = exp(W(t)) * phase_factor / alpha`.

Deterministic gate:

- request:
  `FMOD-WV-HMC-NONZERO-W-MEASUREMENT-GATE-20260531`
- job:
  `18290.anode01`
- log:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_debug_tests_20260530/nonzero_W_measurement_gate_20260531/pbs_boot_18290.anode01.log`
- status:
  `test_wv_hmc_math_kernels` PASS and
  `test_wv_hmc_constraint_kernels` PASS, including dense/operator nonzero-`W`
  measurement-factor agreement.

Cluster observable checks used the same `n=2`, `eps=0.003`, `nstep=20`,
`T0=1e-4`, `T1=1e-3`, `d0=1e-4`, `d1=2.5e-4`, bank initialization, and
64 seeds x 10000 cycles.

| W gamma | seed range | strongest exact-reference z | result | readback |
|---:|---:|---:|---|---|
| 20 | 41001-41064 | `2.61` | failed; this is a `W'` force stress, not a small-gamma validation | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_reflectfix_gamma20_n2_64x10000_20260531/combined_64seed/readback` |
| 0.2 | 42001-42064 | `2.29` | failed; nonzero-`W` transition/mixing remains unresolved at this slope | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_reflectfix_gamma0p2_n2_64x10000_20260531/combined_64seed/readback` |
| 0, same seeds as 0.2 | 42001-42064 | `0.991` | passed; the gamma=0.2 deviation is not explained by this seed range alone | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_reflectfix_gamma0_control_seeds42001_n2_64x10000_20260531/combined_64seed/readback` |
| 0.02, same seeds as 0.2 | 42001-42064 | `1.43` | passed; the nonzero-`W` code path is not generically broken in the perturbatively tiny-slope limit | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_reflectfix_gamma0p02_n2_64x10000_20260531/combined_64seed/readback` |

The observable checks above are not a proof that the nonzero-`W` transition
kernel is correct.  They are finite-chain smoke tests.  After the `gamma=0.2`
failure, the validation was moved to a formula-level identity check instead of
continuing to scan longer chains.

Formula-level deterministic identity:

- request:
  `FMOD-WV-HMC-NONZERO-W-REWEIGHT-IDENTITY-GH3T3-RERUN2-20260531`
- job:
  `18309.anode01`
- readback:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_w_reweight_identity_rerun2_20260531_18309.anode01/wv_nonzero_w_reweight_identity.md`
- CSV:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_observable_validation_20260530/wv_hmc_w_reweight_identity_rerun2_20260531_18309.anode01/wv_nonzero_w_reweight_identity.csv`
- status:
  PASS for the measurement/reweighting identity on all available flowed GH
  slots.

The identity checked, point by point over multiple flow-time quadrature nodes,

```text
exp(-Re S - W) * alpha * |det J|
  * [exp(W) * exp(-i Im S) * detJ/|detJ| / alpha]
= exp(-S) * detJ .
```

This verifies the sign of `W` in the measurement factor, the `alpha`
cancellation convention, and the Jacobian phase convention without relying on
Markov-chain convergence.  The script also computes wrong-sign controls:
`exp(-W)` and no-`W` measurement factors.  It uses grouped Fortran Stephanov
state ordering; the older flowed GH helper had used interleaved indexing and
was corrected.

| gamma | samples | skipped slots | max pointwise direct-WV rel err | max observable direct-WV abs | max observable wrong-sign-direct abs |
|---:|---:|---:|---:|---:|---:|
| 0 | 19491 | 192 | `2.711e-20` | `1.110e-16` | `1.110e-16` |
| 0.02 | 19491 | 192 | `2.794e-20` | `1.669e-16` | `3.849e-08` |
| 0.2 | 19491 | 192 | `2.794e-20` | `1.112e-16` | `3.849e-07` |
| 20 | 19491 | 192 | `2.794e-20` | `5.610e-17` | `3.857e-05` |

The current conclusion is deliberately narrow:

- Verified: nonzero-`W` measurement/reweighting algebra with `exp(+W)`,
  `alpha`, and `detJ/|detJ|` is correct on flowed states produced by the
  current dense builder.
- Not yet verified: nonzero-`W` transition-kernel correctness and mixing for
  practical slopes such as `gamma=0.2`.
- Therefore, do not promote `gamma=0.2` based on observable trial runs.  The
  next check must be a transition audit: nonzero-`W` Hamiltonian difference,
  reversibility/RG behavior, reflection behavior with `W'`, and flow-time
  distribution/mixing under tuned HMC parameters.

## Nonzero W Transition Gate

The dedicated transition audit was added after the `gamma=0.2` observable
failure, using the same small-`T1` paper-wall setup:
`T0=1e-4`, `T1=1e-3`, `d0=1e-4`, `d1=2.5e-4`, `gamma=0.2`.

- request:
  `FMOD-WV-HMC-NONZERO-W-TRANSITION-GATE-20260531`
- job:
  `18310.anode01`
- log:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_debug_tests_20260530/nonzero_W_transition_gate_20260531/pbs_boot_18310.anode01.log`
- status:
  PASS for paper-wall `W'` force finite difference, dense transition reverse
  gate, and one-step/two-half-step Hamiltonian scaling.

Key log lines:

```text
[CHECK] wv_worldvolume_force_fd ok=T fd=3.0018E-01 force_dir=3.0018E-01 diff=5.5589E-13
[CHECK] wv_nonzero_w_transition_gate ok=T dH=8.6491E-12 accept=1.0000E+00 rg_state=5.1113E-12 rg_pi=4.3599E-13 status=0
[CHECK] wv_nonzero_w_energy_scaling ok=T dH_large=2.3488E-11 dH_small=5.8717E-12 t_large=5.5121E-04 t_small=5.5121E-04
```

This closes the local transition-mechanics gate for the dense explicit-J
kernel.  It does **not** close the production gate, because the existing
`gamma=0.2`, 64 seed x 10000 cycle observable run still has coherent
two-sigma-level exact-reference deviations and no history output.  Production
readiness therefore requires a history-aware validation run with block/seed
jackknife, cumulative z, first/second-half checks, flow-time occupancy, and
state-movement diagnostics.

## Current Interpretation

The dense `E/F` decomposition and dense measurement factor have nonzero-flow
deterministic oracle tests.  The main algorithmic bugs found and fixed were:

- Newton boundary exits must be classified as boundary reflections, not generic
  construction failures.
- The flow-time wall reflection must preserve fixed-flow tangent momentum and
  flip only the worldvolume flow-time component.

The dense explicit-J WV-HMC path is ready to proceed only after the nonzero-`W`
transition audit is closed.  The transition audit is now closed for a local
paper-wall `gamma=0.2` gate, but larger-slope production remains blocked by
observable/history validation.  Nonzero `W(t)` is validated for deterministic
measurement/reweighting and local transition mechanics; `gamma=0.2` remains a
finite-chain mixing/statistics production-risk item, not a closed production
SOP.

## Remaining Checks Before Matrix-Free/BiCGStab Wiring

- Keep DOP853 as the active/default ODE backend for WV-HMC validation.
- For nonzero `W(t)`, run a history-aware production validation before
  promoting `gamma=0.2` or larger slopes: block/seed jackknife, first/second
  half, cumulative z, flow-time histogram/mixing, x/state movement, reverse
  gate diagnostics, and exact-reference gates.
- Keep the flow-time wall reflection test in the deterministic gate.
- Run `git diff --check`.
- Ensure the scheduler ledger, runbook, PBS scripts, and readback scripts are in
  a consistent worktree state before moving on.
