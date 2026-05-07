# State Vector and Legacy Initial-State Convention

This document is the canonical specification for state vector `x(:)` semantics.
`initial_x.dat` behavior is legacy compatibility only.

## 1. Canonical `x(:)` Semantics

Use the following contract throughout the codebase:

- `x(1)`: flow time (`t_flow`)
- `x(2:)`: real seed/state entries
- `size(x) = 1 + seed_size`

Do not rely on ad hoc indexing logic in algorithm code; use helper APIs from `src/core/utils.f90`.

## 2. Legacy `initial_x.dat` File Format

`initial_x.dat` is not part of the default runtime path.
When it is used for compatibility, these formats are accepted.

### Headerless value format

No size header. One value per line:

1. `x(1)` (flow time)
2. `x(2)`
3. `x(3)`
4. ...

Example:

```text
0.40000000000000002E+00
-0.91646707023808116E+00
```

### Legacy format (read-compatible)

Legacy files with a size header are still accepted on read:

1. integer `n_total = size(x)`
2. values for `x(1:n_total)` on subsequent lines

The writer now emits the preferred headerless format.

## 3. API Contract (`src/core/utils.f90`)

Use these routines instead of direct indexing/parsing:

- `x_get_flow_time(x)`
- `x_set_flow_time(x, t)`
- `x_get_seed_real(x, x_seed)`
- `x_set_seed_real(x, x_seed)`
- `x_get_seed_complex(x, z_seed)`
- `x_set_seed_from_complex(x, z_seed)`
- `read_initial_state(file, flow_time, x_seed)`
- `save_initial_state(file, flow_time, x_seed)`

## 4. Interaction with `parameters.dat`

`param_mod` requires explicit runtime state size in config:

- `x_size` must be set to a positive value (`>= 2`).
- `z_size` is derived internally as `x_size - 1`.

Relevant structured fields:

- `config%state%x_size`
- `config%state%z_size`
- `config%integrator%initial_flow_time`
- `config%integrator%method` (`rattle`)
- `config%analysis%bootstrap_samples` (`0` means auto for expectation bootstrap)

## 5. Migration Guidance

- Default workflow should use randomized starts from sampler codepaths (no `initial_x.dat` dependency).
- Existing datasets in legacy format remain valid for compatibility.
- New runtime paths should avoid introducing new `initial_x.dat` dependencies.
- Planned direction: remove `initial_x.dat` compatibility after remaining legacy users are migrated.
