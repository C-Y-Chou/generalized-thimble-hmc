# DFO-LS Claim Provenance Policy

Updated: 2026-05-12 JST

Scope: closure policy for CV-006. This file defines what can be claimed as
embedded official DFO-LS evidence and what must remain historical/internal
DFO-LS-style evidence.

## Policy File

The machine-readable policy is:

```text
codex/workspaces/fortran_modernization/schema/DFOLS_CLAIM_PROVENANCE_POLICY_V1.json
```

## Claim Boundary

- `official_dfols` means the embedded official package bridge was used, with
  `DFO-LS==1.6.5`, `GPL-3.0-or-later`, a recorded
  `TLTM_OFFICIAL_DFOLS_PYTHONPATH`, `QN_SOLVER_BACKEND=official_dfols`, and
  `QN_OFFICIAL_DFOLS_PRESET=stable_gate77` unless a future explicit decision
  changes the preset.
- `historical_internal_dfols_style` means in-house or older DFO-LS-style
  evidence. It may be useful background, but it must not certify the embedded
  official package line.
- M6 reference packages remain historical/internal behavior anchors unless a
  package/runtime provenance row explicitly says otherwise.

## Closure Statement

CV-006 can close once M4 validates this policy and the official-line kernel
gate writes a manifest that distinguishes official package evidence from
historical/internal evidence.
