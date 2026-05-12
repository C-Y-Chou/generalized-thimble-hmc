#!/usr/bin/env python3
"""Validate the CV-005 script/evidence audit registry."""

import argparse
import csv
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


AUDIT_REL = Path("codex/workspaces/fortran_modernization/state/SCRIPT_EVIDENCE_AUDIT_20260512.tsv")
DEFAULT_OUTPUT_REL = Path("output/tests/script_evidence_audit")
AUDITED_ROOTS = (
    "scripts",
    "codex/tasks",
    "codex/workspaces/fortran_modernization/tasks",
)
REQUIRED_COLUMNS = (
    "path",
    "kind",
    "evidence_tier",
    "execution_surface",
    "python_floor",
    "claim_boundary",
    "audit_verdict",
    "notes",
)
EVIDENCE_TIERS = {
    "current_build",
    "current_control_plane",
    "current_evidence",
    "current_governance",
    "historical_reference",
    "analysis_only",
    "metadata_only",
}
EXECUTION_SURFACES = {
    "local",
    "remote_login",
    "remote_worker",
    "remote_worker_historical",
    "none",
}
AUDIT_VERDICTS = {
    "pass_current",
    "pass_governance",
    "pass_control_plane",
    "pass_analysis_only",
    "pass_metadata_only",
    "pass_historical_quarantined",
}
CURRENT_TIERS = {
    "current_build",
    "current_control_plane",
    "current_evidence",
    "current_governance",
}
LEGACY_REMOTE_TOKENS = (
    "/home/cychou/TLTM",
    "/lustre1/home/cychou/TLTM",
    "qn_error_handling_validation",
)
CANONICAL_REMOTE = "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization"


def parse_args():
    parser = argparse.ArgumentParser(description="Validate CV-005 script/evidence audit coverage.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument(
        "--audit",
        default=str(AUDIT_REL),
        help="Audit TSV path relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--output-root",
        default=str(DEFAULT_OUTPUT_REL),
        help="Manifest output root relative to repo root, or absolute.",
    )
    return parser.parse_args()


def resolve(repo_root, raw_path):
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return repo_root / path


def git_tracked(repo_root):
    cmd = ["git", "ls-files", "--cached", "--"] + list(AUDITED_ROOTS)
    output = subprocess.check_output(cmd, cwd=str(repo_root), universal_newlines=True)
    return sorted(line.strip() for line in output.splitlines() if line.strip())


def read_rows(path):
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != REQUIRED_COLUMNS:
            raise RuntimeError(
                "Unexpected audit TSV header in {0}: {1}".format(
                    path,
                    "\t".join(reader.fieldnames or []),
                )
            )
        return list(reader)


def file_text(repo_root, rel_path):
    return (repo_root / rel_path).read_text(encoding="utf-8", errors="replace")


def validate(repo_root, audit_path):
    failures = []
    tracked = git_tracked(repo_root)
    rows = read_rows(audit_path)
    by_path = {}

    for idx, row in enumerate(rows, start=2):
        path = row["path"]
        if not path:
            failures.append("row {0}: empty path".format(idx))
            continue
        if path in by_path:
            failures.append("duplicate audit path: {0}".format(path))
        by_path[path] = row

        if row["evidence_tier"] not in EVIDENCE_TIERS:
            failures.append("{0}: invalid evidence_tier={1}".format(path, row["evidence_tier"]))
        if row["execution_surface"] not in EXECUTION_SURFACES:
            failures.append("{0}: invalid execution_surface={1}".format(path, row["execution_surface"]))
        if row["audit_verdict"] not in AUDIT_VERDICTS:
            failures.append("{0}: invalid audit_verdict={1}".format(path, row["audit_verdict"]))
        if "\t" in row["notes"] or not row["notes"].strip():
            failures.append("{0}: notes must be non-empty and tab-free".format(path))

        rel_path = Path(path)
        if not (repo_root / rel_path).exists():
            failures.append("{0}: audited path does not exist".format(path))
            continue

        text = file_text(repo_root, rel_path)
        legacy_hits = [token for token in LEGACY_REMOTE_TOKENS if token in text and CANONICAL_REMOTE not in text]
        if legacy_hits and row["evidence_tier"] in CURRENT_TIERS:
            failures.append(
                "{0}: current-tier row contains legacy route token(s): {1}".format(
                    path,
                    ", ".join(legacy_hits),
                )
            )
        if row["evidence_tier"] == "historical_reference" and row["audit_verdict"] != "pass_historical_quarantined":
            failures.append("{0}: historical_reference must use pass_historical_quarantined".format(path))
        if row["evidence_tier"] in CURRENT_TIERS and row["audit_verdict"] == "pass_historical_quarantined":
            failures.append("{0}: current-tier row cannot be historical-quarantined".format(path))

    missing = [path for path in tracked if path not in by_path]
    extra = [path for path in by_path if path not in tracked]
    for path in missing:
        failures.append("missing audit row for tracked file: {0}".format(path))
    for path in extra:
        failures.append("audit row for untracked file: {0}".format(path))

    return {
        "status": "fail" if failures else "pass",
        "tracked_count": len(tracked),
        "audited_count": len(rows),
        "missing_count": len(missing),
        "extra_count": len(extra),
        "failures": failures,
    }


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    audit_path = resolve(repo_root, args.audit)
    output_root = resolve(repo_root, args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    result = validate(repo_root, audit_path)
    result["audit_path"] = str(audit_path)
    result["generated_at_utc"] = (
        datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )

    manifest = output_root / "CV005_script_evidence_audit_manifest.json"
    manifest.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("status={0}".format(result["status"]))
    print("tracked_count={0}".format(result["tracked_count"]))
    print("audited_count={0}".format(result["audited_count"]))
    print("manifest={0}".format(manifest))
    if result["failures"]:
        for failure in result["failures"][:80]:
            print("[CV005][FAIL] {0}".format(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
