#!/usr/bin/env python3
"""Compare WV-HMC observable estimates under alternative offline weights."""

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


def cmul(a_re, a_im, b_re, b_im):
    return a_re*b_re - a_im*b_im, a_re*b_im + a_im*b_re


def cdiv(n_re, n_im, d_re, d_im):
    den = d_re*d_re + d_im*d_im
    if den <= 0.0:
        return float("nan"), float("nan")
    return (n_re*d_re + n_im*d_im)/den, (n_im*d_re - n_re*d_im)/den


def empty(obs_count):
    return {
        "samples": 0,
        "d_re": 0.0,
        "d_im": 0.0,
        "absw": 0.0,
        "num_re": [0.0] * obs_count,
        "num_im": [0.0] * obs_count,
    }


def add_sample(block, w_re, w_im, obs_re, obs_im):
    block["samples"] += 1
    block["d_re"] += w_re
    block["d_im"] += w_im
    block["absw"] += math.hypot(w_re, w_im)
    for idx in range(len(obs_re)):
        nr, ni = cmul(w_re, w_im, obs_re[idx], obs_im[idx])
        block["num_re"][idx] += nr
        block["num_im"][idx] += ni


def add_block(total, block):
    total["samples"] += block["samples"]
    total["d_re"] += block["d_re"]
    total["d_im"] += block["d_im"]
    total["absw"] += block["absw"]
    for idx in range(len(total["num_re"])):
        total["num_re"][idx] += block["num_re"][idx]
        total["num_im"][idx] += block["num_im"][idx]


def sub_block(total, block):
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
    return cdiv(block["num_re"][idx], block["num_im"][idx], block["d_re"], block["d_im"])


def jk_se(values):
    if len(values) < 2:
        return float("nan")
    mean = sum(values) / float(len(values))
    return math.sqrt((len(values) - 1.0) / len(values) * sum((value - mean) ** 2 for value in values))


def observable_names(root):
    paths = sorted(glob.glob(os.path.join(root, "chunks/chunk_*/*_observables.csv")))
    if not paths:
        raise RuntimeError("no observables files under {}".format(root))
    out = []
    with open(paths[0], newline="") as handle:
        for row in csv.DictReader(handle):
            out.append(row["name"])
    return out


def variant_weights(row):
    wr = float(row["weight_re"])
    wi = float(row["weight_im"])
    pr = float(row["phase_re"])
    pi = float(row["phase_im"])
    alpha = float(row["alpha"])
    if not math.isfinite(alpha) or alpha <= 0.0:
        alpha = float("nan")
    variants = {
        "current_wv_factor": (wr, wi),
        "conj_current_wv_factor": (wr, -wi),
        "phase_only": (pr, pi),
        "conj_phase_only": (pr, -pi),
    }
    if math.isfinite(alpha) and alpha > 0.0:
        variants.update({
            "phase_over_alpha": (pr/alpha, pi/alpha),
            "conj_phase_over_alpha": (pr/alpha, -pi/alpha),
            "phase_times_alpha": (pr*alpha, pi*alpha),
            "conj_phase_times_alpha": (pr*alpha, -pi*alpha),
            "current_times_alpha": (wr*alpha, wi*alpha),
            "conj_current_times_alpha": (wr*alpha, -wi*alpha),
            "current_times_alpha2": (wr*alpha*alpha, wi*alpha*alpha),
            "current_over_alpha": (wr/alpha, wi/alpha),
        })
    return variants


def summarize_variant(name, seed_blocks, names):
    total = empty(len(names))
    blocks = list(seed_blocks.values())
    for block in blocks:
        add_block(total, block)
    rows = []
    for idx, obs_name in enumerate(names):
        est_re, est_im = estimate(total, idx)
        jk_re = []
        jk_im = []
        for block in blocks:
            leave = sub_block(total, block)
            value_re, value_im = estimate(leave, idx)
            jk_re.append(value_re)
            jk_im.append(value_im)
        se_re = jk_se(jk_re)
        se_im = jk_se(jk_im)
        target = EXACT.get(obs_name)
        z_re = ""
        z_im = ""
        if target is not None and se_re > 0.0:
            z_re = (est_re - target) / se_re
        if target is not None and se_im > 0.0:
            z_im = est_im / se_im
        rows.append({
            "variant": name,
            "observable": obs_name,
            "seeds": len(blocks),
            "samples": total["samples"],
            "phase_coherence": math.hypot(total["d_re"], total["d_im"]) / total["absw"] if total["absw"] > 0.0 else float("nan"),
            "estimate_re": est_re,
            "estimate_im": est_im,
            "se_re": se_re,
            "se_im": se_im,
            "z_re": z_re,
            "z_im": z_im,
        })
    return rows


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--cycle-end", type=int, default=0)
    args = parser.parse_args()
    names = observable_names(args.root)
    obs_count = len(names)
    by_variant = {}
    for path in sorted(glob.glob(os.path.join(args.root, "chunks/chunk_*/*_observable_history.csv"))):
        seed = seed_from_path(path)
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                if args.cycle_end > 0 and int(float(row["cycle"])) > args.cycle_end:
                    continue
                obs_re = [float(row["obs_{}_re".format(idx + 1)]) for idx in range(obs_count)]
                obs_im = [float(row["obs_{}_im".format(idx + 1)]) for idx in range(obs_count)]
                for variant, (w_re, w_im) in variant_weights(row).items():
                    if not (math.isfinite(w_re) and math.isfinite(w_im)):
                        continue
                    seed_blocks = by_variant.setdefault(variant, {})
                    block = seed_blocks.setdefault(seed, empty(obs_count))
                    add_sample(block, w_re, w_im, obs_re, obs_im)
    rows = []
    for variant in sorted(by_variant):
        rows.extend(summarize_variant(variant, by_variant[variant], names))
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    write_csv(args.out, rows)
    print(args.out)


if __name__ == "__main__":
    main()
