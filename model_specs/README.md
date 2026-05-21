# Model Specification Staging Area

This directory is an inert staging area for future model definitions and plans.
Files here are not compiled or imported by the Fortran build.

Use this area to draft a model before promoting it into active source:

- action definition
- observable definitions
- lattice/state layout
- model parameters and couplings
- validation and smoke-test plan

Promotion target after review:

- `src/physics/model_action_body.inc`
- `src/physics/model_observable_registry.inc`
- `src/physics/model_observable_body.inc`
- `src/config/param_mod.f90` when new parameters or lattice-shape controls are needed

Current active draft:

- `high_dimensional/`
