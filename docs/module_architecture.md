# Module Architecture

This document defines the architectural contract for module dependencies and responsibilities.

## 1. Dependency Contract

Allowed dependency direction is strictly one-way:

`apps -> sampler -> physics -> config -> core`

Rules:

- A lower layer must not `use` a higher layer.
- Cross-layer shortcuts are not allowed.
- Shared logic should be moved downward to the lowest valid layer.

## 2. Layer Responsibilities

### `core`

Representative modules:

- `mtdefs`, `mt95`, `utils`

Responsibilities:

- primitive types/constants
- random number foundations
- common vector/matrix helpers
- state-vector access and file helpers

### `config`

Representative modules:

- `param_mod`

Responsibilities:

- parameter parsing (`key=value` + legacy format support)
- runtime validation
- synchronization of structured config with legacy globals

### `physics`

Representative modules:

- `model`, `model_observables`, `solve_flow`

Responsibilities:

- action, derivatives, Hessian
- model-owned observable definitions and observable lookup
- flow ODE right-hand side and integration
- adaptive ODEX integration with tolerance control (`at`, `rt`)

### `sampler`

Representative modules:

- `hmc_kernels`, `hmc_constraints`, `hmc_state_buffers`, `hmc_reversibility_checks`
- `hmc_integrator_core`, `hmc`
- `quasi_newton_linear_solver`, `quasi_newton_solver`
- `markovchain_phase`, `markovchain_io`, `markovchain_metropolis`, `markovchain_mod`, `markovchain`

Responsibilities:

- constrained dynamics kernels and projections
- RATTLE step implementation and trajectory propagation
- nonlinear constraint solving (Newton / quasi-Newton)
- Markov transition, persistence, and phase handling

### `apps`

Representative modules/programs:

- `generate_markov_chain`, `evaluate_expectations`

Responsibilities:

- executable-level orchestration
- no duplication of core algorithm logic

## 3. Change Management Rules

- Add reusable numerical primitives to `core` before using them elsewhere.
- Add runtime controls in `config` first, then propagate through existing sync paths.
- If a module starts mixing physics and sampling concerns, split responsibilities into separate modules.
- Keep compatibility wrappers explicit and documented; avoid introducing new wrappers unless necessary.

## 4. Review Checklist for New Modules

- Does the new module sit in the lowest appropriate layer?
- Are all `use` dependencies layer-compliant?
- Is runtime configuration routed through `param_mod` rather than local parsing?
- Are tests or diagnostics added for any new numerical behavior?
