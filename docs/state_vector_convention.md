# State Vector Convention

This document is the canonical specification for TLTM state-vector semantics.
The old `initial_x.dat` runtime input path has been removed.

## 1. Canonical State Semantics

Use the following contract in new sampler, product, and high-dimensional code:

- `flow_time`: fixed flow-label metadata owned by a slot or replica.
- `x(:)`: real physical seed/state coordinates only.
- `size(x) = physical_state_size = z_size`.

`flow_time` is not a mutable component of `x(:)`. Local HMC/RATTLE updates
evolve the physical coordinates at a fixed label. Replica exchange evaluates
one physical state under another slot label without storing that label inside
the state vector.

## 2. Flow API Contract

New call sites should pass the label explicitly:

- `flow_at(flow_time, x, z, jac, ...)`
- `flowz_at(flow_time, x, z, ...)`
- `flowzr_at(flow_time, z, ...)`
- `metropolis_step_at(flow_time, x, z, jac, ...)`

The legacy packed API is retained only as a compatibility boundary:

- legacy packed `x_legacy(1)`: flow time.
- legacy packed `x_legacy(2:)`: physical state entries.
- `pack_legacy_x(flow_time, x, x_legacy)`
- `unpack_legacy_x(x_legacy, flow_time, x)`

Do not add new algorithm code that reads or writes `x(1)` as a flow-time
field.

## 3. Interaction with `parameters.dat`

Preferred structured fields:

- `physical_state_size`: number of real physical coordinates.
- `config%state%physical_size`
- `config%state%z_size`
- `config%integrator%initial_flow_time`
- `config%integrator%method` (`rattle`)
- `config%analysis%bootstrap_samples` (`0` means auto for expectation bootstrap)

For compatibility, `x_size` and `n_size` remain accepted as legacy packed sizes:

- `x_size = physical_state_size + 1`
- if only `x_size` is supplied, `physical_state_size = x_size - 1`
- if both are supplied, they must satisfy `x_size = physical_state_size + 1`

Product and high-dimensional configs should prefer `physical_state_size` so the
flow label is not counted as a state coordinate.

## 4. Migration Guidance

- Default workflow uses randomized starts from sampler codepaths.
- Existing historical `initial_x.dat` files are not runtime inputs anymore.
- Existing raw outputs that contain legacy packed state vectors should be read
  as compatibility artifacts, not as the current state contract.
- New history/output schema should emit flow time as metadata or a separate
  label column, not as `x(1)`.
