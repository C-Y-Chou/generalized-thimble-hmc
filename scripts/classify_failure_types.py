#!/usr/bin/env python3
"""Classify constraint-solver failure types from geometry + quasi trace."""

from __future__ import annotations

import argparse
import csv
import math
import struct
from collections import Counter, defaultdict
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Classify failure types for captured 100-case failures."
    )
    parser.add_argument(
        "--geometry-summary-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots/intersection_summary.csv"),
        help="Path to geometry intersection summary CSV.",
    )
    parser.add_argument(
        "--quasi-trace-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_quasi_trace.csv"),
        help="Path to quasi trace CSV.",
    )
    parser.add_argument(
        "--case-dir",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots/case_by_case_normal"),
        help="Directory of case_XXX.png figures.",
    )
    parser.add_argument(
        "--out-summary-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/failure_type_summary.csv"),
    )
    parser.add_argument(
        "--out-counts-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/failure_type_counts.csv"),
    )
    parser.add_argument(
        "--ensemble-z-history-file",
        type=Path,
        default=Path("output/production/z_history.dat"),
        help="Raw ensemble z-history stream for min|Re z| and max|Re z|.",
    )
    parser.add_argument(
        "--z0-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_z0.dat"),
        help="z0 stream file used only to infer z-size for z-history parsing.",
    )
    parser.add_argument(
        "--proposal-near-i-threshold",
        type=float,
        default=0.25,
        help="Threshold on min |z_proposal - i| for proposal-stuck-near-i class.",
    )
    parser.add_argument(
        "--band-boundary-eps",
        type=float,
        default=0.0,
        help="Optional epsilon slack used on band boundaries.",
    )
    parser.add_argument(
        "--high-plateau-threshold",
        type=float,
        default=1.0e-2,
        help="Threshold on min_residual to define high plateau.",
    )
    parser.add_argument(
        "--near-tol-threshold",
        type=float,
        default=1.0e-8,
        help="Threshold on min_residual to define near-tol stall.",
    )
    parser.add_argument(
        "--side-zero-abs-eps",
        type=float,
        default=1.0e-8,
        help="Absolute epsilon for Re-side sign classification around zero.",
    )
    parser.add_argument(
        "--side-zero-rel-to-min-abs-re",
        type=float,
        default=1.0e-3,
        help="Relative epsilon (x ensemble min|Re z|) for Re-side sign classification.",
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


def load_geometry(path: Path) -> dict[int, dict[str, str]]:
    with path.open("r", newline="") as fobj:
        rows = list(csv.DictReader(fobj))
    return {int(r["sample_idx"]): r for r in rows}


def load_trace_metrics(path: Path, sample_ids: set[int]) -> dict[int, dict[str, float]]:
    # Use final accepted proposal per (attempt_idx, iter_idx) to avoid line-search clutter.
    by_iter: dict[tuple[int, int, int], tuple[int, float, complex]] = {}
    with path.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sid = int(row["sample_idx"])
            if sid not in sample_ids:
                continue
            if int(row["accepted"]) != 1:
                continue
            it = int(row["iter_idx"])
            if it <= 0:
                continue
            at = int(row["attempt_idx"])
            pidx = int(row["proposal_idx"])
            key = (sid, at, it)
            res = float(row["res_norm"])
            z_prop = complex(float(row["z_prop_re"]), float(row["z_prop_im"]))
            old = by_iter.get(key)
            if old is None or pidx > old[0]:
                by_iter[key] = (pidx, res, z_prop)

    by_sid: dict[int, list[tuple[int, int, float, complex]]] = defaultdict(list)
    for (sid, at, it), (_, res, z_prop) in by_iter.items():
        by_sid[sid].append((at, it, res, z_prop))

    out: dict[int, dict[str, float]] = {}
    for sid in sample_ids:
        seq = sorted(by_sid.get(sid, []), key=lambda x: (x[0], x[1]))
        if not seq:
            out[sid] = {
                "accepted_iter_count": 0.0,
                "min_residual": math.inf,
                "last_residual": math.inf,
                "last_over_best": math.inf,
                "proposal_min_i_dist": math.inf,
                "stuck_z_re": math.inf,
                "stuck_z_im": math.inf,
                "abs_re_stuck_z": math.inf,
            }
            continue

        min_res = min(x[2] for x in seq)
        last_res = seq[-1][2]
        last_z = seq[-1][3]
        proposal_min_i = min(abs(x[3] - 1j) for x in seq)
        out[sid] = {
            "accepted_iter_count": float(len(seq)),
            "min_residual": float(min_res),
            "last_residual": float(last_res),
            "last_over_best": float(last_res / max(min_res, 1.0e-300)),
            "proposal_min_i_dist": float(proposal_min_i),
            "stuck_z_re": float(last_z.real),
            "stuck_z_im": float(last_z.imag),
            "abs_re_stuck_z": float(abs(last_z.real)),
        }
    return out


def infer_z_size_from_z0(path: Path) -> int:
    with path.open("rb") as fobj:
        head = fobj.read(8)
        if len(head) != 8:
            raise RuntimeError(f"Failed to read z0 header from {path}")
        _, n = struct.unpack("<ii", head)
    if n <= 0:
        raise RuntimeError(f"Invalid z-size inferred from {path}: {n}")
    return int(n)


def read_ensemble_reals(z_history_file: Path, z_size: int) -> list[float]:
    if z_size <= 0:
        raise RuntimeError(f"Invalid z_size={z_size} for ensemble parsing.")
    if not z_history_file.exists():
        raise RuntimeError(f"Ensemble z-history file not found: {z_history_file}")

    raw = z_history_file.read_bytes()
    if len(raw) == 0:
        raise RuntimeError(f"Empty ensemble z-history file: {z_history_file}")
    if (len(raw) % 8) != 0:
        raise RuntimeError(f"Corrupted ensemble z-history (byte count not multiple of 8): {z_history_file}")

    vals = struct.unpack("<" + "d" * (len(raw) // 8), raw)
    if len(vals) % 2 != 0:
        raise RuntimeError(f"Corrupted ensemble z-history (odd float64 count): {z_history_file}")

    # z_history is [Re0, Im0, Re1, Im1, ...]
    reals = list(vals[0::2])
    if (len(reals) % z_size) != 0:
        raise RuntimeError(
            "Cannot infer sample count from ensemble z-history: "
            f"n_complex={len(reals)} not divisible by z_size={z_size}"
        )
    return reals


def compute_re_band_bounds(reals: list[float]) -> tuple[float, float]:
    finite_abs_re = [abs(x) for x in reals if math.isfinite(x)]
    if not finite_abs_re:
        raise RuntimeError("No finite Re(z) values in ensemble z-history.")
    return min(finite_abs_re), max(finite_abs_re)


def classify_intersection_band(
    *,
    hit_status: str,
    abs_re_intersection: float,
    min_abs_re: float,
    max_abs_re: float,
    eps: float,
) -> str:
    if hit_status != "hit" or (not math.isfinite(abs_re_intersection)):
        return "no_hit"
    if abs_re_intersection < (min_abs_re - eps):
        return "abs_re_hit_lt_min_abs_re"
    if abs_re_intersection > (max_abs_re + eps):
        return "abs_re_hit_gt_max_abs_re"
    return "min_abs_re_le_abs_re_hit_le_max_abs_re"


def classify_stuck_re_band(
    *,
    abs_re_stuck_z: float,
    min_abs_re: float,
    max_abs_re: float,
    eps: float,
) -> str:
    if not math.isfinite(abs_re_stuck_z):
        return "no_stuck_z"
    if abs_re_stuck_z < (min_abs_re - eps):
        return "abs_re_stuck_z_lt_min_abs_re"
    if abs_re_stuck_z > (max_abs_re + eps):
        return "abs_re_stuck_z_gt_max_abs_re"
    return "min_abs_re_le_abs_re_stuck_z_le_max_abs_re"


def classify_re_side(value: float, eps: float) -> str:
    if not math.isfinite(value):
        return "unknown"
    if value > eps:
        return "pos"
    if value < -eps:
        return "neg"
    return "zero"


def classify_final_vs_hit_side(
    *,
    hit_status: str,
    hit_re: float,
    final_re: float,
    eps: float,
) -> tuple[str, str, str, int]:
    if hit_status != "hit" or (not math.isfinite(hit_re)):
        return "no_hit", "unknown", "unknown", 0

    hit_side = classify_re_side(hit_re, eps)
    final_side = classify_re_side(final_re, eps)

    if final_side == "unknown":
        return "no_stuck", hit_side, final_side, 0
    if hit_side == "zero" or final_side == "zero":
        return "touch_zero", hit_side, final_side, 0
    if hit_side == final_side:
        return "same_side", hit_side, final_side, 0
    return "opposite_side", hit_side, final_side, 1


def classify_final_vs_ref_side(
    *,
    ref_re: float,
    final_re: float,
    eps: float,
) -> tuple[str, str, str, int]:
    ref_side = classify_re_side(ref_re, eps)
    final_side = classify_re_side(final_re, eps)

    if ref_side == "unknown" or final_side == "unknown":
        return "unknown", ref_side, final_side, 0
    if ref_side == "zero" or final_side == "zero":
        return "touch_zero", ref_side, final_side, 0
    if ref_side == final_side:
        return "same_side", ref_side, final_side, 0
    return "opposite_side", ref_side, final_side, 1


def classify_high_level(
    *,
    intersection_band: str,
    proposal_min_i: float,
    proposal_near_i_threshold: float,
) -> str:
    if intersection_band == "no_hit":
        return "type4_no_solution"
    if proposal_min_i <= proposal_near_i_threshold:
        return f"{intersection_band}_proposal_stuck_near_i"
    return f"{intersection_band}_proposal_not_stuck_near_i"


def classify_detailed(
    *,
    high_level: str,
    min_residual: float,
    high_plateau_threshold: float,
    near_tol_threshold: float,
) -> str:
    if high_level == "type4_no_solution":
        return "type4_no_solution"

    if min_residual <= near_tol_threshold:
        return f"{high_level}_near_tol_stall"
    if min_residual >= high_plateau_threshold:
        return f"{high_level}_high_plateau"
    return f"{high_level}_mid_res_stall"


def case_png(case_dir: Path, sample_idx: int) -> str:
    return str((case_dir / f"case_{sample_idx:03d}.png").as_posix())


def main() -> None:
    args = parse_args()
    geo = load_geometry(args.geometry_summary_csv)
    sample_ids = set(geo.keys())
    trace = load_trace_metrics(args.quasi_trace_csv, sample_ids)
    z_size = infer_z_size_from_z0(args.z0_file)
    reals = read_ensemble_reals(args.ensemble_z_history_file, z_size)
    min_abs_re, max_abs_re = compute_re_band_bounds(reals)
    side_zero_eps = max(
        max(0.0, float(args.side_zero_abs_eps)),
        max(0.0, float(args.side_zero_rel_to_min_abs_re)) * min_abs_re,
    )

    rows_out: list[dict[str, str | float | int]] = []
    for sid in sorted(sample_ids):
        g = geo[sid]
        t = trace[sid]
        hit = g.get("hit_status", "").strip()
        hit_re = math.nan
        if g.get("primary_hit_re", "").strip() and g.get("primary_hit_im", "").strip():
            z_hit = complex(float(g["primary_hit_re"]), float(g["primary_hit_im"]))
            d_hit_to_i = abs(z_hit - 1j)
            hit_re = float(g["primary_hit_re"])
            abs_re_hit = abs(float(g["primary_hit_re"]))
        else:
            d_hit_to_i = math.inf
            abs_re_hit = math.inf

        intersection_band = classify_intersection_band(
            hit_status=hit,
            abs_re_intersection=abs_re_hit,
            min_abs_re=min_abs_re,
            max_abs_re=max_abs_re,
            eps=max(0.0, float(args.band_boundary_eps)),
        )
        stuck_re_band = classify_stuck_re_band(
            abs_re_stuck_z=t["abs_re_stuck_z"],
            min_abs_re=min_abs_re,
            max_abs_re=max_abs_re,
            eps=max(0.0, float(args.band_boundary_eps)),
        )
        stuck_re_filter_pass = int(stuck_re_band == "min_abs_re_le_abs_re_stuck_z_le_max_abs_re")
        final_vs_hit_side, hit_re_side, final_re_side, cross_zero_flag = classify_final_vs_hit_side(
            hit_status=hit,
            hit_re=hit_re,
            final_re=t["stuck_z_re"],
            eps=side_zero_eps,
        )
        final_vs_z0_side, z0_re_side, final_re_side_vs_z0, cross_zero_vs_z0_flag = classify_final_vs_ref_side(
            ref_re=parse_float(g.get("z0_re", "")),
            final_re=t["stuck_z_re"],
            eps=side_zero_eps,
        )
        # Sanity: keep one canonical final-side field in summary table.
        if final_re_side == "unknown":
            final_re_side = final_re_side_vs_z0

        high = classify_high_level(
            intersection_band=intersection_band,
            proposal_min_i=t["proposal_min_i_dist"],
            proposal_near_i_threshold=args.proposal_near_i_threshold,
        )
        detailed = classify_detailed(
            high_level=high,
            min_residual=t["min_residual"],
            high_plateau_threshold=args.high_plateau_threshold,
            near_tol_threshold=args.near_tol_threshold,
        )

        rows_out.append(
            {
                "sample_idx": sid,
                "high_level_type": high,
                "detailed_type": detailed,
                "hit_status": hit,
                "num_intersections": int(g.get("num_intersections", "0") or 0),
                "d_hit_to_i": d_hit_to_i,
                "abs_re_intersection": abs_re_hit,
                "intersection_band": intersection_band,
                "ensemble_min_abs_re": min_abs_re,
                "ensemble_max_abs_re": max_abs_re,
                "proposal_min_i_dist": t["proposal_min_i_dist"],
                "stuck_z_re": t["stuck_z_re"],
                "stuck_z_im": t["stuck_z_im"],
                "abs_re_stuck_z": t["abs_re_stuck_z"],
                "stuck_re_band": stuck_re_band,
                "stuck_re_filter_pass": stuck_re_filter_pass,
                "hit_re_side": hit_re_side,
                "final_re_side": final_re_side,
                "final_vs_hit_side": final_vs_hit_side,
                "cross_zero_flag": cross_zero_flag,
                "z0_re_side": z0_re_side,
                "final_vs_z0_side": final_vs_z0_side,
                "cross_zero_vs_z0_flag": cross_zero_vs_z0_flag,
                "side_zero_eps": side_zero_eps,
                "accepted_iter_count": int(t["accepted_iter_count"]),
                "min_residual": t["min_residual"],
                "last_residual": t["last_residual"],
                "last_over_best": t["last_over_best"],
                "primary_hit_dist_to_base": parse_float(g.get("primary_hit_dist_to_base", "")),
                "min_line_distance": parse_float(g.get("min_line_distance", "")),
                "case_png": case_png(args.case_dir, sid),
            }
        )

    args.out_summary_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.out_summary_csv.open("w", newline="") as fobj:
        fieldnames = [
            "sample_idx",
            "high_level_type",
            "detailed_type",
            "hit_status",
            "num_intersections",
            "d_hit_to_i",
            "abs_re_intersection",
            "intersection_band",
            "ensemble_min_abs_re",
            "ensemble_max_abs_re",
            "proposal_min_i_dist",
            "stuck_z_re",
            "stuck_z_im",
            "abs_re_stuck_z",
            "stuck_re_band",
            "stuck_re_filter_pass",
            "hit_re_side",
            "final_re_side",
            "final_vs_hit_side",
            "cross_zero_flag",
            "z0_re_side",
            "final_vs_z0_side",
            "cross_zero_vs_z0_flag",
            "side_zero_eps",
            "accepted_iter_count",
            "min_residual",
            "last_residual",
            "last_over_best",
            "primary_hit_dist_to_base",
            "min_line_distance",
            "case_png",
        ]
        writer = csv.DictWriter(fobj, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows_out)

    high_counts = Counter(str(r["high_level_type"]) for r in rows_out)
    detail_counts = Counter(str(r["detailed_type"]) for r in rows_out)
    band_counts = Counter(str(r["intersection_band"]) for r in rows_out)
    stuck_band_counts = Counter(str(r["stuck_re_band"]) for r in rows_out)
    stuck_filter_counts = Counter(int(r["stuck_re_filter_pass"]) for r in rows_out)
    hit_side_counts = Counter(str(r["hit_re_side"]) for r in rows_out)
    final_side_counts = Counter(str(r["final_re_side"]) for r in rows_out)
    side_relation_counts = Counter(str(r["final_vs_hit_side"]) for r in rows_out)
    cross_zero_counts = Counter(int(r["cross_zero_flag"]) for r in rows_out)
    z0_side_counts = Counter(str(r["z0_re_side"]) for r in rows_out)
    side_relation_z0_counts = Counter(str(r["final_vs_z0_side"]) for r in rows_out)
    cross_zero_z0_counts = Counter(int(r["cross_zero_vs_z0_flag"]) for r in rows_out)
    high_stuck_pass_counts = Counter(
        str(r["high_level_type"])
        for r in rows_out
        if int(r["stuck_re_filter_pass"]) == 1
    )
    band_order = [
        "abs_re_hit_lt_min_abs_re",
        "min_abs_re_le_abs_re_hit_le_max_abs_re",
        "abs_re_hit_gt_max_abs_re",
        "no_hit",
    ]
    stuck_band_order = [
        "abs_re_stuck_z_lt_min_abs_re",
        "min_abs_re_le_abs_re_stuck_z_le_max_abs_re",
        "abs_re_stuck_z_gt_max_abs_re",
        "no_stuck_z",
    ]
    side_order = ["pos", "neg", "zero", "unknown"]
    side_relation_order = ["same_side", "opposite_side", "touch_zero", "no_hit", "no_stuck", "unknown"]
    with args.out_counts_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(["kind", "type", "count"])
        for name in band_order:
            writer.writerow(["intersection_band", name, band_counts.get(name, 0)])
        for name in stuck_band_order:
            writer.writerow(["stuck_re_band", name, stuck_band_counts.get(name, 0)])
        writer.writerow(["stuck_re_filter", "pass", stuck_filter_counts.get(1, 0)])
        writer.writerow(["stuck_re_filter", "fail", stuck_filter_counts.get(0, 0)])
        for name in side_order:
            writer.writerow(["hit_re_side", name, hit_side_counts.get(name, 0)])
        for name in side_order:
            writer.writerow(["final_re_side", name, final_side_counts.get(name, 0)])
        for name in side_relation_order:
            writer.writerow(["final_vs_hit_side", name, side_relation_counts.get(name, 0)])
        writer.writerow(["cross_zero_flag", "1", cross_zero_counts.get(1, 0)])
        writer.writerow(["cross_zero_flag", "0", cross_zero_counts.get(0, 0)])
        for name in side_order:
            writer.writerow(["z0_re_side", name, z0_side_counts.get(name, 0)])
        for name in side_relation_order:
            writer.writerow(["final_vs_z0_side", name, side_relation_z0_counts.get(name, 0)])
        writer.writerow(["cross_zero_vs_z0_flag", "1", cross_zero_z0_counts.get(1, 0)])
        writer.writerow(["cross_zero_vs_z0_flag", "0", cross_zero_z0_counts.get(0, 0)])
        for name, count in sorted(high_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            writer.writerow(["high_level", name, count])
        for name, count in sorted(high_stuck_pass_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            writer.writerow(["high_level_stuck_filter_pass", name, count])
        for name, count in sorted(detail_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            writer.writerow(["detailed", name, count])

    print(f"[DONE] classified_cases={len(rows_out)} summary={args.out_summary_csv}")
    print(
        "[BANDS] "
        f"min_abs_re={min_abs_re:.6e} max_abs_re={max_abs_re:.6e}"
    )
    print("[INTERSECTION_BAND_COUNTS]")
    for name in band_order:
        print(f"  {name}: {band_counts.get(name, 0)}")
    print("[STUCK_RE_BAND_COUNTS]")
    for name in stuck_band_order:
        print(f"  {name}: {stuck_band_counts.get(name, 0)}")
    print(
        "[STUCK_RE_FILTER] "
        f"pass={stuck_filter_counts.get(1, 0)} fail={stuck_filter_counts.get(0, 0)}"
    )
    print("[HIGH_LEVEL_COUNTS]")
    for name, count in sorted(high_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {name}: {count}")
    print("[HIGH_LEVEL_COUNTS_STUCK_FILTER_PASS]")
    for name, count in sorted(high_stuck_pass_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {name}: {count}")
    print("[DETAILED_COUNTS]")
    for name, count in sorted(detail_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {name}: {count}")


if __name__ == "__main__":
    main()
