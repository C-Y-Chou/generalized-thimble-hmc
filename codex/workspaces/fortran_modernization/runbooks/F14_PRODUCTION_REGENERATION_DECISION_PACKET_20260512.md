# F14 Production Regeneration Decision Packet

Updated: 2026-05-12 JST

## Position

The user rejected reduced-scope F3/F4/F7/F8 acceptance. The conservative
pre-redo gates are now implemented and M4 passed them.

This does not automatically approve final publication regeneration. It means
the previous reduced-scope blockers for F3/F4/F7/F8 have been replaced by
machine-checkable gates, and those gates currently pass.

Do not treat the provisional production-comparison artifact
`official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` as the final
modernization-head production redo. It was generated under the
production-comparison worktree at commit `c0e4021`.

## Covered Before Redo

- F1 ODEX endpoint backend is accepted reduced scope for pre-redo: standalone
  endpoint package, Hairer `IWORK(3)=3` sequence, endpoint-only API, strict
  final proposal flow, dense output out of scope, solver assist default-off,
  and assist-on diagnostic opt-in only.
- F2 official DFO-LS backend replacement is accepted representative scope under
  `DFO-LS==1.6.5`, `stable_gate77`, and TLTM residual-gate acceptance.
- F3 retained-core branch/measure harness is complete for pre-redo: Newton
  replay, successful RATTLE/reverse-gate pass replay, BTN residual
  reconstruction, official package-success route census, stub no-fallback
  behavior, reverse-gate reject stay-put identity, and failure-as-rejection
  accounting.
- F4 diagnostics/accounting is complete for pre-redo: local transition
  accounting now constructs `tltm_local_transition_event_t`, derives counters
  from that event, and validates typed audit rows through
  `F4_LOCAL_TRANSITION_AUDIT_V1`.
- F7 schema/naming is complete for pre-redo:
  `F7_METHOD_ALIASES_V1` freezes public `nofb` and `withfb`, while keeping
  `no_fb` and `fb_norefine` as compatibility aliases.
- F8 reference-comparison harness is complete for pre-redo:
  `F8_PATCH_REFERENCE_STATEMENT_V1` plus
  `f14_complete_pre_redo_gate.py` writes and validates the patch-local
  reference statement against the M6 summary/report anchors.

## Verification

Commands:

```bash
make -C build FC=gfortran LDFLAGS= test_retained_core_rg_reject_identity
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Readback:

- focused reverse-gate reject identity/accounting test passed;
- M4 passed all guardrails;
- M4 passed `F14 complete pre-redo gate validates F3/F4/F7/F8`;
- F14 manifest:
  `output/tests/m4_guardrails/f14_complete_pre_redo_gate/F14_complete_pre_redo_gate_manifest.json`
  reports `status=pass` and `reduced_scope_accepted=false`;
- current F8 patch statement classifies the patch as behavior-relevant only
  because solver assist was explicitly changed to default-off:
  `allowed_drift=explicitly_accepted_assist_default_off`.

## Still Not Decided

The remaining F14 decisions are production-execution decisions, not reduced
foundation caveats:

1. Redo scope: matched `nofb` + `withfb`, or a narrower canonical run.
2. Redo scale: seed count and cycle count.
3. Target: exact local/remote worktree and commit to promote.
4. Promotion boundary: what the next redo can claim while CV-001/CV-002/CV-006
   remain explicit production/provenance caveats.

## Gate Statement

F3/F4/F7/F8 no longer block F14 as reduced-scope caveats. F14 remains blocked
only until the exact production redo scope/scale, target commit/worktree, and
promotion boundary are recorded.
