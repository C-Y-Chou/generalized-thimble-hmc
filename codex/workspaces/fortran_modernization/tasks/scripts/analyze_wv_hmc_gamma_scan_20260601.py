#!/usr/bin/env python3
"""Summarize short WV-HMC gamma scans.

Reads a scan root containing one run directory per gamma value.  The script is
safe on partial outputs: it reports whatever histories and summaries are present.
"""

import argparse
import csv
import glob
import math
import os
import re
from collections import defaultdict


EXACT = {
    "chiral_condensate": 0.0244771983,
    "number_density": 0.5661155667,
}


def gamma_from_text(text):
    match = re.search(r"gamma([0-9]+)", text)
    if match:
        return float(match.group(1))
    return float("nan")


def seed_from_path(path):
    match = re.search(r"seed_(\d+)_", os.path.basename(path))
    return int(match.group(1)) if match else -1


def zero(nobs):
    return {
        "samples": 0,
        "d_re": 0.0,
        "d_im": 0.0,
        "absw": 0.0,
        "num_re": [0.0] * nobs,
        "num_im": [0.0] * nobs,
    }


def add_sample(block, w_re, w_im, absw, nums_re, nums_im):
    block["samples"] += 1
    block["d_re"] += w_re
    block["d_im"] += w_im
    block["absw"] += absw
    for idx in range(len(nums_re)):
        block["num_re"][idx] += nums_re[idx]
        block["num_im"][idx] += nums_im[idx]


def add_block(total, block):
    total["samples"] += block["samples"]
    total["d_re"] += block["d_re"]
    total["d_im"] += block["d_im"]
    total["absw"] += block["absw"]
    for idx in range(len(total["num_re"])):
        total["num_re"][idx] += block["num_re"][idx]
        total["num_im"][idx] += block["num_im"][idx]


def subtract_block(total, block):
    out = zero(len(total["num_re"]))
    out["samples"] = total["samples"] - block["samples"]
    out["d_re"] = total["d_re"] - block["d_re"]
    out["d_im"] = total["d_im"] - block["d_im"]
    out["absw"] = total["absw"] - block["absw"]
    for idx in range(len(total["num_re"])):
        out["num_re"][idx] = total["num_re"][idx] - block["num_re"][idx]
        out["num_im"][idx] = total["num_im"][idx] - block["num_im"][idx]
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
    values = [value for value in values if math.isfinite(value)]
    if len(values) < 2:
        return float("nan")
    mean = sum(values) / float(len(values))
    return math.sqrt((len(values) - 1.0) / len(values) * sum((value - mean) ** 2 for value in values))


def observable_names(run_root):
    paths = sorted(glob.glob(os.path.join(run_root, "chunks", "chunk_*", "*_observables.csv")))
    if not paths:
        return []
    with open(paths[0], newline="") as handle:
        return [row["name"] for row in csv.DictReader(handle)]


def empty_hist_bins(bins):
    return [
        {
            "count": 0,
            "sum_abs_weight": 0.0,
            "denominator_re": 0.0,
            "denominator_im": 0.0,
        }
        for _ in range(bins)
    ]


def hist_index(value, bins, t0, t1):
    if t1 <= t0:
        return -1
    width = (t1 - t0) / float(bins)
    if value < t0 or value > t1:
        return -1
    return min(bins - 1, max(0, int((value - t0) / width)))


def summarize_run(run_root, bins, t0, t1):
    gamma = gamma_from_text(os.path.basename(run_root))
    names = observable_names(run_root)
    seed_blocks = {}
    flow_times = []
    hist_bins = empty_hist_bins(bins)
    last_cycles = []
    history_files = sorted(glob.glob(os.path.join(run_root, "chunks", "chunk_*", "*_observable_history.csv")))
    for path in history_files:
        seed = seed_from_path(path)
        block = zero(len(names))
        last_cycle = 0
        with open(path, newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader, None)
            if header is None:
                continue
            index = {name: idx for idx, name in enumerate(header)}
            if "cycle" not in index or "flow_time" not in index:
                continue
            num_re_idx = [index["num_{}_re".format(i + 1)] for i in range(len(names))] if names else []
            num_im_idx = [index["num_{}_im".format(i + 1)] for i in range(len(names))] if names else []
            for row in reader:
                last_cycle = int(float(row[index["cycle"]]))
                flow_time = float(row[index["flow_time"]])
                flow_times.append(flow_time)
                bin_idx = hist_index(flow_time, bins, t0, t1)
                if bin_idx >= 0:
                    hist_bins[bin_idx]["count"] += 1
                    hist_bins[bin_idx]["sum_abs_weight"] += float(row[index["abs_weight"]])
                    hist_bins[bin_idx]["denominator_re"] += float(row[index["weight_re"]])
                    hist_bins[bin_idx]["denominator_im"] += float(row[index["weight_im"]])
                if not names:
                    continue
                w_re = float(row[index["weight_re"]])
                w_im = float(row[index["weight_im"]])
                absw = float(row[index["abs_weight"]])
                nums_re = [float(row[idx]) for idx in num_re_idx]
                nums_im = [float(row[idx]) for idx in num_im_idx]
                add_sample(block, w_re, w_im, absw, nums_re, nums_im)
        if names and block["samples"] > 0:
            seed_blocks[seed] = block
        last_cycles.append(last_cycle)

    summary_rows = []
    blocks = list(seed_blocks.values())
    if blocks:
        total = zero(len(names))
        for block in blocks:
            add_block(total, block)
        phase_c = math.hypot(total["d_re"], total["d_im"]) / total["absw"] if total["absw"] > 0 else float("nan")
        for idx, name in enumerate(names):
            est_re, est_im = estimate(total, idx)
            jk_re, jk_im = [], []
            for block in blocks:
                leave = subtract_block(total, block)
                value_re, value_im = estimate(leave, idx)
                jk_re.append(value_re)
                jk_im.append(value_im)
            se_re = jk_se(jk_re)
            se_im = jk_se(jk_im)
            target = EXACT.get(name)
            summary_rows.append({
                "gamma": gamma,
                "run_root": run_root,
                "history_files": len(history_files),
                "seeds_with_samples": len(blocks),
                "samples": total["samples"],
                "last_cycle_min": min(last_cycles) if last_cycles else 0,
                "last_cycle_median": sorted(last_cycles)[len(last_cycles)//2] if last_cycles else 0,
                "last_cycle_max": max(last_cycles) if last_cycles else 0,
                "flow_time_mean": sum(flow_times) / float(len(flow_times)) if flow_times else float("nan"),
                "flow_time_p10": percentile(flow_times, 0.10),
                "flow_time_p50": percentile(flow_times, 0.50),
                "flow_time_p90": percentile(flow_times, 0.90),
                "phase_coherence": phase_c,
                "observable": name,
                "estimate_re": est_re,
                "estimate_im": est_im,
                "se_re": se_re,
                "se_im": se_im,
                "z_re": (est_re - target) / se_re if target is not None and se_re > 0 else "",
                "z_im": est_im / se_im if target is not None and se_im > 0 else "",
            })

    hist_rows = []
    total_count = sum(item["count"] for item in hist_bins)
    total_abs_weight = sum(item["sum_abs_weight"] for item in hist_bins)
    width = (t1 - t0) / float(bins)
    for idx, item in enumerate(hist_bins):
        abs_den = math.hypot(item["denominator_re"], item["denominator_im"])
        hist_rows.append({
            "gamma": gamma,
            "bin": idx,
            "t_low": t0 + idx * width,
            "t_high": t0 + (idx + 1) * width,
            "count": item["count"],
            "count_fraction": item["count"] / float(total_count) if total_count else float("nan"),
            "sum_abs_weight": item["sum_abs_weight"],
            "sum_abs_weight_fraction": item["sum_abs_weight"] / total_abs_weight if total_abs_weight else float("nan"),
            "abs_denominator": abs_den,
            "phase_coherence": abs_den / item["sum_abs_weight"] if item["sum_abs_weight"] > 0 else float("nan"),
        })
    return summary_rows, hist_rows


def percentile(values, q):
    values = sorted(value for value in values if math.isfinite(value))
    if not values:
        return float("nan")
    pos = q * (len(values) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return values[lo]
    frac = pos - lo
    return values[lo] * (1.0 - frac) + values[hi] * frac


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--bins", type=int, default=16)
    parser.add_argument("--t0", type=float, default=0.0001)
    parser.add_argument("--t1", type=float, default=0.03)
    args = parser.parse_args()

    run_roots = sorted(path for path in glob.glob(os.path.join(args.root, "wv_hmc_n6_t003_gamma*_gitless_20260601")) if os.path.isdir(path))
    if not run_roots:
        raise RuntimeError("no gamma run roots under {}".format(args.root))
    all_summary = []
    all_hist = []
    for run_root in run_roots:
        summary_rows, hist_rows = summarize_run(run_root, args.bins, args.t0, args.t1)
        all_summary.extend(summary_rows)
        all_hist.extend(hist_rows)
    os.makedirs(args.out_dir, exist_ok=True)
    summary_path = os.path.join(args.out_dir, "gamma_scan_estimator_summary.csv")
    hist_path = os.path.join(args.out_dir, "gamma_scan_flow_histogram.csv")
    if all_summary:
        with open(summary_path, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(all_summary[0].keys()))
            writer.writeheader()
            writer.writerows(all_summary)
    with open(hist_path, "w", newline="") as handle:
        if all_hist:
            writer = csv.DictWriter(handle, fieldnames=list(all_hist[0].keys()))
            writer.writeheader()
            writer.writerows(all_hist)
    print(summary_path if all_summary else "no estimator rows yet")
    print(hist_path)
    for row in all_summary:
        if row["observable"] in ("chiral_condensate", "number_density"):
            print(
                "gamma {:5.1f} {:18s} samples={} t50={:.5f} C={:.5g} Re={:.8g} z={}".format(
                    float(row["gamma"]),
                    row["observable"],
                    int(row["samples"]),
                    float(row["flow_time_p50"]),
                    float(row["phase_coherence"]),
                    float(row["estimate_re"]),
                    "{:.3f}".format(float(row["z_re"])) if row["z_re"] != "" else "",
                )
            )


if __name__ == "__main__":
    main()
