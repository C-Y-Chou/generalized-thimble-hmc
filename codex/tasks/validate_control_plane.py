#!/usr/bin/env python3
"""Validate compact codex control-plane files."""

from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List


REQUIRED = [
    "codex/context/HANDOFF_MIN.txt",
    "codex/context/L0_BOOT.md",
    "codex/indexes/L1_INDEX.tsv",
    "codex/runbooks/READ_POLICY.md",
    "codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md",
    "codex/state/DECISIONS.tsv",
    "codex/state/OPEN_ITEMS.tsv",
    "codex/state/REMOTE_TARGETS.tsv",
    "codex/state/WORKTREES.tsv",
    "codex/state/LOCAL_TARGETS.tsv",
    "codex/state/LOCAL_WORKTREES.tsv",
    "codex/state/JOBS.tsv",
    "codex/state/DATASETS.tsv",
    "codex/logs/REMOTE_EVENTS.tsv",
]


TSV_HEADERS = {
    "codex/indexes/L1_INDEX.tsv": ["topic", "status", "source_of_truth", "when_to_read", "archive_or_detail"],
    "codex/state/DECISIONS.tsv": ["date_jst", "scope", "decision", "rationale", "impact", "reversible", "source"],
    "codex/state/OPEN_ITEMS.tsv": ["id", "scope", "status", "priority", "item", "next_action", "source"],
    "codex/state/REMOTE_TARGETS.tsv": [
        "target_id",
        "host",
        "user",
        "repo_path",
        "worktree_path",
        "branch",
        "purpose",
        "fast_forward_policy",
        "notes",
    ],
    "codex/state/WORKTREES.tsv": [
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
    "codex/state/LOCAL_TARGETS.tsv": [
        "target_id",
        "path",
        "purpose",
        "fast_forward_policy",
        "notes",
    ],
    "codex/state/LOCAL_WORKTREES.tsv": [
        "refreshed_at_jst",
        "target_id",
        "path",
        "branch",
        "commit",
        "upstream",
        "ahead",
        "behind",
        "dirty",
        "stash_count",
        "safe_to_pull",
        "notes",
    ],
    "codex/state/JOBS.tsv": [
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
}


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    return Path(result.stdout.strip()).resolve()


def read_header(path: Path) -> List[str]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t")
        return next(reader)


def read_tsv(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def fail(message: str, errors: List[str]) -> None:
    errors.append(message)


def main() -> int:
    root = repo_root()
    errors: List[str] = []
    for rel in REQUIRED:
        path = root / rel
        if not path.exists():
            fail(f"missing required file: {rel}", errors)
    route_guard = root / "codex/tasks/assert_canonical_route.sh"
    if not route_guard.exists():
        fail("missing route guard: codex/tasks/assert_canonical_route.sh", errors)
    elif not route_guard.stat().st_mode & 0o111:
        fail("route guard is not executable: codex/tasks/assert_canonical_route.sh", errors)
    for rel, expected in TSV_HEADERS.items():
        path = root / rel
        if path.exists():
            actual = read_header(path)
            if actual != expected:
                fail(f"bad header for {rel}: {actual}", errors)

    l0 = root / "codex/context/L0_BOOT.md"
    if l0.exists() and l0.stat().st_size > 12000:
        fail("L0_BOOT.md exceeds 12 KB compactness budget", errors)

    handoff = (root / "codex/context/HANDOFF_MIN.txt").read_text(encoding="utf-8")
    if "L0_BOOT.md" not in handoff:
        fail("HANDOFF_MIN.txt does not reference L0_BOOT.md", errors)
    if "/Users/ccy/Documents/TLTM_qn_error_handling" not in handoff:
        fail("HANDOFF_MIN.txt does not name the canonical local TLTM repo", errors)
    if "codex/fortran-modernization" not in handoff:
        fail("HANDOFF_MIN.txt does not name the current official DFO-LS branch", errors)
    if "New project/TLTM_repo is a legacy" not in handoff:
        fail("HANDOFF_MIN.txt does not mark New project/TLTM_repo as legacy", errors)
    local_targets = read_tsv(root / "codex/state/LOCAL_TARGETS.tsv")
    if not any(
        row.get("target_id") == "local_canonical_official_dfols"
        and row.get("path") == "/Users/ccy/Documents/TLTM_qn_error_handling"
        for row in local_targets
    ):
        fail("LOCAL_TARGETS.tsv does not contain canonical official-DFO-LS local target", errors)
    if not any(
        row.get("target_id") == "local_legacy_control_plane_checkout"
        and "Legacy" in row.get("purpose", "")
        for row in local_targets
    ):
        fail("LOCAL_TARGETS.tsv does not mark New project/TLTM_repo as legacy", errors)
    remote_targets = read_tsv(root / "codex/state/REMOTE_TARGETS.tsv")
    if not any(
        row.get("target_id") == "fortran_modernization"
        and row.get("worktree_path") == "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization"
        and row.get("branch") == "codex/fortran-modernization"
        for row in remote_targets
    ):
        fail("REMOTE_TARGETS.tsv does not contain canonical fortran_modernization execution target", errors)
    if not any(
        row.get("target_id") == "tltm_production_comparison_provisional"
        and row.get("worktree_path") == "/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison"
        and row.get("branch") == "codex/tltm-production-comparison-official-dfols"
        for row in remote_targets
    ):
        fail("REMOTE_TARGETS.tsv does not contain production-comparison execution target", errors)
    task_registry = read_tsv(root / "codex/runbooks/task_registry.tsv")
    for row in task_registry:
        if row.get("status") == "active" and row.get("root_path", "").startswith("/home/cychou/TLTM/codex"):
            fail(f"active task registry row uses old remote codex root: {row.get('task_slug')}", errors)
    guarded_scripts = [
        "codex/tasks/bootstrap.sh",
        "codex/tasks/doctor.sh",
        "codex/tasks/refresh_context.sh",
        "codex/tasks/refresh_global_context.sh",
        "codex/tasks/refresh_live_board.sh",
        "codex/tasks/task/init_task.sh",
        "codex/tasks/task/refresh_task_context.sh",
    ]
    for rel in guarded_scripts:
        text = (root / rel).read_text(encoding="utf-8")
        if "/home/cychou/TLTM" in text:
            fail(f"{rel} hardcodes /home/cychou/TLTM; derive repo root from script location", errors)
    stage_queue = root / "codex/workspaces/tltm_production_comparison/runbooks/QUEUE_OPTIMIZATION.md"
    if stage_queue.exists() and "SUPERSEDED" not in stage_queue.read_text(encoding="utf-8")[:500]:
        fail("Production-comparison queue optimization playbook lacks SUPERSEDED marker", errors)
    production_pbs = [
        "codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preflight_build.pbs",
        "codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_small_20260511_10seed_10k_nofb_withfb.pbs",
        "codex/workspaces/tltm_production_comparison/tasks/pbs/judgment_20260508_128seed_100k_p28_rg_chunk.pbs",
        "codex/workspaces/tltm_production_comparison/tasks/pbs/judgment_20260508_128seed_100k_p28_rg_merge.pbs",
    ]
    for rel in production_pbs:
        text = (root / rel).read_text(encoding="utf-8")
        if "TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison" not in text:
            fail(f"{rel} does not default to the production-comparison worktree", errors)
        if "TLTM_EXPECTED_GIT_BRANCH:=codex/tltm-production-comparison-official-dfols" not in text:
            fail(f"{rel} does not default to the production-comparison official-DFO-LS branch", errors)

    if errors:
        for error in errors:
            print(f"[control-plane][error] {error}", file=sys.stderr)
        return 1
    print("[control-plane] validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
