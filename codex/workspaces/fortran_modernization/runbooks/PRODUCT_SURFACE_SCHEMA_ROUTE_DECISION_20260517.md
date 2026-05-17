# Product Surface Schema Route Decision

Updated: 2026-05-17 JST
Scope: final product-facing naming, route identity, and schema/API cleanup boundary after the HWA source-contract queue and F20 strict-double readiness closure.

## Decision

The v1 product surface uses a low-cardinality route id plus separate component policy ids.  It must not encode model dimensions, retired solver branches, or comparison-only ODE package experiments in the route name.

Product ids:

```text
algorithm_id = tltm_hmc_v1
canonical_route_id = constrained_hmc_reverse_gate_metropolis_v1
integrator_policy_id = rattle_v1
constraint_solver_policy_id = newton_projection_v1
flow_policy_id = odex_hairer_endpoint_v1
qn_solver_policy_id = official_dfols_residual_certified_v1
reverse_gate_policy_id = reverse_trajectory_certification_v1
failure_policy_id = reject_stay_put_v1
precision_policy_id = double_strict_v1
```

Model/problem dimensions belong in resolved config/model metadata, not in route identity:

```text
x_size
z_size
constraint_dim
model_id
config_digest
```

## Product Surface Rules

- v1 package output is the active product schema.
- v0 output names remain compatibility evidence and adapters; they are not the product naming model.
- Product route ids are semantic route labels, not concatenated call paths.
- Product manifest provenance records official DFO-LS preset/env details, but the active public API does not expose retired backend-selector or deleted solver-policy envs as product knobs.
- ODE package comparison work is preserved as historical evidence only; the product ODE policy is the Hairer-aligned endpoint ODEX route.
- Strict double precision is the only certified product precision policy until F20 is reopened.

## Compatibility Boundary

Keep existing v0 files and readers until an accepted production redo/readback has consumed the v1 surface.  Do not rename or delete v0 columns in place.  Where a legacy v0 field name describes retired implementation history, v1 diagnostics should either omit it or report a clearer category with a compatibility mapping.

## Implemented Slice

- `src/sampler/tltm_stage2_driver.f90` now writes `tltm.stage2.manifest.v1alpha2`, `tltm.stage2.protocol.v1alpha2`, and `config.resolved.json` for v1 package sidecars.
- The manifest writes the route/component ids above, links `config.resolved.json`, and omits retired product env knobs.
- `config.resolved.json` carries model dimensions, model parameters, integrator controls, solver tolerances, Stage2 controls, RNG contract, and strict-double precision policy.
- `scripts/audit_tltm_tempering_protocol.py` accepts the v1alpha2 schema, checks the product route identity plus resolved-config package file, and cross-checks Stage3 sidecar paths against the audited manifest/protocol/config package.
- `scripts/run_stage3_3_multiseed.py` propagates `stage2_v1_resolved_config_file` into run manifests and per-seed summaries, and no longer injects retired solver-policy env knobs into Stage2 launches.
- `scripts/run_tltm_product.py` is the first thin product compatibility wrapper: it delegates to Stage3 while enforcing v1 sidecars and protocol audit policy, validates sidecar-on output packages, and writes `product_wrapper_manifest.json`.
- `scripts/run_tltm_product.py` also writes product-facing adapter tables `product_per_seed_summary_table.csv` and `product_aggregated_summary_table.csv`. These tables expose canonical `product_method` values (`nofb`, `withfb`) while preserving `raw_method` compatibility names (`no_fb`, `fb_norefine`) and route/component policy ids.
- The F12 remote wrapper tiny-screen scaffold exists as `tasks/config/f12_product_wrapper_tiny_stage3.json` plus `tasks/pbs/f12_product_wrapper_tiny_stage3_20260517.pbs`. Because the canonical remote worktree refresh found dirty state, the first real readback ran from scratch tree `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_f12_wrapper_scratch_20260517T032346Z` at commit `e91da96397b3a5dcdf45fb709f3151fcd18fe119`; PBS job `15550.anode01` passed with wrapper manifest validation `pass`, 2 per-seed rows, sidecars enabled, protocol audit verdicts `pass`, and zero missing package paths. A readback-only adapter rerun at scratch commit `3bb57960d725bd2447e4b18a3506968f35f3a66d` generated product tables with `product_method=nofb,withfb`.
- `scripts/run_m4_guardrails.py` treats retired product env knobs as forbidden in the Stage2 v1 sidecar and requires the resolved config path to survive Stage3 merge/readback.
- `f14_complete_pre_redo_gate.py` requires sidecar-on Stage3 rows to include a valid resolved config with `double_strict_v1` precision metadata and now accepts `--existing-product-wrapper-output` to validate wrapper manifest readback as optional F12 scope evidence.
- `scripts/run_m4_guardrails.py` now orders wrapper validate-only before F14 when using the tiny sidecar smoke, then passes the wrapper output into F14 so the F14 manifest records the F12 wrapper readback.

## Next Work

1. Keep raw Stage1/Stage2/Stage3 executables as developer/compatibility entry points until wrapper readback reproduces the workflow at the accepted handoff scale.
2. Separate any future source deletion of comparison-only ODE package code into its own behavior-preserving build/API cleanup slice.
3. Keep production-comparison regeneration in the external `tltm_production_comparison` tree with a frozen modernization commit.
