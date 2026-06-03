#!/usr/bin/env python3
"""WV-HMC ratio summaries for diagnostic flow-time measurement cuts."""

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


def empty(nobs):
    return {
        "seed": -1,
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
    out = empty(len(total["num_re"]))
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
    if len(values) < 2:
        return float("nan")
    mean = sum(values) / float(len(values))
    return math.sqrt((len(values) - 1.0) / len(values) * sum((value - mean) ** 2 for value in values))


def observable_names(root):
    paths = sorted(glob.glob(os.path.join(root, "chunks", "chunk_*", "*_observables.csv")))
    if not paths:
        raise RuntimeError("no observable files under {}".format(root))
    with open(paths[0], newline="") as handle:
        return [row["name"] for row in csv.DictReader(handle)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--cuts", default="0.0001,0.002,0.005,0.01,0.015,0.02,0.025,0.028")
    parser.add_argument("--t-max", type=float, default=0.03)
    args = parser.parse_args()

    cuts = [float(part) for part in args.cuts.split(",") if part.strip()]
    names = observable_names(args.root)
    by_cut_seed = {cut: {} for cut in cuts}
    for path in sorted(glob.glob(os.path.join(args.root, "chunks", "chunk_*", "*_observable_history.csv"))):
        seed = seed_from_path(path)
        with open(path, newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            index = {name: idx for idx, name in enumerate(header)}
            num_re_idx = [index["num_{}_re".format(i + 1)] for i in range(len(names))]
            num_im_idx = [index["num_{}_im".format(i + 1)] for i in range(len(names))]
            for row in reader:
                t = float(row[index["flow_time"]])
                if t > args.t_max:
                    continue
                active = [cut for cut in cuts if t >= cut]
                if not active:
                    continue
                w_re = float(row[index["weight_re"]])
                w_im = float(row[index["weight_im"]])
                absw = float(row[index["abs_weight"]])
                nums_re = [float(row[idx]) for idx in num_re_idx]
                nums_im = [float(row[idx]) for idx in num_im_idx]
                for cut in active:
                    block = by_cut_seed[cut].setdefault(seed, empty(len(names)))
                    block["seed"] = seed
                    add_sample(block, w_re, w_im, absw, nums_re, nums_im)

    rows = []
    for cut in cuts:
        blocks = list(by_cut_seed[cut].values())
        total = empty(len(names))
        for block in blocks:
            add_block(total, block)
        phase_c = math.hypot(total["d_re"], total["d_im"]) / total["absw"] if total["absw"] > 0 else float("nan")
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
            rows.append({
                "t_min": cut,
                "t_max": args.t_max,
                "seeds": len(blocks),
                "samples": total["samples"],
                "phase_coherence": phase_c,
                "observable": name,
                "estimate_re": est_re,
                "estimate_im": est_im,
                "se_re": se_re,
                "se_im": se_im,
                "z_re": (est_re - target) / se_re if target is not None and se_re > 0 else "",
                "z_im": est_im / se_im if target is not None and se_im > 0 else "",
            })

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(args.out)
    for row in rows:
        if row["observable"] in ("chiral_condensate", "number_density"):
            print(
                "t>={:.4g} {:18s} Re={:.8g} SE={:.3g} z={:.3f} Im={:.3g} zIm={:.3f} C={:.5g} n={}".format(
                    float(row["t_min"]),
                    row["observable"],
                    float(row["estimate_re"]),
                    float(row["se_re"]),
                    float(row["z_re"]),
                    float(row["estimate_im"]),
                    float(row["z_im"]),
                    float(row["phase_coherence"]),
                    int(row["samples"]),
                )
            )


if __name__ == "__main__":
    main()
