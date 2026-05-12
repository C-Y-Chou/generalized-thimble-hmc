#!/usr/bin/env python3
"""Refresh remote SSH/PBS/worktree state into compact codex registries."""

from __future__ import annotations

import csv
import json
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    return Path(result.stdout.strip()).resolve()


def jst_now() -> str:
    return datetime.now(timezone(timedelta(hours=9))).replace(microsecond=0).isoformat()


def read_tsv(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def write_tsv(path: Path, fieldnames: List[str], rows: List[Dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "NA") for key in fieldnames})


def clean(value: Optional[str]) -> str:
    if value is None or value == "":
        return "NA"
    return str(value).replace("\t", " ").replace("\n", " ")


def run_ssh(user: str, host: str, worktrees: List[str]) -> Tuple[int, str, str]:
    quoted_paths = " ".join(subprocess.list2cmdline([path]) for path in worktrees)
    remote = r'''
set +e
echo "__REMOTE_DATE__ $(date -Is)"
echo "__REMOTE_HOSTNAME__ $(hostname)"
echo "__WORKTREES_BEGIN__"
for wt in "$@"; do
  echo "__WT_BEGIN__ $wt"
  if git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "exists=1"
    echo "branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "commit=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo unknown)"
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "dirty_count=${dirty:-unknown}"
  else
    echo "exists=0"
    echo "branch=unknown"
    echo "commit=unknown"
    echo "dirty_count=unknown"
  fi
  echo "__WT_END__"
done
echo "__JOBS_BEGIN__"
if command -v qstat >/dev/null 2>&1; then
  qstat -u "$USER" 2>/dev/null | awk 'NR>5 {print $1}' | while read -r jid; do
    [ -z "$jid" ] && continue
    echo "__JOB_BEGIN__ $jid"
    qstat -f "$jid" 2>/dev/null | awk '
      /^[[:space:]]*Job_Name =/ {print}
      /^[[:space:]]*job_state =/ {print}
      /^[[:space:]]*queue =/ {print}
      /^[[:space:]]*exec_host =/ {print}
      /^[[:space:]]*Exit_status =/ {print}
      /^[[:space:]]*Resource_List.select =/ {print}
      /^[[:space:]]*Variable_List =/ {print}
      /^[[:space:]]+[A-Za-z0-9_]+=/{print}
    '
    echo "__JOB_END__"
  done
fi
echo "__QSTAT_SUMMARY_BEGIN__"
if command -v qstat >/dev/null 2>&1; then
  qstat -u "$USER" 2>/dev/null || true
fi
'''
    command = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=12", f"{user}@{host}", "bash", "-s", "--", *worktrees]
    proc = subprocess.run(command, input=remote, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return proc.returncode, proc.stdout, proc.stderr


def parse_key_value(line: str) -> Optional[Tuple[str, str]]:
    if " = " in line:
        key, value = line.split(" = ", 1)
        return key.strip(), value.strip()
    if "=" in line:
        key, value = line.split("=", 1)
        return key.strip(), value.strip()
    return None


def parse_remote_output(text: str) -> Dict[str, object]:
    worktrees: Dict[str, Dict[str, str]] = {}
    jobs: List[Dict[str, str]] = []
    current_wt: Optional[Dict[str, str]] = None
    current_job: Optional[Dict[str, str]] = None
    current_path = ""
    section = ""
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if line.startswith("__REMOTE_DATE__ "):
            continue
        if line.startswith("__REMOTE_HOSTNAME__ "):
            continue
        if line == "__WORKTREES_BEGIN__":
            section = "worktrees"
            continue
        if line.startswith("__WT_BEGIN__ "):
            current_path = line.split(" ", 1)[1]
            current_wt = {"worktree_path": current_path}
            continue
        if line == "__WT_END__":
            if current_wt is not None:
                worktrees[current_path] = current_wt
            current_wt = None
            current_path = ""
            continue
        if line == "__JOBS_BEGIN__":
            section = "jobs"
            continue
        if line.startswith("__JOB_BEGIN__ "):
            current_job = {"job_id": line.split(" ", 1)[1]}
            continue
        if line == "__JOB_END__":
            if current_job is not None:
                var_text = current_job.get("Variable_List", "")
                current_job["worktree"] = extract_var(var_text, "TLTM_WORKTREE")
                if current_job["worktree"] == "NA":
                    current_job["worktree"] = extract_var(var_text, "PBS_O_WORKDIR")
                current_job["expected_commit"] = extract_var(var_text, "TLTM_EXPECTED_GIT_COMMIT")
                jobs.append(current_job)
            current_job = None
            continue
        if line == "__QSTAT_SUMMARY_BEGIN__":
            section = "summary"
            continue

        parsed = parse_key_value(line)
        if parsed is None:
            continue
        key, value = parsed
        if section == "worktrees" and current_wt is not None:
            current_wt[key] = value
        elif section == "jobs" and current_job is not None:
            if key == "Variable_List" and "Variable_List" in current_job:
                current_job[key] += "," + value
            elif key != "Variable_List" and re.match(r"^[A-Za-z0-9_]+$", key) and current_job.get("Variable_List"):
                current_job["Variable_List"] += "," + f"{key}={value}"
            else:
                current_job[key] = value
    return {"worktrees": worktrees, "jobs": jobs}


def extract_var(variable_list: str, name: str) -> str:
    match = re.search(rf"(?:^|,){re.escape(name)}=([^,]+)", variable_list)
    return match.group(1) if match else "NA"


def same_or_truncated_path(lhs: str, rhs: str) -> bool:
    if lhs in {"", "NA"} or rhs in {"", "NA"}:
        return False
    lhs = lhs.rstrip("/")
    rhs = rhs.rstrip("/")
    if lhs == rhs:
        return True
    if lhs.startswith(rhs + "/"):
        return True
    # PBS qstat may truncate Variable_List values. Permit a truncated job
    # workdir to match its registered target, but do not let sibling paths such
    # as TLTM and TLTM_worktrees match by a bare string prefix.
    return len(lhs) >= 16 and rhs.startswith(lhs)


def main() -> int:
    root = repo_root()
    codex = root / "codex"
    targets_path = codex / "state" / "REMOTE_TARGETS.tsv"
    live_path = codex / "state" / "REMOTE_LIVE_CACHE.json"
    worktrees_path = codex / "state" / "WORKTREES.tsv"
    jobs_path = codex / "state" / "JOBS.tsv"
    events_path = codex / "logs" / "REMOTE_EVENTS.tsv"
    targets = read_tsv(targets_path)
    now = jst_now()

    grouped: Dict[Tuple[str, str], List[Dict[str, str]]] = defaultdict(list)
    for target in targets:
        grouped[(target["user"], target["host"])].append(target)

    cache: Dict[str, object] = {"refreshed_at_jst": now, "targets": targets, "hosts": {}, "errors": []}
    all_jobs: List[Dict[str, str]] = []
    worktree_rows: List[Dict[str, str]] = []

    for (user, host), host_targets in grouped.items():
        worktrees = sorted({row["worktree_path"] for row in host_targets})
        code, stdout, stderr = run_ssh(user, host, worktrees)
        host_key = f"{user}@{host}"
        parsed = parse_remote_output(stdout)
        cache["hosts"][host_key] = {
            "returncode": code,
            "stderr": stderr.strip(),
            "parsed": parsed,
        }
        if code != 0:
            cache["errors"].append({"host": host_key, "stderr": stderr.strip()})

        jobs = parsed.get("jobs", [])
        if isinstance(jobs, list):
            for job in jobs:
                if isinstance(job, dict):
                    job["host"] = host
                    all_jobs.append(job)

        parsed_worktrees = parsed.get("worktrees", {})
        if not isinstance(parsed_worktrees, dict):
            parsed_worktrees = {}
        for target in host_targets:
            wt = parsed_worktrees.get(target["worktree_path"], {})
            if not isinstance(wt, dict):
                wt = {}
            active_jobs = [
                clean(job.get("job_id"))
                for job in all_jobs
                if same_or_truncated_path(clean(job.get("worktree")), target["worktree_path"])
                and clean(job.get("job_state")) in {"R", "Q", "H", "B"}
            ]
            pinned_commits = sorted(
                {
                    clean(job.get("expected_commit"))
                    for job in all_jobs
                    if same_or_truncated_path(clean(job.get("worktree")), target["worktree_path"])
                    and clean(job.get("expected_commit")) != "NA"
                    and clean(job.get("job_state")) in {"R", "Q", "H", "B"}
                }
            )
            dirty_count = clean(wt.get("dirty_count"))
            target_purpose = clean(target.get("purpose"))
            target_policy = clean(target.get("fast_forward_policy"))
            safe_to_ff = "no" if active_jobs else "check_required"
            if target.get("fast_forward_policy") == "do_not_fast_forward_if_active_pinned_jobs" and active_jobs:
                safe_to_ff = "no"
            if target_policy == "read_only_inventory_until_delete" or "quarantined" in target_purpose:
                safe_to_ff = "no_fast_forward_quarantined"
            if target_policy == "deleted_tombstone" or "retired_deleted" in target_purpose:
                safe_to_ff = "deleted"
            worktree_rows.append(
                {
                    "refreshed_at_jst": now,
                    "target_id": target["target_id"],
                    "host": host,
                    "worktree_path": target["worktree_path"],
                    "branch": clean(wt.get("branch")),
                    "commit": clean(wt.get("commit")),
                    "dirty": dirty_count,
                    "active_jobs": ",".join(active_jobs) if active_jobs else "none",
                    "pinned_commits": ",".join(pinned_commits) if pinned_commits else "none",
                    "safe_to_fast_forward": safe_to_ff,
                    "notes": clean(target.get("notes")),
                }
            )

    job_rows: List[Dict[str, str]] = []
    for job in all_jobs:
        job_rows.append(
            {
                "refreshed_at_jst": now,
                "job_id": clean(job.get("job_id")),
                "name": clean(job.get("Job_Name")),
                "queue": clean(job.get("queue")),
                "state": clean(job.get("job_state")),
                "worktree": clean(job.get("worktree")),
                "expected_commit": clean(job.get("expected_commit")),
                "dataset": infer_dataset(clean(job.get("Job_Name"))),
                "action_needed": infer_action(clean(job.get("job_state"))),
                "notes": clean(job.get("exec_host") or job.get("Exit_status") or job.get("Resource_List.select")),
            }
        )

    live_path.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_tsv(
        worktrees_path,
        [
            "refreshed_at_jst",
            "target_id",
            "host",
            "worktree_path",
            "branch",
            "commit",
            "dirty",
            "active_jobs",
            "pinned_commits",
            "safe_to_fast_forward",
            "notes",
        ],
        worktree_rows,
    )
    write_tsv(
        jobs_path,
        [
            "refreshed_at_jst",
            "job_id",
            "name",
            "queue",
            "state",
            "worktree",
            "expected_commit",
            "dataset",
            "action_needed",
            "notes",
        ],
        job_rows,
    )
    with events_path.open("a", encoding="utf-8") as handle:
        handle.write(
            "\t".join(
                [
                    now,
                    "refresh_remote_state",
                    "all",
                    "multiple",
                    "multiple",
                    "NA",
                    "NA",
                    "refresh",
                    "ok" if not cache["errors"] else "partial",
                    f"jobs={len(job_rows)} worktrees={len(worktree_rows)}",
                ]
            )
            + "\n"
        )
    print(f"remote_live_cache={live_path}")
    print(f"worktrees={worktrees_path}")
    print(f"jobs={jobs_path}")
    return 0 if not cache["errors"] else 1


def infer_dataset(name: str) -> str:
    if name.startswith("pc32_"):
        return "official_dfols_gate_20260511_32seed_50k"
    if name.startswith("m6R1"):
        return "m6_r1_4seed_1k"
    if name.startswith("m6R2"):
        return "m6_r2_10seed_10k"
    if name.startswith("m6R3"):
        return "m6_r3_32seed_50k"
    if name.startswith("m6R4"):
        return "m6_r4_128seed_100k"
    if "s34" in name or name.startswith("m6") is False and "stage3" in name.lower():
        return "stage3_4_or_other"
    return "unknown"


def infer_action(state: str) -> str:
    if state in {"R", "Q", "H", "B"}:
        return "monitor"
    if state == "F":
        return "inspect_if_expected"
    return "none"


if __name__ == "__main__":
    raise SystemExit(main())
