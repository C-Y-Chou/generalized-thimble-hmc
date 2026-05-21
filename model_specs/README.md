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

- `src/physics/model_<name>.f90` as the active hand-written provider
- `src/physics/model.f90` only as the stable API facade to the active provider
- `src/physics/model_observables.f90` only as the stable observable facade
- `src/config/param_mod.f90` when new parameters or lattice-shape controls are needed

Current active draft:

- `high_dimensional/`
