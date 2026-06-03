#!/usr/bin/env python3
"""Group WV-HMC seed summaries by actual initial-bank record."""

import argparse
import csv
import glob
import math
import os
import re
import statistics


def seed_from_path(path):
    match = re.search(r"seed_(\d+)", os.path.basename(path))
    return int(match.group(1)) if match else None


def parse_log_bank_records(root):
    out = {}
    bank_pattern = re.compile(r"\binit_bank_record\s+(\d+)\b")
    for path in glob.glob(os.path.join(root, "chunks", "chunk_*", "seed_*.log")):
        seed = seed_from_path(path)
        if seed is None:
            continue
        with open(path, errors="replace") as handle:
            text = handle.read(8192)
        match = bank_pattern.search(text)
        if match:
            out[seed] = int(match.group(1))
    return out


def mean(values):
    return sum(values) / float(len(values)) if values else float("nan")


def std(values):
    return statistics.pstdev(values) if len(values) > 1 else 0.0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--seed-summary", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    seed_to_bank = parse_log_bank_records(args.root)
    with open(args.seed_summary, newline="") as handle:
        seed_rows = list(csv.DictReader(handle))

    groups = {}
    for row in seed_rows:
        seed = int(row["seed"])
        bank = seed_to_bank.get(seed, -1)
        groups.setdefault(bank, []).append(row)

    rows = []
    for bank, items in sorted(groups.items()):
        chiral = [float(row["chiral_condensate_re"]) for row in items]
        density = [float(row["number_density_re"]) for row in items]
        phase_c = [float(row["phase_coherence"]) for row in items]
        samples = [float(row["samples"]) for row in items]
        rows.append({
            "init_bank_record": bank,
            "seed_count": len(items),
            "sample_sum": int(sum(samples)),
            "chiral_re_seed_mean": mean(chiral),
            "chiral_re_seed_std": std(chiral),
            "chiral_re_seed_min": min(chiral),
            "chiral_re_seed_max": max(chiral),
            "density_re_seed_mean": mean(density),
            "density_re_seed_std": std(density),
            "phase_coherence_seed_mean": mean(phase_c),
            "phase_coherence_seed_min": min(phase_c),
        })

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print("seed_rows", len(seed_rows), "seeds_with_bank", len(seed_to_bank), "bank_groups", len(rows))
    print(args.out)
    for row in rows:
        print(
            "bank={:02d} n={} chiral_mean={:.8g} chiral_sd={:.4g} "
            "density_mean={:.8g} C_mean={:.5g}".format(
                int(row["init_bank_record"]),
                int(row["seed_count"]),
                float(row["chiral_re_seed_mean"]),
                float(row["chiral_re_seed_std"]),
                float(row["density_re_seed_mean"]),
                float(row["phase_coherence_seed_mean"]),
            )
        )


if __name__ == "__main__":
    main()
