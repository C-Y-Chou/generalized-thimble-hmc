# Product Evidence Packet - 2026-06-03

## Scope

This packet summarizes the evidence used for the pre-public product package.
It is not a new simulation readback and does not change sampler decision gates.

## Sampler Status

| sampler | status | evidence |
| --- | --- | --- |
| TLTM | canonical production-style TLTM path for this package | frozen criterion closure and final Stephanov `n=6` TLTM observable packet |
| WV-HMC dense explicit-J | validated sibling sampler with burn-in caveat | Stephanov `n=6` long validation readback |
| Matrix-free WV-HMC | deferred roadmap item | not part of this product package |

## Key Evidence Paths

| item | path |
| --- | --- |
| TLTM final observable packet | `codex/workspaces/fortran_modernization/runbooks/generated/stephanov_n6_final_observable_z_20260529_complete/` |
| TLTM closure packet | `codex/workspaces/fortran_modernization/runbooks/generated/post_tltm_wv_hmc_ready_20260529/` |
| WV-HMC long validation | `codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md` |
| WV-HMC verification ledger | `codex/workspaces/fortran_modernization/runbooks/generated/wv_hmc_verification_workflow_20260602/CURRENT_CODE_VERIFICATION_LEDGER_AND_TODO_WORKFLOW.md` |
| Productization workflow | `codex/workspaces/fortran_modernization/runbooks/generated/productization_closure_workflow_20260603/PRODUCTIZATION_CLOSURE_WORKFLOW_20260603.md` |
| Model provider contract | `docs/MODEL_PROVIDER.md` |
| Public sampler status | `docs/SAMPLERS.md` |

## WV-HMC Validation Summary

The Stephanov `n=6` dense explicit-J WV-HMC validation used:

- `16` seeds;
- `10000` cycles per seed;
- `160000` total cycles;
- DOP853 flow backend;
- `epsilon = 0.016`;
- `nstep = 10`;
- flow-time interval `[1e-4, 0.03]`;
- paper-wall potential with `gamma = 55`.

The all-cycle estimate shows a startup transient. The late-cycle cuts are
compatible with the exact chiral condensate and number density references. This
supports public dense WV-HMC development use with explicit burn-in handling.

## Public Package Boundaries

- Public docs and wrapper expose only the active TLTM and dense WV-HMC paths.
- Production-shaped runs remain scheduler-gated.
- Matrix-free trajectories, high-dimensional performance work, broader module
  slimming, and additional benchmark campaigns are future work.

## Public Guardrail Commands

```bash
git diff --check
make build
make test
make wv-hmc-smoke
```

## Source And Output Provenance

Each product-wrapper run writes `product_run_manifest.json` containing sampler,
parameter, output, and wrapper settings. Production readbacks should additionally
record source commit, scheduler metadata, and run root.
