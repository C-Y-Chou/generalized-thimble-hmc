#!/usr/bin/env python3
"""Streaming readback for the WV-HMC Stephanov n=6 15k production run."""

import argparse
import csv
import glob
import json
import math
import os
import re
import statistics
import time


EXACT = {
    "chiral_condensate": 0.0244771983,
    "number_density": 0.5661155667,
}


def seed_from_path(path):
    match = re.search(r"seed_(\d+)_", os.path.basename(path))
    return int(match.group(1)) if match else -1


def empty_block(obs_count):
    return {
        "seed": -1,
        "samples": 0,
        "d_re": 0.0,
        "d_im": 0.0,
        "absw": 0.0,
        "num_re": [0.0] * obs_count,
        "num_im": [0.0] * obs_count,
        "cycle_min": 10**18,
        "cycle_max": -1,
    }


def add_values(block, cycle, weight_re, weight_im, abs_weight, nums_re, nums_im):
    block["samples"] += 1
    block["cycle_min"] = min(block["cycle_min"], cycle)
    block["cycle_max"] = max(block["cycle_max"], cycle)
    block["d_re"] += weight_re
    block["d_im"] += weight_im
    block["absw"] += abs_weight
    for idx in range(len(nums_re)):
        block["num_re"][idx] += nums_re[idx]
        block["num_im"][idx] += nums_im[idx]


def add_block(target, source):
    target["samples"] += source["samples"]
    target["d_re"] += source["d_re"]
    target["d_im"] += source["d_im"]
    target["absw"] += source["absw"]
    target["cycle_min"] = min(target["cycle_min"], source["cycle_min"])
    target["cycle_max"] = max(target["cycle_max"], source["cycle_max"])
    for idx in range(len(target["num_re"])):
        target["num_re"][idx] += source["num_re"][idx]
        target["num_im"][idx] += source["num_im"][idx]


def subtract_block(total, source):
    out = empty_block(len(total["num_re"]))
    out["samples"] = total["samples"] - source["samples"]
    out["d_re"] = total["d_re"] - source["d_re"]
    out["d_im"] = total["d_im"] - source["d_im"]
    out["absw"] = total["absw"] - source["absw"]
    out["cycle_min"] = total["cycle_min"]
    out["cycle_max"] = total["cycle_max"]
    for idx in range(len(total["num_re"])):
        out["num_re"][idx] = total["num_re"][idx] - source["num_re"][idx]
        out["num_im"][idx] = total["num_im"][idx] - source["num_im"][idx]
    return out


def estimate(block, idx):
    den = block["d_re"] * block["d_re"] + block["d_im"] * block["d_im"]
    if den <= 0.0:
        return float("nan"), float("nan")
    nr = block["num_re"][idx]
    ni = block["num_im"][idx]
    return (
        (nr * block["d_re"] + ni * block["d_im"]) / den,
        (ni * block["d_re"] - nr * block["d_im"]) / den,
    )


def jk_se(values):
    if len(values) < 2:
        return float("nan")
    mean = sum(values) / float(len(values))
    return math.sqrt((len(values) - 1.0) / len(values) * sum((value - mean) ** 2 for value in values))


def summarize_blocks(cut, blocks, names):
    total = empty_block(len(names))
    for block in blocks:
        add_block(total, block)
    rows = []
    for idx, name in enumerate(names):
        est_re, est_im = estimate(total, idx)
        jk_re = []
        jk_im = []
        for block in blocks:
            leave = subtract_block(total, block)
            value_re, value_im = estimate(leave, idx)
            jk_re.append(value_re)
            jk_im.append(value_im)
        se_re = jk_se(jk_re)
        se_im = jk_se(jk_im)
        target = EXACT.get(name)
        z_re = ""
        z_im = ""
        if target is not None and se_re > 0.0:
            z_re = (est_re - target) / se_re
        if target is not None and se_im > 0.0:
            z_im = est_im / se_im
        rows.append({
            "cut": cut,
            "error_method": "seed_jackknife",
            "blocks": len(blocks),
            "seeds": len([block for block in blocks if block.get("seed", -1) >= 0]),
            "samples": total["samples"],
            "cycle_min": total["cycle_min"],
            "cycle_max": total["cycle_max"],
            "phase_coherence": math.hypot(total["d_re"], total["d_im"]) / total["absw"] if total["absw"] > 0.0 else float("nan"),
            "denominator_re": total["d_re"],
            "denominator_im": total["d_im"],
            "abs_denominator": math.hypot(total["d_re"], total["d_im"]),
            "sum_abs_weight": total["absw"],
            "observable": name,
            "estimate_re": est_re,
            "estimate_im": est_im,
            "se_re": se_re,
            "se_im": se_im,
            "target_re": "" if target is None else target,
            "target_im": "" if target is None else 0.0,
            "z_re": z_re,
            "z_im": z_im,
        })
    return rows


def read_observable_names(root):
    paths = sorted(glob.glob(os.path.join(root, "chunks/chunk_*/*_observables.csv")))
    if not paths:
        raise RuntimeError("no observables files found")
    rows = []
    with open(paths[0], newline="") as handle:
        for row in csv.DictReader(handle):
            rows.append(row["name"])
    return rows


def read_csv_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle))


def safe_int(row, key):
    try:
        return int(float(row.get(key, "0") or 0))
    except ValueError:
        return 0


def safe_float(row, key):
    try:
        return float(row.get(key, "nan"))
    except ValueError:
        return float("nan")


def write_csv(path, rows):
    keys = []
    for row in rows:
        for key in row:
            if key not in keys:
                keys.append(key)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)


def fmt(value):
    if value == "":
        return ""
    try:
        return "{:.6g}".format(float(value))
    except (TypeError, ValueError):
        return str(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--prefix-cycles", default="5000,10000,15000")
    parser.add_argument("--half-cycle", type=int, default=7500)
    args = parser.parse_args()

    t0 = time.time()
    prefixes = [int(part) for part in args.prefix_cycles.split(",") if part.strip()]
    names = read_observable_names(args.root)
    obs_count = len(names)
    history_paths = sorted(glob.glob(os.path.join(args.root, "chunks/chunk_*/*_observable_history.csv")))
    all_by_seed = {}
    prefix_by_seed = {prefix: {} for prefix in prefixes}
    half_by_seed = {"first_half": {}, "second_half": {}}
    seed_rows = []

    for path in history_paths:
        seed = seed_from_path(path)
        all_block = empty_block(obs_count)
        all_block["seed"] = seed
        prefix_blocks = {prefix: empty_block(obs_count) for prefix in prefixes}
        half_blocks = {"first_half": empty_block(obs_count), "second_half": empty_block(obs_count)}
        for block in prefix_blocks.values():
            block["seed"] = seed
        for block in half_blocks.values():
            block["seed"] = seed
        with open(path, newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            index = {name: idx for idx, name in enumerate(header)}
            num_re_idx = [index["num_{}_re".format(i + 1)] for i in range(obs_count)]
            num_im_idx = [index["num_{}_im".format(i + 1)] for i in range(obs_count)]
            for row in reader:
                if not row:
                    continue
                cycle = int(float(row[index["cycle"]]))
                weight_re = float(row[index["weight_re"]])
                weight_im = float(row[index["weight_im"]])
                abs_weight = float(row[index["abs_weight"]])
                nums_re = [float(row[idx]) for idx in num_re_idx]
                nums_im = [float(row[idx]) for idx in num_im_idx]
                add_values(all_block, cycle, weight_re, weight_im, abs_weight, nums_re, nums_im)
                for prefix in prefixes:
                    if cycle <= prefix:
                        add_values(prefix_blocks[prefix], cycle, weight_re, weight_im, abs_weight, nums_re, nums_im)
                half_name = "first_half" if cycle <= args.half_cycle else "second_half"
                add_values(half_blocks[half_name], cycle, weight_re, weight_im, abs_weight, nums_re, nums_im)
        all_by_seed[seed] = all_block
        for prefix, block in prefix_blocks.items():
            if block["samples"] > 0:
                prefix_by_seed[prefix][seed] = block
        for half_name, block in half_blocks.items():
            if block["samples"] > 0:
                half_by_seed[half_name][seed] = block
        seed_row = {
            "seed": seed,
            "samples": all_block["samples"],
            "cycle_min": all_block["cycle_min"],
            "cycle_max": all_block["cycle_max"],
            "phase_coherence": math.hypot(all_block["d_re"], all_block["d_im"]) / all_block["absw"] if all_block["absw"] > 0.0 else float("nan"),
            "abs_denominator": math.hypot(all_block["d_re"], all_block["d_im"]),
        }
        for idx, name in enumerate(names):
            value_re, value_im = estimate(all_block, idx)
            seed_row["{}_re".format(name)] = value_re
            seed_row["{}_im".format(name)] = value_im
        seed_rows.append(seed_row)

    estimator_rows = []
    estimator_rows.extend(summarize_blocks("all", list(all_by_seed.values()), names))
    estimator_rows.extend(summarize_blocks("first_half", list(half_by_seed["first_half"].values()), names))
    estimator_rows.extend(summarize_blocks("second_half", list(half_by_seed["second_half"].values()), names))
    for prefix in prefixes:
        estimator_rows.extend(summarize_blocks("prefix_{}".format(prefix), list(prefix_by_seed[prefix].values()), names))

    summary_rows = []
    for path in glob.glob(os.path.join(args.root, "chunks/chunk_*/seed_*_summary.csv")):
        summary_rows.extend(read_csv_rows(path))
    manifest_rows = []
    for path in glob.glob(os.path.join(args.root, "chunks/chunk_*/wv_hmc_dense_observable_validation_manifest.csv")):
        manifest_rows.extend(read_csv_rows(path))

    diagnostics = {
        "root": args.root,
        "history_files": len(history_paths),
        "summary_rows": len(summary_rows),
        "manifest_rows": len(manifest_rows),
        "observable_names": names,
        "elapsed_analysis_sec": time.time() - t0,
    }
    for key in [
        "cycles_completed", "accepted", "rejected", "transitions_failed",
        "metropolis_rejected", "reverse_gate_rejected", "reverse_gate_checked",
        "reverse_gate_failed", "measurement_attempted", "measurement_included",
        "measurement_skipped", "measurement_failed", "solver_stop_converged",
        "solver_stop_max_iter", "solver_stop_boundary_exit", "odex_calls",
        "odex_failure", "trajectory_steps", "bounced_steps",
    ]:
        diagnostics[key] = sum(safe_int(row, key) for row in summary_rows)
    runtimes = [safe_float(row, "runtime_sec") for row in manifest_rows]
    runtimes = sorted(value for value in runtimes if math.isfinite(value))
    if runtimes:
        diagnostics.update({
            "runtime_sec_sum_over_seeds": sum(runtimes),
            "runtime_sec_min_seed": min(runtimes),
            "runtime_sec_median_seed": statistics.median(runtimes),
            "runtime_sec_mean_seed": sum(runtimes) / len(runtimes),
            "runtime_sec_p90_seed": runtimes[int(0.9 * (len(runtimes) - 1))],
            "runtime_sec_max_seed": max(runtimes),
            "seed_node_hours_sum": sum(runtimes) / 3600.0,
        })
    cycles = diagnostics["cycles_completed"]
    diagnostics["acceptance_rate"] = diagnostics["accepted"] / float(cycles) if cycles else float("nan")
    diagnostics["rejected_rate"] = diagnostics["rejected"] / float(cycles) if cycles else float("nan")
    diagnostics["transitions_failed_per_cycle"] = diagnostics["transitions_failed"] / float(cycles) if cycles else float("nan")
    diagnostics["reverse_gate_failed_per_checked"] = diagnostics["reverse_gate_failed"] / float(diagnostics["reverse_gate_checked"]) if diagnostics["reverse_gate_checked"] else float("nan")
    diagnostics["odex_failure_per_call"] = diagnostics["odex_failure"] / float(diagnostics["odex_calls"]) if diagnostics["odex_calls"] else float("nan")
    diagnostics["boundary_per_trajectory_step"] = diagnostics["bounced_steps"] / float(diagnostics["trajectory_steps"]) if diagnostics["trajectory_steps"] else float("nan")

    os.makedirs(args.out_dir, exist_ok=True)
    estimator_path = os.path.join(args.out_dir, "estimator_summary.csv")
    seed_path = os.path.join(args.out_dir, "seed_summary.csv")
    diagnostics_path = os.path.join(args.out_dir, "run_diagnostics.json")
    markdown_path = os.path.join(args.out_dir, "README.md")
    write_csv(estimator_path, estimator_rows)
    write_csv(seed_path, seed_rows)
    with open(diagnostics_path, "w") as handle:
        json.dump(diagnostics, handle, indent=2, sort_keys=True)

    lines = [
        "# WV-HMC N6 t=0.03 15k Streaming Readback",
        "",
        "Root: `{}`".format(args.root),
        "",
        "## Diagnostics",
        "",
        "| item | value |",
        "|---|---:|",
    ]
    for key in [
        "history_files", "summary_rows", "manifest_rows", "cycles_completed",
        "measurement_included", "acceptance_rate", "transitions_failed_per_cycle",
        "reverse_gate_failed_per_checked", "odex_failure_per_call",
        "runtime_sec_median_seed", "runtime_sec_max_seed", "seed_node_hours_sum",
    ]:
        lines.append("| {} | {} |".format(key, diagnostics.get(key)))
    lines.extend([
        "",
        "## All Seed Jackknife",
        "",
        "| observable | Re | SE Re | z Re | Im | SE Im | z Im | phase C | samples |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ])
    for row in [r for r in estimator_rows if r["cut"] == "all"]:
        lines.append(
            "| {observable} | {estimate_re} | {se_re} | {z_re} | {estimate_im} | {se_im} | {z_im} | {phase} | {samples} |".format(
                observable=row["observable"],
                estimate_re=fmt(row["estimate_re"]),
                se_re=fmt(row["se_re"]),
                z_re=fmt(row["z_re"]),
                estimate_im=fmt(row["estimate_im"]),
                se_im=fmt(row["se_im"]),
                z_im=fmt(row["z_im"]),
                phase=fmt(row["phase_coherence"]),
                samples=row["samples"],
            )
        )
    lines.extend([
        "",
        "## Exact-Reference Prefix Z",
        "",
        "| cut | chiral Re z | chiral Im z | density Re z | density Im z | phase C | samples |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ])
    by_cut = {}
    for row in estimator_rows:
        if row["observable"] in ("chiral_condensate", "number_density"):
            by_cut.setdefault(row["cut"], {})[row["observable"]] = row
    for cut in ["prefix_5000", "prefix_10000", "prefix_15000", "first_half", "second_half", "all"]:
        data = by_cut.get(cut, {})
        ch = data.get("chiral_condensate", {})
        de = data.get("number_density", {})
        lines.append("| {} | {} | {} | {} | {} | {} | {} |".format(
            cut,
            fmt(ch.get("z_re", "")),
            fmt(ch.get("z_im", "")),
            fmt(de.get("z_re", "")),
            fmt(de.get("z_im", "")),
            fmt(ch.get("phase_coherence", "")),
            ch.get("samples", ""),
        ))
    lines.extend([
        "",
        "Artifacts:",
        "- `{}`".format(estimator_path),
        "- `{}`".format(seed_path),
        "- `{}`".format(diagnostics_path),
    ])
    with open(markdown_path, "w") as handle:
        handle.write("\n".join(lines) + "\n")

    print(markdown_path)
    print(estimator_path)
    print(seed_path)
    print(diagnostics_path)


if __name__ == "__main__":
    main()
