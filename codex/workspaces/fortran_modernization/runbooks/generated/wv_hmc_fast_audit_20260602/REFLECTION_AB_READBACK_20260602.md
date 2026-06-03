# WV-HMC Reflection A/B Readback 2026-06-02

Purpose: compare the old normal/component-reflection WV-HMC data against the
new simplified-paper full-flip boundary implementation.

## Match Status

This is **not** a same-seed matched A/B.

The old normal-reflection validation used seeds starting at `9620001` or
`9630001`.  The new full-flip fast-audit runs use seeds `9720001-9720032`.
Therefore the existing files support a historical before/after comparison, not
a paired seed-level matched comparison.

The closest old normal-reflection source is:

```text
runbooks/generated/wv_hmc_t0_retune_20260601
remote output:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_retune_20260601/wv_hmc_n6_t0_retuned_g65e009n10_validation_32x1500_20260601
source pin:
8ec6dc0d9b87-86f750bba994
seeds:
9620001-9620032
```

The new full-flip high-flow diagnostic is:

```text
runbooks/generated/wv_hmc_fast_audit_20260602/n6_highflow_paperflip_32x3000
remote output:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602
source pin:
8ec6dc0d9b87-022697b6d53d
seeds:
9720001-9720032
```

Both use Stephanov `n=6`, `mu=0.6`, `tau=0`, `[T0,T1]=[0,0.03]`,
`gamma=65`, `epsilon=0.009`, `nstep=10`, `constraint_tol=1e-10`, and
`constraint_max_iter=192`.

## High-Flow Historical Comparison

Rows compare high-flow measurements near `t >= 0.028`.

| boundary policy | run | seeds | cycles | samples | C | chiral Re z | chiral Im z | density Re z | density Im z |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| normal/component reflection | old retune, all cycles, `t>=0.028` | 32 | 1500 | 3533 | 0.13745 | -1.707 | -0.221 | 0.248 | -0.439 |
| normal/component reflection | old retune, cycles 1001-1500, `t>=0.028` | 32 | 1500 | 1208 | 0.11546 | -0.838 | 0.616 | 0.703 | -0.344 |
| normal/component reflection | old 64x15000 long, `t>=0.028` | 63 | 15000 | 61745 | 0.11304 | -1.980 | 1.227 | 0.022 | -0.627 |
| full flip | new fast audit, `[0.028,0.03]` | 32 | 3000 | 5628 | 0.10431 | -0.784 | -1.046 | 0.599 | -0.0955 |

## Interim Reading

The high-flow comparison does **not** show a decisive observable-level
advantage of the full-flip implementation over old normal reflection.  Both
policies can produce high-flow cuts with all four primary z components near the
`O(1)` range.

The deterministic kernel audit still proves a paper-policy mismatch:

```text
old normal-reflection implementation:
wv_boundary_paper_full_flip ok=F
full_flip_error=3.2097E-01
normal_reflect_error=0.0000E+00

new full-flip implementation:
wv_boundary_paper_full_flip ok=T
full_flip_error=0.0000E+00
normal_reflect_error=3.2097E-01
```

So the boundary-policy fix is mathematically/algorithmically justified for the
simplified-WV implementation, but the existing old high-flow observable files
do not prove that this was the sole cause of the earlier observable drift.

## What Existing Files Can And Cannot Answer

Can answer now:

- Old normal-reflection and new full-flip both have reasonable high-flow
  observable cuts at current statistics.
- The old normal-reflection full or broad measurement windows were more biased
  than their high-flow cuts.
- The new full-flip high-flow cut is compatible with exact references at this
  precision.

Cannot answer from existing files:

- Same-seed paired method difference.
- Whether full flip fixes the full `[0,0.03]` estimator relative to
  normal/component reflection under identical seeds.
- Whether reflection alone explains the earlier full-window drift.

The matched full-window full-flip run is still in progress.  Once complete, the
proper next table is:

```text
old normal-reflection 32x1500 full-window / flow cuts
vs
new full-flip 32x3000 full-window / flow cuts
```

This will still be unpaired unless an old normal-reflection run with the same
`9720001-9720032` seeds is run or discovered.

