# Stage2 Snapshot Restart Contract

Date: 2026-05-23
Scope: local Stage2 TLTM final snapshots and initialization from snapshots.

## Purpose

The current long TLTM production output streams observables but does not contain
enough state for exact continuation. Stage2 now has a local final-snapshot path
that stores all replica state needed to continue from a completed segment.

This is intentionally separate from dense-output flow caches. Dense output will
reduce preflow/reflow cost later; this snapshot path makes production segments
restartable.

## Driver Controls

- `TLTM_STAGE2_SNAPSHOT_FILE=/path/final_snapshot.bin`
  writes a final binary snapshot at the end of a Stage2 segment.
- `TLTM_STAGE2_INIT_SNAPSHOT_FILE=/path/final_snapshot.bin`
  initializes all Stage2 slots from a previous snapshot.
- `TLTM_STAGE2_INIT_MODE=snapshot`
  is accepted and requires `TLTM_STAGE2_INIT_SNAPSHOT_FILE`.
- `TLTM_STAGE2_CYCLE_OFFSET=N`
  manually offsets absolute cycle numbering when no snapshot is used.
- `TLTM_STAGE2_RESTART_BOUNDARY_POLICY=skip|write`
  controls whether a snapshot restart writes the restored boundary cycle before
  advancing. The default is `skip` for snapshot initialization and `write` for
  fresh initialization.

Snapshot initialization overrides `TLTM_STAGE2_INITIAL_X_FILE`.

## Exact-Restart Boundary

Exact continuation is currently supported only for
`TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2`.

The snapshot stores:

- final absolute cycle index
- physical state size, slot/pair/label counts
- base seed and swap seed
- per-slot `x`, `z`, `jac`
- per-slot label id, flow time, counters, `phi_sum`, and state version
- pair swap counters and last accept probability
- label round-trip bookkeeping

Phase/action/logdet and swap-reflow caches are not serialized; they are
invalidated on load and recomputed as needed.

## Wrapper Controls

`tasks/scripts/run_stephanov_n6_tltm_ladder.py` now supports:

- `--write-final-snapshot`
- `--init-snapshot-root ROOT`
  expecting `ROOT/records/record_XXXX/final_snapshot.bin`
- `--init-snapshot-file FILE`
  for a single-record continuation
- `--restart-boundary-policy skip|write`
  defaults to `skip` for snapshot continuation

The wrapper records `init_snapshot_file` and `final_snapshot_file` in
`tltm_ladder_summary.csv`, along with `restart_boundary_policy` for continuation
runs.

## Validation

Local smoke:

- continuous path: 4 cycles with final snapshot
- split path: 2 cycles with final snapshot, then restart for 2 more cycles
- parameters: `data/parameters_stephanov_n2_smoke.dat`
- ladder: `0,0`
- RNG contract: `stage2_kernel_rng_v2`

Result:

- final continuous and split-restart snapshots matched exactly after ignoring
  wall-clock-only fields by not comparing them in the parser
- snapshot headers both ended at cycle 4 with restored base seed 777
- with `TLTM_STAGE2_RESTART_BOUNDARY_POLICY=skip`, restarted label trace began
  at absolute cycle 3 after loading a cycle-2 snapshot
- observable stream sample counts were continuous=5, first segment=3,
  continuation=2, so the boundary sample was not duplicated

Evidence root:

`output/tests/stage2_snapshot_boundary_smoke`

Wrapper smoke:

`output/tests/stage2_snapshot_boundary_script/restart_wrapper`

Additional flow-bank/snapshot smoke:

- dense cache root:
  `output/tests/flow_bank_dense_stage2_smoke/cache`
- Stage2 initialized from `TLTM_STAGE2_INIT_MODE=flow_bank` and wrote a final
  snapshot:
  `output/tests/flow_bank_dense_stage2_smoke/stage2/final_snapshot.bin`
- snapshot continuation from that flow-bank-initialized run began at absolute
  cycle 3 after loading a cycle-2 snapshot:
  `output/tests/flow_bank_dense_stage2_smoke/restart`

The wrapper now also supports `--write-cold-x-history`, which is the required
flag when a shorter follow-up segment is used to create a high-flow physical
`x` bank for dense-cache construction.

## Boundary Contract

Snapshot continuation uses `skip` boundary policy by default. The output stream
for a continuation segment therefore begins at `snapshot_cycle + 1`, not at the
restored boundary state. This avoids double-counting when concatenating segments.

If `TLTM_STAGE2_RESTART_BOUNDARY_POLICY=write` or wrapper
`--restart-boundary-policy write` is used, the restored boundary row is emitted
explicitly and downstream concatenation must drop the duplicate cycle.

Run-level transient diagnostics such as solver counters and accepted-route
census are segment-local after restart. Slot, pair, and label counters are
preserved in the snapshot.
