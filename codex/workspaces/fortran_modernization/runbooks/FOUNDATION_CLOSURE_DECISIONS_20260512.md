# Foundation Closure Decisions

Updated: 2026-05-12 JST

Scope: durable decision record from the modernization foundation-closure
discussion. These decisions supersede reduced-scope wording where a product
boundary was selected, and define the exact evidence required for remaining
open caveats.

## Decisions

| Caveat | Decision | Closure rule |
| --- | --- | --- |
| CV-007 ODEX backend completeness | Endpoint product boundary closed; solver policy reopened | TLTM modernization targets an endpoint-only ODEX backend for TLTM flow endpoint evaluation. Dense output and a general-purpose Hairer ODEX library claim are non-goals. The earlier solver-assist default-off/later-deletion direction is superseded for the next solver-policy slice by `NAVIGATION_ASSIST_STRICT_CERTIFICATION_POLICY_20260513.md`. |
| CV-001 official DFO-LS line kernel correctness | Close by formal gate | Add and pass a modernization-tree official-line kernel correctness gate under embedded official `DFO-LS==1.6.5`, `stable_gate77`, solver assist default-off, and the canonical p28 route. This is a kernel correctness gate, not a production-statistics redo. |
| CV-006 DFO-LS claim boundary | Close by strict claim/provenance policy | Add a claim dictionary and provenance policy that separates embedded official package evidence from historical in-house or DFO-LS-style evidence in reports, schemas, manifests, and readbacks. |
| CV-005 auxiliary-script evidence boundary | Closed by deep audit and gate | Every tracked file under audited script/task roots now has a registry row with evidence role, execution surface, Python floor, claim boundary, and verdict. M4 validates coverage and legacy-route quarantine through `validate_script_evidence_audit.py`. |
| CV-004 behavior-relevant source refactors | Close as permanent governance | Convert the caveat into a permanent rule: every behavior-relevant source patch needs an F8 patch statement, M4 guardrails, and an affected-baseline comparison or explicitly approved narrower baseline. |
| CV-011 RNG/workspace/reentrancy | Route B selected; RNG stream migration implemented; keep open for remaining workspace/reentrancy work | Stage1/Stage2 now use per-replica/per-slot local-update RNG streams and Stage2 has a separate swap stream. Keep CV-011 open until remaining non-RNG module-state/workspace ownership and deterministic serial/reentrant checks are complete. |

## Immediate Execution Order

1. Record these decisions in caveat/open-item state.
2. Implement and wire the CV-001 official-line kernel correctness gate.
3. Implement the CV-006 claim/provenance policy and validate it from M4.
4. Keep CV-005 closed by maintaining `SCRIPT_EVIDENCE_AUDIT_20260512.tsv`; any new or reclassified helper must update the registry before M4 evidence passes.
5. Continue CV-011 after route-B RNG stream migration; close only after remaining workspace/reentrancy implementation and tests are complete.
6. Resume larger source modernization only through the permanent CV-004/F8 behavior-preservation rule.

## Production-Comparison Boundary

Production redo remains owned by the `tltm_production_comparison` worktree. The
official-line kernel gate in this modernization tree must not submit or stand in
for production redo jobs. It closes kernel/foundation evidence only.

## Modernization Finish Boundary

The final modernization target includes full OpenMP/thread-safe productization,
not only route-B RNG stream migration. CV-011 remains open until behavior-bearing
module state/workspaces, counters, diagnostics, policy state, and deterministic
serial/reentrant checks are migrated or explicitly scoped.

Production redo is deliberately split out of modernization. The modernization
tree defines source/product readiness and provides frozen commits, schemas, and
manifests for redo to consume; redo scope, scale, queueing, readback, and final
production-output promotion are owned by `tltm_production_comparison`.

Detailed finish decisions are recorded in
`MODERNIZATION_FINISH_DECISIONS_20260512.md`.
