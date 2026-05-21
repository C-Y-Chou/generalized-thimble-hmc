# F20F 1D Manuscript Claim Boundary

Date: 2026-05-21 JST

Status: manuscript-facing claim boundary for the completed 1D model evidence.
This file is an interpretation layer over the existing F20F evidence packet; it
does not define new simulations or scheduler work.

## Evidence Source

Use these files as the numeric/provenance source:

```text
codex/workspaces/tltm_production_comparison/runbooks/F20F_PRODUCTION_FACING_EVIDENCE_PACKET_20260521.md
codex/workspaces/tltm_production_comparison/state/F20F_FINAL_VALIDATION_20260521.tsv
```

The canonical raw data remain in:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

## Claims Supported By The 1D Evidence

The 1D F20F evidence supports the following claims:

1. Fixed-flow sampling can fail as a physics sampler at large flow time in this
   model.  At fixed flow time `t=0.5`, `no_fb` is sign-locked in high-flow
   `Re z`, and the production-facing virial / `z dS/dz - 1` observable has
   `Ohat_re = -0.2412559808` with `Z = -211.902`.
2. The sign-lock pathology is not merely an odd-sector cancellation issue.
   Positive-only and negative-only fixed-flow sectors both give
   `Ohat_re ~= -0.241`.
3. Two-replica TLTM with the low005 ladder repairs the fixed-flow `t=0.5`
   pathology.  In the final `128 seeds x 200000 cycles` TLTM readback, both
   `no_fb` and `fb_norefine` have `Ohat` and `z` compatible with their exact
   targets at the current scale.
4. The fallback route substantially improves solver-health counters in TLTM
   `t=0.5`: unresolved failures drop from `4094188` to `189662`.
5. In this 1D toy model, fallback has not shown a robust observable necessity
   signal once TLTM is active.  The final paired TLTM difference is
   `dOhat_re Z = -0.772`, `dOhat_im Z = 1.933`, `dz_re Z = -1.537`, and
   `dz_im Z = -0.261`.

## Claims Not Supported By The 1D Evidence

Do not claim from this dataset alone:

1. Solver failures imply sampling bias.
2. Fallback is required for unbiased TLTM observables in the 1D toy model.
3. `no_fb` and `fb_norefine` produce demonstrably different TLTM sampling
   distributions in this model.
4. The 1D toy model by itself is sufficient evidence for the strongest BTN
   fallback motivation.

## Recommended Manuscript Framing

Use the 1D result as a controlled failure-and-repair example:

> In the one-dimensional test model, fixed flow at sufficiently large flow time
> can create a genuine undercoverage pathology.  A two-replica TLTM ladder
> repairs that fixed-flow pathology.  The BTN fallback mechanism dramatically
> improves solver robustness, but in this 1D example the repaired TLTM
> observable is not measurably changed by fallback at the current scale.

This supports a narrower and more defensible message:

- TLTM / flow-time tempering is essential in the demonstrated 1D large-flow
  scenario.
- Fallback is an algorithmic robustness layer whose observable necessity is not
  established by this 1D model.
- A stronger fallback claim needs a model where larger flow time, higher
  dimension, or more complex connectivity makes solver failure visibly distort
  the TLTM ensemble.

## Paper-Level Consequence

The prior BTN-style narrative should be softened if it implied that the 1D
model proves fallback is necessary for unbiased observables.  The current
evidence instead says:

- fixed flow can be wrong;
- TLTM can fix the fixed-flow failure;
- fallback improves solver health;
- the need for fallback as a physics-bias correction remains a target for the
  next model, not a conclusion from this completed 1D dataset.

## Closed Direction

Do not spend more production-scale cycles on this same 1D F20F setup unless a
new question is explicitly opened.  The next scientific step for a strong BTN
fallback claim is a new scenario, not another rerun of the completed 1D roots.
