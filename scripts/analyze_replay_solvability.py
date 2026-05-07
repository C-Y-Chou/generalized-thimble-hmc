#!/usr/bin/env python3
"""Summarize replay solvability by online fail categories.

This script joins:
  - post-session fail metadata (`constraint_solver_fail_meta.csv`)
  - replay output from `bin/replay_quasi_failures`

and reports replay success rates for key groups, especially:
  - far_fail_fast (proxy for false-prune rate).
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass
class ReplayRow:
    sample_idx: int
    success: int
    proposal_count: int
    min_res: float
    last_res: float


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--post-dir",
        type=Path,
        required=True,
        help="Post-session directory containing constraint_solver_fail_meta.csv.",
    )
    p.add_argument(
        "--replay-csv",
        type=Path,
        required=True,
        help="CSV produced by bin/replay_quasi_failures.",
    )
    p.add_argument(
        "--out-csv",
        type=Path,
        default=None,
        help="Optional output CSV for group metrics.",
    )
    p.add_argument(
        "--out-json",
        type=Path,
        default=None,
        help="Optional output JSON for group metrics.",
    )
    return p.parse_args()


def to_int(text: str, default: int = 0) -> int:
    try:
        return int(str(text).strip())
    except Exception:
        return default


def to_float(text: str, default: float = float("nan")) -> float:
    try:
        return float(str(text).strip())
    except Exception:
        return default


def load_replay(path: Path) -> dict[int, ReplayRow]:
    out: dict[int, ReplayRow] = {}
    with path.open("r", newline="", encoding="utf-8", errors="replace") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sid = to_int(row.get("sample_idx", ""), -1)
            if sid <= 0:
                continue
            out[sid] = ReplayRow(
                sample_idx=sid,
                success=to_int(row.get("success", ""), 0),
                proposal_count=to_int(row.get("proposal_count", ""), -1),
                min_res=to_float(row.get("min_res", "")),
                last_res=to_float(row.get("last_res", "")),
            )
    return out


def load_meta(path: Path) -> dict[int, dict[str, str]]:
    out: dict[int, dict[str, str]] = {}
    with path.open("r", newline="", encoding="utf-8", errors="replace") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sid = to_int(row.get("sample_idx", ""), -1)
            if sid <= 0:
                continue
            # Keep first row per sample_idx.
            if sid not in out:
                out[sid] = row
    return out


def rate(n_ok: int, n_all: int) -> float:
    if n_all <= 0:
        return float("nan")
    return float(n_ok) / float(n_all)


def evaluate_group(
    name: str,
    sample_ids: list[int],
    replay: dict[int, ReplayRow],
) -> dict[str, float | int | str]:
    n_all = len(sample_ids)
    n_with_replay = 0
    n_success = 0
    proposal_counts: list[int] = []
    for sid in sample_ids:
        rr = replay.get(sid)
        if rr is None:
            continue
        n_with_replay += 1
        if rr.success == 1:
            n_success += 1
        if rr.proposal_count >= 0:
            proposal_counts.append(rr.proposal_count)
    prop_mean = float("nan")
    if proposal_counts:
        prop_mean = sum(proposal_counts) / float(len(proposal_counts))
    return {
        "group": name,
        "n_meta": n_all,
        "n_replay": n_with_replay,
        "n_success": n_success,
        "success_rate": rate(n_success, n_with_replay),
        "mean_proposal_count": prop_mean,
    }


def main() -> None:
    args = parse_args()
    post_dir = args.post_dir.resolve()
    meta_csv = post_dir / "constraint_solver_fail_meta.csv"
    if not meta_csv.exists():
        raise RuntimeError(f"Missing fail meta CSV: {meta_csv}")
    if not args.replay_csv.exists():
        raise RuntimeError(f"Missing replay CSV: {args.replay_csv}")

    meta = load_meta(meta_csv)
    replay = load_replay(args.replay_csv.resolve())
    sample_ids = sorted(meta.keys())

    def pred_all(_: dict[str, str]) -> bool:
        return True

    def pred_near(r: dict[str, str]) -> bool:
        return to_int(r.get("is_near_case", "0"), 0) == 1

    def pred_far(r: dict[str, str]) -> bool:
        return to_int(r.get("is_near_case", "0"), 0) != 1

    def pred_far_ff(r: dict[str, str]) -> bool:
        return (to_int(r.get("is_near_case", "0"), 0) != 1) and (to_int(r.get("far_fail_fast", "0"), 0) == 1)

    def pred_far_noff(r: dict[str, str]) -> bool:
        return (to_int(r.get("is_near_case", "0"), 0) != 1) and (to_int(r.get("far_fail_fast", "0"), 0) == 0)

    def pred_near_ff(r: dict[str, str]) -> bool:
        return (to_int(r.get("is_near_case", "0"), 0) == 1) and (to_int(r.get("near_fail_fast", "0"), 0) == 1)

    groups: list[tuple[str, Callable[[dict[str, str]], bool]]] = [
        ("all", pred_all),
        ("near_case", pred_near),
        ("far_case", pred_far),
        ("far_fail_fast", pred_far_ff),
        ("far_not_fail_fast", pred_far_noff),
        ("near_fail_fast", pred_near_ff),
    ]

    results: list[dict[str, float | int | str]] = []
    for name, pred in groups:
        sids = [sid for sid in sample_ids if pred(meta[sid])]
        results.append(evaluate_group(name, sids, replay))

    # Console report.
    print(f"[INFO] post_dir={post_dir}")
    print(f"[INFO] meta_samples={len(sample_ids)} replay_rows={len(replay)}")
    print("[RESULT] group,n_meta,n_replay,n_success,success_rate,mean_proposal_count")
    for r in results:
        print(
            f"[RESULT] {r['group']},{r['n_meta']},{r['n_replay']},{r['n_success']},"
            f"{r['success_rate']:.6f},{r['mean_proposal_count']:.3f}"
        )

    # Key KPI: false-prune proxy.
    far_ff = next((r for r in results if r["group"] == "far_fail_fast"), None)
    if far_ff is not None:
        print(
            f"[KPI] far_fail_fast_replay_success_rate={far_ff['success_rate']:.6f} "
            "(lower is better; high means we are cutting solvable points)"
        )

    if args.out_csv is not None:
        args.out_csv.parent.mkdir(parents=True, exist_ok=True)
        with args.out_csv.open("w", newline="", encoding="utf-8") as fobj:
            writer = csv.DictWriter(
                fobj,
                fieldnames=[
                    "group",
                    "n_meta",
                    "n_replay",
                    "n_success",
                    "success_rate",
                    "mean_proposal_count",
                ],
            )
            writer.writeheader()
            writer.writerows(results)

    if args.out_json is not None:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        with args.out_json.open("w", encoding="utf-8") as fobj:
            json.dump(results, fobj, indent=2, ensure_ascii=True)


if __name__ == "__main__":
    main()
