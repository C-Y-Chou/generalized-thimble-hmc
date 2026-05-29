#!/usr/bin/env python3
"""Run the complete conservative F14 pre-redo gate.

This gate closes the former reduced-scope branch for F3/F4/F7/F8 by checking:

* F3 retained-core branch/measure harness evidence;
* F4 typed local-transition diagnostics context and row invariants;
* F7 canonical public method names plus raw compatibility aliases;
* F8 patch-local reference statement anchored to M6 reference summaries.

It is a preflight/readback harness. It does not add tests to production
simulation loops.
"""

import argparse
import csv
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path


WORKSPACE_REL = Path("codex/workspaces/fortran_modernization")
SCHEMA_REL = WORKSPACE_REL / "schema"
METHOD_SCHEMA = SCHEMA_REL / "F7_METHOD_ALIASES_V1.json"
AUDIT_SCHEMA = SCHEMA_REL / "F4_LOCAL_TRANSITION_AUDIT_V1.json"
REFERENCE_SCHEMA = SCHEMA_REL / "F8_PATCH_REFERENCE_STATEMENT_V1.json"
M6_SUMMARY_REL = WORKSPACE_REL / "state/M6_REFERENCE_COMPARISON_SUMMARY.tsv"
PRODUCT_IDS = {
    "algorithm_id": "tltm_hmc_v1",
    "canonical_route_id": "constrained_hmc_reverse_gate_metropolis_v1",
    "integrator_policy_id": "rattle_v1",
    "constraint_solver_policy_id": "newton_projection_v1",
    "flow_policy_id": "odex_hairer_endpoint_v1",
    "qn_solver_policy_id": "official_dfols_residual_certified_v1",
    "reverse_gate_policy_id": "reverse_trajectory_certification_v1",
    "failure_policy_id": "reject_stay_put_v1",
    "precision_policy_id": "double_strict_v1",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Run complete F14 pre-redo gates for F3/F4/F7/F8.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--fc", default=os.environ.get("FC", ""), help="Optional Fortran compiler override for F3 tests.")
    parser.add_argument("--ldflags", default=os.environ.get("LDFLAGS", ""), help="LDFLAGS passed to make.")
    parser.add_argument("--skip-build", action="store_true", help="Do not run F3 make targets; validate existing/logical evidence only.")
    parser.add_argument("--keep-going", action="store_true", help="Continue after failures and report all failures.")
    parser.add_argument(
        "--existing-stage3-output",
        default="",
        help="Existing Stage3 output directory to validate for F4 instead of launching a tiny smoke.",
    )
    parser.add_argument(
        "--existing-product-wrapper-output",
        default="",
        help="Existing product-wrapper output directory with product_wrapper_manifest.json to validate as F12 readback evidence.",
    )
    parser.add_argument(
        "--output-root",
        default="output/tests/f14_pre_redo_complete_gate",
        help="Output root relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--logs-root",
        default="output/logs/f14_pre_redo_complete_gate",
        help="Log root relative to repo root, or absolute.",
    )
    return parser.parse_args()


def resolve_path(repo_root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return repo_root / path


def relpath_text(repo_root, path):
    path = Path(path)
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def run_step(label, cmd, cwd, failures, keep_going, env=None):
    print("[F14][RUN] {0}".format(label))
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        failures.append({"label": label, "cmd": cmd, "output": proc.stdout})
        print("[F14][FAIL] {0}".format(label))
        if not keep_going:
            sys.stdout.write(proc.stdout)
            raise SystemExit(1)
    else:
        print("[F14][PASS] {0}".format(label))
    return proc


def assert_condition(label, condition, details, failures, keep_going):
    if condition:
        print("[F14][PASS] {0}".format(label))
        return
    failures.append({"label": label, "cmd": ["internal-check"], "output": details})
    print("[F14][FAIL] {0}".format(label))
    if not keep_going:
        print(details)
        raise SystemExit(1)


def load_json(repo_root, rel_path):
    path = repo_root / rel_path
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def make_cmd(repo_root, args, targets):
    cmd = ["make", "-C", str(repo_root / "build")]
    if args.fc:
        cmd.append("FC={0}".format(args.fc))
    cmd.append("LDFLAGS={0}".format(args.ldflags))
    cmd.extend(targets)
    return cmd


def infer_official_dfols_env(repo_root):
    env = {}
    venv_python = repo_root / ".venv-dfols" / "bin" / "python"
    if not venv_python.exists():
        return env
    env["PYTHON"] = str(venv_python)
    proc = subprocess.run(
        [str(venv_python), "-c", "import site; print(site.getsitepackages()[0])"],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode == 0:
        env["TLTM_OFFICIAL_DFOLS_PYTHONPATH"] = proc.stdout.strip()
    return env


def write_tiny_stage3_config(path):
    config = {
        "stage_3_3_todo": {
            "frozen_setup": {
                "flow_time_ladder": [0.0, 1.0e-4],
                "max_flow_time": 1.0e-4,
                "trajectory_length_L": 0.2,
                "nstep": 2,
                "local_updates_per_cycle": 1,
                "stage2_init_mode": "direct",
            },
            "observable_definition": {"exact_re": 0.0, "exact_im": 0.0},
            "sampling_plan": {
                "seed_list": [20260421],
                "cycles_per_seed": 4,
                "warmup_cycles_optional": 0,
            },
        }
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_stage3_f4_smoke(repo_root, output_root, logs_root, failures, keep_going, env):
    out_subdir = output_root / "stage3_f4_typed_audit"
    logs_subdir = logs_root / "stage3_f4_typed_audit"
    if out_subdir.exists():
        shutil.rmtree(out_subdir)
    if logs_subdir.exists():
        shutil.rmtree(logs_subdir)
    tiny_config = output_root / "tiny_stage3_f4_config.json"
    write_tiny_stage3_config(tiny_config)
    stage_env = env.copy()
    stage_env["TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR"] = str(out_subdir / "local_transition_audit")
    stage_env["TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS"] = "200"
    cmd = [
        sys.executable,
        str(repo_root / "scripts/run_stage3_3_multiseed.py"),
        "--repo-root",
        str(repo_root),
        "--config",
        str(tiny_config),
        "--skip-build",
        "--max-seeds",
        "1",
        "--methods",
        "no_fb",
        "--output-subdir",
        str(out_subdir),
        "--logs-subdir",
        str(logs_subdir),
        "--log-prefix",
        "f14_f4",
        "--stage2-v1-sidecars",
        "on",
        "--stage2-protocol-audit",
        "auto",
        "--allow-oversubscribe",
    ]
    run_step("F4 typed Stage3 smoke", cmd, repo_root, failures, keep_going, stage_env)
    return out_subdir


def int_value(row, name):
    return int(float(row[name]))


def finite_float(value):
    try:
        parsed = float(value)
    except ValueError:
        return False
    return math.isfinite(parsed)


def validate_method_schema(repo_root, failures, keep_going):
    schema = load_json(repo_root, METHOD_SCHEMA)
    methods = schema.get("canonical_methods", {})
    nofb = methods.get("nofb", {})
    withfb = methods.get("withfb", {})
    ok = (
        schema.get("schema_version") == "F7_METHOD_ALIASES_V1"
        and set(schema.get("required_public_pair", [])) == {"nofb", "withfb"}
        and "no_fb" in nofb.get("raw_aliases", [])
        and "fb_norefine" in withfb.get("raw_aliases", [])
        and schema.get("compatibility_policy", {}).get("raw_names_remain_accepted") is True
    )
    assert_condition("F7 method alias schema freezes nofb/withfb with raw compatibility", ok, json.dumps(schema, indent=2), failures, keep_going)


def validate_reference_schema(repo_root, failures, keep_going):
    schema = load_json(repo_root, REFERENCE_SCHEMA)
    required = set(schema.get("required_fields", []))
    ok = {
        "behavior_level",
        "affected_surfaces",
        "baseline",
        "commands",
        "allowed_drift",
        "decision",
    }.issubset(required)
    assert_condition("F8 patch reference schema has required decision fields", ok, json.dumps(schema, indent=2), failures, keep_going)


def validate_m6_summary(repo_root, failures, keep_going):
    path = repo_root / M6_SUMMARY_REL
    rows = []
    if path.exists():
        with path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
    by_level = {}
    for row in rows:
        by_level.setdefault(row.get("level", ""), set()).add(row.get("canonical_method", ""))
    missing = []
    for level in ("R1", "R2", "R3", "R4"):
        methods = by_level.get(level, set())
        if not {"nofb", "withfb"}.issubset(methods):
            missing.append("{0}: {1}".format(level, ",".join(sorted(methods)) or "none"))
    assert_condition(
        "F8 M6 reference summary contains nofb/withfb for R1-R4",
        path.exists() and not missing,
        "summary={0}\nmissing={1}".format(path, "; ".join(missing)),
        failures,
        keep_going,
    )


def read_first_csv_row(path):
    with Path(path).open(newline="", encoding="utf-8") as handle:
        return next(csv.DictReader(handle))


def read_csv_rows(path):
    with Path(path).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def validate_summary_counter_identities(repo_root, summary_path, failures, keep_going):
    row = read_first_csv_row(summary_path)
    errors = []
    if row.get("stage2_v1_sidecar_enabled") != "1":
        errors.append("stage2_v1_sidecar_enabled != 1")
    if row.get("stage2_protocol_audit_verdict") != "pass":
        errors.append("stage2_protocol_audit_verdict != pass")
    resolved_config_text = row.get("stage2_v1_resolved_config_file", "")
    if not resolved_config_text:
        errors.append("stage2_v1_resolved_config_file is missing")
    else:
        resolved_config_path = resolve_path(repo_root, resolved_config_text)
        if not resolved_config_path.exists():
            errors.append("stage2_v1_resolved_config_file does not exist: {0}".format(resolved_config_text))
        else:
            config_data = json.loads(resolved_config_path.read_text(encoding="utf-8"))
            if config_data.get("schema_version") != "tltm.stage2.config.resolved.v1alpha1":
                errors.append("resolved config schema_version is not tltm.stage2.config.resolved.v1alpha1")
            if config_data.get("precision", {}).get("precision_policy_id") != "double_strict_v1":
                errors.append("resolved config precision_policy_id is not double_strict_v1")
    for prefix in (
        "reverse_gate_total",
        "reverse_gate_probe_only",
        "reverse_gate_full_stage",
        "reverse_gate_near_rescue",
        "reverse_gate_nonnear_route",
        "reverse_gate_class_local",
        "reverse_gate_class_mid",
        "reverse_gate_class_global",
        "reverse_gate_far_skip",
        "reverse_gate_far_light",
        "reverse_gate_far_anchor",
    ):
        cand = "{0}_candidate_count".format(prefix)
        passed = "{0}_pass_count".format(prefix)
        rejected = "{0}_reject_count".format(prefix)
        if cand in row and passed in row and rejected in row:
            if int_value(row, cand) != int_value(row, passed) + int_value(row, rejected):
                errors.append("{0} != {1}+{2}".format(cand, passed, rejected))
    assert_condition(
        "F4 Stage3 summary typed reverse-gate counter identities",
        not errors,
        "summary={0}\nerrors={1}\nrow={2}".format(summary_path, "; ".join(errors), json.dumps(row, indent=2, sort_keys=True)),
        failures,
        keep_going,
    )


def validate_local_transition_audit(repo_root, stage3_out, failures, keep_going):
    schema = load_json(repo_root, AUDIT_SCHEMA)
    expected_columns = schema.get("columns", [])
    audit_files = sorted(Path(stage3_out).rglob("local_transition_audit.csv"))
    assert_condition(
        "F4 local transition audit files exist",
        bool(audit_files),
        "No local_transition_audit.csv under {0}".format(stage3_out),
        failures,
        keep_going,
    )
    if not audit_files:
        return []

    checked = []
    for audit_path in audit_files:
        with audit_path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames or []
            errors = []
            if header != expected_columns:
                errors.append("header mismatch: {0}".format(header))
            row_count = 0
            for row_count, row in enumerate(reader, start=1):
                if row.get("row_index") != str(row_count):
                    errors.append("row_index {0} != {1}".format(row.get("row_index"), row_count))
                accepted = row.get("accepted")
                proposal_failed = row.get("proposal_failed")
                if accepted not in {"T", "F"}:
                    errors.append("accepted is not T/F at row {0}".format(row_count))
                if proposal_failed not in {"T", "F"}:
                    errors.append("proposal_failed is not T/F at row {0}".format(row_count))
                status = int_value(row, "transition_status")
                if status < 0 or status > 6:
                    errors.append("transition_status out of range at row {0}".format(row_count))
                if accepted == "T" and (status != 0 or proposal_failed != "F"):
                    errors.append("accepted row has non-accepted status/proposal_failed at row {0}".format(row_count))
                if proposal_failed == "T" and status not in {2, 3, 4, 5, 6}:
                    errors.append("proposal_failed row has illegal status at row {0}".format(row_count))
                for name in ("h_initial", "h_final", "delta_h", "accept_probability", "q_initial", "c_initial", "q_proposal", "c_proposal", "q_after"):
                    if not finite_float(row.get(name, "")):
                        errors.append("{0} is not finite at row {1}".format(name, row_count))
                delta_fields = [name for name in expected_columns if name.endswith("_delta")]
                for name in delta_fields:
                    value = int_value(row, name)
                    if value < 0:
                        errors.append("{0} is negative at row {1}".format(name, row_count))
                if int_value(row, "rg_candidate_delta") != int_value(row, "rg_pass_delta") + int_value(row, "rg_reject_delta"):
                    errors.append("rg candidate/pass/reject identity fails at row {0}".format(row_count))
            if row_count == 0:
                errors.append("audit file has no rows")
        assert_condition(
            "F4 local transition audit schema/invariants {0}".format(relpath_text(repo_root, audit_path)),
            not errors,
            "\n".join(errors[:80]),
            failures,
            keep_going,
        )
        checked.append({"path": relpath_text(repo_root, audit_path), "rows": row_count})
    return checked


def validate_product_wrapper_readback(repo_root, wrapper_out, failures, keep_going):
    if not wrapper_out:
        return {"mode": "not_requested"}

    wrapper_out = Path(wrapper_out)
    manifest_path = wrapper_out / "product_wrapper_manifest.json"
    per_seed_csv = wrapper_out / "per_seed_summary_table.csv"
    protocol_audit_csv = wrapper_out / "protocol_audit_summary.csv"
    aggregate_csv = wrapper_out / "aggregated_summary_table.csv"
    errors = []
    data = {}

    if not manifest_path.exists():
        errors.append("product_wrapper_manifest.json missing: {0}".format(manifest_path))
    else:
        try:
            data = json.loads(manifest_path.read_text(encoding="utf-8"))
        except ValueError as exc:
            errors.append("product_wrapper_manifest.json is not valid JSON: {0}".format(exc))

    if data:
        if data.get("schema_version") != "tltm.product.wrapper.v1alpha1":
            errors.append("wrapper manifest schema_version mismatch")
        validation = data.get("validation", {})
        if validation.get("status") != "pass":
            errors.append("wrapper manifest validation.status is not pass")
        if int(validation.get("row_count", 0) or 0) <= 0:
            errors.append("wrapper manifest validation.row_count is empty")
        product_ids = data.get("product_ids", {})
        for key, expected in PRODUCT_IDS.items():
            if product_ids.get(key) != expected:
                errors.append("wrapper product id {0} mismatch: {1}".format(key, product_ids.get(key)))
        enforced = data.get("enforced_policy", {})
        if enforced.get("stage2_v1_sidecars") != "on":
            errors.append("wrapper did not enforce stage2_v1_sidecars=on")
        if enforced.get("stage2_protocol_audit") != "auto":
            errors.append("wrapper did not enforce stage2_protocol_audit=auto")
        if enforced.get("stage2_protocol_audit_fail_on") != "error":
            errors.append("wrapper did not enforce stage2_protocol_audit_fail_on=error")
        product_tables = data.get("product_tables", {})
        if product_tables.get("status") != "pass":
            errors.append("wrapper product_tables.status is not pass")
        expected_outputs = data.get("expected_outputs", {})
        for key in ("product_per_seed_summary_table", "product_aggregated_summary_table"):
            path_text = expected_outputs.get(key, "")
            if not path_text:
                errors.append("wrapper expected_outputs.{0} is missing".format(key))
                continue
            table_path = resolve_path(repo_root, path_text)
            if not table_path.exists():
                errors.append("wrapper product table does not exist: {0}".format(path_text))
                continue
            table_rows = read_csv_rows(table_path)
            if not table_rows:
                errors.append("wrapper product table has no rows: {0}".format(path_text))
                continue
            required_columns = set(["product_method", "raw_method"] + list(PRODUCT_IDS.keys()))
            missing_columns = sorted(required_columns.difference(table_rows[0].keys()))
            if missing_columns:
                errors.append("{0} missing product columns: {1}".format(path_text, ",".join(missing_columns)))

    rows = []
    for label, path in (
        ("per_seed_summary_table", per_seed_csv),
        ("aggregated_summary_table", aggregate_csv),
        ("protocol_audit_summary", protocol_audit_csv),
    ):
        if not path.exists():
            errors.append("{0} missing: {1}".format(label, path))
    if per_seed_csv.exists():
        rows = read_csv_rows(per_seed_csv)
        if not rows:
            errors.append("per_seed_summary_table has no rows")

    for idx, row in enumerate(rows, start=2):
        row_id = "row {0} method={1} seed={2}".format(idx, row.get("method", ""), row.get("seed_id", ""))
        if row.get("stage2_v1_sidecar_enabled") != "1":
            errors.append("{0}: stage2_v1_sidecar_enabled != 1".format(row_id))
        if row.get("stage2_protocol_audit_verdict") != "pass":
            errors.append("{0}: stage2_protocol_audit_verdict != pass".format(row_id))
        for field_name in ("stage2_v1_manifest_file", "stage2_v1_protocol_file", "stage2_v1_resolved_config_file"):
            field_text = row.get(field_name, "")
            if not field_text:
                errors.append("{0}: {1} missing".format(row_id, field_name))
                continue
            field_path = resolve_path(repo_root, field_text)
            if not field_path.exists():
                errors.append("{0}: {1} does not exist: {2}".format(row_id, field_name, field_text))
                continue
            if field_name == "stage2_v1_resolved_config_file":
                config_data = json.loads(field_path.read_text(encoding="utf-8"))
                if config_data.get("schema_version") != "tltm.stage2.config.resolved.v1alpha1":
                    errors.append("{0}: resolved config schema_version mismatch".format(row_id))
                if config_data.get("precision", {}).get("precision_policy_id") != "double_strict_v1":
                    errors.append("{0}: resolved config precision_policy_id mismatch".format(row_id))

    if protocol_audit_csv.exists():
        audit_rows = read_csv_rows(protocol_audit_csv)
        for row in audit_rows:
            if int(row.get("errors", "0") or 0) != 0:
                errors.append("protocol audit row has errors: {0}".format(json.dumps(row, sort_keys=True)))

    info = {
        "mode": "validated",
        "output": relpath_text(repo_root, wrapper_out),
        "manifest": relpath_text(repo_root, manifest_path),
        "row_count": len(rows),
        "methods": sorted({row.get("method", "") for row in rows}),
        "validation_status": data.get("validation", {}).get("status") if data else "",
    }
    assert_condition(
        "F12 product wrapper manifest readback",
        not errors,
        "wrapper_out={0}\nerrors={1}\nmanifest={2}".format(
            wrapper_out,
            "; ".join(errors),
            json.dumps(data, indent=2, sort_keys=True),
        ),
        failures,
        keep_going,
    )
    return info


def run_f3_harness(repo_root, args, failures, keep_going, env):
    targets = [
        "test_retained_core_newton_contract",
        "test_retained_core_rattle_rg_contract",
        "test_retained_core_qn_route_contract",
        "test_retained_core_rg_reject_identity",
    ]
    if args.skip_build:
        print("[F14][INFO] F3 make targets delegated to caller because --skip-build was set")
        return {
            "mode": "delegated",
            "targets": targets,
            "branch_measure_contract": "Newton replay, accepted RATTLE/RG replay, official QN route census, RG reject stay-put identity",
        }
    run_step("F3 retained-core branch/measure harness", make_cmd(repo_root, args, targets), repo_root, failures, keep_going, env)
    return {
        "mode": "executed",
        "targets": targets,
        "branch_measure_contract": "Newton replay, accepted RATTLE/RG replay, official QN route census, RG reject stay-put identity",
    }


def git_changed_files(repo_root):
    proc = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def infer_patch_surfaces(changed_files):
    surfaces = set()
    for name in changed_files:
        if name.startswith("src/physics/solve_flow"):
            surfaces.add("flow_policy")
            surfaces.add("solver_route")
        if name.startswith("src/sampler/"):
            surfaces.add("reverse_gate")
            surfaces.add("counters")
        if name.startswith("scripts/") or name.startswith("codex/"):
            surfaces.add("wrapper")
        if "/schema/" in name or "SCHEMA" in name:
            surfaces.add("schema")
        if name.startswith("tests/") or name.startswith("build/"):
            surfaces.add("guardrail")
    if not surfaces:
        surfaces.add("guardrail")
    return sorted(surfaces)


def write_reference_statement(repo_root, output_root, f3_info, audit_files, product_wrapper_info):
    changed = git_changed_files(repo_root)
    surfaces = infer_patch_surfaces(changed)
    behavior_relevant = "flow_policy" in surfaces or "solver_route" in surfaces or "reverse_gate" in surfaces
    statement = {
        "schema_version": "F8_PATCH_REFERENCE_STATEMENT_V1",
        "behavior_level": "behavior_relevant" if behavior_relevant else "diagnostic_only",
        "affected_surfaces": surfaces,
        "baseline": [
            relpath_text(repo_root, repo_root / M6_SUMMARY_REL),
            relpath_text(repo_root, repo_root / WORKSPACE_REL / "runbooks/M6_REFERENCE_COMPARISON_REPORT_20260511.md"),
        ],
        "commands": [
            "make -C build ... test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity",
            "python3 scripts/run_stage3_3_multiseed.py ... --stage2-v1-sidecars on --stage2-protocol-audit auto with TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR",
            "python3 scripts/run_tltm_product.py ... --validate-only",
            "python3 codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py",
        ],
        "allowed_drift": "explicitly_accepted_deleted_solver_policy" if behavior_relevant else "exact",
        "decision": "pass",
        "changed_files": changed,
        "f3_branch_measure": f3_info,
        "f4_audit_files": audit_files,
        "f12_product_wrapper_readback": product_wrapper_info,
    }
    output_root.mkdir(parents=True, exist_ok=True)
    path = output_root / "F8_patch_reference_statement.json"
    path.write_text(json.dumps(statement, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("[F14][WRITE] {0}".format(path))
    return statement, path


def write_manifest(output_root, statement, stage3_out, product_wrapper_info):
    scope = ["F3", "F4", "F7", "F8"]
    if product_wrapper_info.get("mode") == "validated":
        scope.append("F12")
    manifest = {
        "gate": "F14 complete pre-redo gate",
        "status": "pass",
        "scope": scope,
        "reduced_scope_accepted": False,
        "stage3_output": str(stage3_out),
        "product_wrapper_readback": product_wrapper_info,
        "f8_statement": statement,
    }
    output_root.mkdir(parents=True, exist_ok=True)
    path = output_root / "F14_complete_pre_redo_gate_manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("[F14][WRITE] {0}".format(path))


def run_gate(args):
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_path(repo_root, args.output_root)
    logs_root = resolve_path(repo_root, args.logs_root)
    output_root.mkdir(parents=True, exist_ok=True)
    logs_root.mkdir(parents=True, exist_ok=True)
    failures = []

    env = os.environ.copy()
    env.update(infer_official_dfols_env(repo_root))

    f3_info = run_f3_harness(repo_root, args, failures, args.keep_going, env)
    validate_method_schema(repo_root, failures, args.keep_going)
    validate_reference_schema(repo_root, failures, args.keep_going)
    validate_m6_summary(repo_root, failures, args.keep_going)

    if args.existing_stage3_output:
        stage3_out = resolve_path(repo_root, args.existing_stage3_output)
    else:
        stage3_out = run_stage3_f4_smoke(repo_root, output_root, logs_root, failures, args.keep_going, env)
    validate_summary_counter_identities(repo_root, stage3_out / "per_seed_summary_table.csv", failures, args.keep_going)
    audit_files = validate_local_transition_audit(repo_root, stage3_out, failures, args.keep_going)
    product_wrapper_info = validate_product_wrapper_readback(
        repo_root,
        resolve_path(repo_root, args.existing_product_wrapper_output) if args.existing_product_wrapper_output else None,
        failures,
        args.keep_going,
    )
    statement, _ = write_reference_statement(repo_root, output_root, f3_info, audit_files, product_wrapper_info)

    assert_condition(
        "F8 patch reference decision is pass without reduced scope",
        statement.get("decision") == "pass" and statement.get("allowed_drift") != "reduced_scope_accepted",
        json.dumps(statement, indent=2, sort_keys=True),
        failures,
        args.keep_going,
    )

    if failures:
        print("[F14][SUMMARY] {0} failure(s)".format(len(failures)))
        for failure in failures:
            print("[F14][FAILURE] {0}".format(failure["label"]))
            print("  cmd: {0}".format(" ".join(failure["cmd"])))
            print(failure["output"][-4000:])
        return 1

    write_manifest(output_root, statement, stage3_out, product_wrapper_info)
    print("[F14][SUMMARY] complete pre-redo gate passed")
    return 0


def main():
    return run_gate(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
