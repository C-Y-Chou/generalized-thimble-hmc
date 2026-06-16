# Samplers

This repository follows the notation used in the Fukuma TLTM/WV-HMC literature:

- `Sigma_t`: the integration surface obtained by flowing the original real
  surface to flow time `t` with the antiholomorphic gradient flow;
- `TLTM`: parallel tempering in the flow-time direction;
- `GT-HMC`: HMC on a fixed deformed surface `Sigma_t`;
- `WV-HMC`: HMC on the worldvolume formed by the continuous family of
  deformed surfaces.

## TLTM

TLTM is the canonical tempered Lefschetz thimble workflow in this repository.
It treats the flow time as the tempering parameter and runs replica exchange
between deformed surfaces.  This is the mature sampler path for current
production-style TLTM experiments.

Public entry point:

```bash
python3 scripts/run_tltm_product.py tltm --config path/to/tltm_protocol.json
```

TLTM outputs per-seed summaries, aggregate summaries, observable estimates, and
replica-label histories through the product runner.

## GT-HMC

GT-HMC means HMC constrained to one fixed deformed surface `Sigma_t`.  In this
repository, the dense explicit-J GT-HMC kernels are part of the WV-HMC
implementation and validation surface.  Standalone fixed-surface production
packaging is not the current public workflow.

## WV-HMC

WV-HMC is implemented as a sibling sampler, not as a hidden TLTM mode. The
current public path is dense explicit-J WV-HMC, where the Markov chain evolves
on the worldvolume and the measurement factor is applied when accumulating
observables.

The default dense WV-HMC boundary policy is `normal_reflect`, which reflects
the flow-normal component of the momentum at local boundary events.  The
`full_bounce` / `paper_full_flip` policy is retained as an optional benchmark
policy.  Rejection-heavy boundary variants are diagnostic paths, not the
product default.

Public entry point:

```bash
python3 scripts/run_tltm_product.py wv-hmc --cycles 1000 --history
```

Current claim level:

- dense explicit-J kernel and constraints are covered by public tests;
- Stephanov `n=6` boundary-policy benchmarks favor `normal_reflect` after
  burn-in and middle-flow-time diagnostic cuts;
- burn-in and measurement-window handling must be recorded in production runs;
- matrix-free trajectories, iterative orthogonal decomposition, and
  high-dimensional performance optimization are
  roadmap work.

## Choosing Parameters

Use this order:

1. Fix the physics target and flow-time interval.
2. Choose the worldvolume potential `W(t)` so the sampled flow-time histogram
   covers the intended interval.
3. Tune HMC step size for a reasonable acceptance scale.
4. Tune trajectory length through the number of integration steps.
5. Inspect movement, burn-in, observable histories, and seed stability.
6. Freeze parameters before large validation or production runs.
