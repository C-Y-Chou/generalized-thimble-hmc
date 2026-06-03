#!/usr/bin/env python3
"""Summarize WV-HMC T0=0 retune scans, including partial running chunks.

Unlike the generic scan summarizer, this helper can recover `step_size` and
`num_steps` from PBS boot logs before per-chunk manifests are written.
"""

import argparse
import csv
import math
import os
import re
from pathlib import Path


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


def parse_hist(text):
    if not text:
        return []
    return [safe_int(part) for part in str(text).split(";") if part != ""]


def merge_hist(rows, key):
    hist = []
    for row in rows:
        counts = parse_hist(row.get(key, ""))
        if not counts:
            continue
        if not hist:
            hist = [0] * len(counts)
        if len(counts) != len(hist):
            continue
        for idx, count in enumerate(counts):
            hist[idx] += count
    return hist


def hist_ratio(hist):
    nonzero = [value for value in hist if value > 0]
    if not nonzero:
        return float("nan")
    return max(nonzero) / float(min(nonzero))


def hist_adjacent_flatness(hist):
    terms = []
    for left, right in zip(hist[:-1], hist[1:]):
        denom = 0.5 * (left + right)
        if denom > 0.0:
            terms.append(((right - left) / denom) ** 2)
    return sum(terms) / len(terms) if terms else float("nan")


def weighted_mean(rows, value_key, weight_key):
    numerator = 0.0
    denominator = 0.0
    for row in rows:
        value = safe_float(row.get(value_key))
        weight = safe_float(row.get(weight_key), 0.0)
        if math.isfinite(value) and weight > 0.0:
            numerator += value * weight
            denominator += weight
    return numerator / denominator if denominator > 0.0 else float("nan")


def job_id_from_chunk_dir(path):
    match = re.search(r"_(\d+\.anode\d+)$", path.name)
    return match.group(1) if match else ""


def read_boot_vars(log_root):
    out = {}
    if not log_root.exists():
        return out
    keys = {
        "WV_OBS_STEP_SIZE",
        "WV_OBS_NUM_STEPS",
        "WV_OBS_W_GAMMA",
        "WV_OBS_T0",
        "WV_OBS_T1",
        "WV_OBS_D0",
        "WV_OBS_D1",
    }
    for path in sorted(log_root.glob("pbs_boot_*.log")):
        job_id = path.name.replace("pbs_boot_", "").replace(".log", "")
        row = {}
        with path.open(errors="ignore") as handle:
            for line in handle:
                if "=" not in line:
                    continue
                key, value = line.strip().split("=", 1)
                if key in keys:
                    row[key] = value
        out[job_id] = row
    return out


def read_manifest_vars(run_root):
    out = {}
    for path in sorted(run_root.glob("chunks/chunk_*/wv_hmc_dense_observable_validation_manifest.csv")):
        chunk = path.parent.name
        with path.open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        if not rows:
            continue
        row = rows[0]
        out[chunk] = {
            "WV_OBS_STEP_SIZE": row.get("step_size", ""),
            "WV_OBS_NUM_STEPS": row.get("num_steps", ""),
            "WV_OBS_W_GAMMA": row.get("w_gamma", ""),
            "WV_OBS_T0": row.get("sampler_t0", ""),
            "WV_OBS_T1": row.get("sampler_t1", ""),
            "WV_OBS_D0": row.get("d0", ""),
            "WV_OBS_D1": row.get("d1", ""),
        }
    return out


def collect_rows(run_root, log_root):
    boot_vars = read_boot_vars(log_root)
    manifest_vars = read_manifest_vars(run_root)
    rows = []
    for path in sorted(run_root.glob("chunks/chunk_*/*_summary.csv")):
        with path.open(newline="") as handle:
            source_rows = list(csv.DictReader(handle))
        if len(source_rows) != 1:
            continue
        row = dict(source_rows[0])
        chunk_dir = path.parent
        job_id = job_id_from_chunk_dir(chunk_dir)
        params = {}
        params.update(boot_vars.get(job_id, {}))
        params.update(manifest_vars.get(chunk_dir.name, {}))
        row["scan_step_size"] = params.get("WV_OBS_STEP_SIZE", "")
        row["scan_num_steps"] = params.get("WV_OBS_NUM_STEPS", "")
        row["scan_w_gamma"] = row.get("w_gamma") or params.get("WV_OBS_W_GAMMA", "")
        row["chunk_dir"] = str(chunk_dir)
        row["summary_path"] = str(path)
        rows.append(row)
    return rows


def summarize_group(key, rows):
    gamma, step_size, num_steps = key
    cycles = sum(safe_int(row.get("cycles_completed")) for row in rows)
    accepted = sum(safe_int(row.get("accepted")) for row in rows)
    rejected = sum(safe_int(row.get("rejected")) for row in rows)
    transitions_failed = sum(safe_int(row.get("transitions_failed")) for row in rows)
    metropolis = sum(safe_int(row.get("metropolis_rejected")) for row in rows)
    reverse_gate = sum(safe_int(row.get("reverse_gate_rejected")) for row in rows)
    odex_failure = sum(safe_int(row.get("odex_failure")) for row in rows)
    solver_iterations = sum(safe_int(row.get("solver_iterations")) for row in rows)
    reverse_solver_iterations = sum(safe_int(row.get("reverse_solver_iterations")) for row in rows)
    measurement_included = sum(safe_int(row.get("measurement_included")) for row in rows)
    measurement_failed = sum(safe_int(row.get("measurement_failed")) for row in rows)
    flow_hist = merge_hist(rows, "flow_time_hist_inside")
    measurement_hist = merge_hist(rows, "measurement_flow_time_hist_inside")
    return {
        "w_gamma": gamma,
        "step_size": step_size,
        "num_steps": num_steps,
        "seeds_with_summary": len(rows),
        "cycles_completed": cycles,
        "measurement_included": measurement_included,
        "measurement_failed": measurement_failed,
        "acceptance": accepted / float(cycles) if cycles else float("nan"),
        "accepted_over_acc_plus_rej": accepted / float(accepted + rejected) if accepted + rejected else float("nan"),
        "transitions_failed_per_cycle": transitions_failed / float(cycles) if cycles else float("nan"),
        "reverse_gate_rejected_per_cycle": reverse_gate / float(cycles) if cycles else float("nan"),
        "metropolis_rejected_per_cycle": metropolis / float(cycles) if cycles else float("nan"),
        "odex_failure_per_cycle": odex_failure / float(cycles) if cycles else float("nan"),
        "solver_iterations_per_cycle": solver_iterations / float(cycles) if cycles else float("nan"),
        "reverse_solver_iterations_per_cycle": reverse_solver_iterations / float(cycles) if cycles else float("nan"),
        "effective_x_jump_sq_mean": weighted_mean(rows, "effective_x_jump_sq_mean", "cycles_completed"),
        "effective_z_jump_sq_mean": weighted_mean(rows, "effective_z_jump_sq_mean", "cycles_completed"),
        "effective_flow_time_jump_abs_mean": weighted_mean(rows, "effective_flow_time_jump_abs_mean", "cycles_completed"),
        "accepted_x_jump_sq_mean": weighted_mean(rows, "accepted_x_jump_sq_mean", "accepted_jump_count"),
        "accepted_z_jump_sq_mean": weighted_mean(rows, "accepted_z_jump_sq_mean", "accepted_jump_count"),
        "accepted_flow_time_jump_abs_mean": weighted_mean(rows, "accepted_flow_time_jump_abs_mean", "accepted_jump_count"),
        "flow_time_mean": weighted_mean(rows, "flow_time_mean", "flow_time_observations"),
        "flow_time_min": min(safe_float(row.get("flow_time_min")) for row in rows),
        "flow_time_max": max(safe_float(row.get("flow_time_max")) for row in rows),
        "flow_hist_zero_bins": len(flow_hist) - len([value for value in flow_hist if value > 0]),
        "flow_hist_max_min_ratio": hist_ratio(flow_hist),
        "flow_hist_adjacent_flatness": hist_adjacent_flatness(flow_hist),
        "measurement_hist_zero_bins": len(measurement_hist) - len([value for value in measurement_hist if value > 0]),
        "measurement_hist_max_min_ratio": hist_ratio(measurement_hist),
        "measurement_hist_adjacent_flatness": hist_adjacent_flatness(measurement_hist),
    }


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
        writer.writerows(rows)


def write_markdown(path, rows):
    lines = [
        "# WV-HMC T0 Retune Scan Summary",
        "",
        "| gamma | eps | nstep | seeds | cycles | acc | fail/cyc | RG/cyc | t_mean | t_max | hist ratio | eff_x | eff_t |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| {w_gamma:g} | {step_size:g} | {num_steps:g} | {seeds_with_summary} | {cycles_completed} | "
            "{acceptance:.4g} | {transitions_failed_per_cycle:.4g} | {reverse_gate_rejected_per_cycle:.4g} | "
            "{flow_time_mean:.5g} | {flow_time_max:.5g} | {measurement_hist_max_min_ratio:.4g} | "
            "{effective_x_jump_sq_mean:.4g} | {effective_flow_time_jump_abs_mean:.4g} |".format(**row)
        )
    path.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--log-root", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    records = collect_rows(args.run_root, args.log_root)
    groups = {}
    for row in records:
        key = (
            safe_float(row.get("scan_w_gamma")),
            safe_float(row.get("scan_step_size")),
            safe_int(row.get("scan_num_steps")),
        )
        groups.setdefault(key, []).append(row)
    rows = [summarize_group(key, group_rows) for key, group_rows in sorted(groups.items())]
    write_csv(args.out_dir / "wv_hmc_t0_retune_scan_summary.csv", rows)
    write_markdown(args.out_dir / "wv_hmc_t0_retune_scan_summary.md", rows)
    print(args.out_dir / "wv_hmc_t0_retune_scan_summary.csv")
    print(args.out_dir / "wv_hmc_t0_retune_scan_summary.md")


if __name__ == "__main__":
    main()
