#!/usr/bin/env python3
"""Render compact L0 boot context from control-plane registries."""

from __future__ import annotations

import csv
import json
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, List


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


def main() -> int:
    root = repo_root()
    codex = root / "codex"
    jobs = read_tsv(codex / "state" / "JOBS.tsv")
    worktrees = read_tsv(codex / "state" / "WORKTREES.tsv")
    local_worktrees = read_tsv(codex / "state" / "LOCAL_WORKTREES.tsv")
    open_items = read_tsv(codex / "state" / "OPEN_ITEMS.tsv")
    caveats = read_tsv(codex / "state" / "CAVEATS.tsv")
    decisions = read_tsv(codex / "state" / "DECISIONS.tsv")
    live_path = codex / "state" / "REMOTE_LIVE_CACHE.json"
    live = {}
    if live_path.exists():
        try:
            live = json.loads(live_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            live = {}

    active_jobs = [row for row in jobs if row.get("state") in {"R", "Q", "H", "B"}]
    unsafe_worktrees = [row for row in worktrees if row.get("safe_to_fast_forward") == "no"]
    local_risks = [
        row
        for row in local_worktrees
        if row.get("safe_to_pull") not in {"yes", ""}
        or row.get("dirty") not in {"0", "", "NA"}
    ]
    high_open = [row for row in open_items if row.get("priority") == "high" and row.get("status") == "active"]
    high_caveats = [row for row in caveats if row.get("priority") == "high" and row.get("status") == "active"]
    recent_decisions = decisions[-6:]
    refreshed = live.get("refreshed_at_jst", "not refreshed")

    lines: List[str] = []
    lines.append("# TLTM Codex L0 Boot")
    lines.append("")
    lines.append(f"Generated: {jst_now()}")
    lines.append(f"Remote refreshed: {refreshed}")
    lines.append("")
    lines.append("## Canonical Entry")
    lines.append("")
    lines.append("- Local source of truth: `/Users/ccy/Documents/TLTM_qn_error_handling`.")
    lines.append("- Default branch/workline: `codex/fortran-modernization` with embedded official DFO-LS as the default QN backend.")
    lines.append("- Modernization/source execution target: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.")
    lines.append("- Production-comparison execution target: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` after sync to the chosen official-DFO-LS commit.")
    lines.append("- `/Users/ccy/Documents/New project/TLTM_repo` is legacy unless the user explicitly asks for legacy/control-plane work.")
    lines.append("")
    lines.append("## Hard Rules")
    lines.append("")
    lines.append("- Heavy TLTM execution must use PBS compute nodes, not the login/frontend node.")
    lines.append("- Before remote SSH/PBS/git cleanup work, run `bash codex/tasks/refresh_remote_state.sh` and `bash codex/tasks/render_l0_boot.sh`.")
    lines.append("- Before local TLTM `git pull`, branch switch, cleanup, or overwrite, run `bash codex/tasks/refresh_local_state.sh` and `bash codex/tasks/render_l0_boot.sh`.")
    lines.append("- If a remote worktree has active pinned jobs, do not fast-forward or clean it.")
    lines.append("- For cluster02 queue choice, work splitting, submission, or job repair, use the cluster02 scheduling agent.")
    lines.append("- Do not use `qmove` as the official repair path; cancel/resubmit/rebuild dependencies.")
    lines.append("- Default read set is `HANDOFF_MIN -> L0_BOOT -> CAVEATS -> L1_INDEX -> chosen workspace STATE_BRIEF`.")
    lines.append("")
    lines.append("## Active Remote Risk")
    lines.append("")
    if unsafe_worktrees:
        for row in unsafe_worktrees[:6]:
            active_ids = [item for item in row.get("active_jobs", "").split(",") if item and item != "none"]
            active_summary = "none"
            if active_ids:
                active_summary = "{} active jobs, examples: {}".format(
                    len(active_ids),
                    ",".join(active_ids[:8]),
                )
            lines.append(
                f"- `{row.get('target_id')}`: branch `{row.get('branch')}`, commit `{row.get('commit')}`, {active_summary}, pinned `{row.get('pinned_commits')}`. Do not fast-forward."
            )
    else:
        lines.append("- No unsafe worktree recorded in the latest registry. If cache is stale, refresh before acting.")
    lines.append("")
    lines.append("## Active Local Risk")
    lines.append("")
    if local_risks:
        for row in local_risks[:6]:
            lines.append(
                f"- `{row.get('target_id')}`: branch `{row.get('branch')}`, commit `{row.get('commit')}`, dirty `{row.get('dirty')}`, ahead `{row.get('ahead')}`, behind `{row.get('behind')}`, stashes `{row.get('stash_count')}`, safe_to_pull `{row.get('safe_to_pull')}`."
            )
    else:
        lines.append("- No local worktree risk recorded in `codex/state/LOCAL_WORKTREES.tsv`.")
    lines.append("")
    lines.append("## Active/Pending Jobs")
    lines.append("")
    if active_jobs:
        for row in active_jobs[:12]:
            lines.append(
                f"- `{row.get('job_id')}` `{row.get('name')}` queue `{row.get('queue')}` state `{row.get('state')}` dataset `{row.get('dataset')}`."
            )
        if len(active_jobs) > 12:
            lines.append(f"- ... {len(active_jobs) - 12} more jobs in `codex/state/JOBS.tsv`.")
    else:
        lines.append("- No active jobs in `codex/state/JOBS.tsv`.")
    lines.append("")
    lines.append("## Active Caveats")
    lines.append("")
    if high_caveats:
        for row in high_caveats[:6]:
            lines.append(
                f"- `{row.get('id')}` {row.get('scope')} blocks `{row.get('blocks')}`: {row.get('item')} Rerun trigger: {row.get('rerun_trigger')}"
            )
    else:
        lines.append("- No active high-priority caveat recorded in `codex/state/CAVEATS.tsv`.")
    lines.append("")
    lines.append("## High-Priority Open Items")
    lines.append("")
    if high_open:
        for row in high_open[:6]:
            lines.append(f"- `{row.get('id')}` {row.get('scope')}: {row.get('item')} Next: {row.get('next_action')}")
    else:
        lines.append("- No active high-priority open item recorded.")
    lines.append("")
    lines.append("## Recent Decisions")
    lines.append("")
    for row in recent_decisions:
        lines.append(f"- {row.get('date_jst')} `{row.get('scope')}`: {row.get('decision')}")
    lines.append("")
    lines.append("## Pointers")
    lines.append("")
    lines.append("- L1 index: `codex/indexes/L1_INDEX.tsv`")
    lines.append("- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`")
    lines.append("- Local worktrees: `codex/state/LOCAL_WORKTREES.tsv`")
    lines.append("- Caveats: `codex/state/CAVEATS.tsv`")
    lines.append("- Jobs: `codex/state/JOBS.tsv`")
    lines.append("- Worktrees: `codex/state/WORKTREES.tsv`")
    lines.append("- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`")
    lines.append("- Read policy: `codex/runbooks/READ_POLICY.md`")
    lines.append("")

    out = codex / "context" / "L0_BOOT.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"rendered={out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
