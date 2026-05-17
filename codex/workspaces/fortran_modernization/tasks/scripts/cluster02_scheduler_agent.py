#!/usr/bin/env python3
"""Persistent scheduler utility for iTHEMS cluster02 TLTM work."""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Iterable, List, Optional


KNOWLEDGE_PATH = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json")
OBSERVATIONS_PATH = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_OBSERVATIONS.tsv")
SNAPSHOT_ROOT = Path("output/logs/fortran_modernization/cluster02_scheduler/snapshots")


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        universal_newlines=True,
        stdout=subprocess.PIPE,
    )
    return Path(result.stdout.strip()).resolve()


def run(args: List[str], *, cwd: Path, check: bool = True) -> str:
    result = subprocess.run(
        args,
        cwd=str(cwd),
        check=check,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0 and not check:
        return result.stdout + result.stderr
    return result.stdout.strip()


def load_knowledge(root: Path) -> Dict[str, object]:
    return json.loads((root / KNOWLEDGE_PATH).read_text(encoding="utf-8"))


def jst_now() -> str:
    jst = timezone(timedelta(hours=9))
    return datetime.now(jst).replace(microsecond=0).isoformat()


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def parse_state_count(value: str) -> Dict[str, int]:
    return {key: int(raw) for key, raw in re.findall(r"([A-Za-z]+):(\d+)", value)}


def parse_qstat_qf(text: str) -> Dict[str, Dict[str, object]]:
    queues: Dict[str, Dict[str, object]] = {}
    current: Optional[Dict[str, object]] = None
    for line in text.splitlines():
        if line.startswith("Queue: "):
            name = line.split(":", 1)[1].strip()
            current = {"name": name}
            queues[name] = current
            continue
        if current is None or " = " not in line:
            continue
        key, value = (part.strip() for part in line.split(" = ", 1))
        if key == "enabled":
            current["enabled"] = value.lower() == "true"
        elif key == "started":
            current["started"] = value.lower() == "true"
        elif key == "state_count":
            current["state_count"] = parse_state_count(value)
        elif key == "total_jobs":
            try:
                current["total_jobs"] = int(value)
            except ValueError:
                current["total_jobs"] = value
    return queues


def show_policy(root: Path) -> int:
    knowledge = load_knowledge(root)
    queue_policy = knowledge.get("queue_policy", {})
    if not isinstance(queue_policy, dict):
        raise RuntimeError("invalid queue_policy in scheduler knowledge")
    resource_model = knowledge.get("resource_model", {})
    candidates = queue_policy.get("default_cpu_candidates", [])
    excluded = queue_policy.get("excluded_by_default", {})
    print("cluster={}".format(knowledge.get("cluster", "unknown")))
    print("manual={}".format(knowledge.get("manual", {}).get("source", "unknown") if isinstance(knowledge.get("manual"), dict) else "unknown"))
    if isinstance(resource_model, dict):
        print("resource_model={}".format(resource_model.get("type", "unknown")))
        print("resource_principle={}".format(resource_model.get("principle", "unknown")))
    print("default_cpu_candidates={}".format(",".join(candidates) if isinstance(candidates, list) else candidates))
    print("excluded_by_default:")
    if isinstance(excluded, dict):
        for queue, reason in sorted(excluded.items()):
            print("  {}: {}".format(queue, reason))
    return 0


def snapshot(root: Path) -> int:
    text = run(["qstat", "-Qf"], cwd=root)
    SNAPSHOT_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = utc_stamp()
    raw_path = SNAPSHOT_ROOT / "qstat_Qf_{}.txt".format(stamp)
    json_path = SNAPSHOT_ROOT / "qstat_Qf_{}.json".format(stamp)
    raw_path.write_text(text + "\n", encoding="utf-8")
    parsed = parse_qstat_qf(text)
    json_path.write_text(json.dumps(parsed, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("snapshot_raw={}".format(raw_path))
    print("snapshot_json={}".format(json_path))
    return 0


def qstat_job(root: Path, job_id: str) -> Dict[str, str]:
    full_id = job_id if "." in job_id else "{}.anode01".format(job_id)
    text = run(["qstat", "-x", "-f", full_id], cwd=root, check=False)
    fields: Dict[str, str] = {"job_id": full_id}
    for line in text.splitlines():
        if " = " not in line:
            continue
        key, value = (part.strip() for part in line.split(" = ", 1))
        if key in {
            "Job_Name",
            "job_state",
            "queue",
            "exec_host",
            "Exit_status",
            "comment",
            "Resource_List.select",
            "Resource_List.walltime",
            "depend",
        }:
            fields[key] = value
    return fields


def check_jobs(root: Path, job_ids: Iterable[str]) -> int:
    for job_id in job_ids:
        fields = qstat_job(root, job_id)
        summary = [
            fields.get("job_id", job_id),
            fields.get("Job_Name", "NA"),
            fields.get("job_state", "NA"),
            fields.get("queue", "NA"),
            fields.get("Exit_status", "NA"),
            fields.get("exec_host", "NA"),
        ]
        print("\t".join(summary))
        comment = fields.get("comment")
        if comment:
            print("  comment={}".format(comment))
    return 0


def tsv_clean(value: Optional[str]) -> str:
    if value is None or value == "":
        return "NA"
    return str(value).replace("\t", " ").replace("\n", " ")


def record_observation(root: Path, args: argparse.Namespace) -> int:
    path = root / OBSERVATIONS_PATH
    line = "\t".join(
        [
            jst_now(),
            tsv_clean(args.queue),
            tsv_clean(args.resource_shape),
            tsv_clean(args.outcome),
            tsv_clean(args.exit_status),
            tsv_clean(args.node),
            tsv_clean(args.job_id),
            tsv_clean(args.action),
            tsv_clean(args.note),
        ]
    )
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")
    print("recorded={}".format(path))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Persistent cluster02 scheduler agent utility.")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("show-policy")
    subparsers.add_parser("snapshot")
    check_parser = subparsers.add_parser("check-jobs")
    check_parser.add_argument("job_ids", nargs="+")
    record_parser = subparsers.add_parser("record-observation")
    record_parser.add_argument("--queue", required=True)
    record_parser.add_argument("--resource-shape", required=True)
    record_parser.add_argument("--outcome", required=True)
    record_parser.add_argument("--exit-status", default="NA")
    record_parser.add_argument("--node", default="NA")
    record_parser.add_argument("--job-id", default="NA")
    record_parser.add_argument("--action", required=True)
    record_parser.add_argument("--note", required=True)
    args = parser.parse_args()
    if not args.command:
        parser.print_help(sys.stderr)
        return 2

    root = repo_root()
    os.chdir(str(root))
    if args.command == "show-policy":
        return show_policy(root)
    if args.command == "snapshot":
        return snapshot(root)
    if args.command == "check-jobs":
        return check_jobs(root, args.job_ids)
    if args.command == "record-observation":
        return record_observation(root, args)
    raise RuntimeError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())
