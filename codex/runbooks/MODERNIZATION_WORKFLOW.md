# Modernization Main Workflow

Updated: 2026-06-16 JST

This is the single active operational workflow for the current TLTM Fortran
modernization effort.  Use this file together with
`codex/runbooks/MODERNIZATION_STATUS.md`.  Generated runbooks are evidence
packets only; do not use them as workflow routers unless this file or the
status file explicitly names them.

## Required Read Order

1. `codex/runbooks/MODERNIZATION_WORKFLOW.md`
2. `codex/runbooks/MODERNIZATION_STATUS.md`
3. `codex/runbooks/WV_HMC_POLICY_BENCHMARK_SUMMARY_20260616.md`

## Execution Rules

- Production and validation simulations run on the cluster, not locally.
- Cluster submission must use the cluster02 scheduler authority:
  `TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler`,
  `TLTM_SCHEDULER_REQUEST_ID=<request-id>`, and
  `codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh`.
- Before choosing a queue or repairing a failed job, consult persistent
  scheduler observations and live PBS state.
- WV-HMC production-like jobs must use a source pin or runtime snapshot and
  must not depend on compute-node `git` or node-local Python.
- Generated evidence packets are not workflow entrypoints.

## Active WV-HMC Policy Route

Main policy:

- `normal_reflect`

Optional benchmark:

- `full_bounce`

Historical/diagnostic only:

- `stay_reject`
- `paper_bounce_reject`

This closes the previous four-policy ambiguity.  The next WV-HMC validation
should start from `normal_reflect` and only use `full_bounce` when a direct
policy benchmark is part of the question.

## Dense WV-HMC Validation SOP

1. Fix the physics target, model provider, and parameter file.
2. Select the sampler interval `[T0,T1]` and soft-wall widths `[D0,D1]`.
3. Tune `W(t)` for flow-time coverage before relying on observable windows.
4. Tune `epsilon` from acceptance and movement.
5. Tune `nstep` / `L = epsilon*nstep` from configuration and flow-time
   movement.
6. Keep `boundary_policy=normal_reflect` unless explicitly benchmarking
   `full_bounce`.
7. Record measurement cuts separately from transition settings.  Measurement
   cuts must not feed back into transitions.
8. For Stephanov `n=6`, inspect burn and middle-flow-time windows; current
   benchmark evidence favors burn `2k..15k` and middle windows around
   `[0.006,0.024]` to `[0.008,0.022]`.
9. Use ratio-preserving seed jackknife for chiral condensate and number
   density.
10. Do not claim final WV-HMC production correctness from a single diagnostic
    window; require stability under seed/bootstrap/block/window checks.

## Product-Readiness Route

Before public/product claims:

- Public wrappers must default to `normal_reflect`.
- Product manifests must record `boundary_policy`.
- Documentation must state that `full_bounce` is optional benchmark behavior.
- TLTM remains the canonical mature production workflow.
- WV-HMC dense explicit-J remains validation/development level until
  high-dimensional and matrix-free validation is completed.

## Deferred Modernization Blocks

- WV-HMC matrix-free / BiCGStab trajectory wiring.
- High-dimensional model performance validation.
- Historical cluster output archive compaction.
- Broader documentation cleanup after the next release candidate.
