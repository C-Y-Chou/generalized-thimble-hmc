#!/usr/bin/env python3
"""Persistent scheduler utility for iTHEMS cluster02 TLTM work."""

import argparse
import csv
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Iterable, List, Optional


KNOWLEDGE_PATH = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json")
OBSERVATIONS_PATH = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_OBSERVATIONS.tsv")
NODE_INVENTORY_JSON = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_NODE_INVENTORY.json")
NODE_INVENTORY_CSV = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_NODE_INVENTORY.csv")
QUEUE_NODE_MATRIX_CSV = Path("codex/workspaces/fortran_modernization/state/CLUSTER02_QUEUE_NODE_MATRIX.csv")
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
        elif (
            key.startswith("resources_max.")
            or key.startswith("resources_default.")
            or key.startswith("resources_min.")
            or key.startswith("default_chunk.")
            or key.startswith("resources_assigned.")
            or key.startswith("max_run_res.")
        ):
            current[key] = value
        elif key in {"queue_type", "Priority", "max_running", "max_user_run", "from_route_only"}:
            current[key] = value
    return queues


def parse_pbsnodes(text: str) -> Dict[str, Dict[str, object]]:
    nodes: Dict[str, Dict[str, object]] = {}
    current_name: Optional[str] = None
    current: Optional[Dict[str, object]] = None
    current_key: Optional[str] = None
    for raw_line in text.splitlines():
        if not raw_line.strip():
            continue
        if raw_line and not raw_line[0].isspace():
            current_name = raw_line.strip()
            current = {"name": current_name}
            nodes[current_name] = current
            current_key = None
            continue
        if current is None:
            continue
        line = raw_line.strip()
        if " = " in line:
            key, value = (part.strip() for part in line.split(" = ", 1))
            current[key] = value
            current_key = key
        elif current_key:
            current[current_key] = "{} {}".format(current[current_key], line)
    return nodes


def parse_lscpu(text: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key in {
            "Architecture",
            "CPU(s)",
            "Thread(s) per core",
            "Core(s) per socket",
            "Socket(s)",
            "NUMA node(s)",
            "Vendor ID",
            "Model name",
            "CPU family",
            "Model",
            "Stepping",
            "CPU MHz",
            "CPU max MHz",
            "CPU min MHz",
            "L1d cache",
            "L1i cache",
            "L2 cache",
            "L3 cache",
        }:
            result[key] = value
    return result


def parse_probe_output(text: str) -> Dict[str, object]:
    info: Dict[str, object] = {}
    lscpu_lines: List[str] = []
    in_lscpu = False
    for line in text.splitlines():
        if line == "__LSCPU_BEGIN__":
            in_lscpu = True
            continue
        if line == "__LSCPU_END__":
            in_lscpu = False
            continue
        if in_lscpu:
            lscpu_lines.append(line)
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            info[key.strip()] = value.strip()
    info["lscpu"] = parse_lscpu("\n".join(lscpu_lines))
    return info


def probe_node(node: str, timeout: int) -> Dict[str, object]:
    remote_script = r"""
set -u
echo "probe_hostname=$(hostname 2>/dev/null || echo NA)"
echo "probe_date=$(date -Iseconds 2>/dev/null || date 2>/dev/null || echo NA)"
echo "nproc=$(nproc 2>/dev/null || echo NA)"
echo "mem_total_kb=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo NA)"
echo "cpu_model=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo NA)"
echo "cpu_mhz_sample=$(awk -F': ' '/cpu MHz/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo NA)"
echo "git_path=$(command -v git 2>/dev/null || echo MISSING)"
echo "gfortran_path=$(command -v gfortran 2>/dev/null || echo MISSING)"
echo "ifx_path=$(command -v ifx 2>/dev/null || echo MISSING)"
echo "python3_path=$(command -v python3 2>/dev/null || echo MISSING)"
echo "loadavg=$(cat /proc/loadavg 2>/dev/null || echo NA)"
echo "__LSCPU_BEGIN__"
lscpu 2>/dev/null || true
echo "__LSCPU_END__"
"""
    try:
        text = run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout={}".format(timeout),
                node,
                remote_script,
            ],
            cwd=Path.cwd(),
            check=False,
        )
        info = parse_probe_output(text)
        info["ssh_ok"] = bool(info.get("probe_hostname"))
        info["ssh_error"] = "" if info["ssh_ok"] else text.strip()[:500]
        return info
    except Exception as exc:  # pragma: no cover - defensive for cluster heterogeneity
        return {"ssh_ok": False, "ssh_error": str(exc)[:500]}


def split_csv_field(value: object) -> List[str]:
    if not isinstance(value, str) or not value.strip():
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def queue_hard_limit(queue: Dict[str, object], key: str) -> str:
    raw = queue.get(key)
    return str(raw) if raw is not None else ""


def parse_int(value: object, default: int = 0) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return default


def parse_walltime_seconds(value: object) -> Optional[int]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    parts = text.split(":")
    try:
        if len(parts) == 3:
            hours, minutes, seconds = (int(part) for part in parts)
            return hours * 3600 + minutes * 60 + seconds
        if len(parts) == 2:
            minutes, seconds = (int(part) for part in parts)
            return minutes * 60 + seconds
        return int(text)
    except ValueError:
        return None


def parse_user_nodect_cap(value: object) -> Optional[int]:
    """Extract PBS max_run_res.nodect per-user cap, if present.

    cluster02 reports values such as ``[u:PBS_GENERIC=4]``.  For our one-node
    chunk jobs, this is the effective queue-level concurrent job cap for the
    user, even when each physical node can pack multiple chunks.
    """
    if value is None:
        return None
    match = re.search(r"\[u:[^=\]]+=(\d+)\]", str(value))
    if not match:
        return None
    return int(match.group(1))


def shell_quote(value: object) -> str:
    return shlex.quote(str(value))


def git_value(root: Path, args: List[str]) -> str:
    return run(["git"] + args, cwd=root)


def git_status_text(root: Path) -> str:
    return run(["git", "status", "--short"], cwd=root, check=False)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def source_manifest(root: Path) -> List[str]:
    excluded_dirs = {
        ".git",
        ".deps",
        ".cluster_deps",
        ".venv",
        ".venv-dfols",
        ".venv-dfols-py36",
        "__pycache__",
        ".pytest_cache",
        ".obj",
        "output",
    }
    excluded_suffixes = {".o", ".mod", ".smod", ".pyc"}
    lines: List[str] = []
    for dirpath, dirnames, filenames in os.walk(str(root)):
        rel_dir = Path(dirpath).relative_to(root)
        dirnames[:] = [name for name in dirnames if name not in excluded_dirs]
        for filename in sorted(filenames):
            path = Path(dirpath) / filename
            rel = path.relative_to(root)
            if any(part in excluded_dirs for part in rel.parts):
                continue
            if path.suffix in excluded_suffixes:
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue
            digest = hashlib.sha256(data).hexdigest()
            lines.append("{}\t{}\t{}".format(rel.as_posix(), len(data), digest))
    lines.sort()
    return lines


def write_source_pin_file(root: Path, output_path: Path, *, allow_dirty: bool, snapshot_root: Optional[Path]) -> Dict[str, object]:
    branch = git_value(root, ["rev-parse", "--abbrev-ref", "HEAD"])
    commit = git_value(root, ["rev-parse", "HEAD"])
    status = git_status_text(root)
    dirty_lines = [line for line in status.splitlines() if line.strip()]
    if dirty_lines and not allow_dirty:
        raise RuntimeError("worktree is dirty; pass --allow-dirty only for an explicit snapshot/pin workflow")
    status_sha = sha256_text(status)
    manifest_lines = source_manifest(root)
    manifest_text = "\n".join(manifest_lines) + ("\n" if manifest_lines else "")
    manifest_sha = sha256_text(manifest_text)
    pin_id = "{}-{}".format(commit[:12], manifest_sha[:12])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    status_path = output_path.with_suffix(output_path.suffix + ".git_status_short")
    status_path.write_text(status + ("\n" if status and not status.endswith("\n") else ""), encoding="utf-8")
    manifest_path = output_path.with_suffix(output_path.suffix + ".source_manifest.tsv")
    manifest_path.write_text(manifest_text, encoding="utf-8")
    values = {
        "TLTM_SOURCE_PIN_SCHEMA": "1",
        "TLTM_SOURCE_PIN_CREATED_AT_JST": jst_now(),
        "TLTM_SOURCE_PIN_ID": pin_id,
        "TLTM_SOURCE_PIN_WORKTREE": str(root),
        "TLTM_SOURCE_PIN_SNAPSHOT_ROOT": str(snapshot_root) if snapshot_root is not None else "",
        "TLTM_SOURCE_PIN_BRANCH": branch,
        "TLTM_SOURCE_PIN_COMMIT": commit,
        "TLTM_SOURCE_PIN_DIRTY_COUNT": len(dirty_lines),
        "TLTM_SOURCE_PIN_STATUS_SHA256": status_sha,
        "TLTM_SOURCE_PIN_STATUS_PATH": str(status_path),
        "TLTM_SOURCE_PIN_MANIFEST_SHA256": manifest_sha,
        "TLTM_SOURCE_PIN_MANIFEST_PATH": str(manifest_path),
        "TLTM_SOURCE_PIN_MANIFEST_ROWS": len(manifest_lines),
        "TLTM_SOURCE_PIN_DIRTY_ALLOWED": int(bool(allow_dirty)),
    }
    lines = ["# Generated by cluster02_scheduler_agent.py source-pin; safe to source from PBS.\n"]
    for key in sorted(values):
        lines.append("{}={}\n".format(key, shell_quote(values[key])))
    output_path.write_text("".join(lines), encoding="utf-8")
    return values


def source_pin(root: Path, args: argparse.Namespace) -> int:
    output = root / Path(args.output)
    values = write_source_pin_file(root, output, allow_dirty=args.allow_dirty, snapshot_root=None)
    print("source_pin={}".format(output))
    print("source_pin_id={}".format(values["TLTM_SOURCE_PIN_ID"]))
    print("commit={}".format(values["TLTM_SOURCE_PIN_COMMIT"]))
    print("dirty_count={}".format(values["TLTM_SOURCE_PIN_DIRTY_COUNT"]))
    return 0


def runtime_snapshot(root: Path, args: argparse.Namespace) -> int:
    snapshot_root = Path(args.snapshot_root).expanduser()
    if not snapshot_root.is_absolute():
        snapshot_root = (root / snapshot_root).resolve()
    if snapshot_root == root:
        raise RuntimeError("snapshot root must differ from current worktree")
    snapshot_root.parent.mkdir(parents=True, exist_ok=True)
    excludes = [
        "--exclude=.git",
        "--exclude=.cluster_deps",
        "--exclude=.venv-dfols-py36",
        "--exclude=output",
        "--exclude=build/.obj",
        "--exclude=*.o",
        "--exclude=*.mod",
        "--exclude=*.smod",
        "--exclude=.pytest_cache",
        "--exclude=__pycache__",
    ]
    if args.delete:
        rsync_args = ["rsync", "-a", "--delete"] + excludes + [str(root) + "/", str(snapshot_root) + "/"]
    else:
        rsync_args = ["rsync", "-a"] + excludes + [str(root) + "/", str(snapshot_root) + "/"]
    print("rsync_target={}".format(snapshot_root))
    run(rsync_args, cwd=root)
    pin_rel = Path(args.pin_relpath)
    pin_path = snapshot_root / pin_rel
    values = write_source_pin_file(root, pin_path, allow_dirty=args.allow_dirty, snapshot_root=snapshot_root)
    print("runtime_snapshot={}".format(snapshot_root))
    print("source_pin={}".format(pin_path))
    print("source_pin_id={}".format(values["TLTM_SOURCE_PIN_ID"]))
    print("commit={}".format(values["TLTM_SOURCE_PIN_COMMIT"]))
    print("dirty_count={}".format(values["TLTM_SOURCE_PIN_DIRTY_COUNT"]))
    return 0


def cpu_speed_prior(model: object) -> float:
    text = str(model).upper()
    if "6542Y" in text:
        return 2.6
    if "6342" in text:
        return 1.9
    if "6242R" in text:
        return 1.6
    if "6142" in text:
        return 1.0
    return 0.5


def rank_queues(root: Path, args: argparse.Namespace) -> int:
    knowledge = load_knowledge(root)
    inventory_path = root / NODE_INVENTORY_JSON
    if not inventory_path.exists():
        raise RuntimeError("missing {}; run inventory first".format(inventory_path))
    inventory_data = json.loads(inventory_path.read_text(encoding="utf-8"))
    rows = inventory_data.get("derived_rows", [])
    queues = inventory_data.get("queues", {})
    if not isinstance(rows, list) or not isinstance(queues, dict):
        raise RuntimeError("invalid inventory schema in {}".format(inventory_path))

    queue_policy = knowledge.get("queue_policy", {})
    excluded = queue_policy.get("excluded_by_default", {}) if isinstance(queue_policy, dict) else {}
    penalties = queue_policy.get("queue_penalty_overrides", {}) if isinstance(queue_policy, dict) else {}
    requested_wall = parse_walltime_seconds(args.walltime)
    results: List[Dict[str, object]] = []
    by_queue: Dict[str, List[Dict[str, object]]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        for queue in split_csv_field(row.get("qlist")):
            by_queue.setdefault(queue, []).append(row)

    for queue, qrows in sorted(by_queue.items()):
        qinfo = queues.get(queue, {})
        reasons: List[str] = []
        enabled = bool(qinfo.get("enabled", False)) if isinstance(qinfo, dict) else False
        started = bool(qinfo.get("started", False)) if isinstance(qinfo, dict) else False
        if not enabled or not started:
            reasons.append("queue_not_enabled_started")
        if args.cpu_only and queue.startswith("G") and not args.allow_gpu:
            reasons.append("gpu_queue_for_cpu_job")
        if isinstance(excluded, dict) and queue in excluded and not args.allow_excluded:
            reasons.append("excluded_by_policy:{}".format(excluded[queue]))
        max_wall = parse_walltime_seconds(qinfo.get("resources_max.walltime")) if isinstance(qinfo, dict) else None
        if requested_wall is not None and max_wall is not None and requested_wall > max_wall:
            reasons.append("walltime_exceeds_queue_max")

        compatible: List[Dict[str, object]] = []
        incompatible_count = 0
        for row in qrows:
            node_reasons = []
            if parse_int(row.get("pbs_ncpus")) < args.ncpus:
                node_reasons.append("insufficient_ncpus")
            if args.require_git and row.get("git_path") == "MISSING":
                node_reasons.append("missing_git_for_current_pbs_guard")
            if args.require_ssh and str(row.get("ssh_ok")) != "True":
                node_reasons.append("ssh_probe_failed")
            if node_reasons:
                incompatible_count += 1
            else:
                compatible.append(row)
        if not compatible:
            reasons.append("no_compatible_nodes")
        if incompatible_count and not args.allow_placement_risk:
            reasons.append("mixed_node_compatibility_requires_placement_or_gitless_guard")

        state_count = qinfo.get("state_count", {}) if isinstance(qinfo, dict) else {}
        queued = parse_int(state_count.get("Queued", 0)) if isinstance(state_count, dict) else 0
        waiting = parse_int(state_count.get("Waiting", 0)) if isinstance(state_count, dict) else 0
        held = parse_int(state_count.get("Held", 0)) if isinstance(state_count, dict) else 0
        running = parse_int(state_count.get("Running", 0)) if isinstance(state_count, dict) else 0
        penalty = float(penalties.get(queue, 0)) if isinstance(penalties, dict) else 0.0
        speeds = [cpu_speed_prior(row.get("cpu_model")) for row in compatible]
        best_speed = max(speeds) if speeds else 0.0
        median_speed = sorted(speeds)[len(speeds) // 2] if speeds else 0.0
        free_capacity = sum(max(0, parse_int(row.get("pbs_ncpus")) - parse_int(row.get("assigned_ncpus"))) for row in compatible)
        jobs_per_node = [parse_int(row.get("pbs_ncpus")) // args.ncpus for row in compatible if args.ncpus > 0]
        free_jobs_by_ncpus = sum(
            max(0, (parse_int(row.get("pbs_ncpus")) - parse_int(row.get("assigned_ncpus"))) // args.ncpus)
            for row in compatible
            if args.ncpus > 0
        )
        max_jobs_by_ncpus = sum(jobs_per_node)
        user_nodect_cap = parse_user_nodect_cap(qinfo.get("max_run_res.nodect")) if isinstance(qinfo, dict) else None
        cap_remaining = "" if user_nodect_cap is None else max(0, user_nodect_cap - running)
        schedulable_jobs_now = free_jobs_by_ncpus if user_nodect_cap is None else min(free_jobs_by_ncpus, max(0, user_nodect_cap - running))
        score = 100.0 * median_speed + 25.0 * best_speed + min(free_capacity, args.ncpus * 4)
        score -= 12.0 * queued + 16.0 * waiting + 20.0 * held + 2.0 * running + penalty
        if reasons:
            score -= 10000.0
        results.append(
            {
                "queue": queue,
                "score": round(score, 3),
                "eligible": not reasons,
                "reasons": ";".join(reasons),
                "node_count": len(qrows),
                "compatible_node_count": len(compatible),
                "incompatible_node_count": incompatible_count,
                "best_speed_prior": best_speed,
                "median_speed_prior": median_speed,
                "free_capacity_ncpus": free_capacity,
                "jobs_per_node_min": min(jobs_per_node) if jobs_per_node else 0,
                "jobs_per_node_max": max(jobs_per_node) if jobs_per_node else 0,
                "max_jobs_by_ncpus": max_jobs_by_ncpus,
                "free_jobs_by_ncpus": free_jobs_by_ncpus,
                "user_nodect_cap": "" if user_nodect_cap is None else user_nodect_cap,
                "user_cap_remaining": cap_remaining,
                "schedulable_jobs_now": schedulable_jobs_now,
                "queued": queued,
                "waiting": waiting,
                "held": held,
                "running": running,
                "models": ",".join(sorted(set(str(row.get("cpu_model", "")) for row in qrows))),
                "compatible_nodes": ",".join(row.get("node", "") for row in compatible),
            }
        )

    results.sort(key=lambda row: (not bool(row["eligible"]), -float(row["score"]), str(row["queue"])))
    fieldnames = [
        "queue",
        "score",
        "eligible",
        "reasons",
        "node_count",
        "compatible_node_count",
        "incompatible_node_count",
        "best_speed_prior",
        "median_speed_prior",
        "free_capacity_ncpus",
        "jobs_per_node_min",
        "jobs_per_node_max",
        "max_jobs_by_ncpus",
        "free_jobs_by_ncpus",
        "user_nodect_cap",
        "user_cap_remaining",
        "schedulable_jobs_now",
        "queued",
        "waiting",
        "held",
        "running",
        "models",
        "compatible_nodes",
    ]
    if args.output_csv:
        write_csv(root / Path(args.output_csv), results, fieldnames)
        print("ranking_csv={}".format(root / Path(args.output_csv)))
    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    for row in results:
        writer.writerow(row)
    return 0


def build_inventory_rows(
    pbs_nodes: Dict[str, Dict[str, object]],
    probes: Dict[str, Dict[str, object]],
) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for name in sorted(pbs_nodes):
        node = pbs_nodes[name]
        probe = probes.get(name, {})
        lscpu = probe.get("lscpu", {}) if isinstance(probe.get("lscpu"), dict) else {}
        qlist = split_csv_field(node.get("resources_available.Qlist", ""))
        rows.append(
            {
                "node": name,
                "state": node.get("state", ""),
                "qlist": ",".join(qlist),
                "pbs_ncpus": node.get("resources_available.ncpus", ""),
                "pbs_mem": node.get("resources_available.mem", ""),
                "assigned_ncpus": node.get("resources_assigned.ncpus", ""),
                "assigned_mem": node.get("resources_assigned.mem", ""),
                "jobs": node.get("jobs", ""),
                "host": node.get("resources_available.host", ""),
                "ssh_ok": probe.get("ssh_ok", False),
                "hostname": probe.get("probe_hostname", ""),
                "nproc": probe.get("nproc", ""),
                "mem_total_kb": probe.get("mem_total_kb", ""),
                "cpu_model": probe.get("cpu_model") or lscpu.get("Model name", ""),
                "cpu_mhz_sample": probe.get("cpu_mhz_sample") or lscpu.get("CPU MHz", ""),
                "lscpu_cpu_max_mhz": lscpu.get("CPU max MHz", ""),
                "lscpu_threads_per_core": lscpu.get("Thread(s) per core", ""),
                "lscpu_cores_per_socket": lscpu.get("Core(s) per socket", ""),
                "lscpu_sockets": lscpu.get("Socket(s)", ""),
                "lscpu_l3_cache": lscpu.get("L3 cache", ""),
                "git_path": probe.get("git_path", ""),
                "gfortran_path": probe.get("gfortran_path", ""),
                "ifx_path": probe.get("ifx_path", ""),
                "python3_path": probe.get("python3_path", ""),
                "loadavg": probe.get("loadavg", ""),
                "ssh_error": probe.get("ssh_error", ""),
            }
        )
    return rows


def write_csv(path: Path, rows: List[Dict[str, object]], fieldnames: List[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_queue_node_matrix(
    path: Path,
    queues: Dict[str, Dict[str, object]],
    inventory_rows: List[Dict[str, object]],
) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for inv in inventory_rows:
        qlist = split_csv_field(inv.get("qlist"))
        for queue in qlist:
            qinfo = queues.get(queue, {})
            rows.append(
                {
                    "queue": queue,
                    "node": inv.get("node", ""),
                    "node_state": inv.get("state", ""),
                    "enabled": qinfo.get("enabled", ""),
                    "started": qinfo.get("started", ""),
                    "state_count": json.dumps(qinfo.get("state_count", {}), sort_keys=True),
                    "pbs_ncpus": inv.get("pbs_ncpus", ""),
                    "nproc": inv.get("nproc", ""),
                    "cpu_model": inv.get("cpu_model", ""),
                    "cpu_mhz_sample": inv.get("cpu_mhz_sample", ""),
                    "lscpu_cpu_max_mhz": inv.get("lscpu_cpu_max_mhz", ""),
                    "mem_total_kb": inv.get("mem_total_kb", ""),
                    "git_path": inv.get("git_path", ""),
                    "ssh_ok": inv.get("ssh_ok", ""),
                    "assigned_ncpus": inv.get("assigned_ncpus", ""),
                }
            )
    write_csv(
        path,
        rows,
        [
            "queue",
            "node",
            "node_state",
            "enabled",
            "started",
            "state_count",
            "pbs_ncpus",
            "nproc",
            "cpu_model",
            "cpu_mhz_sample",
            "lscpu_cpu_max_mhz",
            "mem_total_kb",
            "git_path",
            "ssh_ok",
            "assigned_ncpus",
        ],
    )
    return rows


def inventory(root: Path, args: argparse.Namespace) -> int:
    stamp = utc_stamp()
    SNAPSHOT_ROOT.mkdir(parents=True, exist_ok=True)
    pbsnodes_text = run(["pbsnodes", "-a"], cwd=root)
    qstat_text = run(["qstat", "-Qf"], cwd=root)
    (SNAPSHOT_ROOT / "pbsnodes_a_{}.txt".format(stamp)).write_text(pbsnodes_text + "\n", encoding="utf-8")
    (SNAPSHOT_ROOT / "qstat_Qf_inventory_{}.txt".format(stamp)).write_text(qstat_text + "\n", encoding="utf-8")
    pbs_nodes = parse_pbsnodes(pbsnodes_text)
    queues = parse_qstat_qf(qstat_text)
    node_names = sorted(pbs_nodes)
    if args.node_regex:
        pattern = re.compile(args.node_regex)
        node_names = [name for name in node_names if pattern.search(name)]

    probes: Dict[str, Dict[str, object]] = {}
    if args.hardware_probe:
        with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
            futures = {executor.submit(probe_node, node, args.ssh_timeout): node for node in node_names}
            for future in as_completed(futures):
                node = futures[future]
                probes[node] = future.result()

    rows = build_inventory_rows(pbs_nodes, probes)
    inv_json = {
        "schema_version": 1,
        "cluster": "iTHEMS cluster02",
        "collected_at_jst": jst_now(),
        "collected_at_utc": stamp,
        "hardware_probe": bool(args.hardware_probe),
        "node_count": len(pbs_nodes),
        "probed_node_count": len(probes),
        "queues": queues,
        "nodes": pbs_nodes,
        "hardware": probes,
        "derived_rows": rows,
    }
    (root / NODE_INVENTORY_JSON).write_text(json.dumps(inv_json, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_csv(
        root / NODE_INVENTORY_CSV,
        rows,
        [
            "node",
            "state",
            "qlist",
            "pbs_ncpus",
            "pbs_mem",
            "assigned_ncpus",
            "assigned_mem",
            "host",
            "ssh_ok",
            "hostname",
            "nproc",
            "mem_total_kb",
            "cpu_model",
            "cpu_mhz_sample",
            "lscpu_cpu_max_mhz",
            "lscpu_threads_per_core",
            "lscpu_cores_per_socket",
            "lscpu_sockets",
            "lscpu_l3_cache",
            "git_path",
            "gfortran_path",
            "ifx_path",
            "python3_path",
            "loadavg",
            "jobs",
            "ssh_error",
        ],
    )
    matrix_rows = write_queue_node_matrix(root / QUEUE_NODE_MATRIX_CSV, queues, rows)
    print("inventory_json={}".format(root / NODE_INVENTORY_JSON))
    print("inventory_csv={}".format(root / NODE_INVENTORY_CSV))
    print("queue_node_matrix_csv={}".format(root / QUEUE_NODE_MATRIX_CSV))
    print("node_count={}".format(len(pbs_nodes)))
    print("probed_node_count={}".format(len(probes)))
    print("queue_node_rows={}".format(len(matrix_rows)))
    return 0


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
    inventory_parser = subparsers.add_parser("inventory")
    inventory_parser.add_argument("--hardware-probe", action="store_true")
    inventory_parser.add_argument("--ssh-timeout", type=int, default=5)
    inventory_parser.add_argument("--max-workers", type=int, default=12)
    inventory_parser.add_argument("--node-regex", default="")
    rank_parser = subparsers.add_parser("rank-queues")
    rank_parser.add_argument("--ncpus", type=int, default=8)
    rank_parser.add_argument("--mem-gb", type=int, default=16)
    rank_parser.add_argument("--walltime", default="12:00:00")
    rank_parser.add_argument("--cpu-only", action="store_true", default=True)
    rank_parser.add_argument("--allow-gpu", action="store_true")
    rank_parser.add_argument("--allow-excluded", action="store_true")
    rank_parser.add_argument("--allow-placement-risk", action="store_true")
    rank_parser.set_defaults(require_git=True)
    rank_parser.add_argument("--require-git", dest="require_git", action="store_true")
    rank_parser.add_argument("--no-require-git", dest="require_git", action="store_false")
    rank_parser.add_argument("--gitless-guard", dest="require_git", action="store_false")
    rank_parser.add_argument("--require-ssh", action="store_true", default=True)
    rank_parser.add_argument("--output-csv", default="")
    source_pin_parser = subparsers.add_parser("source-pin")
    source_pin_parser.add_argument("--output", default="codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env")
    source_pin_parser.add_argument("--allow-dirty", action="store_true")
    snapshot_parser = subparsers.add_parser("runtime-snapshot")
    snapshot_parser.add_argument("--snapshot-root", required=True)
    snapshot_parser.add_argument("--pin-relpath", default="codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env")
    snapshot_parser.add_argument("--allow-dirty", action="store_true")
    snapshot_parser.add_argument("--delete", action="store_true")
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
    if args.command == "inventory":
        return inventory(root, args)
    if args.command == "rank-queues":
        return rank_queues(root, args)
    if args.command == "source-pin":
        return source_pin(root, args)
    if args.command == "runtime-snapshot":
        return runtime_snapshot(root, args)
    if args.command == "check-jobs":
        return check_jobs(root, args.job_ids)
    if args.command == "record-observation":
        return record_observation(root, args)
    raise RuntimeError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())
