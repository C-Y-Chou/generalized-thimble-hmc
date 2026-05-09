# State Vector Convention

This document is the canonical specification for state vector `x(:)` semantics.
The old `initial_x.dat` runtime input path has been removed.

## 1. Canonical `x(:)` Semantics

Use the following contract throughout the codebase:

- `x(1)`: flow time (`t_flow`)
- `x(2:)`: real seed/state entries
- `size(x) = 1 + seed_size`

Do not rely on ad hoc indexing logic in algorithm code; use helper APIs from `src/core/utils.f90`.

## 2. API Contract (`src/core/utils.f90`)

Use these routines instead of direct indexing/parsing:

- `x_get_flow_time(x)`
- `x_set_flow_time(x, t)`
- `x_get_seed_real(x, x_seed)`
- `x_set_seed_real(x, x_seed)`
- `x_get_seed_complex(x, z_seed)`
- `x_set_seed_from_complex(x, z_seed)`

## 3. Interaction with `parameters.dat`

`param_mod` requires explicit runtime state size in config:

- `x_size` must be set to a positive value (`>= 2`).
- `z_size` is derived internally as `x_size - 1`.

Relevant structured fields:

- `config%state%x_size`
- `config%state%z_size`
- `config%integrator%initial_flow_time`
- `config%integrator%method` (`rattle`)
- `config%analysis%bootstrap_samples` (`0` means auto for expectation bootstrap)

## 4. Migration Guidance

- Default workflow uses randomized starts from sampler codepaths.
- Existing historical `initial_x.dat` files are not runtime inputs anymore; migrate any needed values into explicit sampler/driver initialization logic before use.
- New runtime paths must not reintroduce `initial_x.dat` dependencies.
