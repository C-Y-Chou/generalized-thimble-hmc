#!/usr/bin/env python3
"""Aggregate WV-HMC dense first-constraint Newton residual traces.

The output is a calibration aid only.  It reports observed convergence and
max-iteration behavior for a concrete model/parameter/run-root combination; it
does not define a universal WV-HMC Newton fail-fast policy.
"""

from __future__ import print_function

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path


STOP_REASON_NAMES = {
    0: "unknown",
    1: "converged",
    2: "max_iter",
    3: "residual_error",
    4: "update_error",
    5: "nonfinite",
    6: "divergence",
    7: "stagnation",
    8: "invalid_input",
    9: "not_run",
}


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def finite(values):
    return [value for value in values if math.isfinite(value)]


def quantile(values, q):
    vals = sorted(finite(values))
    if not vals:
        return ""
    if len(vals) == 1:
        return "{:.17g}".format(vals[0])
    pos = q*(len(vals) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return "{:.17g}".format(vals[lo])
    weight = pos - lo
    return "{:.17g}".format((1.0 - weight)*vals[lo] + weight*vals[hi])


def finite_max(values):
    vals = finite(values)
    return "" if not vals else "{:.17g}".format(max(vals))


def finite_min(values):
    vals = finite(values)
    return "" if not vals else "{:.17g}".format(min(vals))


def safe_ratio(numerator, denominator):
    if denominator <= 0:
        return ""
    return "{:.17g}".format(float(numerator)/float(denominator))


def read_scan_summary(run_root):
    summary_path = run_root / "dense_pilot_scan_summary.csv"
    rows = []
    if summary_path.exists():
        with summary_path.open(newline="") as handle:
            rows = list(csv.DictReader(handle))
    return rows


def trace_path_for_row(run_root, row):
    path = row.get("newton_trace_path", "")
    if path:
        return Path(path)
    label = row.get("label", "")
    if label:
        return run_root / (label + "_newton_trace.csv")
    return None


def read_trace(trace_path):
    solves = defaultdict(list)
    if trace_path is None or not trace_path.exists():
        return solves
    with trace_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            solve_id = to_int(row.get("solve_id"), -1)
            if solve_id < 0:
                continue
            item = {
                "solve_id": solve_id,
                "cycle": to_int(row.get("cycle"), 0),
                "direction": to_int(row.get("direction"), 0),
                "step": to_int(row.get("step"), 0),
                "iter": to_int(row.get("iter"), 0),
                "residual_norm": to_float(row.get("residual_norm")),
                "tol": to_float(row.get("tol")),
                "h": to_float(row.get("h")),
                "u_norm": to_float(row.get("u_norm")),
                "lambda_norm": to_float(row.get("lambda_norm")),
                "stop_reason": to_int(row.get("stop_reason"), 0),
            }
            solves[solve_id].append(item)
    return solves


def summarize_solve(rows):
    rows_sorted = sorted(rows, key=lambda item: (item["cycle"], item["direction"], item["step"], item["iter"]))
    final = rows_sorted[-1]
    final_reason = final["stop_reason"]
    if final_reason == 0:
        nonzero = [row for row in rows_sorted if row["stop_reason"] != 0]
        if nonzero:
            final_reason = nonzero[-1]["stop_reason"]
    residuals = [row["residual_norm"] for row in rows_sorted]
    initial = residuals[0] if residuals else float("nan")
    final_residual = final["residual_norm"]
    min_residual = min(finite(residuals)) if finite(residuals) else float("nan")
    max_iter = max([row["iter"] for row in rows_sorted]) if rows_sorted else 0
    direction = final["direction"]
    step = final["step"]
    cycle = final["cycle"]
    first_growth_iter = ""
    previous = None
    for row in rows_sorted:
        current = row["residual_norm"]
        if previous is not None and math.isfinite(current) and math.isfinite(previous) and current > previous:
            first_growth_iter = row["iter"]
            break
        previous = current
    return {
        "cycle": cycle,
        "direction": direction,
        "step": step,
        "final_iter": max_iter,
        "final_stop_reason": final_reason,
        "final_stop_name": STOP_REASON_NAMES.get(final_reason, "other"),
        "initial_residual": initial,
        "final_residual": final_residual,
        "min_residual": min_residual,
        "best_to_initial": min_residual/initial if math.isfinite(min_residual) and math.isfinite(initial) and initial > 0 else float("nan"),
        "final_to_initial": final_residual/initial if math.isfinite(final_residual) and math.isfinite(initial) and initial > 0 else float("nan"),
        "first_growth_iter": first_growth_iter,
        "row_count": len(rows_sorted),
    }


def summarize_candidate(row, trace_solves):
    solve_summaries = [summarize_solve(rows) for _, rows in sorted(trace_solves.items())]
    reason_counts = defaultdict(int)
    direction_counts = defaultdict(int)
    for solve in solve_summaries:
        reason_counts[solve["final_stop_name"]] += 1
        direction_counts[solve["direction"]] += 1
    converged = [solve for solve in solve_summaries if solve["final_stop_reason"] == 1]
    failed = [solve for solve in solve_summaries if solve["final_stop_reason"] != 1]
    return {
        "label": row.get("label", ""),
        "return_code": row.get("return_code", ""),
        "timed_out": row.get("timed_out", ""),
        "cycles_completed": row.get("cycles_completed", ""),
        "step_size": row.get("step_size", ""),
        "num_steps": row.get("num_steps", ""),
        "trajectory_length": row.get("trajectory_length", ""),
        "solve_count": len(solve_summaries),
        "forward_solve_count": direction_counts.get(1, 0),
        "reverse_solve_count": direction_counts.get(-1, 0),
        "converged_count": len(converged),
        "max_iter_count": reason_counts.get("max_iter", 0),
        "divergence_count": reason_counts.get("divergence", 0),
        "stagnation_count": reason_counts.get("stagnation", 0),
        "residual_error_count": reason_counts.get("residual_error", 0),
        "update_error_count": reason_counts.get("update_error", 0),
        "nonfinite_count": reason_counts.get("nonfinite", 0),
        "other_stop_count": len(failed) - reason_counts.get("max_iter", 0) - reason_counts.get("divergence", 0)
        - reason_counts.get("stagnation", 0) - reason_counts.get("residual_error", 0)
        - reason_counts.get("update_error", 0) - reason_counts.get("nonfinite", 0),
        "converged_rate": safe_ratio(len(converged), len(solve_summaries)),
        "converged_iter_q50": quantile([solve["final_iter"] for solve in converged], 0.5),
        "converged_iter_q90": quantile([solve["final_iter"] for solve in converged], 0.9),
        "converged_iter_max": finite_max([solve["final_iter"] for solve in converged]),
        "failed_iter_q50": quantile([solve["final_iter"] for solve in failed], 0.5),
        "failed_iter_min": finite_min([solve["final_iter"] for solve in failed]),
        "initial_residual_q50": quantile([solve["initial_residual"] for solve in solve_summaries], 0.5),
        "initial_residual_q90": quantile([solve["initial_residual"] for solve in solve_summaries], 0.9),
        "final_residual_q50": quantile([solve["final_residual"] for solve in solve_summaries], 0.5),
        "final_residual_q90": quantile([solve["final_residual"] for solve in solve_summaries], 0.9),
        "best_to_initial_q50": quantile([solve["best_to_initial"] for solve in solve_summaries], 0.5),
        "final_to_initial_q50": quantile([solve["final_to_initial"] for solve in solve_summaries], 0.5),
        "candidate_runtime_sec": row.get("runtime_sec", ""),
        "trace_path": str(trace_path_for_row(Path("."), row) or ""),
    }, solve_summaries


def iteration_rows(label, solve_summaries, trace_solves):
    rows_out = []
    final_by_id = {}
    for solve_id, rows in trace_solves.items():
        final_by_id[solve_id] = summarize_solve(rows)
    grouped = defaultdict(list)
    for solve_id, rows in trace_solves.items():
        final = final_by_id.get(solve_id, {})
        for row in rows:
            key = (row["direction"], row["iter"], final.get("final_stop_name", "unknown"))
            grouped[key].append(row["residual_norm"])
    for (direction, iter_idx, final_stop_name), residuals in sorted(grouped.items()):
        rows_out.append({
            "label": label,
            "direction": direction,
            "iter": iter_idx,
            "final_stop_name": final_stop_name,
            "n": len(residuals),
            "residual_q10": quantile(residuals, 0.1),
            "residual_q50": quantile(residuals, 0.5),
            "residual_q90": quantile(residuals, 0.9),
        })
    return rows_out


def write_csv(path, rows, fieldnames):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--output-dir", default="")
    args = parser.parse_args()

    run_root = Path(args.run_root)
    output_dir = Path(args.output_dir) if args.output_dir else run_root / "newton_trace_analysis"
    output_dir.mkdir(parents=True, exist_ok=True)

    scan_rows = read_scan_summary(run_root)
    candidate_rows = []
    solve_rows = []
    per_iter_rows = []
    availability = {
        "run_root": str(run_root),
        "scan_summary_exists": (run_root / "dense_pilot_scan_summary.csv").exists(),
        "candidate_count": len(scan_rows),
        "trace_files_present": 0,
        "total_solves": 0,
    }
    for row in scan_rows:
        label = row.get("label", "")
        trace_path = trace_path_for_row(run_root, row)
        trace_solves = read_trace(trace_path)
        if trace_solves:
            availability["trace_files_present"] += 1
        summary, solves = summarize_candidate(row, trace_solves)
        summary["trace_path"] = str(trace_path) if trace_path is not None else ""
        candidate_rows.append(summary)
        availability["total_solves"] += len(solves)
        for solve in solves:
            solve_row = {"label": label}
            solve_row.update(solve)
            solve_rows.append(solve_row)
        per_iter_rows.extend(iteration_rows(label, solves, trace_solves))

    candidate_fields = [
        "label", "return_code", "timed_out", "cycles_completed", "step_size", "num_steps", "trajectory_length",
        "solve_count", "forward_solve_count", "reverse_solve_count", "converged_count", "max_iter_count",
        "divergence_count", "stagnation_count", "residual_error_count", "update_error_count", "nonfinite_count",
        "other_stop_count", "converged_rate", "converged_iter_q50", "converged_iter_q90", "converged_iter_max",
        "failed_iter_q50", "failed_iter_min", "initial_residual_q50", "initial_residual_q90",
        "final_residual_q50", "final_residual_q90", "best_to_initial_q50", "final_to_initial_q50",
        "candidate_runtime_sec", "trace_path",
    ]
    solve_fields = [
        "label", "cycle", "direction", "step", "final_iter", "final_stop_reason", "final_stop_name",
        "initial_residual", "final_residual", "min_residual", "best_to_initial", "final_to_initial",
        "first_growth_iter", "row_count",
    ]
    iter_fields = ["label", "direction", "iter", "final_stop_name", "n", "residual_q10", "residual_q50", "residual_q90"]

    write_csv(output_dir / "wv_newton_trace_candidate_summary.csv", candidate_rows, candidate_fields)
    write_csv(output_dir / "wv_newton_trace_solve_summary.csv", solve_rows, solve_fields)
    write_csv(output_dir / "wv_newton_trace_iteration_summary.csv", per_iter_rows, iter_fields)
    with (output_dir / "wv_newton_trace_availability.json").open("w") as handle:
        json.dump(availability, handle, indent=2, sort_keys=True)
        handle.write("\n")

    md_lines = [
        "# WV-HMC Newton Trace Analysis",
        "",
        "Run root: `{}`".format(run_root),
        "",
        "This is a calibration aid only.  Newton fail-fast thresholds must be recalibrated per model, parameter set, `W(t)`, HMC trajectory setting, DOP853 policy, and initial-bank distribution.",
        "",
        "| label | cycles | solves | conv | max_iter | conv rate | conv iter q50/q90/max | init res q50 | final res q50 | best/init q50 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in candidate_rows:
        md_lines.append(
            "| {label} | {cycles} | {solves} | {conv} | {max_iter} | {rate} | {iq50}/{iq90}/{imax} | {r0} | {rf} | {best} |".format(
                label=row["label"],
                cycles=row["cycles_completed"],
                solves=row["solve_count"],
                conv=row["converged_count"],
                max_iter=row["max_iter_count"],
                rate=row["converged_rate"],
                iq50=row["converged_iter_q50"],
                iq90=row["converged_iter_q90"],
                imax=row["converged_iter_max"],
                r0=row["initial_residual_q50"],
                rf=row["final_residual_q50"],
                best=row["best_to_initial_q50"],
            )
        )
    md_lines.extend([
        "",
        "Artifacts:",
        "- `wv_newton_trace_candidate_summary.csv`",
        "- `wv_newton_trace_solve_summary.csv`",
        "- `wv_newton_trace_iteration_summary.csv`",
        "- `wv_newton_trace_availability.json`",
        "",
        "Calibration rule: do not enable adaptive Newton stop from this table alone.  First check that eventually convergent solves would not be rejected by the proposed cutoff, then rerun the same candidate with the candidate cutoff enabled and verify transition/observable diagnostics are unchanged except for intended fail-fast cost reduction.",
    ])
    (output_dir / "wv_newton_trace_analysis.md").write_text("\n".join(md_lines) + "\n")

    print("wrote {}".format(output_dir / "wv_newton_trace_analysis.md"))
    print("wrote {}".format(output_dir / "wv_newton_trace_candidate_summary.csv"))
    print("wrote {}".format(output_dir / "wv_newton_trace_solve_summary.csv"))
    print("wrote {}".format(output_dir / "wv_newton_trace_iteration_summary.csv"))
    print("wrote {}".format(output_dir / "wv_newton_trace_availability.json"))


if __name__ == "__main__":
    main()
