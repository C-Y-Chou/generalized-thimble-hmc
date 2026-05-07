# Stage 3.4 Non-Near Rescue Ablation - 2026-04-24

Goal: test whether the stage-3.4 `t=0.35` Re-virial bias is driven by accepted
non-near S1 rescue moves.

Code switch added:

- `QN_S1_NONNEAR_RESCUE_ENABLED=0`
- This disables the non-near cheap full retry after a failed probe.
- Probe-only quasi success remains enabled.
- Near rescue remains enabled.

Changed code:

- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/tltm_stage2_driver.f90`
- `scripts/run_stage3_3_multiseed.py`

## 5 seeds x 1000 cycles

Outputs:

- `output/tests/local_kernel_ablation/stage3_4_5seed_1000_full`
- `output/tests/local_kernel_ablation/stage3_4_5seed_1000_nonnear_off`

Key result:

| policy | fb unresolved failures | fb accepted nonnear rescue | fb mean Re<O> | paired mean dRe |
|---|---:|---:|---:|---:|
| full | 11 | 21 | -0.268919 | -0.248997 |
| nonnear off | 75 | 0 | -0.203933 | -0.184011 |

Interpretation: toggle worked, but 1000-cycle estimates were too noisy.

## 5 seeds x 5000 cycles

Outputs:

- `output/tests/local_kernel_ablation/stage3_4_5seed_5000_full`
- `output/tests/local_kernel_ablation/stage3_4_5seed_5000_nonnear_off`

Key result:

| policy | fb unresolved failures | fb accepted nonnear rescue | fb accepted probe-only | fb mean Re<O> | paired mean dRe |
|---|---:|---:|---:|---:|---:|
| full | 52 | 108 | 974 | -0.136990 | -0.004909 |
| nonnear off | 354 | 0 | 974 | +0.015831 | +0.147912 |

Additional 5000-cycle comparison:

| policy | fb P68 Re | fb P95 Re | fb mean Zp Re | fb runtime mean |
|---|---:|---:|---:|---:|
| full | 0.6 | 1.0 | -0.788330 | 548.3 s |
| nonnear off | 1.0 | 1.0 | +0.090991 | 408.3 s |

## Current Read

This ablation strongly implicates accepted non-near S1 rescue moves as a
candidate source of the stage-3.4 Re-channel distortion.

It is not final proof because the sample is small (`5 seeds x 5000 cycles`), but
the direction is coherent:

- accepted non-near/full-stage rescue is removed (`108 -> 0`)
- `fb` still keeps most probe-only quasi successes (`974 -> 974`)
- unresolved failures increase but remain much lower than no-fallback
- Re observable moves from negative-biased to near zero / slightly positive
- runtime improves substantially

Next decision point: confirm with a larger but still bounded run, e.g.
`20 seeds x 5000 cycles` or `10 seeds x 10000 cycles`, comparing:

1. no fallback
2. full fallback
3. fallback with non-near rescue disabled
