# Modernization Finish Decisions

Updated: 2026-05-12 JST

Scope: durable decision record for what "modernization finished" means after
CV-011 route-B RNG streams and the production-redo split discussion.

## Decisions

| ID | Decision | Operational consequence |
| --- | --- | --- |
| D1 | Commit the current foundation/RNG work as a checkpoint before starting the next slice. | The checkpoint must include CV-001/CV-004/CV-005/CV-006/CV-007 foundation closure, CV-011 route-B RNG streams, and their guardrail evidence. |
| D2 | Full OpenMP/thread-safe productization remains inside modernization scope. | CV-011 cannot close at RNG stream migration. Remaining module `save` workspaces, counters, diagnostics, policy state, and deterministic serial/reentrant checks must be migrated or explicitly scoped before modernization is finished. |
| D3 | Build a small deterministic post-B reference anchor before larger refactors. | The accepted route-B RNG contract intentionally changes finite same-seed trajectories versus the old shared serial RNG stream, so future patches need a post-B anchor for the new contract. |
| D4 | Migrate behavior-bearing state; scope out only non-behavior caches/logging/perf state when justified. | Workspace migration must prioritize physics/control-flow state. Any non-product state left behind needs an explicit caveat or nonblocking rationale. |
| D5 | Keep v0 outputs mostly compatible; put new semantics in v1 sidecars/manifests. | Existing Stage outputs remain compatibility surfaces while `rng_stream_contract` and future product semantics live in sidecar/provenance records. |
| D6 | Remove or move solver assist out of the production path before final production freeze. | Solver assist remains default-off and diagnostic opt-in for now; final product readiness must not rely on assist-on production policy. |
| D7 | Official DFO-LS is the production backend target; internal QN remains legacy/test comparison until a final release decision says otherwise. | Modernization evidence and docs must distinguish embedded official DFO-LS package evidence from historical/internal QN or DFO-LS-style evidence. |
| D8 | Production redo is fully independent from modernization. | Redo work happens in `tltm_production_comparison` and consumes only a frozen modernization commit plus declared schema/contract inputs. It must not be run, repaired, or promoted from the modernization tree. |
| D9 | Modernization finished means source/product readiness, not redo completion. | F14/CV-002 production-output promotion can remain an external redo-tree activity after modernization source/product gates are satisfied. |

## Modernization Completion Gate

Modernization can be called finished only after these modernization-tree gates
are closed or explicitly scoped:

1. CV-011 full OpenMP/thread-safe productization: explicit state/workspace
   ownership, no behavior-bearing hidden module state, and deterministic
   serial/reentrant checks for the selected route-B RNG contract.
2. Post-B deterministic reference anchor for the new per-replica/per-slot RNG
   stream contract.
3. Unified product interface and schema/manifest policy sufficient for redo to
   consume a frozen commit without relying on modernization working-tree state.
4. Solver-assist production-path cleanup or an explicit final release boundary
   that keeps assist out of canonical production policy.
5. Documentation and guardrail updates proving that production redo is external
   and that modernization-tree evidence is source/product readiness evidence,
   not final production-output evidence.

## Redo Boundary

The `tltm_production_comparison` tree owns production redo scope, scale,
queueing, readback, and final production-output promotion. The modernization
tree may define contracts, frozen commits, manifests, and compatibility
readers, but it must not treat redo completion as a prerequisite for source
modernization completion.
