#!/usr/bin/env python3
"""Flow-time-bin WV-HMC ratio diagnostics."""

import argparse
import csv
import glob
import math
import os
import re


EXACT = {
    "chiral_condensate": 0.0244771983,
    "number_density": 0.5661155667,
}


def seed_from_path(path):
    match = re.search(r"seed_(\d+)_", os.path.basename(path))
    return int(match.group(1)) if match else -1


def empty(obs_count):
    return {
        "samples": 0,
        "d_re": 0.0,
        "d_im": 0.0,
        "absw": 0.0,
        "num_re": [0.0] * obs_count,
        "num_im": [0.0] * obs_count,
    }


def add_sample(block, w_re, w_im, nums_re, nums_im, absw):
    block["samples"] += 1
    block["d_re"] += w_re
    block["d_im"] += w_im
    block["absw"] += absw
    for idx in range(len(nums_re)):
        block["num_re"][idx] += nums_re[idx]
        block["num_im"][idx] += nums_im[idx]


def estimate(block, idx):
    den = block["d_re"]*block["d_re"] + block["d_im"]*block["d_im"]
    if den <= 0.0:
        return float("nan"), float("nan")
    nr = block["num_re"][idx]
    ni = block["num_im"][idx]
    return (nr*block["d_re"] + ni*block["d_im"])/den, (ni*block["d_re"] - nr*block["d_im"])/den


def observable_names(root):
    paths = sorted(glob.glob(os.path.join(root, "chunks/chunk_*/*_observables.csv")))
    if not paths:
        raise RuntimeError("no observables files under {}".format(root))
    out = []
    with open(paths[0], newline="") as handle:
        for row in csv.DictReader(handle):
            out.append(row["name"])
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--bins", type=int, default=16)
    parser.add_argument("--t0", type=float, default=1.0e-4)
    parser.add_argument("--t1", type=float, default=3.0e-2)
    args = parser.parse_args()

    names = observable_names(args.root)
    obs_count = len(names)
    bin_blocks = [empty(obs_count) for _ in range(args.bins)]
    seed_bin_blocks = [{} for _ in range(args.bins)]
    width = (args.t1 - args.t0) / float(args.bins)
    for path in sorted(glob.glob(os.path.join(args.root, "chunks/chunk_*/*_observable_history.csv"))):
        seed = seed_from_path(path)
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                t = float(row["flow_time"])
                if t < args.t0 or t > args.t1:
                    continue
                bin_idx = min(args.bins - 1, max(0, int((t - args.t0) / width)))
                w_re = float(row["weight_re"])
                w_im = float(row["weight_im"])
                absw = float(row["abs_weight"])
                nums_re = [float(row["num_{}_re".format(idx + 1)]) for idx in range(obs_count)]
                nums_im = [float(row["num_{}_im".format(idx + 1)]) for idx in range(obs_count)]
                add_sample(bin_blocks[bin_idx], w_re, w_im, nums_re, nums_im, absw)
                block = seed_bin_blocks[bin_idx].setdefault(seed, empty(obs_count))
                add_sample(block, w_re, w_im, nums_re, nums_im, absw)

    rows = []
    for bin_idx, block in enumerate(bin_blocks):
        t_low = args.t0 + width * bin_idx
        t_high = t_low + width
        for obs_idx, name in enumerate(names):
            est_re, est_im = estimate(block, obs_idx)
            # simple seed jackknife inside the bin
            jk_re = []
            jk_im = []
            for seed_block in seed_bin_blocks[bin_idx].values():
                leave = empty(obs_count)
                leave["samples"] = block["samples"] - seed_block["samples"]
                leave["d_re"] = block["d_re"] - seed_block["d_re"]
                leave["d_im"] = block["d_im"] - seed_block["d_im"]
                leave["absw"] = block["absw"] - seed_block["absw"]
                for j in range(obs_count):
                    leave["num_re"][j] = block["num_re"][j] - seed_block["num_re"][j]
                    leave["num_im"][j] = block["num_im"][j] - seed_block["num_im"][j]
                value_re, value_im = estimate(leave, obs_idx)
                jk_re.append(value_re)
                jk_im.append(value_im)
            def se(values):
                if len(values) < 2:
                    return float("nan")
                mean = sum(values)/float(len(values))
                return math.sqrt((len(values)-1.0)/len(values)*sum((value-mean)**2 for value in values))
            se_re = se(jk_re)
            se_im = se(jk_im)
            target = EXACT.get(name)
            rows.append({
                "bin": bin_idx,
                "t_low": t_low,
                "t_high": t_high,
                "observable": name,
                "samples": block["samples"],
                "seeds": len(seed_bin_blocks[bin_idx]),
                "phase_coherence": math.hypot(block["d_re"], block["d_im"])/block["absw"] if block["absw"] > 0.0 else float("nan"),
                "estimate_re": est_re,
                "estimate_im": est_im,
                "se_re": se_re,
                "se_im": se_im,
                "z_re": (est_re - target)/se_re if target is not None and se_re > 0.0 else "",
                "z_im": est_im/se_im if target is not None and se_im > 0.0 else "",
            })
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    keys = list(rows[0].keys()) if rows else []
    with open(args.out, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)
    print(args.out)


if __name__ == "__main__":
    main()
