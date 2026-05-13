# CV011 Stage2 Kernel RNG v2 Design - 2026-05-14

## Purpose

This is the modernization-tree entry point for the RNG v2 design that came out
of the solver-assist discrepancy investigation.  New modernization sessions
should read this file before continuing CV-011 RNG/reentrancy work.

The production-comparison reproducer evidence is archived at:

`codex/workspaces/tltm_production_comparison/archive/assist_regression_bisect_20260513/notes/ASSIST_REGRESSION_BISECT_20260513.md`

Implementation record:

`codex/workspaces/fortran_modernization/runbooks/CV011_STAGE2_KERNEL_RNG_V2_IMPLEMENTATION_20260514.md`

## Problem Statement

The tiny first-bad-change investigation found that the behavior jump appears at
`d26c939` under forced NT+QN navigation assist.  The transition is tied to the
Stage2 RNG stream contract, not to ODEX extraction, DFO-LS callback context,
typed solver-assist policy, QN diagnostics/policy context, or certification.

Current modernization has:

- historical shared serial behavior: `legacy_global_v0`;
- current explicit stream contract: `per_replica_rng_v1`;
- evidence that `per_replica_rng_v1` changes same-seed Stage2 trajectories and
  is not yet production-equivalent.

Do not treat `legacy_global_v0` as the desired modernization design.  Keep it
only as a historical compatibility baseline.  Do not treat
`per_replica_rng_v1` as production-equivalent until it passes the audits below.

## Target Contract

The modernization target is:

```text
TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2
```

`stage2_kernel_rng_v2` owns randomness by transition-kernel invocation, not by a
mobile label, not by a fixed temperature slot's long-lived stream, and not by
module-global RNG state.

## Design Contract

- RNG is owned by a transition-kernel invocation.
- All random events use domain-separated keys derived from the same `base_seed`.
- No long-lived local-update RNG state is advanced across proposals.
- Accepted replica exchange does not swap RNG state, because RNG state is not
  stored on labels/configurations.
- `mt95.f90` Gaussian spare state remains part of explicit RNG state when MT95
  is used inside a kernel stream; the spare must never cross domain boundaries.
- Solver/HMC/QN/flow contexts must be scratch or diagnostics only.  Any context
  field that changes the proposal law across invocations must be reset per
  proposal or promoted into an explicit Markov-state variable.

## Required Domains

```text
stage2:init              key = base_seed, slot_id, attempt_id
stage2:local_momentum    key = base_seed, cycle_idx, slot_id, update_idx
stage2:local_accept      key = base_seed, cycle_idx, slot_id, update_idx
stage2:swap_accept       key = base_seed, cycle_idx, pair_id
```

Initialization RNG must be separate from production local-update RNG so adaptive
initialization attempt counts cannot shift production sampling randomness.

## Implementation Preference

1. Prefer a counter-based RNG for v2, with `(domain, base_seed, cycle_idx,
   slot_id/pair_id, update_idx, draw_idx)` as the counter/key material.
2. If MT95 must be kept initially, instantiate one short-lived MT95 state per
   domain invocation using a robust 64-bit hash/mixer such as SplitMix64-derived
   seeding.  Do not use linear seed derivation like `base_seed + stride*offset`.
3. `grand(momentum)` must draw from the provided kernel RNG object, not from
   uncontrolled module-global RNG.
4. Metropolis accept and swap accept must draw from their own domain RNG
   objects.
5. Stage1/Stage2 output and sidecars must print the RNG contract string.

## Compatibility Modes

The implementation should expose an explicit contract selector:

```text
TLTM_STAGE2_RNG_STREAM_CONTRACT=legacy_global_v0|per_replica_rng_v1|stage2_kernel_rng_v2
```

Use `legacy_global_v0` only for reproducing historical artifacts or comparing
against old `d3f133d`/official gate outputs.  Keep `per_replica_rng_v1` available
only as an audited intermediate unless it passes parity/statistical checks.

## Minimum Tests

1. Deterministic replay: rerun the same tiny config twice with
   `stage2_kernel_rng_v2`; assert byte-identical diagnostic signature and
   printed contract metadata.
2. Schedule invariance: run the same fixed tiny config with local slot update
   order reversed or parallel-order simulated.  Final signature must be
   identical under domain-separated kernel RNG.
3. Init decoupling: force an extra rejected/adaptive initialization attempt in
   one slot while keeping the first accepted initial configuration fixed.
   Production local RNG keys and post-init transition signatures must not shift.
4. Swap isolation: run a tiny two-slot config with swap disabled vs enabled and
   audit that local momentum/accept RNG keys for a given `(cycle, slot, update)`
   are unchanged.
5. Statistical smoke: run `legacy_global_v0`, `per_replica_rng_v1`, and
   `stage2_kernel_rng_v2` on the established `1 seed x 1000 cycles`
   p28/RG/cttol=1e-13 reproducer with NT+QN navigation assist forced.  This is
   not a proof of correctness; it checks that v2 does not immediately reproduce
   the known v1 bad transition.
6. Longer-chain benchmark: compare `stage2_kernel_rng_v2` against an
   independent physical/statistical benchmark, not only against
   `legacy_global_v0`.  Track failure density, mean Re<O>, mean Im<O>,
   acceptance, swap acceptance, round trips, NT assist, QN success, QN assist,
   and RG rejects.

## Modernization Guidance

This is not a production-comparison side experiment.  It is a CV-011
modernization design requirement because RNG ownership is part of the proposal
law.  Any implementation of `stage2_kernel_rng_v2` is behavior-relevant and must
carry an F8 patch reference statement, M4 guardrails, and an affected baseline
comparison or explicitly approved narrower baseline.
