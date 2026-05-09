# Fallback Policy (Rescue Design Baseline)

This document is the canonical fallback behavior for current Stage 3.4 rescue-design work.

The next QN proposal-inclusion design is specified in:

- `docs/qn_proposal_inclusion_design_2026-04-27.md`

## Policy Lock

- Quasi fallback remains the active improvement path; no-fallback is a reference, not the target design.
- The current working baseline is bounded probe-only:
  - `enable_quasi_fallback=true`
  - `QN_S1_PROBE_MAX_ITER=28`
  - `QN_S1_NEAR_RESCUE_ENABLED=0`
  - `QN_S1_NONNEAR_RESCUE_ENABLED=0`
- Legacy global fallback has been removed from active source; near full retry and non-near cheap/full retry remain disabled by default because the tested versions did not improve the Re-virial bias and can introduce route asymmetry.
- New rescue paths must be treated as kernel-design candidates and validated against the no-fallback reference and the bounded-probe baseline.

## Runtime Path

For each RATTLE projection attempt:

1. `solve_constraint_newton(tol=constraint_tol, max_iter=100)`.
2. If Newton fails and `enable_quasi_fallback=true`, run bounded quasi probe:
   - `try_quasi_stage(tol, max_iter=QN_S1_PROBE_MAX_ITER, stage=probe)`.
3. If bounded probe fails, return failure to the outer RATTLE/TLTM step.

The baseline path intentionally does not run:

- near full retry;
- non-near cheap/full retry;
- diversified restart/sweep paths.

## Current Evidence

Stage 3.4 at `t=0.35` shows:

- no-fallback has a large negative Re-virial bias in the 1024-seed 200k reference:
  `Re<virial> = -0.0208976 +/- 0.0011879`.
- old `probe_only_p28` moved the mean much closer to zero:
  `Re<virial> = +0.00543094 +/- 0.00102383`.
- adding raw/full rescue paths did not improve the result.
- the probe/filter matrix showed that raw global-style rescue paths can add a clear positive Re shift, while filter variants were consistent with bounded probe-only at 64 seeds.

Therefore the problem is not that quasi fallback should be removed. The problem is that extra rescue paths need a better design than adaptive path escalation after failure.

## Design Principle

The likely failure mode is proposal-route asymmetry. Forward and reverse proposals can enter different solver routes (`probe`, `near`, `far`, continuation, restart, sweep), with different support and different effective proposal probabilities. The current Metropolis ratio does not include a route-probability correction.

New rescue paths should therefore satisfy at least one of:

- fixed-route mixture: choose the rescue route from a fixed distribution before solving, so route probability is explicit and symmetric;
- route-certified proposal: accept a rescued proposal only if the reverse move with the same route/budget would also be available;
- derived delayed-rejection correction: include the correct proposal-ratio terms for staged rescue attempts.

Until such a design is implemented, do not re-enable adaptive global/near/non-near path escalation as a production kernel.

## Controls

Primary controls:

- `constraint_tol` in `data/parameters.dat`.
- `enable_quasi_fallback` in `data/parameters.dat` (default `true`; no-fallback references set this to `false`).

Current baseline controls:

- `QN_S1_PROBE_MAX_ITER` (default `28`; keep `<=32` unless running an ablation).
- `QN_S1_NEAR_RESCUE_ENABLED` (default `0`).
- `QN_S1_NONNEAR_RESCUE_ENABLED` (default `0`).

Research-only controls:

- `QN_S1_NEAR_FULL_MAX_ITER`.
- `QN_S1_NONNEAR_CHEAP_MAX_ITER`.

Legacy controls were removed from runtime policy code and have no effect:

- `QN_QUASI_GLOBAL_FALLBACK_ENABLED`.
- `QN_PROGRESSIVE_RESCUE_STAGE`, `QN_BASELINE_STAGE`.
- `QN_ENABLE_LEGACY_RESCUE`, `QN_LEGACY_RESCUE`, `QN_RESCUE_LEVEL`.
