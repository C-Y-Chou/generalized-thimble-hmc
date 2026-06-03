#!/usr/bin/env python3
"""Pack x-only fixed-tau records into a WV-HMC state bank.

Input records are raw ``real64`` x vectors with width ``state_size``.  Output
records are raw ``real64`` WV-HMC state-bank records with width
``state_size + 1``:

    flow_time, x_1, ..., x_state_size

Use this after a lower fixed-tau bank-builder run when the downstream WV-HMC
initializer needs ``WV_HMC_INIT_MODE=state_bank``.
"""

from __future__ import print_function

import argparse
import array
import csv
from pathlib import Path


def read_x_records(path, state_size):
    values = array.array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) % state_size != 0:
        raise RuntimeError(
            "record width mismatch for {0}: doubles={1} state_size={2}".format(path, len(values), state_size)
        )
    for record in range(len(values) // state_size):
        start = record * state_size
        yield record, values[start:start + state_size]


def selected_records(paths, state_size, burn_records, stride, max_records):
    written = 0
    for path in paths:
        for input_record, x_values in read_x_records(path, state_size):
            if input_record < burn_records:
                continue
            if ((input_record - burn_records) % stride) != 0:
                continue
            if max_records >= 0 and written >= max_records:
                return
            yield path, input_record, x_values
            written += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", dest="inputs", action="append", required=True, help="x-only bank/history file")
    parser.add_argument("--output", required=True, help="output WV-HMC state_bank file")
    parser.add_argument("--state-size", type=int, required=True, help="number of x components per input record")
    parser.add_argument("--flow-time", type=float, required=True, help="fixed tau label to prepend to every record")
    parser.add_argument("--burn-records", type=int, default=0, help="drop this many records from each input")
    parser.add_argument("--stride", type=int, default=1, help="keep one record every stride after burn")
    parser.add_argument("--max-records", type=int, default=-1, help="maximum output records; negative means no cap")
    args = parser.parse_args()

    if args.state_size < 1:
        raise SystemExit("--state-size must be positive")
    if args.flow_time < 0.0:
        raise SystemExit("--flow-time must be nonnegative")
    if args.burn_records < 0:
        raise SystemExit("--burn-records must be nonnegative")
    if args.stride < 1:
        raise SystemExit("--stride must be >= 1")

    paths = [Path(item) for item in args.inputs]
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        raise SystemExit("missing input files: {0}".format(", ".join(missing)))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    with output.open("wb") as handle:
        for source_path, input_record, x_values in selected_records(
            paths, args.state_size, args.burn_records, args.stride, args.max_records
        ):
            packed = array.array("d", [args.flow_time])
            packed.extend(x_values)
            packed.tofile(handle)
            rows.append({
                "record": len(rows),
                "source_path": str(source_path),
                "source_record": input_record,
                "flow_time": "{:.17g}".format(args.flow_time),
            })

    if not rows:
        raise SystemExit("no records selected")

    index_path = output.with_suffix(output.suffix + ".index.csv")
    with index_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["record", "source_path", "source_record", "flow_time"])
        writer.writeheader()
        writer.writerows(rows)

    print("state_bank={}".format(output))
    print("index={}".format(index_path))
    print("records={}".format(len(rows)))
    print("record_width={}".format(args.state_size + 1))
    print("flow_time={:.17g}".format(args.flow_time))


if __name__ == "__main__":
    main()
