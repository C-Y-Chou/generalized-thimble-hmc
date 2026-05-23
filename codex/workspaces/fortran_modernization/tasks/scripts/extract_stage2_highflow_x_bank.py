#!/usr/bin/env python3
"""Extract a physical-x bank from Stage2 high-flow outputs."""

import argparse
import csv
import json
import shutil
import struct
from array import array
from datetime import datetime, timezone
from pathlib import Path


SNAPSHOT_MAGIC = 23170523
SNAPSHOT_VERSION = 1


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Extract Stage2 high-flow physical x states into x_bank.dat.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--run-root", required=True, help="Stage2 wrapper run root containing records/record_XXXX.")
    parser.add_argument("--records", default="", help="Comma-separated record ids. Defaults to discovered record dirs.")
    parser.add_argument("--source", choices=("auto", "snapshots", "cold-x-history"), default="auto")
    parser.add_argument("--slot-id", default="max", help="Slot id to extract from snapshots, or 'max' for largest flow time.")
    parser.add_argument("--state-size", type=int, default=0, help="Required for cold-x-history when no snapshot is available.")
    parser.add_argument("--burn-records", type=int, default=0, help="Drop this many x-history rows per record.")
    parser.add_argument("--max-records-per-chain", type=int, default=0, help="Optional cap for x-history rows per record.")
    parser.add_argument("--history-stride", type=int, default=1)
    parser.add_argument("--output-root", default="output/stephanov_flow_banks")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def resolve_repo_path(repo_root, value):
    path = Path(value)
    if path.is_absolute():
        return path
    return repo_root / path


def parse_records(text, run_root):
    if text.strip():
        return [int(item.strip()) for item in text.split(",") if item.strip()]
    records = []
    for parent in (run_root / "records", run_root):
        if not parent.exists():
            continue
        for path in sorted(parent.glob("record_*")):
            suffix = path.name.split("_", 1)[1]
            if suffix.isdigit():
                records.append(int(suffix))
    if not records:
        raise RuntimeError("No record dirs found under {0} or {1}".format(run_root / "records", run_root))
    return sorted(set(records))


def record_dir(run_root, record):
    for width in (4, 6):
        path = run_root / "records" / ("record_{0:0{1}d}".format(record, width))
        if path.exists():
            return path
    for width in (4, 6):
        path = run_root / ("record_{0:0{1}d}".format(record, width))
        if path.exists():
            return path
    return run_root / "records" / ("record_{0:04d}".format(record))


class SnapshotReader:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self.offset = 0

    def take(self, fmt):
        size = struct.calcsize(fmt)
        if self.offset + size > len(self.data):
            raise RuntimeError("Unexpected EOF in {0}".format(self.path))
        value = struct.unpack_from(fmt, self.data, self.offset)
        self.offset += size
        return value

    def take_doubles(self, count):
        size = 8 * count
        if self.offset + size > len(self.data):
            raise RuntimeError("Unexpected EOF in {0}".format(self.path))
        out = array("d")
        out.frombytes(self.data[self.offset:self.offset + size])
        self.offset += size
        return out


def read_snapshot_slots(snapshot_file):
    reader = SnapshotReader(snapshot_file)
    header = reader.take("<10i")
    magic, version, state_size, n_slots, n_pairs, n_labels, cycle, base_seed, swap_seed, rng_code = header
    if magic != SNAPSHOT_MAGIC or version != SNAPSHOT_VERSION:
        raise RuntimeError("Unsupported snapshot magic/version in {0}: {1}/{2}".format(snapshot_file, magic, version))
    slots = []
    for _idx in range(n_slots):
        slot_id, label_id, rng_seed = reader.take("<3i")
        flow_time, local_runtime = reader.take("<2d")
        counters = reader.take("<10i")
        phi_re, phi_im = reader.take("<2d")
        (state_version,) = reader.take("<q")
        x = reader.take_doubles(state_size)
        z = reader.take_doubles(2 * state_size)
        jac = reader.take_doubles(2 * state_size * state_size)
        slots.append(
            {
                "slot_id": slot_id,
                "label_id": label_id,
                "rng_seed": rng_seed,
                "flow_time": flow_time,
                "local_runtime": local_runtime,
                "counters": counters,
                "phi_sum": complex(phi_re, phi_im),
                "state_version": state_version,
                "x": x,
                "z": z,
                "jac": jac,
            }
        )
    return {
        "state_size": state_size,
        "n_slots": n_slots,
        "n_pairs": n_pairs,
        "n_labels": n_labels,
        "cycle": cycle,
        "base_seed": base_seed,
        "swap_seed": swap_seed,
        "rng_code": rng_code,
        "slots": slots,
    }


def choose_snapshot_slot(slots, slot_id_text):
    if slot_id_text == "max":
        return max(slots, key=lambda row: row["flow_time"])
    slot_id = int(slot_id_text)
    for slot in slots:
        if slot["slot_id"] == slot_id:
            return slot
    raise RuntimeError("Snapshot does not contain slot_id={0}".format(slot_id))


def read_x_history(path, state_size):
    values = array("d")
    with Path(path).open("rb") as handle:
        values.fromfile(handle, Path(path).stat().st_size // 8)
    if len(values) % state_size != 0:
        raise RuntimeError("x-history width mismatch for {0}: values={1} state_size={2}".format(path, len(values), state_size))
    rows = []
    for start in range(0, len(values), state_size):
        rows.append(values[start:start + state_size])
    return rows


def extract_from_snapshots(run_root, records, slot_id_text, x_out, idx_writer, start_bank_index):
    bank_index = start_bank_index
    state_size = None
    rows = []
    for record in records:
        snap = record_dir(run_root, record) / "final_snapshot.bin"
        if not snap.exists():
            raise RuntimeError("Missing final snapshot for record {0}: {1}".format(record, snap))
        parsed = read_snapshot_slots(snap)
        state_size = parsed["state_size"] if state_size is None else state_size
        if parsed["state_size"] != state_size:
            raise RuntimeError("Snapshot state-size mismatch at {0}".format(snap))
        slot = choose_snapshot_slot(parsed["slots"], slot_id_text)
        slot["x"].tofile(x_out)
        row = {
            "bank_index": bank_index,
            "source_kind": "snapshot",
            "source_record": record,
            "slot_id": slot["slot_id"],
            "flow_time": slot["flow_time"],
            "cycle": parsed["cycle"],
            "local_x_index": "",
            "snapshot_file": str(snap),
            "x_history_file": "",
        }
        idx_writer.writerow(row)
        rows.append(row)
        bank_index += 1
    return bank_index, state_size, rows


def extract_from_x_history(run_root, records, state_size, burn_records, max_records_per_chain, history_stride, x_out, idx_writer, start_bank_index):
    if state_size < 1:
        raise RuntimeError("--state-size is required for cold-x-history extraction.")
    if burn_records < 0:
        raise RuntimeError("--burn-records must be >= 0.")
    if max_records_per_chain < 0:
        raise RuntimeError("--max-records-per-chain must be >= 0.")
    if history_stride < 1:
        raise RuntimeError("--history-stride must be >= 1.")
    bank_index = start_bank_index
    rows = []
    for record in records:
        x_file = record_dir(run_root, record) / "x_history.dat"
        if not x_file.exists():
            raise RuntimeError("Missing x_history.dat for record {0}: {1}".format(record, x_file))
        x_rows = read_x_history(x_file, state_size)
        selected = x_rows[burn_records::history_stride]
        if max_records_per_chain > 0:
            selected = selected[:max_records_per_chain]
        for local_idx, x_row in enumerate(selected):
            x_row.tofile(x_out)
            raw_idx = burn_records + local_idx * history_stride
            row = {
                "bank_index": bank_index,
                "source_kind": "cold_x_history",
                "source_record": record,
                "slot_id": "max",
                "flow_time": "",
                "cycle": raw_idx,
                "local_x_index": raw_idx,
                "snapshot_file": "",
                "x_history_file": str(x_file),
            }
            idx_writer.writerow(row)
            rows.append(row)
            bank_index += 1
    return bank_index, state_size, rows


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    run_root = resolve_repo_path(repo_root, args.run_root).resolve()
    records = parse_records(args.records, run_root)
    output_root = resolve_repo_path(repo_root, args.output_root).resolve()
    run_name = args.run_name or datetime.now(tz=timezone.utc).strftime("stage2_highflow_x_bank_%Y%m%dT%H%M%SZ")
    out_dir = output_root / run_name
    if out_dir.exists():
        if not args.force:
            raise RuntimeError("Output dir exists; use --force: {0}".format(out_dir))
        shutil.rmtree(out_dir)
    bank_dir = out_dir / "bank"
    bank_dir.mkdir(parents=True, exist_ok=True)

    source = args.source
    if source == "auto":
        first = record_dir(run_root, records[0])
        source = "snapshots" if (first / "final_snapshot.bin").exists() else "cold-x-history"

    x_bank_file = bank_dir / "x_bank.dat"
    index_file = bank_dir / "x_bank_index.csv"
    rows = []
    state_size = args.state_size if args.state_size > 0 else None
    with x_bank_file.open("wb") as x_out, index_file.open("w", newline="", encoding="utf-8") as idx_handle:
        fieldnames = [
            "bank_index",
            "source_kind",
            "source_record",
            "slot_id",
            "flow_time",
            "cycle",
            "local_x_index",
            "snapshot_file",
            "x_history_file",
        ]
        idx_writer = csv.DictWriter(idx_handle, fieldnames=fieldnames)
        idx_writer.writeheader()
        if source == "snapshots":
            _bank_index, state_size, rows = extract_from_snapshots(run_root, records, args.slot_id, x_out, idx_writer, 0)
        else:
            _bank_index, state_size, rows = extract_from_x_history(
                run_root,
                records,
                int(state_size or 0),
                args.burn_records,
                args.max_records_per_chain,
                args.history_stride,
                x_out,
                idx_writer,
                0,
            )

    coverage = {
        "schema": "stage2_highflow_x_bank.v1",
        "created_utc": datetime.now(tz=timezone.utc).isoformat(),
        "source_run_root": str(run_root),
        "source": source,
        "records": records,
        "slot_id_request": args.slot_id,
        "state_size": state_size,
        "selected_checkpoints": len(rows),
        "x_bank_file": str(x_bank_file),
        "index_file": str(index_file),
        "rows": rows[:20],
    }
    (bank_dir / "coverage_summary.json").write_text(json.dumps(coverage, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "x_bank_file": str(x_bank_file),
        "index_file": str(index_file),
        "selected_checkpoints": len(rows),
        "state_size": state_size,
        "source": source,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
