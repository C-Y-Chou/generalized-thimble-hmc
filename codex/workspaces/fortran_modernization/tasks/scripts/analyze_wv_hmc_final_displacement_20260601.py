#!/usr/bin/env python3
"""Compare WV-HMC final states to their selected initial-bank records."""

import argparse
import csv
import glob
import math
import os
import re
import statistics
import struct


def parse_log_records(root):
    seed_pattern = re.compile(r"seed_(\d+)\.log")
    bank_pattern = re.compile(r"\binit_bank_record\s+(\d+)\b")
    flow_in_pattern = re.compile(r"\bflow_time_in\s+([-+.0-9Ee]+)")
    flow_out_pattern = re.compile(r"\bflow_time_out\s+([-+.0-9Ee]+)")
    out = {}
    for path in glob.glob(os.path.join(root, "chunks", "chunk_*", "seed_*.log")):
        seed_match = seed_pattern.search(os.path.basename(path))
        if not seed_match:
            continue
        with open(path, errors="replace") as handle:
            text = handle.read(8192)
        bank_match = bank_pattern.search(text)
        flow_in_match = flow_in_pattern.search(text)
        flow_out_match = flow_out_pattern.search(text)
        if bank_match:
            out[int(seed_match.group(1))] = {
                "bank": int(bank_match.group(1)),
                "flow_time_in_log": float(flow_in_match.group(1)) if flow_in_match else float("nan"),
                "flow_time_out_log": float(flow_out_match.group(1)) if flow_out_match else float("nan"),
            }
    return out


def read_record(path, record, state_size):
    width = state_size + 1
    record_bytes = width * 8
    with open(path, "rb") as handle:
        handle.seek(record * record_bytes)
        data = handle.read(record_bytes)
    if len(data) != record_bytes:
        raise RuntimeError("short record {} in {}".format(record, path))
    return struct.unpack("{}d".format(width), data)


def read_state(path, state_size):
    width = state_size + 1
    data = open(path, "rb").read()
    if len(data) != width * 8:
        raise RuntimeError("state size mismatch {} bytes in {}".format(len(data), path))
    return struct.unpack("{}d".format(width), data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--manifest-glob", default="chunks/chunk_*/wv_hmc_dense_observable_validation_manifest.csv")
    parser.add_argument("--state-size", type=int, default=72)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    seed_info = parse_log_records(args.root)
    rows = []
    for manifest in glob.glob(os.path.join(args.root, args.manifest_glob)):
        with open(manifest, newline="") as handle:
            for row in csv.DictReader(handle):
                seed = int(row["seed"])
                info = seed_info.get(seed)
                state_path = row.get("final_state_path", "")
                bank_path = row.get("init_bank_file", "")
                if not info or not state_path or not bank_path:
                    continue
                initial = read_record(bank_path, info["bank"], args.state_size)
                final = read_state(state_path, args.state_size)
                dx2 = sum((final[idx] - initial[idx]) ** 2 for idx in range(1, args.state_size + 1))
                rows.append({
                    "seed": seed,
                    "init_bank_record": info["bank"],
                    "flow_time_initial": initial[0],
                    "flow_time_final": final[0],
                    "flow_time_in_log": info["flow_time_in_log"],
                    "flow_time_out_log": info["flow_time_out_log"],
                    "dx2": dx2,
                    "dx2_per_dim": dx2 / float(args.state_size),
                    "dx_rms_per_dim": math.sqrt(dx2 / float(args.state_size)),
                    "abs_dt": abs(final[0] - initial[0]),
                })

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    vals = [row["dx2_per_dim"] for row in rows]
    dts = [row["abs_dt"] for row in rows]
    print(args.out)
    print("rows", len(rows))
    for name, series in (("dx2_per_dim", vals), ("abs_dt", dts)):
        ordered = sorted(series)
        print(
            "{} min={:.6g} p10={:.6g} median={:.6g} p90={:.6g} max={:.6g} mean={:.6g}".format(
                name,
                ordered[0],
                ordered[int(0.10 * (len(ordered) - 1))],
                statistics.median(ordered),
                ordered[int(0.90 * (len(ordered) - 1))],
                ordered[-1],
                statistics.mean(ordered),
            )
        )


if __name__ == "__main__":
    main()
