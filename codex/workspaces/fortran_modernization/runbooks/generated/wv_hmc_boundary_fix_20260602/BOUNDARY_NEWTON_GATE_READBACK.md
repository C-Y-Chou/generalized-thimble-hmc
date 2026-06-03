# WV-HMC Boundary/Newton Gate Readback

Date: 2026-06-02

Purpose: record the WV-HMC kernel bug found by the exact positive-target
invariant gate, the source rule that fixes it, and the remaining validation
boundary.  This is a code-correctness readback, not a production physics
conclusion.

## Bottom Line

A concrete WV-HMC transition-kernel bug was found and fixed.

The bug was not merely the choice between normal reflection and the simplified
paper's full momentum flip.  The deeper issue was that
`wv_rattle_step_dense_with_boundary` passed the measurement/wall interval
`[T0-d0,T1+d1]` into the no-boundary Newton/RATTLE solve as an iterative
fail-fast bound.  Intermediate Newton iterates that crossed the measurement
wall were therefore classified as `boundary_exit` before the no-boundary RATTLE
trial had actually been constructed.  Under high boundary stress this produced
an over-accepting Markov kernel that passed local algebra/reverse-like checks
but failed the exact positive-target invariant measure.

The fixed rule is:

- the Newton/RATTLE no-boundary solve may guard only the physical flow domain,
  currently `t >= 0`;
- the measurement/wall interval `[T0-d0,T1+d1]` must be applied only after a
  converged no-boundary trial exists;
- outside-measurement/wall trials are then handled by
  `wv_apply_simplified_boundary_rule`;
- numerical construction failures that cannot be classified as physical-domain
  boundary exits remain rejected-proposal diagnostics.

The current source implements this by passing `target_flow_time_min=0` to
`wv_rattle_step_dense_no_boundary` and no longer passing the wall upper bound
as `target_flow_time_max`.

## Source Touchpoints

- Local source: `src/sampler/wv_hmc_constraints.f90`
- Wrapper: `wv_rattle_step_dense_with_boundary`
- No-boundary solver: `wv_rattle_step_dense_no_boundary`
- Boundary policy kernel: `wv_apply_simplified_boundary_rule`
- Build gate: `codex/workspaces/fortran_modernization/tasks/pbs/wv_hmc_gitless_build_gate_20260602.pbs`

## Source Pins

| role | source pin / snapshot |
| --- | --- |
| Pre-fix current source used by failed invariant runs | `4597ced50bd8` dirty source snapshot |
| Post-fix invariant source pin | `4597ced50bd8-e99b1c4b19b1` |
| Post-fix runtime snapshot | `/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_boundary_fix_20260602_4597ced50bd8-e99b1c4b19b1` |
| Later local source pin after build-gate hard-fail patch and fixture restore | `4597ced50bd8-6cb350f39556` |

The post-fix invariant evidence below uses `4597ced50bd8-e99b1c4b19b1`.

## Exact Positive-Target Invariant Evidence

These gates compare WV-HMC Markov samples to the deterministic positive
worldvolume target.  They are stronger than checking only final reweighted
physical observables, because they test the ensemble-generation kernel itself.

| run | source | setup | status | key z-scores |
| --- | --- | --- | --- | --- |
| old zero/high-L/c10 | pre-fix | `n=2`, `[0,0.01]`, `gamma=0`, `2048` seeds, `10` cycles | fail | positive chiral Re `4.51`, positive density Re `-3.57`, ratio chiral Re `-6.38`, ratio density Re `3.45` |
| old zero/high-L/c50 | pre-fix | `n=2`, `[0,0.01]`, `gamma=0`, `2048` seeds, `50` cycles | fail | positive chiral Re `12.8`, positive density Re `-13.4`, ratio chiral Re `-10.9`, ratio density Re `4.70` |
| old zero/small-L/c50 | pre-fix | lower boundary stress | mixed | positive target passed; ratio chiral Re `-4.59`, ratio density Re `3.19` |
| old zero/high-L/c50 normal-reflect | pre-fix normal-reflect variant | same high boundary stress | fail | positive chiral Re `10.5`, positive density Re `-8.61` |
| old linear20/high-L/c50 | pre-fix | `gamma=20`, `4096` seeds, `50` cycles | fail | positive chiral Re `19.6`, positive density Re `-19.3`, ratio chiral Re `-15.9`, ratio density Re `7.45` |
| fixed zero/high-L/c10 | `4597ced50bd8-e99b1c4b19b1` | same exact target as old high-L/c10 | pass | positive chiral Re `-0.0912`, positive density Re `0.065`, ratio chiral Re `-2.35`, ratio density Re `1.92` |
| fixed zero/high-L/c50 | `4597ced50bd8-e99b1c4b19b1` | same exact target as old high-L/c50 | pass | positive chiral Re `-0.0912`, positive density Re `0.065`, ratio chiral Re `-2.35`, ratio density Re `1.92` |

Post-fix readbacks:

- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_one_step_invariant_20260602/wv_hmc_boundaryfix_invariant_n2_t001_zero_d00_2048_c10_highL_4597ced50bd8_e99b1c4b19b1_20260602/readback/positive_target_invariant_readback.md`
- `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_one_step_invariant_20260602/wv_hmc_boundaryfix_invariant_n2_t001_zero_d00_2048_c50_highL_r2_4597ced50bd8_e99b1c4b19b1_20260602/readback/positive_target_invariant_readback.md`

## Transition Diagnostics

| run | accepted | rejected | acceptance | transitions failed | reverse-gate rejected | bounced steps / trajectory steps | mean accept probability |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| old zero/high-L/c10 | 20434 | 46 | 0.997754 | 43 | 2 | 0.225723 | 0.997785 |
| old zero/high-L/c50 | 102298 | 102 | 0.999004 | 96 | 5 | 0.222659 | 0.999000 |
| fixed zero/high-L/c10 | 14336 | 6144 | 0.700000 | 1 | 6143 | 0.898137 | 0.700000 |
| fixed zero/high-L/c50 | 72106 | 30294 | 0.704160 | 5 | 30289 | 0.899487 | 0.704160 |

Interpretation for future debugging:

- the old kernel was suspiciously over-accepting under high boundary stress;
- high acceptance is not evidence of correctness in WV-HMC;
- the fixed kernel turns the same boundary-heavy pressure into ordinary
  rejection/reverse-gate behavior and passes the positive-target invariant gate.

## Build/Test Gate Hygiene

The gitless build gate now hard-fails if `test_wv_hmc_constraint_kernels` exits
nonzero.  This prevents a build from being considered valid after a partially
failed constraint suite.

The current constraint-kernel fixture suite still needs rebaselining as a
separate hygiene item.  Some brittle fixtures encode old interior/no-boundary
expectations and can fail after the correct wall handling is applied.  That
fixture cleanup is not the same as the exact positive-target invariant gate:

- invariant target gate: current post-fix production-kernel evidence passes for
  the tested `n=2` high-L stress cases;
- unit fixture suite: must be rebaselined and then made a hard prerequisite for
  future source pins.

Do not run multiple build jobs in the same runtime snapshot concurrently.  A
previous concurrent build attempt corrupted intermediate object files with
`.o file truncated`; build/test gates should use one snapshot per active build
or serialize build jobs.

## Current Trust Boundary

Confirmed by this readback:

- the ensemble-generation kernel had a real boundary/Newton construction bug;
- the source rule for the bug is identified and fixed;
- exact positive-target invariant gates pass after the fix for the tested
  `n=2`, `[0,0.01]`, `gamma=0`, high-boundary-stress cases;
- the previous "almost always accept" behavior was not trustworthy.

Not yet claimed:

- WV-HMC code is completely problem-free;
- all constraint-kernel fixtures are rebaselined;
- `n=6` WV-HMC production observables are correct;
- matrix-free/BiCGStab trajectory wiring is ready for production.

Next blocking verification after fixture hygiene is to rerun current-source
positive-target gates and then repeat the `n=6` validation workflow from the
recorded WV-HMC SOP.  Do not proceed to matrix-free trajectory production before
the dense explicit-J current-source gates are closed.
