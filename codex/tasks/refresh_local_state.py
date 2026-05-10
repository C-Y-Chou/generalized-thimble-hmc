#!/usr/bin/env python3
"""Refresh local TLTM worktree state into compact codex registries."""

from __future__ import annotations

import csv
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional


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
    if not path.exists():
        return []
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


def git(path: Path, args: List[str], check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(path), *args],
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def git_value(path: Path, args: List[str], default: str = "NA") -> str:
    proc = git(path, args)
    if proc.returncode != 0:
        return default
    return clean(proc.stdout.strip())


def count_lines(text: str) -> str:
    if not text.strip():
        return "0"
    return str(len(text.splitlines()))


def ahead_behind(path: Path) -> tuple[str, str]:
    proc = git(path, ["rev-list", "--left-right", "--count", "HEAD...@{u}"])
    if proc.returncode != 0:
        return "NA", "NA"
    parts = proc.stdout.strip().split()
    if len(parts) != 2:
        return "NA", "NA"
    return clean(parts[0]), clean(parts[1])


def safe_to_pull(dirty: str, ahead: str, behind: str) -> str:
    if dirty not in {"0", "NA"}:
        return "no_dirty_worktree"
    if ahead not in {"0", "NA"}:
        return "no_local_ahead"
    if behind not in {"0", "NA"}:
        return "check_required"
    if behind == "NA":
        return "check_required"
    return "yes"


def main() -> int:
    root = repo_root()
    codex = root / "codex"
    targets_path = codex / "state" / "LOCAL_TARGETS.tsv"
    worktrees_path = codex / "state" / "LOCAL_WORKTREES.tsv"
    targets = read_tsv(targets_path)
    now = jst_now()
    rows: List[Dict[str, str]] = []

    for target in targets:
        path = Path(target["path"]).expanduser()
        if not path.exists() or git(path, ["rev-parse", "--is-inside-work-tree"]).returncode != 0:
            rows.append(
                {
                    "refreshed_at_jst": now,
                    "target_id": target["target_id"],
                    "path": str(path),
                    "branch": "missing",
                    "commit": "missing",
                    "upstream": "NA",
                    "ahead": "NA",
                    "behind": "NA",
                    "dirty": "NA",
                    "stash_count": "NA",
                    "safe_to_pull": "no_missing",
                    "notes": clean(target.get("notes")),
                }
            )
            continue

        branch = git_value(path, ["rev-parse", "--abbrev-ref", "HEAD"])
        commit = git_value(path, ["rev-parse", "HEAD"])
        upstream = git_value(path, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        ahead, behind = ahead_behind(path)
        dirty = count_lines(git(path, ["status", "--porcelain"]).stdout)
        stash_count = count_lines(git(path, ["stash", "list"]).stdout)
        rows.append(
            {
                "refreshed_at_jst": now,
                "target_id": target["target_id"],
                "path": str(path),
                "branch": branch,
                "commit": commit,
                "upstream": upstream,
                "ahead": ahead,
                "behind": behind,
                "dirty": dirty,
                "stash_count": stash_count,
                "safe_to_pull": safe_to_pull(dirty, ahead, behind),
                "notes": clean(target.get("notes")),
            }
        )

    write_tsv(
        worktrees_path,
        [
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
        rows,
    )
    print(f"local_worktrees={worktrees_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
