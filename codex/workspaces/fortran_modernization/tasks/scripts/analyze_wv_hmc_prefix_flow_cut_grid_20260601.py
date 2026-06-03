#!/usr/bin/env python3
"""WV-HMC prefix-by-flow-cut diagnostic grid.

The grid tests whether the observed chiral bias is tied to measurement over
low/mid flow times, using only completed observable histories.
"""

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


def observable_names(root):
    paths = sorted(glob.glob(os.path.join(root, "chunks", "chunk_*", "*_observables.csv")))
    if not paths:
        raise RuntimeError("no observable files under {}".format(root))
    with open(paths[0], newline="") as handle:
        all_names = [row["name"] for row in csv.DictReader(handle)]
    return [name for name in all_names if name in ("chiral_condensate", "number_density")]


def build_grid(root, prefixes, cuts, names):
    grid = {(prefix, cut): {} for prefix in prefixes for cut in cuts}
    paths = sorted(glob.glob(os.path.join(root, "chunks", "chunk_*", "*_observable_history.csv")))
    if not paths:
        raise RuntimeError("no observable history files under {}".format(root))
    for path in paths:
        seed = seed_from_path(path)
        with open(path, newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            index = {name: idx for idx, name in enumerate(header)}
            names_in_file = []
            observable_paths = sorted(glob.glob(os.path.join(os.path.dirname(path), "*_observables.csv")))
            if observable_paths:
                with open(observable_paths[0], newline="") as obs_handle:
                    names_in_file = [row["name"] for row in csv.DictReader(obs_handle)]
            if not names_in_file:
                raise RuntimeError("missing observable names near {}".format(path))
            obs_indices = [names_in_file.index(name) + 1 for name in names]
            num_re_idx = [index["num_{}_re".format(obs_idx)] for obs_idx in obs_indices]
            num_im_idx = [index["num_{}_im".format(obs_idx)] for obs_idx in obs_indices]
            for row in reader:
                cycle = int(row[index["cycle"]])
                t = float(row[index["flow_time"]])
                active_prefixes = [prefix for prefix in prefixes if cycle <= prefix]
                if not active_prefixes:
                    break
                active_cuts = [cut for cut in cuts if t >= cut]
                if not active_cuts:
                    continue
                w_re = float(row[index["weight_re"]])
                w_im = float(row[index["weight_im"]])
                absw = float(row[index["abs_weight"]])
                nums_re = [float(row[idx]) for idx in num_re_idx]
                nums_im = [float(row[idx]) for idx in num_im_idx]
                for prefix in active_prefixes:
                    for cut in active_cuts:
                        block = grid[(prefix, cut)].setdefault(seed, zero(len(names)))
                        add_sample(block, w_re, w_im, absw, nums_re, nums_im)
    return grid


def summarize(prefix, cut, blocks_by_seed, names):
    blocks = list(blocks_by_seed.values())
    if not blocks:
        return []
    total = zero(len(names))
    for block in blocks:
        add_block(total, block)
    phase_c = math.hypot(total["d_re"], total["d_im"]) / total["absw"] if total["absw"] > 0 else float("nan")
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
        target = EXACT[name]
        rows.append({
            "prefix_cycle": prefix,
            "t_min": cut,
            "seeds": len(blocks),
            "samples": total["samples"],
            "phase_coherence": phase_c,
            "observable": name,
            "estimate_re": est_re,
            "estimate_im": est_im,
            "se_re": se_re,
            "se_im": se_im,
            "z_re": (est_re - target) / se_re if se_re > 0 else "",
            "z_im": est_im / se_im if se_im > 0 else "",
        })
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--prefixes", default="1500,2500,5000,10000,15000")
    parser.add_argument("--cuts", default="0.0001,0.02,0.025,0.028")
    args = parser.parse_args()
    prefixes = sorted({int(part) for part in args.prefixes.split(",") if part.strip()})
    cuts = sorted({float(part) for part in args.cuts.split(",") if part.strip()})
    names = observable_names(args.root)
    grid = build_grid(args.root, prefixes, cuts, names)
    rows = []
    for prefix in prefixes:
        for cut in cuts:
            rows.extend(summarize(prefix, cut, grid[(prefix, cut)], names))
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(args.out)
    for row in rows:
        print(
            "prefix {:5d} t>={:.4g} {:18s} Re={:.8g} SE={:.3g} z={:.3f} C={:.5g} n={}".format(
                int(row["prefix_cycle"]),
                float(row["t_min"]),
                row["observable"],
                float(row["estimate_re"]),
                float(row["se_re"]),
                float(row["z_re"]),
                float(row["phase_coherence"]),
                int(row["samples"]),
            )
        )


if __name__ == "__main__":
    main()
