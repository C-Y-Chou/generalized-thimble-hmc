# F20F Production-Comparison Archive Boundary

Date: 2026-05-21 JST

## Decision

F20F is now the only active double-precision preset.  Production-comparison
outputs generated before the F20F preset and fixed-flow diagnostic split are
historical or calibration evidence, not the active main dataset for the current
BTN/no-fallback claim.

## Active Evidence Boundary

The active no-fallback scientific evidence is now owned by:

```text
codex/workspaces/nofb_diagnostics
```

The active F20F diagnostic registry is:

```text
codex/workspaces/nofb_diagnostics/state/F20F_DATASET_REGISTRY.tsv
```

The main fixed-flow diagnostic dataset is:

```text
f20f_fixed_flow_t030_512seed_200k
```

The current no-fallback pathology threshold dataset is:

```text
f20f_fixed_flow_t050_nofb_128seed_200k
```

## Archive Policy

- Existing `tltm_production_comparison` readbacks remain useful historical
  evidence, but they must be cited as pre-F20F/provisional unless explicitly
  regenerated with the F20F preset and current source contract.
- Do not mix old production-comparison outputs with F20F fixed-flow diagnostic
  evidence as if they were the same protocol.
- Future production-facing outputs should either:
  - cite the `nofb_diagnostics` registry as the diagnostic basis, or
  - be regenerated as a new F20F production-comparison campaign with explicit
    source commit, preset, scheduler request id, and readback packet.

## Not Moved

This boundary is a control-plane/archive classification.  It does not move or
delete raw remote outputs.

The F23/stage2 worktree is intentionally untouched by this cleanup.
