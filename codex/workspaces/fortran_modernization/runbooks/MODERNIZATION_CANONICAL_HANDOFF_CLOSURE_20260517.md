# Modernization Canonical Handoff Closure

Updated: 2026-05-17 JST

Scope: final source/product-surface handoff evidence after the remote canonical worktree was rebuilt from the clean modernization commit and then advanced through the F9 pre-handoff hygiene closure. This is a closure and provenance packet, not new physics evidence.

## Clean Commit Freeze

Selected source/product code contract commit:

```text
8ab252e62eb8f5cbb55ebf8f36c0959e55ac4e02
```

This includes the F9 code-driven pre-handoff hygiene sweep and the remote
Linux-case precision-audit repair.  If a later commit only updates this
handoff documentation, production-comparison may still treat the code contract
above as the frozen source contract.

Local source of truth:

```text
/Users/ccy/Documents/TLTM_qn_error_handling
branch = codex/fortran-modernization
status = clean and synced to origin/codex/fortran-modernization
```

Remote canonical target:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
branch = codex/fortran-modernization
HEAD = 8ab252e62eb8f5cbb55ebf8f36c0959e55ac4e02
status = clean
```

The old dirty remote tree was preserved whole rather than reset in place:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_saved_20260517T035700Z
```

The earlier patch/untracked archive is also retained:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_archive_20260517T034954Z
```

The remote-only source inspection found no source improvement that should block the rebuild. The dirty tree mainly contained the older TLTM endpoint ODEX policy split, old product route strings, and stale method env overrides already superseded by the clean target.

## Static Handoff Gate

No local TLTM Stage2/Stage3 simulation screen was run.

Local and rebuilt remote static gates passed:

```text
python3 -m py_compile scripts/run_tltm_product.py scripts/run_m4_guardrails.py scripts/run_stage3_3_multiseed.py scripts/audit_tltm_tempering_protocol.py codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py
bash -n codex/workspaces/fortran_modernization/tasks/pbs/f12_product_wrapper_tiny_stage3_20260517.pbs
python3 -m json.tool codex/workspaces/fortran_modernization/tasks/config/f12_product_wrapper_tiny_stage3.json
```

Post-F9 remote no-simulation gates at
`8ab252e62eb8f5cbb55ebf8f36c0959e55ac4e02` passed:

```text
git diff --check
python3 -m py_compile scripts/run_tltm_product.py scripts/run_stage3_3_multiseed.py scripts/merge_stage3_multiseed_chunks.py scripts/run_m4_guardrails.py codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py
python3 codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py --repo-root . --output-root output/tests/pre_handoff_f9_remote/script_evidence_audit
python3 codex/workspaces/fortran_modernization/tasks/scripts/precision_readiness_audit.py --repo-root . --output-root output/tests/pre_handoff_f9_remote/precision_readiness
python3 scripts/run_tltm_product.py --repo-root . --config codex/workspaces/fortran_modernization/tasks/config/f12_product_wrapper_tiny_stage3.json --output-subdir output/tests/fortran_modernization/f12_product_wrapper_canonical_handoff_20260517_20260517T040448Z_68f494a918a1/product_wrapper --validate-only
```

Readback:

```text
script evidence audit = pass, tracked_count=112, audited_count=112
precision readiness audit = pass, precision_mode=double, tolerance_profile=strict_double, checks=12
product wrapper validate-only = pass
```

## Canonical Remote F12 PBS Gate

The first canonical PBS attempt failed before build and before Stage2/Stage3 execution:

```text
job = 15551.anode01
queue = C8
node = cnode17
Exit_status = 4
walltime = 00:00:01
first_error = missing Python.h; rebuilt canonical tree lacked .deps/python-devel-3.11
```

This was an environment-cache rebuild issue, not a product-wrapper or numerical failure. The canonical remote tree was repaired by copying the existing Python 3.11 development header cache from the approved scratch/saved tree into:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/.deps/python-devel-3.11
```

That cache is ignored by git; the canonical worktree remained clean.

The repaired canonical PBS gate passed:

```text
job = 15552.anode01
queue = C8
node = cnode17
Exit_status = 0
walltime = 00:01:08
commit = 68f494a918a1a661b6dd26ea6883f1dc1c803b22
campaign = f12_product_wrapper_canonical_handoff_20260517_20260517T040448Z_68f494a918a1
artifact_root = output/tests/fortran_modernization/f12_product_wrapper_canonical_handoff_20260517_20260517T040448Z_68f494a918a1/product_wrapper
```

This remains the latest canonical remote PBS tiny wrapper execution.  After F9,
no additional Stage2/Stage3 simulation screen was launched; the existing
canonical F12 artifact was revalidated with the updated product wrapper at the
frozen code contract commit above.

Readback:

```text
product_wrapper_manifest.schema_version = tltm.product.wrapper.v1alpha1
product_wrapper_manifest.validation.status = pass
method_set = canonical_pair
canonical_route_id = constrained_hmc_reverse_gate_metropolis_v1
precision_policy_id = double_strict_v1
product_tables.status = pass
per_seed_summary_table rows = 2
product_per_seed_summary_table rows = 2
product_aggregated_summary_table rows = 2
product methods = nofb,withfb
raw methods = fb_norefine,no_fb
missing sidecar/protocol/resolved-config paths = 0
protocol audit verdicts = pass
```

Wrapper validate-only on the canonical output passed again after F9:

```text
python3 scripts/run_tltm_product.py --repo-root . --config codex/workspaces/fortran_modernization/tasks/config/f12_product_wrapper_tiny_stage3.json --method-set canonical_pair --output-subdir output/tests/fortran_modernization/f12_product_wrapper_canonical_handoff_20260517_20260517T040448Z_68f494a918a1/product_wrapper --validate-only
```

## F14/M4 Boundary

The F14/M4 wrapper-manifest hook remains code-backed and synthetic-readback verified by the source commit that introduced it. The canonical F12 artifact above is a valid F12 product-wrapper output and passes wrapper validation.

Do not reinterpret the canonical F12 product-wrapper output as an F4 local-transition-audit fixture: the F4 readback requires `local_transition_audit.csv`, while the product-wrapper screen intentionally validates the wrapper/sidecar/package surface. Running F14 with the wrapper output as both F4 and F12 evidence correctly fails the F4 fixture check. The correct closure claim is:

```text
F12 canonical product-wrapper readback = pass
F14 wrapper-manifest hook = implemented and previously synthetic-readback verified
F4 local-transition audit fixture = separate guardrail evidence, not supplied by F12
```

## Closure Position

Modernization source/product-surface handoff is ready for first production-comparison consumption.  The frozen code contract is `8ab252e62eb8f5cbb55ebf8f36c0959e55ac4e02`; the latest canonical remote worktree has been fast-forwarded cleanly to that commit and passes the no-simulation handoff gates above.

The product-facing wrapper contract is:

```text
route id = constrained_hmc_reverse_gate_metropolis_v1
precision policy = double_strict_v1
methods = nofb, withfb
raw compatibility methods = no_fb, fb_norefine
raw Stage tables = preserved for compatibility
product_* tables = canonical product methods plus route/component policy ids, with retired raw diagnostic/comparison fields filtered
```

Remaining work is no longer a current-source HWA blocker or canonical-wrapper blocker. Remaining scopes are:

- external production-comparison regeneration and CV-002 promotion in `tltm_production_comparison`;
- accepted-scale wrapper handoff, if required by production-comparison;
- future public API/schema deprecation of raw Stage scripts after accepted handoff scale;
- future single/mixed precision, weaker tolerance, GPU/threaded semantics, or dense-output/general-ODEX reopen packets if those product goals are selected.
