#!/usr/bin/env python3
"""Thin product-facing TLTM compatibility runner.

This wrapper intentionally delegates execution to the existing Stage3 multiseed
driver while enforcing the current product-surface package policy: v1 sidecars,
protocol audit, and the cleaned route/component identifiers.
"""

import argparse
import csv
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


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

METHOD_SETS = {
    "canonical_pair": "no_fb_fbnorefine",
    "nofb": "no_fb",
    "withfb": "fb_norefine",
    "legacy_stage3_pair": "both",
}
METHOD_ALIAS_SCHEMA = Path("codex/workspaces/fortran_modernization/schema/F7_METHOD_ALIASES_V1.json")
PRODUCT_PER_SEED_TABLE = "product_per_seed_summary_table.csv"
PRODUCT_AGGREGATED_TABLE = "product_aggregated_summary_table.csv"
RETIRED_PRODUCT_RAW_FIELDS = {
    "accepted_local_nonnear_route_count",
    "quasi_watchdog_hit_count",
    "quasi_watchdog_used_sum",
    "quasi_watchdog_used_max",
    "quasi_watchdog_budget_last",
    "total_accepted_local_nonnear_route_count",
    "total_quasi_watchdog_hit_count",
    "total_quasi_watchdog_used_sum",
    "total_quasi_watchdog_used_max",
    "total_quasi_watchdog_budget_last",
}
RETIRED_PRODUCT_RAW_PREFIXES = (
    "cvode_",
    "mean_cvode_",
    "total_cvode_",
)
RETIRED_PRODUCT_RAW_SUBSTRINGS = (
    "post_refine",
    "solver_assist",
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run the current TLTM product compatibility workflow through the Stage3 driver."
    )
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--config", required=True, help="Stage3 protocol JSON, relative to repo root or absolute.")
    parser.add_argument(
        "--method-set",
        choices=tuple(sorted(METHOD_SETS)),
        default=os.environ.get("TLTM_PRODUCT_METHOD_SET", "canonical_pair"),
        help="Product method set. canonical_pair maps to current nofb/withfb compatibility execution.",
    )
    parser.add_argument(
        "--stage3-methods",
        choices=("both", "no_fb_fbnorefine", "no_fb", "fb", "fb_norefine"),
        default="",
        help="Developer compatibility override for the delegated Stage3 method selector.",
    )
    parser.add_argument("--seed-offset", type=int, default=0, help="First selected seed offset.")
    parser.add_argument("--max-seeds", type=int, default=0, help="Maximum selected seeds; 0 means all selected seeds.")
    parser.add_argument("--jobs", type=int, default=1, help="Parallel Stage3 worker count.")
    parser.add_argument(
        "--stage2-threads",
        type=int,
        default=int(os.environ.get("TLTM_PRODUCT_STAGE2_THREADS", "1")),
        help="Thread budget for each run_tltm_stage2 process.",
    )
    parser.add_argument(
        "--eval-threads",
        type=int,
        default=int(os.environ.get("TLTM_PRODUCT_EVAL_THREADS", "1")),
        help="Thread budget for each evaluate_expectations process.",
    )
    parser.add_argument(
        "--schedule",
        choices=("paired", "task"),
        default=os.environ.get("TLTM_PRODUCT_SCHEDULE", "paired"),
        help="Delegated Stage3 scheduling policy.",
    )
    parser.add_argument(
        "--pair-order",
        choices=("alternating", "no_fb_first", "fb_first"),
        default=os.environ.get("TLTM_PRODUCT_PAIR_ORDER", "alternating"),
        help="Delegated paired-schedule method order.",
    )
    parser.add_argument(
        "--task-method-order",
        choices=("no_fb_first", "fb_first"),
        default=os.environ.get("TLTM_PRODUCT_TASK_METHOD_ORDER", "no_fb_first"),
        help="Delegated task-schedule method order.",
    )
    parser.add_argument(
        "--output-subdir",
        default=os.environ.get("TLTM_PRODUCT_OUTPUT_SUBDIR", "output/product/tltm_run"),
        help="Output directory relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--logs-subdir",
        default=os.environ.get("TLTM_PRODUCT_LOGS_SUBDIR", "output/logs/tltm_product"),
        help="Log directory relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--log-prefix",
        default=os.environ.get("TLTM_PRODUCT_LOG_PREFIX", "tltm_product"),
        help="Prefix used in delegated Stage2/evaluation log filenames.",
    )
    parser.add_argument(
        "--report-title",
        default=os.environ.get("TLTM_PRODUCT_REPORT_TITLE", "TLTM Product Compatibility Run"),
        help="Markdown report title.",
    )
    parser.add_argument("--skip-build", action="store_true", help="Pass --skip-build to the Stage3 driver.")
    parser.add_argument("--dry-run", action="store_true", help="Print the delegated Stage3 plan without executing.")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate an existing product wrapper output directory without launching Stage3.",
    )
    parser.add_argument(
        "--allow-oversubscribe",
        action="store_true",
        help="Pass --allow-oversubscribe to the Stage3 driver.",
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


def selected_stage3_methods(args):
    if args.stage3_methods:
        return args.stage3_methods
    return METHOD_SETS[args.method_set]


def build_stage3_command(repo_root, args, stage3_methods):
    cmd = [
        sys.executable,
        str(repo_root / "scripts" / "run_stage3_3_multiseed.py"),
        "--repo-root",
        str(repo_root),
        "--config",
        str(args.config),
        "--methods",
        stage3_methods,
        "--seed-offset",
        str(args.seed_offset),
        "--max-seeds",
        str(args.max_seeds),
        "--jobs",
        str(args.jobs),
        "--stage2-threads",
        str(args.stage2_threads),
        "--eval-threads",
        str(args.eval_threads),
        "--schedule",
        args.schedule,
        "--pair-order",
        args.pair_order,
        "--task-method-order",
        args.task_method_order,
        "--output-subdir",
        args.output_subdir,
        "--logs-subdir",
        args.logs_subdir,
        "--log-prefix",
        args.log_prefix,
        "--report-title",
        args.report_title,
        "--stage2-v1-sidecars",
        "on",
        "--stage2-protocol-audit",
        "auto",
        "--stage2-protocol-audit-fail-on",
        "error",
    ]
    if args.skip_build:
        cmd.append("--skip-build")
    if args.dry_run:
        cmd.append("--dry-run")
    if args.allow_oversubscribe:
        cmd.append("--allow-oversubscribe")
    return cmd


def read_csv_rows(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv_rows(path, fieldnames, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def load_method_aliases(repo_root):
    schema_path = repo_root / METHOD_ALIAS_SCHEMA
    data = json.loads(schema_path.read_text(encoding="utf-8"))
    mapping = {}
    for canonical, spec in data.get("canonical_methods", {}).items():
        mapping[canonical] = canonical
        for alias in spec.get("raw_aliases", []):
            mapping[alias] = canonical
    return mapping


def is_product_raw_field_retired(key):
    if key in RETIRED_PRODUCT_RAW_FIELDS:
        return True
    if any(key.startswith(prefix) for prefix in RETIRED_PRODUCT_RAW_PREFIXES):
        return True
    if any(fragment in key for fragment in RETIRED_PRODUCT_RAW_SUBSTRINGS):
        return True
    return False


def collect_fieldnames(rows):
    fieldnames = []
    seen = set()
    for row in rows:
        for key in row:
            if key not in seen:
                seen.add(key)
                fieldnames.append(key)
    return fieldnames


def productize_rows(rows, alias_map):
    product_rows = []
    unknown = []
    excluded = set()
    for row in rows:
        raw_method = row.get("method", "")
        product_method = alias_map.get(raw_method, "")
        if not product_method:
            unknown.append(raw_method)
            product_method = raw_method
        product_row = {"product_method": product_method, "raw_method": raw_method}
        product_row.update(PRODUCT_IDS)
        for key, value in row.items():
            if key == "method":
                continue
            if is_product_raw_field_retired(key):
                excluded.add(key)
                continue
            product_row[key] = value
        product_rows.append(product_row)
    return product_rows, sorted(set(unknown)), sorted(excluded)


def write_product_tables(repo_root, output_dir):
    alias_map = load_method_aliases(repo_root)
    generated = {}
    unknown_methods = []
    excluded_raw_fields = set()
    for source_name, target_name in (
        ("per_seed_summary_table.csv", PRODUCT_PER_SEED_TABLE),
        ("aggregated_summary_table.csv", PRODUCT_AGGREGATED_TABLE),
    ):
        source_path = output_dir / source_name
        target_path = output_dir / target_name
        rows = read_csv_rows(source_path)
        product_rows, unknown, excluded = productize_rows(rows, alias_map)
        unknown_methods.extend(unknown)
        excluded_raw_fields.update(excluded)
        if product_rows:
            fieldnames = collect_fieldnames(product_rows)
        else:
            fieldnames = ["product_method", "raw_method"] + list(PRODUCT_IDS.keys())
        write_csv_rows(target_path, fieldnames, product_rows)
        generated[target_name] = relpath_text(repo_root, target_path)
    return {
        "status": "pass" if not unknown_methods else "warning",
        "generated": generated,
        "unknown_raw_methods": sorted(set(unknown_methods)),
        "excluded_raw_fields": sorted(excluded_raw_fields),
    }


def validate_stage3_product_output(repo_root, output_dir):
    errors = []
    per_seed_csv = output_dir / "per_seed_summary_table.csv"
    aggregate_csv = output_dir / "aggregated_summary_table.csv"
    protocol_audit_csv = output_dir / "protocol_audit_summary.csv"

    for label, path in (
        ("per_seed_summary_table", per_seed_csv),
        ("aggregated_summary_table", aggregate_csv),
        ("protocol_audit_summary", protocol_audit_csv),
    ):
        if not path.exists():
            errors.append("{0} missing: {1}".format(label, path))

    rows = []
    if per_seed_csv.exists():
        rows = read_csv_rows(per_seed_csv)
        if not rows:
            errors.append("per_seed_summary_table has no rows: {0}".format(per_seed_csv))

    for idx, row in enumerate(rows, start=2):
        row_id = "row {0} method={1} seed={2}".format(idx, row.get("method", ""), row.get("seed_id", ""))
        if row.get("stage2_v1_sidecar_enabled") != "1":
            errors.append("{0}: stage2_v1_sidecar_enabled != 1".format(row_id))
        if row.get("stage2_protocol_audit_verdict") != "pass":
            errors.append("{0}: stage2_protocol_audit_verdict != pass".format(row_id))
        for field_name in (
            "stage2_v1_manifest_file",
            "stage2_v1_protocol_file",
            "stage2_v1_resolved_config_file",
        ):
            field_text = row.get(field_name, "")
            if not field_text:
                errors.append("{0}: {1} is missing".format(row_id, field_name))
                continue
            field_path = resolve_path(repo_root, field_text)
            if not field_path.exists():
                errors.append("{0}: {1} does not exist: {2}".format(row_id, field_name, field_text))
                continue
            if field_name == "stage2_v1_resolved_config_file":
                try:
                    config_data = json.loads(field_path.read_text(encoding="utf-8"))
                except ValueError as exc:
                    errors.append("{0}: resolved config is not valid JSON: {1}".format(row_id, exc))
                    continue
                if config_data.get("schema_version") != "tltm.stage2.config.resolved.v1alpha1":
                    errors.append("{0}: resolved config schema_version mismatch".format(row_id))
                if config_data.get("precision", {}).get("precision_policy_id") != "double_strict_v1":
                    errors.append("{0}: resolved config precision_policy_id mismatch".format(row_id))

    return {
        "status": "fail" if errors else "pass",
        "row_count": len(rows),
        "errors": errors,
        "checked_files": {
            "per_seed_summary_table": relpath_text(repo_root, per_seed_csv),
            "aggregated_summary_table": relpath_text(repo_root, aggregate_csv),
            "protocol_audit_summary": relpath_text(repo_root, protocol_audit_csv),
        },
    }


def write_wrapper_manifest(repo_root, args, stage3_methods, stage3_cmd, validation_result):
    out_dir = resolve_path(repo_root, args.output_subdir)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = out_dir / "product_wrapper_manifest.json"
    product_tables = {}
    if validation_result.get("status") == "pass":
        product_tables = write_product_tables(repo_root, out_dir)
    manifest = {
        "schema_version": "tltm.product.wrapper.v1alpha1",
        "writer_version": "product_compat_wrapper_2026-05-17",
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "repo_root": str(repo_root),
        "config": str(args.config),
        "method_set": args.method_set,
        "stage3_methods": stage3_methods,
        "output_subdir": args.output_subdir,
        "logs_subdir": args.logs_subdir,
        "stage3_command": stage3_cmd,
        "validation": validation_result,
        "product_tables": product_tables,
        "enforced_policy": {
            "stage2_v1_sidecars": "on",
            "stage2_protocol_audit": "auto",
            "stage2_protocol_audit_fail_on": "error",
            "raw_stage_scripts_status": "developer_compatibility_entry_points",
        },
        "product_ids": PRODUCT_IDS,
        "expected_outputs": {
            "per_seed_summary_table": relpath_text(repo_root, out_dir / "per_seed_summary_table.csv"),
            "aggregated_summary_table": relpath_text(repo_root, out_dir / "aggregated_summary_table.csv"),
            "product_per_seed_summary_table": relpath_text(repo_root, out_dir / PRODUCT_PER_SEED_TABLE),
            "product_aggregated_summary_table": relpath_text(repo_root, out_dir / PRODUCT_AGGREGATED_TABLE),
            "protocol_audit_summary": relpath_text(repo_root, out_dir / "protocol_audit_summary.csv"),
        },
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest_path


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    stage3_methods = selected_stage3_methods(args)
    stage3_cmd = build_stage3_command(repo_root, args, stage3_methods)
    out_dir = resolve_path(repo_root, args.output_subdir)

    if args.validate_only:
        validation_result = validate_stage3_product_output(repo_root, out_dir)
        manifest_path = write_wrapper_manifest(repo_root, args, stage3_methods, stage3_cmd, validation_result)
        print("[TLTM-PRODUCT] validate-only status={0}".format(validation_result["status"]))
        print("[TLTM-PRODUCT] manifest={0}".format(relpath_text(repo_root, manifest_path)))
        for error in validation_result["errors"][:40]:
            print("[TLTM-PRODUCT][FAIL] {0}".format(error), file=sys.stderr)
        return 0 if validation_result["status"] == "pass" else 1

    print("[TLTM-PRODUCT] delegated Stage3 command:")
    print(" ".join(stage3_cmd), flush=True)
    returncode = subprocess.call(stage3_cmd, cwd=str(repo_root))
    if returncode != 0:
        return returncode

    if args.dry_run:
        return 0

    validation_result = validate_stage3_product_output(repo_root, out_dir)
    manifest_path = write_wrapper_manifest(repo_root, args, stage3_methods, stage3_cmd, validation_result)
    print("[TLTM-PRODUCT] manifest={0}".format(relpath_text(repo_root, manifest_path)))
    for error in validation_result["errors"][:40]:
        print("[TLTM-PRODUCT][FAIL] {0}".format(error), file=sys.stderr)
    return 0 if validation_result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
