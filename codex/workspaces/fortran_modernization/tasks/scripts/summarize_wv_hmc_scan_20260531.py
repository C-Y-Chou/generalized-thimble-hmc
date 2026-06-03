#!/usr/bin/env python3
"""Summarize WV-HMC scan chunks by tuning parameters.

The input root may contain one or many chunk directories produced by
``run_wv_hmc_dense_observable_validation_20260529.py``.  This script reads
per-seed summaries plus manifests and groups rows by the requested scan keys.
It intentionally uses transition/movement/histogram diagnostics only; exact
observable validation is handled by the history/pilot readback scripts.
"""

import argparse
import csv
import json
import math
from pathlib import Path


DEFAULT_GROUP_KEYS = "w_gamma,step_size,num_steps"


def safe_float(value, default=float("nan")):
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def safe_int(value, default=0):
    try:
        if value is None or value == "":
            return default
        return int(float(value))
    except (TypeError, ValueError):
        return default


def read_csv_rows(path):
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def parse_hist(text):
    if text is None:
        return []
    text = str(text).strip()
    if not text:
        return []
    return [safe_int(part) for part in text.split(";") if part != ""]


def merge_hist(rows, key):
    total = []
    for row in rows:
        counts = parse_hist(row.get(key, ""))
        if not counts:
            continue
        if not total:
            total = [0] * len(counts)
        if len(counts) != len(total):
            raise RuntimeError("histogram width mismatch for {0}".format(key))
        for idx, count in enumerate(counts):
            total[idx] += count
    return total


def hist_metrics(counts):
    total = sum(counts)
    if not counts or total <= 0:
        return {
            "hist_total": total,
            "hist_zero_bins": len(counts),
            "hist_min_nonzero": 0,
            "hist_max": 0,
            "hist_max_min_ratio": float("nan"),
            "hist_adjacent_flatness": float("nan"),
        }
    nonzero = [value for value in counts if value > 0]
    adjacent_terms = []
    for left, right in zip(counts[:-1], counts[1:]):
        denom = 0.5 * (left + right)
        if denom > 0.0:
            adjacent_terms.append(((right - left) / denom) ** 2)
    return {
        "hist_total": total,
        "hist_zero_bins": len(counts) - len(nonzero),
        "hist_min_nonzero": min(nonzero) if nonzero else 0,
        "hist_max": max(counts),
        "hist_max_min_ratio": max(counts) / float(min(nonzero)) if nonzero else float("nan"),
        "hist_adjacent_flatness": sum(adjacent_terms) / len(adjacent_terms) if adjacent_terms else float("nan"),
    }


def weighted_mean(rows, value_key, weight_key):
    numerator = 0.0
    denominator = 0.0
    for row in rows:
        weight = safe_float(row.get(weight_key), 0.0)
        value = safe_float(row.get(value_key))
        if math.isfinite(value) and weight > 0.0:
            numerator += value * weight
            denominator += weight
    return numerator / denominator if denominator > 0.0 else float("nan")


def quantile(values, q):
    values = sorted(value for value in values if math.isfinite(value))
    if not values:
        return float("nan")
    if len(values) == 1:
        return values[0]
    pos = q * (len(values) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return values[lo]
    frac = pos - lo
    return values[lo] * (1.0 - frac) + values[hi] * frac


def collect_rows(root):
    summary_by_seed = {}
    manifest_by_seed = {}
    for path in sorted(root.rglob("seed_*_summary.csv")):
        if "/readback/" in str(path):
            continue
        rows = read_csv_rows(path)
        if len(rows) != 1:
            continue
        row = dict(rows[0])
        row["summary_path"] = str(path)
        seed = row.get("base_seed") or row.get("seed") or path.name.split("_")[1]
        summary_by_seed[(str(seed), str(path.parent))] = row
    for path in sorted(root.rglob("wv_hmc_dense_observable_validation_manifest.csv")):
        for row in read_csv_rows(path):
            row = dict(row)
            row["manifest_path"] = str(path)
            manifest_by_seed[(str(row.get("seed")), str(path.parent))] = row
    records = []
    for key, summary in sorted(summary_by_seed.items()):
        manifest = manifest_by_seed.get(key, {})
        merged = dict(manifest)
        merged.update(summary)
        records.append(merged)
    return records


def group_key(row, keys):
    parts = []
    for key in keys:
        if key in row and row.get(key) not in (None, ""):
            parts.append(str(row.get(key)))
        elif key == "step_size":
            parts.append(str(row.get("step_size", row.get("hmc_epsilon", ""))))
        elif key == "num_steps":
            parts.append(str(row.get("num_steps", row.get("hmc_nstep", ""))))
        else:
            parts.append("")
    return tuple(parts)


def summarize_group(label, rows, group_keys):
    cycles = sum(safe_int(row.get("cycles_completed")) for row in rows)
    accepted = sum(safe_int(row.get("accepted")) for row in rows)
    rejected = sum(safe_int(row.get("rejected")) for row in rows)
    transitions_failed = sum(safe_int(row.get("transitions_failed")) for row in rows)
    reverse_gate_rejected = sum(safe_int(row.get("reverse_gate_rejected")) for row in rows)
    metropolis_rejected = sum(safe_int(row.get("metropolis_rejected")) for row in rows)
    odex_failure = sum(safe_int(row.get("odex_failure")) for row in rows)
    solver_max_iter = sum(safe_int(row.get("solver_stop_max_iter", row.get("solver_stop_max_iter_count"))) for row in rows)
    solver_large_residual = sum(safe_int(row.get("solver_stop_large_residual")) for row in rows)
    boundary = sum(safe_int(row.get("bounced_steps")) for row in rows)
    trajectory_steps = sum(safe_int(row.get("trajectory_steps")) for row in rows)
    measurement_included = sum(safe_int(row.get("measurement_included")) for row in rows)
    runtime_values = [safe_float(row.get("runtime_sec")) for row in rows]
    runtime_values = [value for value in runtime_values if math.isfinite(value)]
    flow_hist = merge_hist(rows, "flow_time_hist_inside")
    measurement_hist = merge_hist(rows, "measurement_flow_time_hist_inside")
    flow_metrics = hist_metrics(flow_hist)
    measurement_metrics = hist_metrics(measurement_hist)
    d_re = sum(safe_float(row.get("wv_denominator_re"), 0.0) for row in rows)
    d_im = sum(safe_float(row.get("wv_denominator_im"), 0.0) for row in rows)
    sum_abs_w = sum(safe_float(row.get("wv_sum_abs_weight"), 0.0) for row in rows)
    phase = math.hypot(d_re, d_im) / sum_abs_w if sum_abs_w > 0.0 else float("nan")
    row = {
        "group": label,
        "seeds": len(rows),
        "cycles": cycles,
        "measurements": measurement_included,
        "accepted": accepted,
        "rejected": rejected,
        "acceptance": accepted / float(cycles) if cycles else float("nan"),
        "accepted_over_accepted_plus_rejected": accepted / float(accepted + rejected)
        if accepted + rejected else float("nan"),
        "metropolis_rejected_per_cycle": metropolis_rejected / float(cycles) if cycles else float("nan"),
        "reverse_gate_rejected_per_cycle": reverse_gate_rejected / float(cycles) if cycles else float("nan"),
        "transitions_failed_per_cycle": transitions_failed / float(cycles) if cycles else float("nan"),
        "odex_failure_per_cycle": odex_failure / float(cycles) if cycles else float("nan"),
        "solver_max_iter_per_cycle": solver_max_iter / float(cycles) if cycles else float("nan"),
        "solver_large_residual_per_cycle": solver_large_residual / float(cycles) if cycles else float("nan"),
        "boundary_per_step": boundary / float(trajectory_steps) if trajectory_steps else float("nan"),
        "accepted_x_jump_sq_mean": weighted_mean(rows, "accepted_x_jump_sq_mean", "accepted_jump_count"),
        "accepted_z_jump_sq_mean": weighted_mean(rows, "accepted_z_jump_sq_mean", "accepted_jump_count"),
        "accepted_flow_time_jump_abs_mean": weighted_mean(
            rows, "accepted_flow_time_jump_abs_mean", "accepted_jump_count"
        ),
        "effective_x_jump_sq_mean": weighted_mean(rows, "effective_x_jump_sq_mean", "cycles_completed"),
        "effective_z_jump_sq_mean": weighted_mean(rows, "effective_z_jump_sq_mean", "cycles_completed"),
        "effective_flow_time_jump_abs_mean": weighted_mean(
            rows, "effective_flow_time_jump_abs_mean", "cycles_completed"
        ),
        "flow_time_mean": weighted_mean(rows, "flow_time_mean", "flow_time_observations"),
        "flow_time_min": min(safe_float(row.get("flow_time_min")) for row in rows),
        "flow_time_max": max(safe_float(row.get("flow_time_max")) for row in rows),
        "flow_hist_max_min_ratio": flow_metrics["hist_max_min_ratio"],
        "flow_hist_zero_bins": flow_metrics["hist_zero_bins"],
        "flow_hist_adjacent_flatness": flow_metrics["hist_adjacent_flatness"],
        "measurement_hist_max_min_ratio": measurement_metrics["hist_max_min_ratio"],
        "measurement_hist_zero_bins": measurement_metrics["hist_zero_bins"],
        "measurement_hist_adjacent_flatness": measurement_metrics["hist_adjacent_flatness"],
        "phase_coherence": phase,
        "runtime_sec_sum": sum(runtime_values) if runtime_values else float("nan"),
        "runtime_sec_median_seed": quantile(runtime_values, 0.5),
        "runtime_sec_max_seed": max(runtime_values) if runtime_values else float("nan"),
    }
    for key, value in zip(group_keys, label.split("|")):
        row[key] = value
    return row


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    keys = []
    for row in rows:
        for key in row:
            if key not in keys:
                keys.append(key)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_markdown(path, rows, group_keys):
    lines = [
        "# WV-HMC Scan Summary",
        "",
        "Grouped by: `{0}`".format(','.join(group_keys)),
        "",
        "| group | seeds | cycles | acc | eff x jump | eff z jump | eff t jump | t mean | t max | hist ratio | hist zero | RG/cyc | fail/cyc | median sec/seed |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| {group} | {seeds} | {cycles} | {acc:.4g} | {ex:.4g} | {ez:.4g} | {et:.4g} | "
            "{tm:.4g} | {tx:.4g} | {hr:.4g} | {hz} | {rg:.4g} | {fail:.4g} | {rt:.4g} |".format(
                group=row["group"],
                seeds=row["seeds"],
                cycles=row["cycles"],
                acc=float(row["acceptance"]),
                ex=float(row["effective_x_jump_sq_mean"]),
                ez=float(row["effective_z_jump_sq_mean"]),
                et=float(row["effective_flow_time_jump_abs_mean"]),
                tm=float(row["flow_time_mean"]),
                tx=float(row["flow_time_max"]),
                hr=float(row["measurement_hist_max_min_ratio"]),
                hz=row["measurement_hist_zero_bins"],
                rg=float(row["reverse_gate_rejected_per_cycle"]),
                fail=float(row["transitions_failed_per_cycle"]),
                rt=float(row["runtime_sec_median_seed"]),
            )
        )
    path.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--group-keys", default=DEFAULT_GROUP_KEYS)
    args = parser.parse_args()
    group_keys = [key.strip() for key in args.group_keys.split(",") if key.strip()]
    records = collect_rows(args.root)
    groups = {}
    for row in records:
        key = group_key(row, group_keys)
        groups.setdefault(key, []).append(row)
    rows = [
        summarize_group("|".join(key), group_rows, group_keys)
        for key, group_rows in sorted(groups.items())
    ]
    args.out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.out_dir / "wv_hmc_scan_summary.csv"
    md_path = args.out_dir / "wv_hmc_scan_summary.md"
    json_path = args.out_dir / "wv_hmc_scan_summary_metadata.json"
    write_csv(csv_path, rows)
    write_markdown(md_path, rows, group_keys)
    json_path.write_text(json.dumps({
        "root": str(args.root),
        "records": len(records),
        "groups": len(rows),
        "group_keys": group_keys,
    }, indent=2, sort_keys=True) + "\n")
    for path in [md_path, csv_path, json_path]:
        print(path)


if __name__ == "__main__":
    main()
