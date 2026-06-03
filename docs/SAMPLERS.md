# Samplers

## TLTM

TLTM is the canonical tempered-ladder generalized-thimble workflow in this
repository. It is the mature sampler path for current production-style TLTM
experiments.

Public entry point:

```bash
python3 scripts/run_tltm_product.py tltm --config path/to/stage3_protocol.json
```

TLTM outputs per-seed summaries, protocol sidecars, observable estimates, and
label histories through the Stage3 driver.

## WV-HMC

WV-HMC is implemented as a sibling sampler, not as a hidden TLTM mode. The
current public path is dense explicit-J WV-HMC.

Public entry point:

```bash
python3 scripts/run_tltm_product.py wv-hmc --cycles 1000 --history
```

Current claim level:

- dense explicit-J kernel and constraints are covered by public tests;
- Stephanov `n=6` validation is compatible with exact references after burn-in;
- burn-in and measurement-window handling must be recorded in production runs;
- matrix-free trajectories and high-dimensional performance optimization are
  roadmap work.

## Choosing Parameters

Use this order:

1. Fix the physics target and flow-time interval.
2. Choose the flow-time potential so the sampled flow-time histogram covers the
   intended interval.
3. Tune HMC step size for a reasonable acceptance scale.
4. Tune trajectory length through the number of integration steps.
5. Inspect movement, burn-in, observable histories, and seed stability.
6. Freeze parameters before production-shaped runs.
