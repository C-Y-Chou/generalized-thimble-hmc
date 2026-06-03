#!/usr/bin/env python3
"""Build a WV-HMC state bank from state-history or cyclic snapshot records.

The input records are written by ``WV_HMC_STATE_HISTORY_FILE`` and have the same
binary layout as a WV state bank: one ``real64`` flow-time value followed by the
physical ``x`` vector.  Cyclic snapshot slot files use the same one-record
layout.  This tool can therefore select late, flow-stratified records and
concatenate them into a restartable ``state_bank`` file.
"""

from __future__ import print_function

import argparse
import array
import csv
import math
import os
import random
import re
from collections import defaultdict
from pathlib import Path


def seed_from_path(path):
    match = re.search(r"seed_(\d+)_(?:state_history\.dat|snapshot_slot_\d+\.bin)$", path.name)
    return int(match.group(1)) if match else -1


def read_manifest_rows(root):
    rows = {}
    for manifest in sorted(root.rglob("wv_hmc_dense_observable_validation_manifest.csv")):
        with manifest.open(newline="") as handle:
            for row in csv.DictReader(handle):
                try:
                    seed = int(row.get("seed", "-1"))
                except ValueError:
                    continue
                if seed >= 0:
                    rows[seed] = row
    return rows


def parse_int(value, default):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def read_snapshot_index_rows(root):
    rows = {}
    for path in sorted(root.rglob("seed_*_snapshot_index.csv")):
        with path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                source = row.get("path", "")
                if not source:
                    continue
                try:
                    cycle = int(float(row.get("cycle", "nan")))
                    slot = int(float(row.get("slot", "nan")))
                except ValueError:
                    continue
                source_path = Path(source)
                if not source_path.is_absolute():
                    source_path = path.parent / source_path
                normalized = os.path.abspath(str(source_path))
                rows[normalized] = {"cycle": cycle, "slot": slot, "index_path": path}
                rows[source_path.name] = {"cycle": cycle, "slot": slot, "index_path": path}
    return rows


def read_records(path, record_width):
    values = array.array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) % record_width != 0:
        raise RuntimeError(
            "record width mismatch for {0}: doubles={1} width={2}".format(path, len(values), record_width)
        )
    for record_index in range(len(values) // record_width):
        start = record_index * record_width
        yield record_index, values[start:start + record_width]


def bin_index(flow_time, t0, t1, bins):
    if bins <= 0 or t1 <= t0:
        return 0
    if flow_time < t0 or flow_time > t1:
        return None
    scaled = (flow_time - t0) / (t1 - t0)
    return min(bins - 1, max(0, int(math.floor(scaled * bins))))


def collect_candidates(args):
    record_width = args.state_size + 1
    manifest_rows = read_manifest_rows(args.input_root)
    snapshot_rows = read_snapshot_index_rows(args.input_root)
    by_bin = defaultdict(list)
    total = 0
    kept = 0
    for path in sorted(args.input_root.rglob("seed_*_state_history.dat")):
        seed = seed_from_path(path)
        manifest = manifest_rows.get(seed, {})
        measurement_start = parse_int(manifest.get("measurement_start_cycle"), args.measurement_start_cycle)
        history_stride = parse_int(manifest.get("history_stride"), args.history_stride)
        for local_record, values in read_records(path, record_width):
            total += 1
            approx_cycle = measurement_start + local_record * history_stride
            if approx_cycle < args.min_cycle:
                continue
            flow_time = values[0]
            idx = bin_index(flow_time, args.flow_t0, args.flow_t1, args.flow_bins)
            if idx is None:
                continue
            kept += 1
            by_bin[idx].append({
                "path": path,
                "source_kind": "state_history",
                "seed": seed,
                "local_record": local_record,
                "approx_cycle": approx_cycle,
                "flow_time": flow_time,
                "values": values,
            })
    for path in sorted(args.input_root.rglob("seed_*_snapshot_slot_*.bin")):
        seed = seed_from_path(path)
        snapshot_meta = snapshot_rows.get(os.path.abspath(str(path)), snapshot_rows.get(path.name, {}))
        approx_cycle = parse_int(snapshot_meta.get("cycle"), args.snapshot_default_cycle)
        slot = parse_int(snapshot_meta.get("slot"), -1)
        for local_record, values in read_records(path, record_width):
            total += 1
            if local_record > 0:
                raise RuntimeError("cyclic snapshot file has more than one record: {0}".format(path))
            if approx_cycle < args.min_cycle:
                continue
            flow_time = values[0]
            idx = bin_index(flow_time, args.flow_t0, args.flow_t1, args.flow_bins)
            if idx is None:
                continue
            kept += 1
            by_bin[idx].append({
                "path": path,
                "source_kind": "cyclic_snapshot",
                "seed": seed,
                "local_record": slot,
                "approx_cycle": approx_cycle,
                "flow_time": flow_time,
                "values": values,
            })
    return total, kept, by_bin


def select_records(by_bin, args):
    rng = random.Random(args.random_seed)
    nonempty = [idx for idx in range(args.flow_bins) if by_bin.get(idx)]
    if not nonempty:
        return []
    if args.records_per_bin > 0:
        per_bin = args.records_per_bin
    else:
        per_bin = min(len(by_bin[idx]) for idx in nonempty)
        if args.max_records > 0:
            per_bin = min(per_bin, max(1, args.max_records // len(nonempty)))
    selected = []
    for idx in nonempty:
        records = list(by_bin[idx])
        if args.shuffle:
            rng.shuffle(records)
        else:
            records.sort(key=lambda row: (row["seed"], row["local_record"]))
        selected.extend(records[:per_bin])
    if args.shuffle:
        rng.shuffle(selected)
    if args.max_records > 0:
        selected = selected[:args.max_records]
    return selected


def write_outputs(selected, by_bin, total, kept, args):
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as out:
        for row in selected:
            row["values"].tofile(out)

    index_path = args.output.with_suffix(args.output.suffix + ".index.csv")
    with index_path.open("w", newline="") as handle:
        fieldnames = [
            "record",
            "source_kind",
            "flow_bin",
            "seed",
            "local_record",
            "approx_cycle",
            "flow_time",
            "source_path",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for record, row in enumerate(selected):
            writer.writerow({
                "record": record,
                "source_kind": row["source_kind"],
                "flow_bin": bin_index(row["flow_time"], args.flow_t0, args.flow_t1, args.flow_bins),
                "seed": row["seed"],
                "local_record": row["local_record"],
                "approx_cycle": row["approx_cycle"],
                "flow_time": "{:.17g}".format(row["flow_time"]),
                "source_path": str(row["path"]),
            })

    hist_path = args.output.with_suffix(args.output.suffix + ".histogram.csv")
    with hist_path.open("w", newline="") as handle:
        fieldnames = ["flow_bin", "flow_low", "flow_high", "available_records", "selected_records"]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        selected_counts = defaultdict(int)
        for row in selected:
            selected_counts[bin_index(row["flow_time"], args.flow_t0, args.flow_t1, args.flow_bins)] += 1
        width = (args.flow_t1 - args.flow_t0) / float(args.flow_bins)
        for idx in range(args.flow_bins):
            writer.writerow({
                "flow_bin": idx,
                "flow_low": "{:.17g}".format(args.flow_t0 + idx * width),
                "flow_high": "{:.17g}".format(args.flow_t0 + (idx + 1) * width),
                "available_records": len(by_bin.get(idx, [])),
                "selected_records": selected_counts[idx],
            })

    print("state_bank={}".format(args.output))
    print("index={}".format(index_path))
    print("histogram={}".format(hist_path))
    print("records_total={}".format(total))
    print("records_after_cuts={}".format(kept))
    print("records_selected={}".format(len(selected)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--state-size", type=int, required=True)
    parser.add_argument("--min-cycle", type=int, default=1001)
    parser.add_argument("--measurement-start-cycle", type=int, default=1)
    parser.add_argument("--history-stride", type=int, default=20)
    parser.add_argument("--snapshot-default-cycle", type=int, default=10**9)
    parser.add_argument("--flow-t0", type=float, default=0.0001)
    parser.add_argument("--flow-t1", type=float, default=0.03)
    parser.add_argument("--flow-bins", type=int, default=10)
    parser.add_argument("--records-per-bin", type=int, default=0)
    parser.add_argument("--max-records", type=int, default=10000)
    parser.add_argument("--random-seed", type=int, default=20260601)
    parser.add_argument("--shuffle", action="store_true")
    args = parser.parse_args()

    if args.state_size < 1:
        raise SystemExit("--state-size must be positive")
    if args.flow_bins < 1:
        raise SystemExit("--flow-bins must be positive")
    if args.flow_t1 <= args.flow_t0:
        raise SystemExit("--flow-t1 must be greater than --flow-t0")

    total, kept, by_bin = collect_candidates(args)
    selected = select_records(by_bin, args)
    if not selected:
        raise SystemExit("no records selected")
    write_outputs(selected, by_bin, total, kept, args)


if __name__ == "__main__":
    main()
