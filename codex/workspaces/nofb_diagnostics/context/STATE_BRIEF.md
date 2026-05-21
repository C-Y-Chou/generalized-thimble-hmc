# nofb_diagnostics State Brief

Date: 2026-05-21 JST

## Purpose

This workspace used to own the F20F no-fallback diagnostics line.  That 1D
line is now closed and downgraded to archive.  Keep this workspace as a compact
registry and provenance pointer only.

## Current Canonical Evidence

The F20F 1D toy evidence is now grouped by physical scenario:

| bucket | canonical role |
| --- | --- |
| `TLTM_t030` | F20F double-preset validation at TLTM `t=0.3`; F20F remains the unique active double preset |
| `fixed_flow_t030` | paired `512 seeds x 200000 cycles` negative control; failures/rejections are large in `no_fb`, but support and observables remain compatible with `fb_norefine` |
| `fixed_flow_t050` | nofb `128 seeds x 200000 cycles` threshold pathology; every seed is locked in one high-flow `Re z` sign sector and `Ohat_re ~= -0.241256` |
| `TLTM_t050` | low005 paired `128 seeds x 200000 cycles` repair dataset; TLTM repairs the fixed-flow pathology, while fallback only has a solver-health advantage in this 1D evidence |

## Boundary

- This workspace does not own source modernization or PBS launcher
  productization.  Those remain in `fortran_modernization`.
- This workspace does not own final production-facing publication output.  That
  remains in `tltm_production_comparison`.
- Raw `z_history.dat` and `phi_history.dat` payloads stay in remote output
  roots.  This workspace stores only registries, readbacks, compact diagnostics,
  and stable paths to raw evidence.

## Closure

The nofb-only two-replica TLTM short scan selected `low005 = [0.05, 0.5]`.
The final paired TLTM `t=0.5` evidence combines the base32 and topup96 raw
components into `128 seeds x 200000 cycles`.

The current interpretation is frozen for cleanup planning:

- TLTM repairs the fixed-flow `t=0.5` undercoverage pathology.
- `fb_norefine` strongly reduces failures, but this one-dimensional toy model
  does not demonstrate that fallback is required for unbiased TLTM observables.
- The base32 Im candidate did not survive independent topup96 validation:
  combined128 paired `no_fb - fb_norefine` is `Re Z = -0.772`,
  `Im Z = 1.933`.

Current production-facing closure lives in:

```text
codex/workspaces/tltm_production_comparison/runbooks/F20F_PRODUCTION_FACING_EVIDENCE_PACKET_20260521.md
codex/workspaces/tltm_production_comparison/runbooks/F20F_1D_MANUSCRIPT_CLAIM_BOUNDARY_20260521.md
codex/workspaces/tltm_production_comparison/state/F20F_FINAL_VALIDATION_20260521.tsv
```

The local archived work log lives in:

```text
codex/workspaces/nofb_diagnostics/archive/f20f_1d_closed_20260521/
```

The first cleanup pass was explicitly approved and executed on 2026-05-21 JST.
It removed F20F compact-only/failed roots and stale execution worktrees, moved
the old dirty archive packet under
`/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521`, and
kept all canonical raw evidence roots.  The dirty legacy-linked worktree
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_saved_20260517T035700Z`
was intentionally held out for a separate source-diff decision.

That source-diff review is now complete:

```text
codex/workspaces/nofb_diagnostics/archive/f20f_1d_closed_20260521/runbooks/F20F_DIRTY_SAVED_SOURCE_DIFF_REVIEW_20260521.md
```

Conclusion: do not port anything from the dirty saved tree.  It is an older
F18b/Hairer-controller intermediate, while current `codex/fortran-modernization`
already contains the later route and readbacks.  Future deletion should use a
plain path deletion after approval, not `git worktree remove`, because the
saved tree points at stale legacy git metadata whose recorded path collides
with the canonical standalone execution worktree.

## Operating Rule

Do not submit new jobs or extend this 1D line.  If the paper needs a stronger
BTN fallback claim, open a new model/higher-dimensional scenario instead of
rerunning this completed F20F 1D setup.
