#!/usr/bin/env python3
"""Build a WV-HMC state bank from per-seed final-state records."""

from __future__ import print_function

import argparse
import csv
from pathlib import Path


def read_manifest_paths(root):
    paths = []
    for manifest in sorted(root.glob("**/wv_hmc_dense_observable_validation_manifest.csv")):
        with manifest.open(newline="") as handle:
            for row in csv.DictReader(handle):
                state_path = row.get("final_state_path", "")
                if state_path:
                    paths.append(Path(state_path))
    return paths


def discover_state_paths(root):
    manifest_paths = read_manifest_paths(root)
    if manifest_paths:
        return sorted(dict.fromkeys(manifest_paths))
    return sorted(root.glob("**/*_final_state.bin"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--state-size", type=int, required=True, help="Number of real x components, excluding flow time.")
    args = parser.parse_args()

    input_root = Path(args.input_root)
    output = Path(args.output)
    record_bytes = (args.state_size + 1) * 8
    paths = discover_state_paths(input_root)
    if not paths:
        raise SystemExit("no final-state files found under {}".format(input_root))

    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    with output.open("wb") as out:
        for path in paths:
            data = path.read_bytes()
            if len(data) != record_bytes:
                raise SystemExit(
                    "state record size mismatch: {} has {} bytes, expected {}".format(path, len(data), record_bytes)
                )
            out.write(data)
            rows.append({"record": len(rows), "source_path": str(path), "bytes": len(data)})

    index_path = output.with_suffix(output.suffix + ".index.csv")
    with index_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["record", "source_path", "bytes"])
        writer.writeheader()
        writer.writerows(rows)

    print("state_bank={}".format(output))
    print("index={}".format(index_path))
    print("records={}".format(len(rows)))


if __name__ == "__main__":
    main()
