#!/usr/bin/env python3
"""Classify quasi-Newton failure modes for captured constraint-solver failures."""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Classify failure reasons for captured quasi-Newton constraint-solver cases "
            "using trace + replay results."
        )
    )
    parser.add_argument(
        "--trace-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_quasi_trace.csv"),
        help="Path to constraint_solver_fail_quasi_trace.csv",
    )
    parser.add_argument(
        "--replay-100-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/quasi_replay_results.csv"),
        help="Replay summary at baseline max_iter (typically 100).",
    )
    parser.add_argument(
        "--replay-400-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/quasi_replay_results_iter400.csv"),
        help="Replay summary at extended max_iter (typically 400).",
    )
    parser.add_argument(
        "--geometry-summary-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots/intersection_summary.csv"),
        help="Path to geometry intersection summary.",
    )
    parser.add_argument(
        "--out-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/failure_mode_summary.csv"),
        help="Per-case classification output CSV.",
    )
    parser.add_argument(
        "--out-counts-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/failure_mode_counts.csv"),
        help="Aggregated count output CSV.",
    )
    parser.add_argument(
        "--include-no-hit",
        action="store_true",
        help="Include no-hit geometry cases in per-case output.",
    )
    parser.add_argument(
        "--high-res-threshold",
        type=float,
        default=1.0e-2,
        help="Threshold for high_res_plateau.",
    )
    parser.add_argument(
        "--mid-res-threshold",
        type=float,
        default=1.0e-4,
        help="Threshold for mid_res_plateau.",
    )
    parser.add_argument(
        "--low-res-threshold",
        type=float,
        default=1.0e-8,
        help="Threshold for low_res_stall.",
    )
    parser.add_argument(
        "--heavy-backtrack-mean",
        type=float,
        default=8.0,
        help="Mean accepted-backtrack threshold for heavy_backtracking tag.",
    )
    parser.add_argument(
        "--heavy-backtrack-max",
        type=int,
        default=14,
        help="Max accepted-backtrack threshold for heavy_backtracking tag.",
    )
    parser.add_argument(
        "--tiny-alpha-median",
        type=float,
        default=1.0e-2,
        help="Median accepted alpha threshold for tiny_step tag.",
    )
    parser.add_argument(
        "--tiny-alpha-min",
        type=float,
        default=1.0e-4,
        help="Minimum accepted alpha threshold for tiny_step tag.",
    )
    return parser.parse_args()


def read_replay_success(path: Path) -> dict[int, int]:
    out: dict[int, int] = {}
    with path.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            out[int(row["sample_idx"].strip())] = int(row["success"].strip())
    return out


def read_hit_status(path: Path) -> dict[int, str]:
    out: dict[int, str] = {}
    with path.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            out[int(row["sample_idx"].strip())] = row["hit_status"].strip()
    return out


def read_accepted_trace(path: Path) -> dict[int, list[dict[str, float | int]]]:
    out: dict[int, list[dict[str, float | int]]] = defaultdict(list)
    with path.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            if int(row["accepted"].strip()) != 1:
                continue
            iter_idx = int(row["iter_idx"].strip())
            if iter_idx <= 0:
                continue
            out[int(row["sample_idx"].strip())].append(
                {
                    "iter_idx": iter_idx,
                    "backtrack_idx": int(row["backtrack_idx"].strip()),
                    "alpha": float(row["alpha"].strip()),
                    "res_norm": float(row["res_norm"].strip()),
                }
            )
    for rows in out.values():
        rows.sort(key=lambda item: int(item["iter_idx"]))
    return out


def classify_cause(
    solved100: bool,
    solved400: bool,
    min_res: float,
    high_res_threshold: float,
    mid_res_threshold: float,
    low_res_threshold: float,
    hit_status: str,
) -> str:
    if hit_status != "hit":
        return "no_geometry_hit"
    if solved100:
        return "already_solved_100"
    if solved400:
        return "iter_budget_limit"
    if min_res >= high_res_threshold:
        return "high_res_plateau"
    if min_res >= mid_res_threshold:
        return "mid_res_plateau"
    if min_res >= low_res_threshold:
        return "low_res_stall"
    return "near_tol_stall"


def main() -> None:
    args = parse_args()

    replay100 = read_replay_success(args.replay_100_csv)
    replay400 = read_replay_success(args.replay_400_csv)
    hit_status = read_hit_status(args.geometry_summary_csv)
    accepted = read_accepted_trace(args.trace_csv)

    sample_ids = sorted(set(replay100) | set(replay400) | set(hit_status) | set(accepted))
    rows_out: list[dict[str, str | float | int]] = []

    for sample_idx in sample_ids:
        status = hit_status.get(sample_idx, "unknown")
        if (not args.include_no_hit) and status != "hit":
            continue

        seq = accepted.get(sample_idx, [])
        if not seq:
            continue

        res = [float(item["res_norm"]) for item in seq if math.isfinite(float(item["res_norm"]))]
        if not res:
            continue

        bt = [int(item["backtrack_idx"]) for item in seq]
        alpha = [float(item["alpha"]) for item in seq]

        first_res = res[0]
        min_res = min(res)
        last_res = res[-1]
        idx_best = min(range(len(res)), key=lambda i: res[i])
        iter_best = int(seq[idx_best]["iter_idx"])
        improve_frac = (first_res - min_res) / max(first_res, 1.0e-300)
        regress_after_best = (last_res / min_res) if min_res > 0.0 else math.inf

        mean_bt = float(sum(bt) / len(bt))
        med_bt = float(statistics.median(bt))
        max_bt = int(max(bt))
        med_alpha = float(statistics.median(alpha))
        min_alpha = float(min(alpha))

        solved100 = replay100.get(sample_idx, 0) == 1
        solved400 = replay400.get(sample_idx, 0) == 1

        cause = classify_cause(
            solved100=solved100,
            solved400=solved400,
            min_res=min_res,
            high_res_threshold=args.high_res_threshold,
            mid_res_threshold=args.mid_res_threshold,
            low_res_threshold=args.low_res_threshold,
            hit_status=status,
        )

        tags: list[str] = []
        if (mean_bt >= args.heavy_backtrack_mean) or (max_bt >= args.heavy_backtrack_max):
            tags.append("heavy_backtracking")
        if (med_alpha <= args.tiny_alpha_median) or (min_alpha <= args.tiny_alpha_min):
            tags.append("tiny_step")
        if (iter_best <= 10) and (regress_after_best > 1.05):
            tags.append("best_early_then_regress")
        if iter_best >= 90:
            tags.append("best_at_end")
        if improve_frac < 0.2:
            tags.append("weak_total_improvement")

        rows_out.append(
            {
                "sample_idx": sample_idx,
                "hit_status": status,
                "cause": cause,
                "tags": ";".join(tags),
                "solved_at_iter100": int(solved100),
                "solved_at_iter400": int(solved400),
                "accepted_iter_count": len(seq),
                "min_res": min_res,
                "last_res": last_res,
                "iter_best": iter_best,
                "mean_backtrack": mean_bt,
                "median_backtrack": med_bt,
                "max_backtrack": max_bt,
                "median_alpha": med_alpha,
                "min_alpha": min_alpha,
                "improve_fraction": improve_frac,
                "last_over_best": regress_after_best,
            }
        )

    args.out_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.out_csv.open("w", newline="") as fobj:
        fieldnames = [
            "sample_idx",
            "hit_status",
            "cause",
            "tags",
            "solved_at_iter100",
            "solved_at_iter400",
            "accepted_iter_count",
            "min_res",
            "last_res",
            "iter_best",
            "mean_backtrack",
            "median_backtrack",
            "max_backtrack",
            "median_alpha",
            "min_alpha",
            "improve_fraction",
            "last_over_best",
        ]
        writer = csv.DictWriter(fobj, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows_out)

    cause_counts = Counter(str(r["cause"]) for r in rows_out)
    tag_counts = Counter(tag for r in rows_out for tag in str(r["tags"]).split(";") if tag)
    with args.out_counts_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(["kind", "name", "count"])
        for name, count in sorted(cause_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            writer.writerow(["cause", name, count])
        for name, count in sorted(tag_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            writer.writerow(["tag", name, count])

    print(f"[DONE] cases={len(rows_out)} out_csv={args.out_csv}")
    print("[CAUSE_COUNTS]")
    for name, count in sorted(cause_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {name}: {count}")
    print("[TAG_COUNTS]")
    for name, count in sorted(tag_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {name}: {count}")


if __name__ == "__main__":
    main()

