# CV-011 RNG / Workspace / Reentrancy Decision Packet

Date: 2026-05-12 JST

## Status

CV-011 remains open. The modernization tree reached a real decision point:
the next source changes could either preserve the current serial RNG trajectory
as the default contract, or move directly to per-replica/per-slot RNG ownership.
Those were not the same product claim.

The selected route is B: per-replica/per-slot RNG now. Implementation evidence
is recorded in `CV011_PER_REPLICA_RNG_IMPLEMENTATION_20260512.md`.

## Source-Backed Facts

1. `src/core/mt95.f90` owns the production RNG as module-global state:
   `mt`, `mti`, `sgrnd`, `grnd`, `gaussrnd`, `mtsave`, and `mtget`.
2. `gaussrnd` has hidden Box-Muller spare state (`gset`, `iset`) that is not
   covered by the existing `mtsave`/`mtget` state save/restore API.
3. Stage1 initializes each replica with a derived per-replica seed, then resets
   the global generator back to `base_seed` before serial local updates.
4. Stage2 initializes each slot with a derived per-slot seed, then resets the
   global generator back to `base_seed` before serial local updates and swap
   decisions.
5. `metropolis_step` draws accept/reject randomness from the global `grnd()`.
   Stage2 swap acceptance also draws from global `grnd()`.
6. Therefore current serial execution is not a collection of independent
   per-replica streams. It is a serial interleaving of global RNG draws after
   initialization.
7. Moving local updates to true per-replica/per-slot streams will change serial
   trajectories unless a legacy-compatibility mode is preserved or the change is
   explicitly accepted as a new stochastic stream contract.

## Decision Required

This decision has been made. The options below are retained for provenance.

### A. Strict Legacy Serial First

Keep the current serial global-stream order as the default public behavior.
Implement explicit RNG context/snapshot APIs and deterministic tests that prove
existing serial outputs are unchanged. Defer true per-replica stream ownership to
a later opt-in mode.

Pros:
- Lowest risk to existing reference data and production comparability.
- Cleanly satisfies the hard rule that modernization must not silently change
  physics/output.
- Lets non-RNG workspace ownership continue after exact-output tests exist.

Cons:
- Does not honestly claim OpenMP-ready per-replica RNG productization.
- CV-011 should remain open or be narrowed until per-replica mode is added.

### B. Per-Replica / Per-Slot RNG Now

Make each replica/slot own its local-update RNG stream now. Add a separate swap
RNG stream for Stage2. Treat changed serial trajectories as an accepted product
semantics change requiring new baselines and provenance.

Pros:
- Direct route to a reentrant/parallel-ready sampler design.
- CV-011 can close more cleanly if deterministic serial/parallel tests pass.

Cons:
- Breaks current serial trajectory comparability.
- Requires explicit acceptance that regenerated baselines are a new stream
  contract, not output-preserving modernization.

### C. Dual-Mode Product Contract

Make `legacy_serial_rng` the default mode and add an explicit opt-in
`per_replica_rng` mode. The legacy mode must reproduce current serial outputs.
The per-replica mode gets its own deterministic tests, sidecar provenance, and
no claim of equivalence to legacy trajectories.

Pros:
- Preserves current physics/output by default while creating a real path to
  reentrant/parallel productization.
- Avoids hiding an RNG stream change behind a refactor.
- Gives production redo a conservative default while allowing controlled future
  parallel experiments.

Cons:
- More implementation and test surface.
- CV-011 closes only after both modes, provenance labels, and deterministic
  serial/parallel checks are implemented.

## Recommendation

Choose C unless schedule pressure is more important than product clarity.

The reason is simple: the present code already mixes two ideas. Initialization
uses derived replica/slot seeds, but production local updates and swaps consume a
shared global serial stream. A direct per-replica migration is scientifically
reasonable, but it is not output-preserving. A dual-mode contract makes that
boundary explicit and keeps the modernization rule intact.

## If C Is Chosen

Implementation should proceed in this order:

1. Add an explicit RNG state type covering MT state plus `gaussrnd` spare state.
2. Add legacy snapshot/restore wrappers without changing default call sites.
3. Add a small deterministic serial RNG-order gate for Stage1/Stage2 local
   update and swap draw boundaries.
4. Add mode provenance to Stage1/Stage2 manifests or sidecars.
5. Add opt-in per-replica/per-slot RNG ownership.
6. Add deterministic tests proving:
   - `legacy_serial_rng` matches current serial outputs;
   - `per_replica_rng` is deterministic under the same seed and mode;
   - the two modes are labeled as different stream contracts.

## Current Stop Condition

The original stop condition is resolved. Continue CV-011 on the remaining
non-RNG workspace/reentrancy migration and deterministic serial/reentrant
checks. Do not claim output-preserving refactor for the B implementation:
finite same-seed trajectories can differ by design.
