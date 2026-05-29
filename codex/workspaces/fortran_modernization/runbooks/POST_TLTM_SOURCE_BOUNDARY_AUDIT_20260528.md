# Post-TLTM Source Boundary Audit

Date: 2026-05-28

Scope: source-level boundary audit that can be completed before final TLTM
production finishes.  This is a static governance audit only; it does not alter
sampler behavior.

Closure update, 2026-05-29: the first source hygiene slice has now removed the
stale `wv` runtime config residue from `src/config/param_mod.f90`.  This remains
behavior-preserving because no active source branch used the old flag and
unknown legacy keys are ignored with a warning.

## Current Layer Contract

The current documented dependency direction is:

```text
apps -> sampler -> physics -> config -> core
```

The post-TLTM target is two sibling samplers sharing lower infrastructure:

```text
shared provider/config/IO/flow/readback
  -> TLTM fixed-flow ladder sampler
  -> future WV-HMC worldvolume sampler
```

## Boundary Findings

| Boundary | Current state | Risk | Pre-production treatment |
| --- | --- | --- | --- |
| Model provider | `src/physics/model.f90` facade with active `model_stephanov.f90` provider. | Low. Stephanov is still source-selected, but sampler-facing calls are generic. | Preserve. Future models replace provider implementation, not sampler logic. |
| Observable registry | `model_observables` and Stephanov provider own observable names/formulas. | Low. Fits model-general direction. | Preserve and document in provider contract. |
| Flow time state | Flow-time split is documented; Stage2 uses explicit slot/replica metadata. | Medium. Legacy packed helpers still exist for compatibility. | Preserve compatibility until final archive; do not move flow time back into physical `x`. |
| TLTM sampler kernel | Stage2 driver owns ladder, local updates, swaps, snapshots, and histories. | Medium. Large driver is hard to maintain. | Do not decompose until final production closes and guardrails are run. |
| withfb/DFO-LS fallback | Present as diagnostic/legacy fallback machinery. | Medium. It can be mistaken as canonical because historical docs/scripts mention it. | Keep default-off; final frozen criterion decides whether it remains legacy. |
| Config state | `param_mod` centralizes runtime config and legacy mirrors. The stale `wv` flag has been removed. | High for broader refactor. Many global mirrors remain. | Keep broader mirror migration deferred until baseline/guardrails. |
| RNG state | `mt95`, `tltm_rng`, Stage2 seed handling, and Metropolis draws are active. | High. Changes can invalidate production comparability. | Do not migrate before accepted baseline. Require Stage2 RNG v2 anchor. |
| Diagnostics state | `constraint_solver_stats` stores many counters and aliases. | Medium/high. Needed for readback but not yet a clean schema. | Preserve outputs now; structured diagnostics migration waits. |
| Snapshot/IO state | Stage2 supports observable history, label trace, final snapshots, and flow-bank init. | Medium. Schema mismatch can corrupt continuations. | Keep fail-closed policy; do not change binary layouts before final archive. |
| Script/PBS surface | Current and historical launch/readback scripts coexist. | Medium. Evidence claim can be confused if old scripts are reused. | Use script evidence audit and SOP mapping; no deletion before archive. |
| WV-HMC residue | No executable WV-HMC kernel found; stale docs corrected and dead `wv` flag removed. | Lower after hygiene; future WV-HMC still needs a clean sibling sampler. | Do not reuse old `wv` semantics. Start WV-HMC only from the simplified-algorithm contract. |

## Model-General Readiness

Already aligned:

- action/derivatives/observables are model-owned;
- production derivatives are manual;
- AD/FD are validation tools;
- Stephanov can serve as provider/reference model;
- high-dimensional model specs live under `model_specs/high_dimensional/`.

Still deferred:

- a documented provider ABI with required gradient, Hessian/Hv, observables,
  parameter schema, and complexification checks;
- removal of any residual model assumptions in apps/examples;
- provider-level validation command that runs random complex-seed gradient and
  Hessian/Hv checks without editing sampler code.

## Source Changes Explicitly Blocked Before Production Closure

Do not perform these until final criterion analysis and archive status are
recorded:

- changing local proposal generation, RATTLE, reverse gate, Metropolis, swap,
  or reflow logic;
- changing RNG stream ownership, stream order, or seed derivation;
- changing observable history, label trace, snapshot, bank/cache, or summary
  schema;
- deleting raw Stage entry points;
- removing compatibility aliases that current production/readback scripts may
  still parse;
- changing withfb/DFO-LS fallback defaults;
- deleting historical evidence artifacts before archive mapping.

## Safe Cleanup Already Allowed

- documentation correction for stale WV-HMC claims;
- runbook/index updates;
- artifact classification;
- future-work gating;
- guardrail checklist creation;
- static source boundary notes.

## First Source Slices After Production Closure

1. Remove or archive stale `wv` config residue.  Completed 2026-05-29.
2. Freeze canonical TLTM entry-point map and mark withfb legacy if final gates
   permit.  Completed by the final criterion closure.
3. Add typed result/status compatibility surface for flow/solver/RATTLE/HMC
   without changing outputs.
4. Add structured diagnostics schema while preserving old summaries.
5. Contract Stage2 driver only after deterministic replay, RNG anchor, snapshot,
   and observable readback pass.
6. Begin WV-HMC only after the above slices pass and TLTM guardrails remain
   unchanged.
