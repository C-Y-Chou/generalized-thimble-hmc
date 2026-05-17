# F9 Pre-Handoff Code Hygiene Closure

Updated: 2026-05-17 JST

## Scope

This packet closes the behavior-preserving F9 source-hygiene slice that was
still worth doing before handing the modernization product wrapper to
production-comparison.

This was not scoped from ad hoc example names alone.  The final slice used a
tracked-code sweep over source, tests, scripts, PBS scaffolds, and product
wrapper output fields to separate active cleanup from compatibility debt.

It does not change the canonical physics route, product route id, RNG stream
contract, Metropolis/RATTLE rejection policy, ODEX controller policy, official
DFO-LS package bridge, public method names, or raw Stage2/Stage3 output schema.

## Audit Method

The final sweep used source-driven searches for:

- legacy helper names: `decompose2`, `rattle2`
- legacy test hooks: `eo`, `istest`, `testmom`
- retired solver/package comparison terms: solver-assist, CVODE, quasi
  watchdog/budget, nonnear local route, post-refine, and p28 route wording
- root-level tracked scripts/PBS files outside canonical script/task roots
- large active procedures that remain W8/W11 architecture debt

The sweep found one active source path missed by the first patch:
`rattle_step_core` still called `decompose2` through
`hmc_integrator_core.f90`.  That is now migrated to the semantic entry point.

The sweep also found raw Stage3/diagnostic compatibility fields that should not
be exposed as product-facing columns.  Those are filtered only in the
`product_*` tables; raw Stage tables remain unchanged for compatibility and
historical readback.

## Source Changes

- Added `decompose_tangent_projection` as the semantic HMC helper entry point.
  The legacy `decompose2` name is retained as a compatibility wrapper around
  the same implementation.
- Updated active HMC proposal/reverse-probe code, the direct RATTLE core path,
  and focused retained-core tests to call `decompose_tangent_projection`.
- Kept `decompose2_workspace_t` and profiler counter naming unchanged so
  existing workspace ownership, diagnostics, and historical evidence remain
  compatible.
- Replaced the active warmup call path with `integrate_hmc_warmup_core`.
  The legacy `rattle2` name remains as a compatibility wrapper.
- Made explicit `momentum_in` take precedence over the legacy global
  `istest/testmom` test hook.  When `momentum_in` is absent, the historical
  `istest=true` deterministic test path still uses `testmom`.
- Deleted tracked root-level legacy helpers:
  - `run_stage3_3_multiseed.py`
  - `run_rg_zacc_single.pbs`

The canonical current driver remains `scripts/run_stage3_3_multiseed.py`.

- Updated `scripts/run_tltm_product.py` so product-facing summary tables exclude
  retired raw diagnostic/comparison fields such as CVODE, solver-assist,
  quasi-watchdog, post-refine, and nonnear-local-route fields.  The wrapper
  manifest records the excluded raw fields.  Raw Stage output is not filtered.

## Behavior Boundary

The only executable behavior change is in a test-hook corner:

```text
old: if istest=true, global testmom overrides explicit momentum_in
new: explicit momentum_in wins; otherwise istest=true uses testmom
```

Production Stage2/Stage3 local updates inject explicit counter-based
`momentum_in` under the Stage2 kernel RNG v2 contract and do not depend on the
global `istest/testmom` hook.  The patch therefore removes a confusing legacy
test override without changing the production route.

The strange names are not deleted from the module interface because existing
tests, archived docs, and possible out-of-tree diagnostic callers may still use
them.  This is a pre-handoff source hygiene closure, not a public API break.

The remaining `decompose2` hits are now limited to the compatibility wrapper,
its compatibility proof test, and historical profiler naming.  The remaining
`rattle2` path is a compatibility wrapper around `integrate_hmc_warmup_core`.

The remaining solver-assist/CVODE/watchdog/post-refine terms are classified as
one of:

- historical/comparison tests or PBS/readback artifacts,
- raw diagnostics/schema compatibility,
- explicit product-wrapper exclusion policy,
- or W8/W11 long-procedure/API debt that should not be rewritten immediately
  before production-comparison handoff.

## Verification

No local Stage2/Stage3 simulation screen was run.

Passed:

```text
python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/run_tltm_product.py scripts/run_m4_guardrails.py codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py
make -C build FC=gfortran LDFLAGS= test_numerical_helper_contracts test_retained_core_rg_reject_identity test_retained_core_rattle_rg_contract
synthetic validate-only product-wrapper fixture checks product retired-field filtering
python3 codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py --repo-root . --output-root output/tests/pre_handoff_f9/script_evidence_audit
python3 codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py --repo-root . --output-root output/tests/pre_handoff_f9/precision_readiness
git diff --check
```

Focused proof added:

- `test_numerical_helper_contracts` checks both the semantic
  `decompose_tangent_projection` entry point and legacy `decompose2` wrapper.
- `test_retained_core_rg_reject_identity` checks that explicit `momentum_in`
  produces the projected initial momentum even when `istest=true` and
  `testmom` is set to a different value.

Script audit result:

```text
status=pass
tracked_count=112
audited_count=112
```

Precision audit result:

```text
status=pass
precision_mode=double
tolerance_profile=strict_double
checks=12
```

## Result

F9 is closed for the current pre-production-comparison handoff scope.

Remaining repo-wide hygiene such as long-subroutine decomposition, raw Stage
schema deprecation, broader API slimming, and product documentation polish is
W8/W11/W13 productization debt.  It is not a current blocker for handing a
frozen modernization commit plus wrapper contract to
`tltm_production_comparison`.
