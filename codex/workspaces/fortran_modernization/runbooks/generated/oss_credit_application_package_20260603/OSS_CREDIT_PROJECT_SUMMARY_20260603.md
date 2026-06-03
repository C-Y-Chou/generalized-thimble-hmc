# Generalized Thimble HMC - OSS/Credit Project Summary

Date: 2026-06-03

Author: CHOU CHIEN YU

## Project

Generalized Thimble HMC is a Fortran toolkit for model-general generalized
thimble simulations.  The package separates sampler mechanics from the physics
provider: a model supplies a scalar action, manual analytic derivatives, flow
right-hand sides, and observable definitions; the samplers provide transition
kernels, flow-time handling, measurement accumulation, outputs, and restart
metadata.

## Implemented Package

- TLTM production-style workflow with product wrapper support.
- Dense explicit-J WV-HMC sibling sampler for validation and development.
- DOP853 flow backend selected by the public WV-HMC wrapper.
- Stephanov model provider with manual gradient and Hessian-vector validation
  on random complex states.
- WV-HMC math-kernel, constraint-kernel, and model-derivative validation
  targets exposed through `make test`.
- Product-facing documentation and wrapper:
  `README.md`, `docs/`, and `scripts/run_tltm_product.py`.
- Observable histories, final-state output, cyclic snapshots, and run manifests
  for reproducible runs.

## Validation Status

The current evidence package supports a bounded pre-public claim:

- TLTM is the mature generalized-thimble workflow in this package.
- Dense explicit-J WV-HMC passes kernel-level correctness gates and has a
  Stephanov `n=6` validation readback compatible with exact references after
  burn-in handling.
- Matrix-free trajectories and high-dimensional performance optimization are
  future work, not current public capability.

Main evidence path:

```text
codex/workspaces/fortran_modernization/runbooks/generated/product_evidence_packet_20260603/
```

## Why Compute Credits Are Needed

The next scientific step is to move from dense benchmark validation to larger
and higher-dimensional models.  That requires:

- multi-seed, multi-cycle production validation for model-general workflows;
- fair TLTM and WV-HMC comparisons under fixed decision gates;
- performance profiling across flow-time ranges, step sizes, and initial-state
  banks;
- matrix-free trajectory development and validation for large systems;
- reproducible scheduler-controlled benchmarks with histories and snapshots.

These runs are too large for routine local execution and need managed cluster
time to make wall-clock efficiency, burn-in behavior, and estimator stability
measurable.

## Current Limitations

- WV-HMC is dense explicit-J only in the public package.
- High-dimensional matrix-free/BiCGStab trajectories are planned but not yet
  product capability.
- Stephanov `n=6` WV-HMC validation requires explicit burn-in handling.
- Production-shaped runs should be launched through the target cluster
  scheduler with source and runtime metadata recorded.

## Roadmap

1. Publish the pre-public package with documented build, test, and smoke-run
   commands.
2. Add high-dimensional model providers under the same model contract.
3. Implement matrix-free/BiCGStab WV-HMC trajectories.
4. Run scaling and estimator-stability studies under scheduler-controlled
   benchmark protocols.
5. Refine performance and restart workflows based on benchmark evidence.
