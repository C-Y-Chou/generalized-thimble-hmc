# M2 Non-ODEX Canonical Cleanup Plan

Updated: 2026-05-08
Scope: behavior-neutral cleanup decisions before the ODEX-only numerical change.

## Policy

All non-flow-policy M2 work before the flow-policy transition must be behavior-neutral for the current canonical p28 production route.

This means:

- Do not change `evaluate_constraint_residual`, the p28 DFO-LS BTN/backflow rescue residual objective, RG semantics, Metropolis semantics, RNG order, or output schema.
- Do not delete solver code paths before dependency and comparison gates are satisfied.
- Mark non-canonical paths as legacy/quarantine in planning first; remove source only after the staged validation gate approves deletion.
- Keep current production defaults/data interpretation stable. Existing completed Stage3_4 outputs must remain interpretable as produced.

## Canonical route fixed before ODEX-only

Canonical p28 route:

`Newton -> QN S1 p28 DFO-LS BTN/backflow rescue residual -> reverse gate -> Metropolis`

Canonical method label for the fallback route:

- `fb_norefine`

Non-canonical or deletion-candidate route families:

- Post-refine after p28 quasi success.
- Non-p28 quasi variants.
- DFO-GN paper route as a production fallback route.
- Broyden/line-search route as a production fallback route.
- Global continuation/restart fallback routes outside the p28 production policy.

## Static dependency findings

Primary files that contained non-canonical route machinery before source cleanup:

- `src/sampler/hmc_integrator_core.f90`
- `src/sampler/quasi_newton_solver.f90`
- `scripts/run_stage3_3_multiseed.py`
- Historical Stage3_4 PBS/scripts under `scripts/` and `codex/workspaces/stage3_4/`

Observed source-level anchors:

- Historical note: `hmc_integrator_core.f90` previously contained post-refine controls and routines; these have since been removed from active source.
- Historical note: `quasi_newton_solver.f90` previously contained `run_dfo_gn_attempt`, `run_dfo_gn_paper_attempt`, `run_quasi_newton_attempt`, Broyden/line-search policy, and the `QN_QUASI_GLOBAL_FALLBACK_ENABLED` control; these have since been removed from active source.
- Stage scripts may still expose historical method labels for reproducibility; those are not canonical production modes.

## Safe to do before ODEX-only

These actions are safe now because they do not alter numerical behavior:

- Document canonical route and legacy/quarantine status.
- Update planning/status/runbook references so future agents do not treat non-p28 routes as canonical.
- Inventory all source/script entry points for legacy solver families.
- Add comments or documentation in future source edits that label legacy paths, provided no executable behavior changes.
- Prepare tests that observe current behavior without changing defaults.

## Not safe before ODEX-only validation

These actions should wait until after the ODEX-only staged validation or an explicit user approval:

- Removing post-refine source code.
- Removing DFO-GN, Broyden/line-search, global fallback, or non-p28 variants from source.
- Changing fallback thresholds, tolerances, residual definitions, route order, route counters, or RG rules.
- Rewriting shared utility/RNG/config/output layers if it can affect random draw order, acceptance order, or output parsing.

## Completion state for this step

The non-ODEX portion is considered handled for the purpose of proceeding to ODEX-only when:

- `fb_norefine` is recorded as the canonical p28 route.
- Post-refine is recorded as deletion candidate, not canonical.
- Non-p28 quasi families are recorded as legacy/quarantine first, not immediate deletion.
- The roadmap states that non-ODEX cleanup before ODEX-only is behavior-neutral only.
- Source deletion is deferred until staged validation confirms no major physical-observable problem.

Status: superseded by the 2026-05-09 QN legacy route source cleanup. The planning/canonicalization-policy level is complete, and the DFO-GN/Broyden/global-continuation/post-refine source paths have been removed after staged validation and user approval.
