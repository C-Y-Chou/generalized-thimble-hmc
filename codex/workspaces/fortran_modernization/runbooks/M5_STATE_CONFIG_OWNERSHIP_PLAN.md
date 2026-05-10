# M5 State And Config Ownership Plan

Updated: 2026-05-10 JST
Scope: source-backed inventory and first refactor-lane decision point for M5 repo-wide modernization.

## Inventory Artifacts

- TSV inventory: `../state/M5_STATE_CONFIG_OWNERSHIP_INVENTORY.tsv`
- Generated summary: `M5_STATE_CONFIG_OWNERSHIP_INVENTORY_SUMMARY.md`
- Scanner: `../../../scripts/inventory_fortran_state.py`

The inventory includes source and tests and records conservative hits for:

- module/procedure `save` declarations
- runtime environment reads
- `param_mod` imports
- RNG calls

## Current Surface

Inventory count:

- 368 total ownership-surface rows after the first Lane A string-env consolidation slice.
- 275 `save` declarations.
- 36 runtime env reads.
- 43 RNG calls.
- 14 `param_mod` import sites.

Main `save` hotspots:

- `src/sampler/constraint_solver_stats.f90`: 71
- `src/physics/solve_flow.f90`: 55
- `src/sampler/quasi_newton_solver.f90`: 48
- `src/sampler/hmc_integrator_core.f90`: 24
- `src/sampler/hmc_constraints.f90`: 21

Main env-read hotspots:

- `src/apps/evaluate_expectations.f90`: 12
- `src/sampler/hmc_integrator_core.f90`: 8
- `src/sampler/quasi_newton_solver.f90`: 6
- `src/config/runtime_env_mod.f90`: 4

Main RNG surface:

- `src/core/mt95.f90`
- `src/sampler/tltm_stage2_driver.f90`
- `src/sampler/tltm_stage1_driver.f90`
- `src/apps/generate_markov_chain.f90`
- `src/sampler/markovchain_metropolis.f90`

## Risk Interpretation

Not all `save` declarations are equally risky.

Lowest-risk ownership surfaces:

- runtime env parsing and provenance reporting when default/override semantics are preserved
- parser/audit/report metadata
- generated inventories and guardrail entry points

Medium-risk ownership surfaces:

- diagnostic counters and route census state
- failure-capture limits and diagnostic policy toggles
- output-path/config provenance plumbing

High-risk ownership surfaces:

- flow/ODEX work arrays and status counters
- Newton/QN workspaces and traces
- HMC/RATTLE reverse-gate state
- RNG state and seed-stream ownership
- model tape/global AD caches

## Candidate M5 Refactor Lanes

Lane A: config/env/provenance ownership.

- Move remaining direct env reads behind typed parser/provenance helpers.
- Preserve env names, defaults, invalid-value semantics, and v0 output fields.
- Best guardrails: `run_m4_guardrails.py`, env parser tests/smokes, Stage3 sidecar/no-sidecar smoke.
- Benefit: improves wrapper/product readiness without touching core numerical kernels.

Lane B: diagnostics/counter ownership.

- Move global counters toward a typed diagnostics context or at least grouped reset/snapshot APIs.
- Preserve all v0 summary names and counts.
- Best guardrails: Stage2 summary exact/counter comparison, Stage3 protocol audit, route-census checks.
- Benefit: untangles scientific diagnostics from solver internals, but counter timing is behavior-observable.

Lane C: solver/workspace ownership.

- Move ODEX/Newton/QN/HMC work arrays away from hidden module globals toward explicit workspaces.
- Requires deterministic micro-baselines before each patch.
- Benefit: reentrancy/OpenMP readiness, but highest regression risk.

Lane D: RNG ownership.

- Design per-run/per-replica RNG streams and seed provenance.
- Requires explicit user decision and fixed draw-order baselines.
- Benefit: future parallel wrapper readiness, but this is a hard stop gate.

Lane E: model/tape cache ownership.

- Move generated/model tape caches behind a model context.
- Should be last unless a wrapper-compatible singleton preserves current serial behavior.
- Requires generator changes and derivative regression checks.

## Recommendation

Do not start with RNG, solver workspaces, or model/tape cache migration.

The safest M5 first refactor lane is Lane A: config/env/provenance ownership.

Reason:

- It supports the M6 product interface and manifest provenance.
- It mostly touches orchestration/config boundaries rather than numerical kernels.
- It can be protected by the new M4 guardrails and targeted env-default tests.
- It avoids changing RNG order, proposal construction, ODE/QN semantics, or public v0 fields.

## Decision Point

This is the first real stop-for-decision point after M4 entry.

The next source refactor should choose one M5 lane:

- Lane A: config/env/provenance ownership.
- Lane B: diagnostics/counter ownership.
- Lane C: solver/workspace ownership.
- Lane D: RNG ownership.
- Lane E: model/tape cache ownership.

Recommendation: choose Lane A first, then Lane B, then targeted Lane C slices. Defer Lane D and Lane E.

## Lane A Progress

2026-05-10 JST:

- Added `runtime_env_mod:read_string_env`.
- Replaced Stage1/Stage2 direct string env reads for flow ladders, summary/history paths, init mode, sidecar paths, git commit provenance, and v1 env manifest fields.
- Preserved env names, defaults, empty-env behavior, too-long env rejection, v0 output fields, RNG order, and numerical code paths.
- M4 guardrails passed after the change.
- Inventory env-read rows dropped from 52 to 36; Stage1/Stage2 no longer directly call `get_environment_variable` outside `runtime_env_mod`.
