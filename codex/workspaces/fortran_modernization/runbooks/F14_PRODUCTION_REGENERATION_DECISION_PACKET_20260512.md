# F14 Production Regeneration Decision Packet

Updated: 2026-05-12 JST

## Position

F14 has reached a real decision point. The current modernization branch is still
not automatically cleared for final publication-grade production regeneration,
but the remaining blockers are now explicit decisions rather than hidden caveats.

Do not treat the provisional production-comparison artifact
`official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` as the final
modernization-head production redo. It was generated under the
production-comparison worktree at commit `c0e4021`.

## What Is Now Covered

- F1 ODEX is accepted reduced scope: endpoint extrapolation backend,
  Hairer `IWORK(3)=3` sequence, no dense output, `stability_control=none`,
  solver-internal assist only for residual evaluation, and strict final
  proposal flow.
- F2 official DFO-LS backend replacement is accepted representative scope under
  `DFO-LS==1.6.5`, `stable_gate77`, and TLTM residual-gate acceptance.
- F3 retained-core guardrails now cover Newton replay, successful RATTLE and
  reverse-gate pass replay, BTN residual reconstruction, official package
  success on route code `10`, a fixed-step route census at `0.002/0.003/0.004`,
  stub no-fallback behavior, reverse-gate reject stay-put identity, and
  failure-as-rejection local-transition accounting.
- The build/test workflow now prevents silent official/stub bridge reuse by
  relinking when `ENABLE_OFFICIAL_DFOLS` changes.
- M4 guardrails now load `.venv-dfols` and `TLTM_OFFICIAL_DFOLS_PYTHONPATH` so
  the official package-success branch is tested locally.

## Still Not Fully Closed

`CV-009` remaining scope:

- A full formal local-volume/branch-measure proof or exhaustive harness for all
  official DFO-LS piecewise branches is not implemented.
- The deterministic branch coverage now tests the important success and reject
  boundaries, but it is still narrower than a mathematical proof over every
  possible solver branch.

`CV-010` remaining scope:

- Status/counter slices and compatibility sidecars exist, but diagnostics are
  not yet represented by one typed proposal/replay/residual/probe/reject event
  context.
- Public counters are still compatibility-first. `projection_failure_count`
  remains a legacy coarse counter, while typed details such as
  `reverse_gate_rejected_count` are appended/sidecar diagnostics.

Schema/wrapper boundary:

- The v1alpha sidecars and method/provenance labels are useful, but the final
  public method naming, schema version, wrapper behavior, and compatibility
  reader policy are not frozen.
- The F7/F8 schema/reference boundary is recorded in
  `SCHEMA_REFERENCE_F7_F8_DECISION_20260512.md`.

## Decision Required

Option A: finish conservative foundation before production.

- Implement F4 typed diagnostics/accounting context.
- Add the formal local-volume/branch-measure proof or a stronger branch harness.
- Freeze F7 public method names/schema roles and F8 reference-comparison
  commands for behavior-relevant source patches.
- Then update production and regenerate final datasets.

Option B: accept reduced-scope production redo now.

- Explicitly accept deterministic branch coverage in place of a full
  local-volume/branch-measure proof.
- Explicitly accept the current compatibility counter/schema policy for this
  production redo.
- Run the production update/regeneration with reduced-scope wording and keep the
  result out of "full publication-ready foundation" language.

Recommendation: choose Option A for publication-grade production. Choose Option B
only if the immediate goal is an operational production rerun with clearly
reduced claims.

## F14 Gate Statement

F14 is blocked until the user chooses Option A or Option B. No final production
regeneration should start from modernization HEAD without that decision.
