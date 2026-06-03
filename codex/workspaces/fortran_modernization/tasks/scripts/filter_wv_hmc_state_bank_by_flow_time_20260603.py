#!/usr/bin/env python3
"""Filter a WV-HMC state bank by its fixed flow-time label.

WV state-bank records are packed as real64 values:

    flow_time, x_1, ..., x_state_size

This utility preserves the record layout, writes an index for provenance, and
optionally fails if no records survive the requested measurement-window cut.
"""

from __future__ import print_function

import argparse
import array
import csv
from pathlib import Path


def read_records(path, state_size):
    width = state_size + 1
    values = array.array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) % width != 0:
        raise RuntimeError(
            "record width mismatch: {0} doubles={1} width={2}".format(path, len(values), width)
        )
    for record in range(len(values) // width):
        start = record * width
        yield record, values[start:start + width]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--state-size", type=int, required=True)
    parser.add_argument("--flow-t0", type=float, required=True)
    parser.add_argument("--flow-t1", type=float, required=True)
    parser.add_argument("--inclusive-upper", action="store_true")
    args = parser.parse_args()

    if args.state_size < 1:
        raise SystemExit("--state-size must be positive")
    if args.flow_t1 <= args.flow_t0:
        raise SystemExit("--flow-t1 must be greater than --flow-t0")

    input_path = Path(args.input)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    index_path = output_path.with_suffix(output_path.suffix + ".index.csv")
    hist_path = output_path.with_suffix(output_path.suffix + ".histogram.csv")

    rows = []
    outside = []
    with output_path.open("wb") as out:
        for source_record, values in read_records(input_path, args.state_size):
            flow_time = values[0]
            in_window = flow_time >= args.flow_t0 and (
                flow_time <= args.flow_t1 if args.inclusive_upper else flow_time < args.flow_t1
            )
            target = rows if in_window else outside
            target.append({"source_record": source_record, "flow_time": flow_time})
            if in_window:
                values.tofile(out)

    with index_path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["record", "source_record", "flow_time", "source_bank"],
        )
        writer.writeheader()
        for record, row in enumerate(rows):
            writer.writerow({
                "record": record,
                "source_record": row["source_record"],
                "flow_time": "{:.17g}".format(row["flow_time"]),
                "source_bank": str(input_path),
            })

    with hist_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["category", "records", "flow_min", "flow_max"])
        writer.writeheader()
        for category, records in [("kept", rows), ("dropped", outside)]:
            if records:
                flow_min = min(row["flow_time"] for row in records)
                flow_max = max(row["flow_time"] for row in records)
            else:
                flow_min = ""
                flow_max = ""
            writer.writerow({
                "category": category,
                "records": len(records),
                "flow_min": "{:.17g}".format(flow_min) if flow_min != "" else "",
                "flow_max": "{:.17g}".format(flow_max) if flow_max != "" else "",
            })

    if not rows:
        raise SystemExit("no records survived flow-time filter")

    print("state_bank={}".format(output_path))
    print("index={}".format(index_path))
    print("histogram={}".format(hist_path))
    print("records_kept={}".format(len(rows)))
    print("records_dropped={}".format(len(outside)))


if __name__ == "__main__":
    main()
