#!/usr/bin/env python3
"""Filter an x-bank to records that passed dense-flow prevalidation."""

from __future__ import print_function

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-x-bank", required=True)
    parser.add_argument("--diagnostics", required=True)
    parser.add_argument("--output-x-bank", required=True)
    parser.add_argument("--state-size", type=int, required=True)
    parser.add_argument("--required-slot-id", type=int, default=-1)
    parser.add_argument("--output-index", default="")
    parser.add_argument("--output-json", default="")
    return parser.parse_args()


def load_selected_records(diagnostics_path, required_slot_id):
    by_record = {}
    with Path(diagnostics_path).open("r", encoding="utf-8", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            source_record = int(row["source_record"])
            slot_id = int(row["slot_id"])
            if required_slot_id >= 0 and slot_id != required_slot_id:
                continue
            entry = by_record.setdefault(source_record, {"rows": 0, "available": 0, "slots": [], "times": []})
            entry["rows"] += 1
            if int(row["available"]) == 1:
                entry["available"] += 1
                entry["slots"].append(slot_id)
                entry["times"].append(row["target_flow_time"])
    selected = []
    for source_record, entry in sorted(by_record.items()):
        if entry["rows"] > 0 and entry["available"] == entry["rows"]:
            selected.append((source_record, entry))
    return selected, by_record


def copy_records(input_x_bank, output_x_bank, state_size, selected):
    record_bytes = state_size * 8
    output_path = Path(output_x_bank)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    copied = 0
    with Path(input_x_bank).open("rb") as src, output_path.open("wb") as dst:
        for source_record, _entry in selected:
            src.seek(source_record * record_bytes)
            payload = src.read(record_bytes)
            if len(payload) != record_bytes:
                raise RuntimeError("Could not read source_record={0} from {1}".format(source_record, input_x_bank))
            dst.write(payload)
            copied += 1
    return copied


def write_index(index_path, selected):
    if not index_path:
        return
    path = Path(index_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["bank_index", "source_record", "available_slots", "target_flow_times"],
        )
        writer.writeheader()
        for bank_index, (source_record, entry) in enumerate(selected):
            writer.writerow({
                "bank_index": bank_index,
                "source_record": source_record,
                "available_slots": ";".join(str(slot) for slot in entry["slots"]),
                "target_flow_times": ";".join(entry["times"]),
            })


def write_manifest(json_path, args, selected, by_record, copied):
    if not json_path:
        return
    path = Path(json_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    total_records = len(by_record)
    payload = {
        "schema": "wv_hmc_safe_x_bank.v1",
        "created_utc": datetime.now(tz=timezone.utc).isoformat(),
        "input_x_bank": str(args.input_x_bank),
        "diagnostics": str(args.diagnostics),
        "output_x_bank": str(args.output_x_bank),
        "state_size": args.state_size,
        "required_slot_id": args.required_slot_id,
        "diagnosed_source_records": total_records,
        "selected_records": len(selected),
        "copied_records": copied,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    if args.state_size < 1:
        raise RuntimeError("--state-size must be positive")
    selected, by_record = load_selected_records(args.diagnostics, args.required_slot_id)
    if not selected:
        raise RuntimeError("No prevalidated records selected from {0}".format(args.diagnostics))
    copied = copy_records(args.input_x_bank, args.output_x_bank, args.state_size, selected)
    write_index(args.output_index, selected)
    write_manifest(args.output_json, args, selected, by_record, copied)
    print(json.dumps({
        "input_x_bank": str(args.input_x_bank),
        "diagnostics": str(args.diagnostics),
        "output_x_bank": str(args.output_x_bank),
        "state_size": args.state_size,
        "selected_records": len(selected),
        "copied_records": copied,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
