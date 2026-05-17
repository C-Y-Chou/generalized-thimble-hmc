# F20 Loose-Double 50k Sensitivity Gate

Date: 2026-05-17 JST

Status: prepared for PBS submission. This is not a new certified production
baseline.

## Question

Can a single-feasible tolerance profile preserve the physical output against
the accepted 32seed/50k strict-double reference?

The accepted reference target is:

```text
reference: m6_r3_32seed_50k
config: docs/modernization_reference_t035_r3_32seed_50k.json
methods: no_fb, fb_norefine
seeds: 32 matched seeds
cycles: 50000 per seed
strict profile: abs_tol=rel_tol=3e-14, constraint/QN=1e-13
```

## First Candidate Profile

Profile id:

```text
single_feasible1e6_rg1e4
```

Runtime controls:

```text
TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-6
TLTM_STAGE2_REL_TOL_OVERRIDE=1e-6
TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-6
QN_QUASI_TOL_OVERRIDE=1e-6
QN_REVERSE_GATE_TOL=1e-4
QN_OFFICIAL_DFOLS_RHOEND=1e-6
QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-12
QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0
```

This is intentionally a single-feasible tolerance screen executed in double
precision.  It does not yet alter `dp = real64`, LAPACK precision, DFO-LS
callback precision, RNG precision, or binary output precision.  Its purpose is
to answer the first question before a real single/mixed precision build exists:
if every certification tolerance is relaxed to a plausible FP32 target, do the
physics observables and kernel diagnostics stay compatible with strict double?

The earlier `loose1e10_rg1e6` idea is not the right first profile for this
question: `1e-10` is still below a practical single-precision residual target.

## Source Support

- `scripts/run_stage3_3_multiseed.py` accepts isolated Stage2 ODE tolerance
  overrides via `TLTM_STAGE2_ABS_TOL_OVERRIDE` and
  `TLTM_STAGE2_REL_TOL_OVERRIDE`.
- `m6_reference_chunk.pbs` now preserves strict defaults but accepts explicit
  loose tolerance env controls.
- `m6_reference_merge_level.pbs` records the tolerance profile and can run a
  paired comparison against the strict reference.
- `compare_tolerance_profile_to_reference.py` emits aggregate deltas and
  same-seed observable drift.

## Submission

From a clean synchronized modernization worktree on the PBS login host:

```bash
TLTM_WORKTREE=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization \
TLTM_EXPECTED_GIT_BRANCH=codex/fortran-modernization \
TLTM_EXPECTED_GIT_COMMIT=<commit> \
bash codex/workspaces/fortran_modernization/tasks/scripts/submit_f20_loose_double_50k.sh
```

The launcher submits one preflight/build job, eight chunk jobs
(`2 methods x 4 chunks x 8 seeds`), and one merge/readback job.

Expected candidate root:

```text
output/tests/f20_loose_double/f20_single_feasible1e6_rg1e4_r3_32seed_50k_<commit>
```

Expected readback:

```text
<candidate-root>/reference_comparison/REPORT.md
<candidate-root>/reference_comparison/paired_observable_drift.tsv
<candidate-root>/reference_comparison/aggregate_delta.tsv
```

## Pass/Fail Interpretation

Pass requires method-by-method compatibility with the strict reference:

- paired same-seed `Ohat_re` and `Ohat_im` drift statistically consistent with
  zero;
- aggregate observable shifts inside the strict-reference uncertainty scale;
- no large systematic change in unresolved failures;
- no large systematic change in reverse-gate rejects or pair0 acceptance;
- no protocol-audit or sidecar metadata failure.

If this profile fails, split the profile into layers:

1. ODE-only loose tolerance;
2. ODE plus constraint/QN loose tolerance;
3. reverse-gate loose tolerance;
4. DFO-LS package stopping tolerance.

Strict double remains the reference oracle regardless of this gate result.
