#!/usr/bin/env python3
"""Check alignment between online quasi classes and post-session 3x3 geometry bands."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from itertools import permutations
from pathlib import Path


GEOM_LT_MIN = "abs_re_hit_lt_min_abs_re"
GEOM_IN_BAND = "min_abs_re_le_abs_re_hit_le_max_abs_re"
GEOM_GT_MAX = "abs_re_hit_gt_max_abs_re"
GEOM_NO_HIT = "no_hit"
GEOM_ORDER = [GEOM_LT_MIN, GEOM_IN_BAND, GEOM_GT_MAX, GEOM_NO_HIT]

ONLINE_LOCAL = "local"
ONLINE_MID = "mid"
ONLINE_GLOBAL = "global"
ONLINE_UNKNOWN = "unknown"
ONLINE_ORDER = [ONLINE_LOCAL, ONLINE_MID, ONLINE_GLOBAL, ONLINE_UNKNOWN]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build confusion matrix between online quasi class "
            "(local/mid/global) and geometry 3x3 intersection band."
        )
    )
    parser.add_argument(
        "--post-session-dir",
        type=Path,
        required=True,
        help="Path like output/post_session_analysis/<run_name>",
    )
    parser.add_argument(
        "--summary-csv",
        type=Path,
        default=None,
        help="Optional explicit failure_type_summary_*.csv",
    )
    parser.add_argument(
        "--trace-csv",
        type=Path,
        default=None,
        help="Optional explicit constraint_solver_fail_quasi_trace*.csv",
    )
    parser.add_argument(
        "--constraint-tol",
        type=float,
        default=1.0e-13,
        help="Quasi tolerance used for online class reproduction (default: 1e-13).",
    )
    parser.add_argument(
        "--out-prefix",
        type=str,
        default="online_vs_geometry_alignment",
        help="Output file prefix under post-session-dir.",
    )
    return parser.parse_args()


def pick_existing(paths: list[Path]) -> Path:
    for path in paths:
        if path.exists():
            return path
    raise FileNotFoundError(f"No candidate file exists: {[str(p) for p in paths]}")


def resolve_inputs(post_dir: Path, summary_csv: Path | None, trace_csv: Path | None) -> tuple[Path, Path]:
    if summary_csv is None:
        summary_csv = pick_existing(
            [
                post_dir / "failure_type_summary_official_100.csv",
                post_dir / "failure_type_summary_light_600.csv",
                post_dir / "failure_type_summary.csv",
            ]
        )
    if trace_csv is None:
        name = summary_csv.name
        if "official_100" in name:
            trace_csv = pick_existing(
                [
                    post_dir / "constraint_solver_fail_quasi_trace_first100.csv",
                    post_dir / "constraint_solver_fail_quasi_trace.csv",
                ]
            )
        elif "light_600" in name:
            trace_csv = pick_existing(
                [
                    post_dir / "constraint_solver_fail_quasi_trace_first600.csv",
                    post_dir / "constraint_solver_fail_quasi_trace.csv",
                ]
            )
        else:
            trace_csv = pick_existing(
                [
                    post_dir / "constraint_solver_fail_quasi_trace.csv",
                    post_dir / "constraint_solver_fail_quasi_trace_first100.csv",
                    post_dir / "constraint_solver_fail_quasi_trace_first600.csv",
                ]
            )
    return summary_csv, trace_csv


def safe_int(text: str, default: int = 0) -> int:
    try:
        return int(text.strip())
    except (TypeError, ValueError, AttributeError):
        return default


def safe_float(text: str, default: float = math.nan) -> float:
    try:
        return float(text.strip())
    except (TypeError, ValueError, AttributeError):
        return default


def read_geometry_band(summary_csv: Path) -> dict[int, str]:
    result: dict[int, str] = {}
    with summary_csv.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sid = safe_int(row.get("sample_idx", ""), default=-1)
            if sid <= 0:
                continue
            band = (row.get("intersection_band", "") or "").strip()
            if band not in GEOM_ORDER:
                band = GEOM_NO_HIT
            result[sid] = band
    if not result:
        raise RuntimeError(f"No sample_idx rows loaded from summary CSV: {summary_csv}")
    return result


def read_trace_rows(trace_csv: Path) -> dict[int, list[dict[str, str]]]:
    by_sample: dict[int, list[dict[str, str]]] = defaultdict(list)
    with trace_csv.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sid = safe_int(row.get("sample_idx", ""), default=-1)
            if sid <= 0:
                continue
            by_sample[sid].append(row)
    return by_sample


def compute_trace_stats(rows: list[dict[str, str]]) -> dict[str, float | bool]:
    if not rows:
        return {
            "available": False,
            "all_eval_ok": False,
            "first": math.nan,
            "best": math.nan,
            "last": math.nan,
        }

    max_attempt = max(safe_int(r.get("attempt_idx", ""), 0) for r in rows)
    last_rows = [r for r in rows if safe_int(r.get("attempt_idx", ""), 0) == max_attempt]
    if not last_rows:
        return {
            "available": False,
            "all_eval_ok": False,
            "first": math.nan,
            "best": math.nan,
            "last": math.nan,
        }

    last_rows.sort(key=lambda r: safe_int(r.get("proposal_idx", ""), 0))
    all_eval_ok = True
    first = math.nan
    best = math.inf
    last = math.nan
    n_used = 0
    n_valid = 0

    for row in last_rows:
        n_used += 1
        eval_ok = safe_int(row.get("eval_ok", ""), 0) != 0
        if not eval_ok:
            all_eval_ok = False
            continue
        n_valid += 1
        r = safe_float(row.get("res_norm", ""))
        if math.isfinite(r) and r > 0.0:
            if not math.isfinite(first):
                first = r
            if r < best:
                best = r
            last = r

    available = n_used > 0 and math.isfinite(first) and math.isfinite(best) and math.isfinite(last)
    if not available:
        best = math.nan
    valid_fraction = (float(n_valid) / float(n_used)) if n_used > 0 else 0.0

    return {
        "available": available,
        "all_eval_ok": all_eval_ok,
        "valid_count": n_valid,
        "valid_fraction": valid_fraction,
        "first": first,
        "best": best,
        "last": last,
    }


def classify_online(stats: dict[str, float | bool], tol: float) -> str:
    available = bool(stats["available"])
    if not available:
        return ONLINE_GLOBAL

    valid_count = int(stats.get("valid_count", 0))
    valid_fraction = float(stats.get("valid_fraction", 0.0))
    trace_first = float(stats["first"])
    trace_best = float(stats["best"])
    trace_last = float(stats["last"])
    tol_floor = max(tol, 1.0e-300)
    trace_scale = max(trace_first, tol_floor)

    class2_retry_res_threshold = max(1.0e4 * tol_floor, 8.0e-2 * trace_scale)
    near_case_res_threshold = max(256.0 * tol_floor, 1.0e-3 * trace_scale)
    near_case_res_threshold = min(near_case_res_threshold, class2_retry_res_threshold)

    trace_progress_ratio = trace_best / trace_first
    trace_regress_ratio = trace_last / trace_best
    best_over_tol = trace_best / tol_floor

    if (
        valid_count >= 3
        and valid_fraction >= 0.50
        and best_over_tol <= 1.0e10
        and trace_progress_ratio <= 0.60
        and trace_regress_ratio <= 96.0
    ):
        return ONLINE_LOCAL
    if (
        valid_count >= 3
        and valid_fraction >= 0.50
        and trace_best <= near_case_res_threshold
        and trace_progress_ratio <= 0.60
        and trace_regress_ratio <= 96.0
    ):
        return ONLINE_LOCAL
    if (
        valid_count >= 2
        and valid_fraction >= 0.30
        and trace_best <= class2_retry_res_threshold
        and trace_progress_ratio <= 0.90
        and trace_regress_ratio <= 192.0
    ):
        return ONLINE_MID
    if valid_count >= 2 and valid_fraction >= 0.20 and trace_best <= class2_retry_res_threshold:
        return ONLINE_MID
    return ONLINE_GLOBAL


def build_confusion(
    geometry_band: dict[int, str],
    trace_rows: dict[int, list[dict[str, str]]],
    tol: float,
) -> tuple[dict[tuple[str, str], int], list[tuple[int, str, str]]]:
    confusion: dict[tuple[str, str], int] = defaultdict(int)
    pairs: list[tuple[int, str, str]] = []
    for sid, band in sorted(geometry_band.items()):
        if sid in trace_rows:
            stats = compute_trace_stats(trace_rows[sid])
            online = classify_online(stats, tol)
        else:
            online = ONLINE_UNKNOWN
        confusion[(online, band)] += 1
        pairs.append((sid, online, band))
    return confusion, pairs


def compute_metrics(confusion: dict[tuple[str, str], int], pairs: list[tuple[int, str, str]]) -> dict[str, float | int | str]:
    metrics: dict[str, float | int | str] = {}
    total = len(pairs)
    metrics["total_cases"] = total
    metrics["unknown_online_cases"] = sum(1 for _, online, _ in pairs if online == ONLINE_UNKNOWN)

    # Best one-to-one match between online(local/mid/global) and geometry 3-band.
    online_3 = [ONLINE_LOCAL, ONLINE_MID, ONLINE_GLOBAL]
    geom_3 = [GEOM_LT_MIN, GEOM_IN_BAND, GEOM_GT_MAX]
    denom = sum(
        confusion[(o, g)]
        for o in online_3
        for g in geom_3
    )
    best_acc = 0.0
    best_map = ""
    if denom > 0:
        best_correct = -1
        for perm in permutations(geom_3):
            correct = 0
            for idx, online in enumerate(online_3):
                correct += confusion[(online, perm[idx])]
            if correct > best_correct:
                best_correct = correct
                best_map = ",".join(f"{online_3[i]}->{perm[i]}" for i in range(3))
        best_acc = best_correct / float(denom)
    metrics["best_match_accuracy_3x3"] = best_acc
    metrics["best_match_mapping_3x3"] = best_map

    global_row_total = sum(confusion[(ONLINE_GLOBAL, g)] for g in GEOM_ORDER)
    gt_col_total = sum(confusion[(o, GEOM_GT_MAX)] for o in ONLINE_ORDER)
    global_gt = confusion[(ONLINE_GLOBAL, GEOM_GT_MAX)]
    metrics["global_to_gt_max_precision"] = (global_gt / global_row_total) if global_row_total > 0 else math.nan
    metrics["gt_max_to_global_recall"] = (global_gt / gt_col_total) if gt_col_total > 0 else math.nan

    for online in ONLINE_ORDER:
        row_total = sum(confusion[(online, g)] for g in GEOM_ORDER)
        if row_total <= 0:
            metrics[f"row_purity_{online}"] = math.nan
            metrics[f"row_majority_{online}"] = "none"
            continue
        majority_band = max(GEOM_ORDER, key=lambda g: confusion[(online, g)])
        purity = confusion[(online, majority_band)] / row_total
        metrics[f"row_purity_{online}"] = purity
        metrics[f"row_majority_{online}"] = majority_band
    return metrics


def write_outputs(
    out_prefix: Path,
    confusion: dict[tuple[str, str], int],
    pairs: list[tuple[int, str, str]],
    metrics: dict[str, float | int | str],
    summary_csv: Path,
    trace_csv: Path,
) -> None:
    matrix_csv = out_prefix.with_suffix(".matrix.csv")
    pairs_csv = out_prefix.with_suffix(".pairs.csv")
    metrics_json = out_prefix.with_suffix(".metrics.json")
    report_md = out_prefix.with_suffix(".report.md")

    with matrix_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(["online_class", *GEOM_ORDER, "row_total"])
        for online in ONLINE_ORDER:
            row_vals = [confusion[(online, g)] for g in GEOM_ORDER]
            writer.writerow([online, *row_vals, sum(row_vals)])
        col_totals = [sum(confusion[(o, g)] for o in ONLINE_ORDER) for g in GEOM_ORDER]
        writer.writerow(["col_total", *col_totals, sum(col_totals)])

    with pairs_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(["sample_idx", "online_class", "geometry_band"])
        for row in pairs:
            writer.writerow(row)

    with metrics_json.open("w") as fobj:
        json.dump(metrics, fobj, indent=2, sort_keys=True)

    with report_md.open("w") as fobj:
        fobj.write("# Online vs Geometry Alignment\n\n")
        fobj.write(f"- summary_csv: `{summary_csv}`\n")
        fobj.write(f"- trace_csv: `{trace_csv}`\n")
        fobj.write(f"- total_cases: {metrics['total_cases']}\n")
        fobj.write(f"- unknown_online_cases: {metrics['unknown_online_cases']}\n")
        fobj.write(f"- best_match_accuracy_3x3: {metrics['best_match_accuracy_3x3']:.6f}\n")
        fobj.write(f"- best_match_mapping_3x3: {metrics['best_match_mapping_3x3']}\n")
        fobj.write(f"- global_to_gt_max_precision: {metrics['global_to_gt_max_precision']:.6f}\n")
        fobj.write(f"- gt_max_to_global_recall: {metrics['gt_max_to_global_recall']:.6f}\n")
        fobj.write("\n## Row Purity\n")
        for online in ONLINE_ORDER:
            fobj.write(
                f"- {online}: majority={metrics[f'row_majority_{online}']}, "
                f"purity={metrics[f'row_purity_{online}']}\n"
            )
        fobj.write("\n## Confusion Matrix Files\n")
        fobj.write(f"- matrix: `{matrix_csv}`\n")
        fobj.write(f"- pairs: `{pairs_csv}`\n")
        fobj.write(f"- metrics: `{metrics_json}`\n")


def main() -> None:
    args = parse_args()
    post_dir = args.post_session_dir.resolve()
    if not post_dir.exists():
        raise FileNotFoundError(f"post-session-dir not found: {post_dir}")

    summary_csv, trace_csv = resolve_inputs(post_dir, args.summary_csv, args.trace_csv)
    geometry_band = read_geometry_band(summary_csv)
    trace_rows = read_trace_rows(trace_csv)
    confusion, pairs = build_confusion(geometry_band, trace_rows, args.constraint_tol)
    metrics = compute_metrics(confusion, pairs)

    out_prefix = post_dir / args.out_prefix
    write_outputs(out_prefix, confusion, pairs, metrics, summary_csv, trace_csv)

    print(f"[DONE] post_session_dir={post_dir}")
    print(f"[DONE] summary_csv={summary_csv}")
    print(f"[DONE] trace_csv={trace_csv}")
    print(f"[DONE] total_cases={metrics['total_cases']} unknown_online={metrics['unknown_online_cases']}")
    print(f"[DONE] best_match_accuracy_3x3={metrics['best_match_accuracy_3x3']:.6f}")
    print(f"[DONE] global_to_gt_max_precision={metrics['global_to_gt_max_precision']:.6f}")
    print(f"[DONE] gt_max_to_global_recall={metrics['gt_max_to_global_recall']:.6f}")
    print(f"[DONE] outputs={(post_dir / args.out_prefix).as_posix()}.*")


if __name__ == "__main__":
    main()
