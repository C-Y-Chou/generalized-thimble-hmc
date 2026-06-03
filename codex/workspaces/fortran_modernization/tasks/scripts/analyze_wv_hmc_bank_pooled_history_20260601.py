#!/usr/bin/env python3
"""Pooled WV-HMC ratio summaries by initial-bank record."""

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
    return int(match.group(1)) if match else None


def parse_log_bank_records(root):
    out = {}
    bank_pattern = re.compile(r"\binit_bank_record\s+(\d+)\b")
    for path in glob.glob(os.path.join(root, "chunks", "chunk_*", "seed_*.log")):
        seed_match = re.search(r"seed_(\d+)\.log", os.path.basename(path))
        if not seed_match:
            continue
        with open(path, errors="replace") as handle:
            text = handle.read(8192)
        bank_match = bank_pattern.search(text)
        if bank_match:
            out[int(seed_match.group(1))] = int(bank_match.group(1))
    return out


def empty(nobs):
    return {
        "seed_count": 0,
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


def add_block(target, source):
    target["seed_count"] += source["seed_count"]
    target["samples"] += source["samples"]
    target["d_re"] += source["d_re"]
    target["d_im"] += source["d_im"]
    target["absw"] += source["absw"]
    for idx in range(len(target["num_re"])):
        target["num_re"][idx] += source["num_re"][idx]
        target["num_im"][idx] += source["num_im"][idx]


def subtract_block(total, source):
    out = empty(len(total["num_re"]))
    out["seed_count"] = total["seed_count"] - source["seed_count"]
    out["samples"] = total["samples"] - source["samples"]
    out["d_re"] = total["d_re"] - source["d_re"]
    out["d_im"] = total["d_im"] - source["d_im"]
    out["absw"] = total["absw"] - source["absw"]
    for idx in range(len(total["num_re"])):
        out["num_re"][idx] = total["num_re"][idx] - source["num_re"][idx]
        out["num_im"][idx] = total["num_im"][idx] - source["num_im"][idx]
    return out


def jk_se(values):
    if len(values) < 2:
        return float("nan")
    avg = sum(values) / float(len(values))
    return math.sqrt((len(values) - 1.0) / len(values) * sum((value - avg) ** 2 for value in values))


def observable_names(root):
    paths = sorted(glob.glob(os.path.join(root, "chunks", "chunk_*", "*_observables.csv")))
    if not paths:
        raise RuntimeError("no observable files found under {}".format(root))
    with open(paths[0], newline="") as handle:
        return [row["name"] for row in csv.DictReader(handle)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--cycle-end", type=int, default=15000)
    args = parser.parse_args()

    names = observable_names(args.root)
    seed_to_bank = parse_log_bank_records(args.root)
    groups = {}
    group_seeds = {}
    for path in sorted(glob.glob(os.path.join(args.root, "chunks", "chunk_*", "*_observable_history.csv"))):
        seed = seed_from_path(path)
        if seed is None:
            continue
        bank = seed_to_bank.get(seed, -1)
        block = groups.setdefault(bank, empty(len(names)))
        group_seeds.setdefault(bank, set()).add(seed)
        with open(path, newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            index = {name: idx for idx, name in enumerate(header)}
            num_re_idx = [index["num_{}_re".format(i + 1)] for i in range(len(names))]
            num_im_idx = [index["num_{}_im".format(i + 1)] for i in range(len(names))]
            for row in reader:
                if int(float(row[index["cycle"]])) > args.cycle_end:
                    continue
                nums_re = [float(row[idx]) for idx in num_re_idx]
                nums_im = [float(row[idx]) for idx in num_im_idx]
                add_sample(
                    block,
                    float(row[index["weight_re"]]),
                    float(row[index["weight_im"]]),
                    float(row[index["abs_weight"]]),
                    nums_re,
                    nums_im,
                )

    rows = []
    total = empty(len(names))
    for bank, block in sorted(groups.items()):
        block["seed_count"] = len(group_seeds.get(bank, ()))
        add_block(total, block)
        phase_c = math.hypot(block["d_re"], block["d_im"]) / block["absw"] if block["absw"] > 0 else float("nan")
        for idx, name in enumerate(names):
            est_re, est_im = estimate(block, idx)
            rows.append({
                "init_bank_record": bank,
                "cycle_end": args.cycle_end,
                "seed_count": block["seed_count"],
                "samples": block["samples"],
                "phase_coherence": phase_c,
                "denominator_re": block["d_re"],
                "denominator_im": block["d_im"],
                "sum_abs_weight": block["absw"],
                "numerator_re": block["num_re"][idx],
                "numerator_im": block["num_im"][idx],
                "observable": name,
                "estimate_re": est_re,
                "estimate_im": est_im,
                "target_re": EXACT.get(name, ""),
                "bias_re": est_re - EXACT[name] if name in EXACT else "",
            })

    bank_blocks = [groups[bank] for bank in sorted(groups)]
    print("bank_jackknife")
    for idx, name in enumerate(names):
        est_re, est_im = estimate(total, idx)
        jk_re = []
        jk_im = []
        for block in bank_blocks:
            leave = subtract_block(total, block)
            value_re, value_im = estimate(leave, idx)
            jk_re.append(value_re)
            jk_im.append(value_im)
        se_re = jk_se(jk_re)
        se_im = jk_se(jk_im)
        target = EXACT.get(name)
        z_re = (est_re - target) / se_re if target is not None and se_re > 0.0 else float("nan")
        z_im = est_im / se_im if target is not None and se_im > 0.0 else float("nan")
        print(
            "{} Re={:.10g} SE_re={:.4g} z_re={:.3f} Im={:.4g} SE_im={:.4g} z_im={:.3f}".format(
                name, est_re, se_re, z_re, est_im, se_im, z_im
            )
        )

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(args.out)
    for row in rows:
        if row["observable"] == "chiral_condensate":
            print(
                "bank={:02d} seeds={} samples={} C={:.5g} chiral={:.8g} bias={:.4g}".format(
                    int(row["init_bank_record"]),
                    int(row["seed_count"]),
                    int(row["samples"]),
                    float(row["phase_coherence"]),
                    float(row["estimate_re"]),
                    float(row["bias_re"]),
                )
            )


if __name__ == "__main__":
    main()
