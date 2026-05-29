# Post-TLTM Guardrail Checklist

Date: 2026-05-28

Scope: guardrail checklist for all post-TLTM cleanup and modernization slices.
This can be prepared before production finishes.  It is not a command to modify
or stop running production.

## Rule

Every cleanup slice must declare one behavior class before editing:

| Class | Meaning | Required gate |
| --- | --- | --- |
| docs-only | Documentation, runbook, index, or comments only. | File review and no source/schema changes. |
| behavior-preserving source | Refactor that should not alter outputs, RNG, proposals, or summaries. | Full local guardrails and affected baseline row. |
| schema-compatible output | Adds fields/sidecars while preserving old readers. | Guardrails plus readback compatibility smoke. |
| behavior-changing | Physics/sampler/schema/RNG/default changes. | User approval plus comparison evidence.  Blocked while production is active. |

## Pre-Edit Checklist

- `git status --short` reviewed.
- Existing user or production changes are not reverted.
- Slice behavior class is written in the work note or commit message.
- Affected files are mapped to one phase in
  `MODERNIZATION_POST_TLTM_WORKFLOW_20260528.md`.
- If touching scripts, `SCRIPT_EVIDENCE_AUDIT_20260512.tsv` update need is
  decided before the script is used as evidence.
- If touching source, affected baseline row is prepared before the patch.

## Docs-Only Gate

Required:

```bash
git diff --check
rg -n "WV-HMC Fortran Project|implements a worldvolume-HMC workflow" docs/readme.md scripts/README.md docs/module_architecture.md docs/file_layout.md
```

Pass condition:

- diff has no whitespace errors;
- current overview docs do not claim current TLTM source already implements
  WV-HMC;
- docs do not change production instructions without pointing to SOP/runbook
  source of truth.

## Source Hygiene Gate

Required before behavior-preserving source cleanup:

```bash
make -C build modernization_guardrails
make -C build script_evidence_audit_gate
make -C build stage2_rng_v2_anchor
make -C build test1
make -C build test2
```

Additional gate when config, RNG, or state ownership is touched:

```bash
make -C build test_mt95_state_contract
make -C build test_tltm_rng_contract
make -C build test_tltm_swap_kernel_contract
```

Additional gate when flow backend or ODE controller is touched:

```bash
make -C build test_odex_solver
make -C build test_odex_foundation_contract
make -C build test_odex_backend_package_contract
make -C build test_odex_flow_jacobian_contract
```

Additional gate when RATTLE/HMC/reverse-gate code is touched:

```bash
make -C build test_retained_core_newton_contract
make -C build test_retained_core_rattle_rg_contract
make -C build test_retained_core_qn_route_contract
make -C build test_retained_core_rg_reject_identity
```

Pass condition:

- all selected gates pass in the local environment or failure is recorded as an
  environment issue, not ignored;
- source patch preserves summary/output schema unless migration is explicitly
  approved;
- RNG anchor remains stable when RNG/state code is not the target.

Observed status, 2026-05-29:

- `make -C build modernization_guardrails`: pass;
- `make -C build test_official_dfols_preset_contract test_retained_core_qn_route_contract test1 test2`: pass;
- `make -C build test_mt95_state_contract test_tltm_rng_contract test_tltm_swap_kernel_contract`: pass;
- `git diff --check`: pass.

## Production-Safety Gate

For any active or future TLTM production campaign, the following are not allowed
without a new gate and explicit approval:

- changing production defaults;
- changing `nofb`/`withfb` decision thresholds;
- changing HMC `epsilon`, `L`, `nstep`, ladder, or flow-bank protocol in source
  defaults;
- changing binary snapshot or observable-history layouts;
- deleting raw Stage compatibility entry points;
- removing legacy fields read by current readback scripts;
- changing DFO-LS fallback defaults;
- migrating RNG streams or large module workspaces.

## Final-Criterion Gate

Status, 2026-05-29: completed for the Stephanov `n=6`, `t_high=0.03` closure
packet:

```text
runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md
```

The frozen criterion analysis used only the existing frozen thresholds:

- observable correctness;
- wall-clock information rate;
- ratio-estimator stability;
- ladder transport and high-flow return;
- failure-mediated repair;
- edge-localized bottleneck;
- seed/bootstrap/block-size robustness.

Required output:

- final criterion Markdown summary;
- estimator summary table;
- seed-level table;
- mixing/high-flow diagnostics table if available;
- failure/solver/runtime diagnostics table if available;
- final dataset archive group table.

Runtime-excluded repair/outlier jobs are explicitly excluded from runtime,
throughput, equal-wall-clock, ESS/hour, and `1/SE^2/hour` claims.

## WV-HMC Gate

WV-HMC implementation cannot start until:

- TLTM final criterion packet exists: done;
- TLTM canonical SOP is runnable: documented;
- stale WV residue is removed or archived: source `wv` flag removed;
- TLTM source guardrails pass after hygiene: done on 2026-05-29;
- shared provider/config/IO boundaries are stable enough for the WV-HMC sibling
  sampler gate;
- WV-HMC implementation plan follows
  `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`.

First WV-HMC validation target:

- Stephanov `n=2`;
- explicit dense projection backend;
- exact-reference observable check;
- projection reconstruction/orthogonality checks;
- simplified RATTLE `(h,u,lambda)` residual checks;
- reversibility and energy-error scaling;
- boundary bounce and flow-time visitation diagnostics.
