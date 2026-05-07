#!/usr/bin/env python3
"""Sort geometry cases by key metrics and emit ranked CSV reports."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sort geometry cases from intersection_summary.csv and write ranked outputs."
        )
    )
    parser.add_argument(
        "--summary-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots/intersection_summary.csv"),
        help="Path to geometry intersection summary CSV.",
    )
    parser.add_argument(
        "--case-dir",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots/case_by_case_normal"),
        help="Directory containing per-case images (case_XXX.png).",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots/geometry_sorted"),
        help="Output directory for sorted reports.",
    )
    return parser.parse_args()


def parse_float(text: str) -> float:
    text = text.strip()
    if not text:
        return math.inf
    try:
        return float(text)
    except ValueError:
        return math.inf


def case_png_rel(case_id: int, case_dir: Path) -> str:
    return str((case_dir / f"case_{case_id:03d}.png").as_posix())


def write_ranked_csv(out_csv: Path, rows: list[dict[str, str]]) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(
            [
                "rank",
                "sample_idx",
                "hit_status",
                "num_intersections",
                "primary_hit_dist_to_base",
                "min_line_distance",
                "primary_hit_re",
                "primary_hit_im",
                "case_png",
            ]
        )
        for rank, row in enumerate(rows, start=1):
            sample_idx = int(row["sample_idx"])
            writer.writerow(
                [
                    rank,
                    sample_idx,
                    row.get("hit_status", ""),
                    row.get("num_intersections", ""),
                    row.get("primary_hit_dist_to_base", ""),
                    row.get("min_line_distance", ""),
                    row.get("primary_hit_re", ""),
                    row.get("primary_hit_im", ""),
                    row.get("_case_png", ""),
                ]
            )


def write_bucket_csv(out_csv: Path, buckets: dict[str, list[dict[str, str]]]) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(
            [
                "bucket",
                "bucket_rank",
                "sample_idx",
                "primary_hit_dist_to_base",
                "min_line_distance",
                "case_png",
            ]
        )
        for bucket_name in ("very_close", "close", "far", "very_far"):
            seq = buckets.get(bucket_name, [])
            for i, row in enumerate(seq, start=1):
                writer.writerow(
                    [
                        bucket_name,
                        i,
                        int(row["sample_idx"]),
                        row.get("primary_hit_dist_to_base", ""),
                        row.get("min_line_distance", ""),
                        row.get("_case_png", ""),
                    ]
                )


def main() -> None:
    args = parse_args()
    if not args.summary_csv.exists():
        raise RuntimeError(f"Summary CSV not found: {args.summary_csv}")

    with args.summary_csv.open("r", newline="") as fobj:
        rows = list(csv.DictReader(fobj))
    if not rows:
        raise RuntimeError(f"No rows in summary CSV: {args.summary_csv}")

    for row in rows:
        sample_idx = int(row["sample_idx"])
        row["_primary_dist"] = parse_float(row.get("primary_hit_dist_to_base", ""))
        row["_line_dist"] = parse_float(row.get("min_line_distance", ""))
        row["_case_png"] = case_png_rel(sample_idx, args.case_dir)

    by_primary = sorted(rows, key=lambda r: (r["_primary_dist"], int(r["sample_idx"])))
    by_line = sorted(rows, key=lambda r: (r["_line_dist"], int(r["sample_idx"])))

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    write_ranked_csv(out_dir / "sorted_by_primary_hit_dist.csv", by_primary)
    write_ranked_csv(out_dir / "sorted_by_min_line_distance.csv", by_line)

    # 4 equal-count buckets by primary intersection distance (q25/q50/q75 style)
    n = len(by_primary)
    q1 = n // 4
    q2 = n // 2
    q3 = (3 * n) // 4
    buckets = {
        "very_close": by_primary[:q1],
        "close": by_primary[q1:q2],
        "far": by_primary[q2:q3],
        "very_far": by_primary[q3:],
    }
    write_bucket_csv(out_dir / "primary_hit_distance_buckets.csv", buckets)

    n_hit = sum(1 for r in rows if r.get("hit_status", "").strip() == "hit")
    print(
        f"[DONE] sorted_cases={len(rows)} hit_cases={n_hit} "
        f"out_dir={out_dir.resolve()}"
    )


if __name__ == "__main__":
    main()
