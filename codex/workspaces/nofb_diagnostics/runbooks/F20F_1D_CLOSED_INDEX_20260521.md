# F20F 1D Closed Index

Date: 2026-05-21 JST

Status: closed and downgraded to archive.  The F20F 1D diagnostic line is no
longer an active experiment-control workspace.

## Active Pointers

The production-facing final packet now lives in:

```text
codex/workspaces/tltm_production_comparison/runbooks/F20F_PRODUCTION_FACING_EVIDENCE_PACKET_20260521.md
codex/workspaces/tltm_production_comparison/runbooks/F20F_1D_MANUSCRIPT_CLAIM_BOUNDARY_20260521.md
codex/workspaces/tltm_production_comparison/state/F20F_FINAL_VALIDATION_20260521.tsv
```

The active dataset registry retained in this workspace is:

```text
codex/workspaces/nofb_diagnostics/state/F20F_DATASET_REGISTRY.tsv
```

## Archived Work Log

Intermediate plans, scan notes, fixed-flow readbacks, cleanup commands, and
old packet drafts were moved to:

```text
codex/workspaces/nofb_diagnostics/archive/f20f_1d_closed_20260521/
```

That archive contains:

- `runbooks/`: historical F20F 1D plans, scan readbacks, cleanup readbacks, and
  compact packet notes;
- `state/`: the old cleanup dry-run inventory and physical dataset grouping.

## Final Interpretation

The closed 1D result is:

- fixed-flow `t=0.5` no-fallback is a real sign-lock / observable-pathology
  example;
- TLTM low005 repairs that fixed-flow pathology;
- fallback improves TLTM solver health but does not show a robust observable
  necessity signal in this 1D toy model;
- further evidence for a strong fallback-necessity claim should come from a new
  model or higher-dimensional scenario, not this completed 1D setup.

## Operating Rule

Do not submit new jobs, reopen scheduler requests, or extend this 1D F20F line
unless the user explicitly opens a new scientific question.
