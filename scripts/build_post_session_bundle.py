#!/usr/bin/env python3
"""Build merged post-session analysis inputs from a multichain run directory."""

from __future__ import annotations

import argparse
import csv
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


@dataclass
class StreamRecord:
    sample_idx: int
    n: int
    payload: bytes


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Merge per-chain constraint failure captures into a single "
            "post-session bundle directory."
        )
    )
    parser.add_argument(
        "--run-dir",
        type=Path,
        required=True,
        help="Path to output/multichain_auto/<run_name>.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        required=True,
        help="Path to output/post_session_analysis/<run_name>.",
    )
    parser.add_argument(
        "--first-n",
        type=int,
        default=100,
        help="First-N subset for official post-session view.",
    )
    parser.add_argument(
        "--light-n",
        type=int,
        default=600,
        help="First-N subset for light post-session view.",
    )
    return parser.parse_args()


def list_chains(run_dir: Path) -> List[Path]:
    chains = sorted(
        [p for p in run_dir.iterdir() if p.is_dir() and p.name.startswith("chain_")]
    )
    if not chains:
        raise RuntimeError(f"No chain_* directories found in {run_dir}")
    return chains


def read_stream_records(path: Path, item_bytes: int) -> List[StreamRecord]:
    records: List[StreamRecord] = []
    with path.open("rb") as fobj:
        while True:
            head = fobj.read(8)
            if not head:
                break
            if len(head) != 8:
                raise RuntimeError(f"Truncated header in {path}")
            sample_idx, n = struct.unpack("<ii", head)
            if n < 0:
                raise RuntimeError(f"Invalid n={n} in {path}")
            payload = fobj.read(item_bytes * n)
            if len(payload) != item_bytes * n:
                raise RuntimeError(f"Truncated payload in {path} at sample_idx={sample_idx}")
            records.append(StreamRecord(sample_idx=sample_idx, n=n, payload=payload))
    return records


def write_stream_records(path: Path, records: List[StreamRecord]) -> None:
    with path.open("wb") as fobj:
        for rec in records:
            fobj.write(struct.pack("<ii", rec.sample_idx, rec.n))
            fobj.write(rec.payload)


def load_chain_records(chain_dir: Path) -> Tuple[Dict[int, StreamRecord], Dict[int, StreamRecord], Dict[int, StreamRecord]]:
    out_dir = chain_dir / "output"
    z0_path = out_dir / "constraint_solver_fail_z0.dat"
    delz_path = out_dir / "constraint_solver_fail_delz.dat"
    x0_path = out_dir / "constraint_solver_fail_x0.dat"
    if not z0_path.exists() or not delz_path.exists() or not x0_path.exists():
        return {}, {}, {}

    z0_records = read_stream_records(z0_path, item_bytes=16)
    delz_records = read_stream_records(delz_path, item_bytes=8)
    x0_records = read_stream_records(x0_path, item_bytes=8)

    z0_map = {r.sample_idx: r for r in z0_records}
    delz_map = {r.sample_idx: r for r in delz_records}
    x0_map = {r.sample_idx: r for r in x0_records}

    common = sorted(set(z0_map) & set(delz_map) & set(x0_map))
    z0_map = {k: z0_map[k] for k in common}
    delz_map = {k: delz_map[k] for k in common}
    x0_map = {k: x0_map[k] for k in common}
    return z0_map, delz_map, x0_map


def build_global_mapping(
    chain_names: List[str], per_chain_sample_ids: Dict[str, List[int]]
) -> Tuple[List[Tuple[int, str, int, int]], Dict[Tuple[str, int], int]]:
    mapping_rows: List[Tuple[int, str, int, int]] = []
    sample_map: Dict[Tuple[str, int], int] = {}

    max_len = max((len(v) for v in per_chain_sample_ids.values()), default=0)
    new_idx = 1
    for local_record_idx in range(1, max_len + 1):
        for chain in chain_names:
            ids = per_chain_sample_ids.get(chain, [])
            if local_record_idx > len(ids):
                continue
            old_sample_idx = ids[local_record_idx - 1]
            mapping_rows.append((new_idx, chain, old_sample_idx, local_record_idx))
            sample_map[(chain, old_sample_idx)] = new_idx
            new_idx += 1
    return mapping_rows, sample_map


def merge_trace_csv(
    chains: List[Path],
    sample_map: Dict[Tuple[str, int], int],
    out_trace_csv: Path,
) -> int:
    rows_out: List[dict] = []
    header: List[str] | None = None
    for chain_dir in chains:
        chain_name = chain_dir.name
        path = chain_dir / "output" / "constraint_solver_fail_quasi_trace.csv"
        if not path.exists():
            continue
        with path.open("r", newline="") as fobj:
            reader = csv.DictReader(fobj)
            if reader.fieldnames is None:
                continue
            if header is None:
                header = list(reader.fieldnames)
            for row in reader:
                try:
                    old_idx = int(row["sample_idx"].strip())
                except Exception:
                    continue
                key = (chain_name, old_idx)
                if key not in sample_map:
                    continue
                row["sample_idx"] = str(sample_map[key])
                rows_out.append(row)

    if header is None:
        header = [
            "sample_idx",
            "proposal_idx",
            "attempt_idx",
            "iter_idx",
            "backtrack_idx",
            "alpha",
            "res_norm",
            "accepted",
            "eval_ok",
            "z_prop_re",
            "z_prop_im",
            "z_flow_re",
            "z_flow_im",
        ]

    rows_out.sort(
        key=lambda r: (
            int(r["sample_idx"]),
            int(r["attempt_idx"]),
            int(r["proposal_idx"]),
        )
    )
    with out_trace_csv.open("w", newline="") as fobj:
        writer = csv.DictWriter(fobj, fieldnames=header)
        writer.writeheader()
        writer.writerows(rows_out)
    return len(rows_out)


def merge_meta_csv(
    chains: List[Path],
    sample_map: Dict[Tuple[str, int], int],
    out_meta_csv: Path,
) -> int:
    rows_out: List[dict] = []
    header: List[str] | None = None
    for chain_dir in chains:
        chain_name = chain_dir.name
        path = chain_dir / "output" / "constraint_solver_fail_meta.csv"
        if not path.exists():
            continue
        with path.open("r", newline="") as fobj:
            reader = csv.DictReader(fobj)
            if reader.fieldnames is None:
                continue
            clean_fieldnames = [fn for fn in reader.fieldnames if fn]
            if header is None:
                header = list(clean_fieldnames) + ["chain"]
            for row in reader:
                # Some Fortran CSV rows may end with a trailing comma; csv.DictReader
                # exposes that as key None. Drop it to keep downstream schema stable.
                row = {k: v for k, v in row.items() if k}
                try:
                    old_idx = int(row["sample_idx"].strip())
                except Exception:
                    continue
                key = (chain_name, old_idx)
                if key not in sample_map:
                    continue
                row["sample_idx"] = str(sample_map[key])
                row["chain"] = chain_name
                rows_out.append(row)

    if header is None:
        return 0

    rows_out.sort(
        key=lambda r: (
            int(r["sample_idx"]),
            int(r.get("chain_sample_idx", "0")),
            int(r.get("hmc_repeat_idx", "0")),
        )
    )
    with out_meta_csv.open("w", newline="") as fobj:
        writer = csv.DictWriter(fobj, fieldnames=header)
        writer.writeheader()
        writer.writerows(rows_out)
    return len(rows_out)


def write_trace_subset(src_csv: Path, dst_csv: Path, max_sample_idx: int) -> int:
    with src_csv.open("r", newline="") as fin:
        reader = csv.DictReader(fin)
        if reader.fieldnames is None:
            raise RuntimeError(f"Missing header in {src_csv}")
        if max_sample_idx <= 0:
            rows = list(reader)
        else:
            rows = [r for r in reader if int(r["sample_idx"]) <= max_sample_idx]
        with dst_csv.open("w", newline="") as fout:
            writer = csv.DictWriter(fout, fieldnames=reader.fieldnames)
            writer.writeheader()
            writer.writerows(rows)
    return len(rows)


def concat_binary(files: List[Path], out_path: Path) -> int:
    total_bytes = 0
    with out_path.open("wb") as fout:
        for path in files:
            if not path.exists():
                continue
            data = path.read_bytes()
            fout.write(data)
            total_bytes += len(data)
    return total_bytes


def subset_tag(limit: int) -> str:
    return "all" if limit <= 0 else str(limit)


def main() -> None:
    args = parse_args()
    run_dir = args.run_dir.resolve()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    chains = list_chains(run_dir)
    chain_names = [c.name for c in chains]

    per_chain_z0: Dict[str, Dict[int, StreamRecord]] = {}
    per_chain_delz: Dict[str, Dict[int, StreamRecord]] = {}
    per_chain_x0: Dict[str, Dict[int, StreamRecord]] = {}
    per_chain_ids: Dict[str, List[int]] = {}

    for chain_dir in chains:
        chain_name = chain_dir.name
        z0_map, delz_map, x0_map = load_chain_records(chain_dir)
        ids = sorted(set(z0_map) & set(delz_map) & set(x0_map))
        per_chain_z0[chain_name] = z0_map
        per_chain_delz[chain_name] = delz_map
        per_chain_x0[chain_name] = x0_map
        per_chain_ids[chain_name] = ids

    mapping_rows, sample_map = build_global_mapping(chain_names, per_chain_ids)

    merged_z0: List[StreamRecord] = []
    merged_delz: List[StreamRecord] = []
    merged_x0: List[StreamRecord] = []
    for new_idx, chain, old_idx, _ in mapping_rows:
        merged_z0.append(StreamRecord(new_idx, per_chain_z0[chain][old_idx].n, per_chain_z0[chain][old_idx].payload))
        merged_delz.append(StreamRecord(new_idx, per_chain_delz[chain][old_idx].n, per_chain_delz[chain][old_idx].payload))
        merged_x0.append(StreamRecord(new_idx, per_chain_x0[chain][old_idx].n, per_chain_x0[chain][old_idx].payload))

    write_stream_records(out_dir / "constraint_solver_fail_z0.dat", merged_z0)
    write_stream_records(out_dir / "constraint_solver_fail_delz.dat", merged_delz)
    write_stream_records(out_dir / "constraint_solver_fail_x0.dat", merged_x0)

    with (out_dir / "sample_id_map.csv").open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(["new_sample_idx", "chain", "old_sample_idx", "local_record_idx"])
        writer.writerows(mapping_rows)

    trace_rows = merge_trace_csv(
        chains=chains,
        sample_map=sample_map,
        out_trace_csv=out_dir / "constraint_solver_fail_quasi_trace.csv",
    )
    meta_rows = merge_meta_csv(
        chains=chains,
        sample_map=sample_map,
        out_meta_csv=out_dir / "constraint_solver_fail_meta.csv",
    )
    first_tag = subset_tag(args.first_n)
    light_tag = subset_tag(args.light_n)
    first_subset = out_dir / f"constraint_solver_fail_quasi_trace_first{first_tag}.csv"
    light_subset = out_dir / f"constraint_solver_fail_quasi_trace_first{light_tag}.csv"

    n_first = write_trace_subset(
        out_dir / "constraint_solver_fail_quasi_trace.csv",
        first_subset,
        args.first_n,
    )
    n_light = write_trace_subset(
        out_dir / "constraint_solver_fail_quasi_trace.csv",
        light_subset,
        args.light_n,
    )

    z_hist_files = [c / "output" / "z_history.dat" for c in chains]
    z_hist_bytes = concat_binary(z_hist_files, out_dir / "ensemble_z_history_merged.dat")

    meta = {
        "run_dir": str(run_dir),
        "out_dir": str(out_dir),
        "chains": chain_names,
        "merged_failure_samples": len(mapping_rows),
        "trace_rows": trace_rows,
        "meta_rows": meta_rows,
        "trace_rows_first_n": n_first,
        "trace_rows_light_n": n_light,
        "z_history_concat_bytes": z_hist_bytes,
        "first_n": args.first_n,
        "light_n": args.light_n,
        "trace_csv_first_n": str(first_subset),
        "trace_csv_light_n": str(light_subset),
        "first_n_tag": first_tag,
        "light_n_tag": light_tag,
    }
    with (out_dir / "bundle_metadata.json").open("w") as fobj:
        json.dump(meta, fobj, indent=2, sort_keys=True)

    print(f"[DONE] out_dir={out_dir}")
    print(f"[DONE] merged_failure_samples={len(mapping_rows)}")
    print(
        f"[DONE] trace_rows={trace_rows} meta_rows={meta_rows} "
        f"first_n_rows={n_first} ({first_tag}) light_n_rows={n_light} ({light_tag})"
    )
    print(f"[DONE] z_history_concat_bytes={z_hist_bytes}")


if __name__ == "__main__":
    main()
