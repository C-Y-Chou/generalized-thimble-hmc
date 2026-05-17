# F12 Product Compatibility Wrapper

Updated: 2026-05-17 JST

Scope: first thin wrapper around the accepted Stage2/Stage3 product-surface workflow. This is orchestration only; it does not change the numerical kernel, Stage2 protocol, Stage3 aggregation, physics outputs, RNG order, or production-comparison boundary.

## Implemented

`scripts/run_tltm_product.py` is a product-facing compatibility runner that delegates to `scripts/run_stage3_3_multiseed.py`.

`scripts/run_m4_guardrails.py` now validates the product wrapper against the existing sidecar-on Stage3 guardrail output and requires the wrapper manifest validation status to pass.

The wrapper enforces the current product package policy:

```text
--stage2-v1-sidecars on
--stage2-protocol-audit auto
--stage2-protocol-audit-fail-on error
```

It validates a completed delegated run before accepting the wrapper output:

- `per_seed_summary_table.csv`, `aggregated_summary_table.csv`, and `protocol_audit_summary.csv` must exist.
- every per-seed row must be sidecar-on with protocol audit verdict `pass`;
- every per-seed row must point to existing manifest, protocol, and resolved-config package files;
- each resolved config must carry `tltm.stage2.config.resolved.v1alpha1` and `double_strict_v1`.

It records the accepted route/component ids and validation result in its wrapper manifest:

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

## Method Mapping

The wrapper exposes product method sets while delegating to existing Stage3 compatibility names:

| Wrapper method set | Delegated Stage3 selector | Meaning |
| --- | --- | --- |
| `canonical_pair` | `no_fb_fbnorefine` | current nofb/withfb compatibility pair |
| `nofb` | `no_fb` | current nofb compatibility route |
| `withfb` | `fb_norefine` | current withfb compatibility route |
| `legacy_stage3_pair` | `both` | legacy Stage3 pair for readback only |

`--stage3-methods` remains a developer compatibility override, not the product naming model.

## Compatibility Boundary

- Raw Stage1/Stage2/Stage3 executables and scripts remain developer/compatibility entry points.
- This wrapper is not permission to delete raw Stage scripts.
- Public behavior replacement requires wrapper readback that reproduces the Stage3 sidecar-on workflow, v1 package audit pass, and a frozen modernization commit for production-comparison handoff.
- Production-comparison regeneration remains external to this modernization tree.

## Local Verification

No local Stage2/Stage3 simulation screen was run for this slice.

Passing local checks:

```text
python3 -m py_compile scripts/run_tltm_product.py scripts/run_stage3_3_multiseed.py
python3 scripts/run_tltm_product.py --repo-root . --config output/tests/m4_guardrails/tiny_stage3_guardrail.json --dry-run --max-seeds 1 --jobs 1 --skip-build
python3 scripts/run_tltm_product.py --repo-root . --config output/tests/m4_guardrails/tiny_stage3_guardrail.json --output-subdir /tmp/tltm_product_validate_smoke --validate-only
git diff --check
```

The dry-run confirmed the delegated Stage3 command carries v1 sidecars and protocol audit policy. The validate-only smoke used a synthetic `/tmp` output package to confirm wrapper readback semantics without launching Stage2/Stage3.

## Remote PBS Readback

The remote tiny wrapper screen scaffold is prepared:

```text
config = codex/workspaces/fortran_modernization/tasks/config/f12_product_wrapper_tiny_stage3.json
pbs = codex/workspaces/fortran_modernization/tasks/pbs/f12_product_wrapper_tiny_stage3_20260517.pbs
```

The config is a 1-seed, 4-cycle wrapper-readback screen only. It is not production physics evidence.

The PBS script requires an explicit `TLTM_EXPECTED_GIT_COMMIT`, verifies branch `codex/fortran-modernization`, refuses a dirty remote worktree, builds the Stage2/evaluation binaries with official DFO-LS support, then runs `scripts/run_tltm_product.py --method-set canonical_pair` with sidecar/audit policy enforced by the wrapper.

The canonical remote target `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization` was refreshed and found to be dirty on branch `codex/fortran-modernization`, so this readback was run from an approved scratch remote tree instead:

```text
scratch = /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_f12_wrapper_scratch_20260517T032346Z
initial_scratch_commit = dc6c8db49b97d68849b7907569506ba2753c5190
readback_commit = e91da96397b3a5dcdf45fb709f3151fcd18fe119
product_adapter_commit = 3bb57960d725bd2447e4b18a3506968f35f3a66d
```

First submission `15549.anode01` failed before Stage2/Stage3 execution because the F12 PBS Python-header fallback included the extracted `Python.h` path but not the system `pyconfig-64.h` platform-fragment path. The PBS script now mirrors the existing official-gate header handling by adding the system Python include path when the extracted header needs `pyconfig-*.h`.

Second submission passed:

```text
job = 15550.anode01
queue = C8
node = cnode17
Exit_status = 0
walltime = 00:00:43
artifact_root = output/tests/fortran_modernization/f12_product_wrapper_tiny_stage3_20260517_20260517T122939_e91da96397b3/product_wrapper
```

Readback:

```text
product_wrapper_manifest.schema_version = tltm.product.wrapper.v1alpha1
validation.status = pass
canonical_route_id = constrained_hmc_reverse_gate_metropolis_v1
precision_policy_id = double_strict_v1
per_seed_rows = 2
methods = fb_norefine,no_fb
stage2_v1_sidecar_enabled = 1
stage2_protocol_audit_verdict = pass
missing_manifest_protocol_config_paths = 0
protocol_audit_errors = 0
protocol_audit_warnings = 0
```

After the wrapper readback passed, `scripts/run_tltm_product.py --validate-only` was rerun from scratch commit `3bb57960d725bd2447e4b18a3506968f35f3a66d` on the same remote output to write product-facing adapter tables without launching Stage2/Stage3:

```text
product_tables.status = pass
product_per_seed_summary_table.csv rows = 2
product_aggregated_summary_table.csv rows = 2
product_method = nofb,withfb
raw_method = fb_norefine,no_fb
```

The raw Stage3 tables remain compatibility/readback artifacts; product-facing tables expose canonical public method names while preserving `raw_method`.

## Next

1. Keep F14's optional product-wrapper readback path wired into M4: wrapper validate-only must run before F14 when a wrapper output is supplied, and F14 records the F12 readback in its manifest scope.
2. Keep raw Stage script deprecation deferred until wrapper readback and production-comparison handoff are accepted.
3. Freeze a clean modernization commit before production-comparison handoff.
