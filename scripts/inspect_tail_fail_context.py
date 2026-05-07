#!/usr/bin/env python3
"""Inspect failure captures in a chain around a target sample window.

This correlates:
- failure meta rows (classification + solver counters),
- z0 / delz captured snapshots,
for events whose `chain_sample_idx` is in [sample_from, sample_to].
"""

from __future__ import annotations

import argparse
import csv
import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


@dataclass
class StreamRecord:
    sample_idx: int
    n: int
    payload: bytes


def read_stream_records(path: Path, item_bytes: int) -> Dict[int, StreamRecord]:
    out: Dict[int, StreamRecord] = {}
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
            out[sample_idx] = StreamRecord(sample_idx=sample_idx, n=n, payload=payload)
    return out


def decode_complex_vec(payload: bytes, n: int) -> List[complex]:
    vals: List[complex] = []
    off = 0
    for _ in range(n):
        re, im = struct.unpack_from("<dd", payload, off)
        vals.append(complex(re, im))
        off += 16
    return vals


def decode_real_vec(payload: bytes, n: int) -> List[float]:
    vals: List[float] = []
    off = 0
    for _ in range(n):
        (x,) = struct.unpack_from("<d", payload, off)
        vals.append(x)
        off += 8
    return vals


def l2_norm(vals: Iterable[float]) -> float:
    s = 0.0
    for v in vals:
        s += v * v
    return math.sqrt(s)


def quasi_case_name(code: int) -> str:
    return {0: "far", 1: "near", 2: "mid"}.get(code, "unknown")


def online_class_name(code: int) -> str:
    return {1: "local", 2: "mid", 3: "global"}.get(code, "unknown")


def main() -> int:
    ap = argparse.ArgumentParser(description="Inspect chain failure contexts around tail sample window.")
    ap.add_argument("--run-dir", required=True, help="Run dir: output/multichain_auto/<run>")
    ap.add_argument("--chain", required=True, help="Chain dir name, e.g. chain_003")
    ap.add_argument("--sample-from", type=int, required=True, help="Inclusive start of chain_sample_idx")
    ap.add_argument("--sample-to", type=int, required=True, help="Inclusive end of chain_sample_idx")
    ap.add_argument("--out-csv", default="", help="Optional output CSV path")
    args = ap.parse_args()

    chain_dir = Path(args.run_dir).resolve() / args.chain / "output"
    meta_path = chain_dir / "constraint_solver_fail_meta.csv"
    z0_path = chain_dir / "constraint_solver_fail_z0.dat"
    delz_path = chain_dir / "constraint_solver_fail_delz.dat"

    if not meta_path.exists():
        raise SystemExit(f"[ERROR] missing meta file: {meta_path}")
    if not z0_path.exists() or not delz_path.exists():
        raise SystemExit(f"[ERROR] missing z0/delz files in: {chain_dir}")

    z0_map = read_stream_records(z0_path, 16)
    delz_map = read_stream_records(delz_path, 8)

    rows: List[dict] = []
    with meta_path.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        if reader.fieldnames is None:
            raise SystemExit(f"[ERROR] missing header in {meta_path}")
        for row in reader:
            try:
                chain_sample_idx = int(row["chain_sample_idx"])
                cap_idx = int(row["sample_idx"])
            except Exception:
                continue
            if chain_sample_idx < args.sample_from or chain_sample_idx > args.sample_to:
                continue
            if cap_idx not in z0_map or cap_idx not in delz_map:
                continue

            z0_rec = z0_map[cap_idx]
            delz_rec = delz_map[cap_idx]
            z0 = decode_complex_vec(z0_rec.payload, z0_rec.n)
            delz = decode_real_vec(delz_rec.payload, delz_rec.n)

            abs_re = [abs(z.real) for z in z0]
            abs_im = [abs(z.imag) for z in z0]
            abs_delz = [abs(x) for x in delz]

            out = {
                "capture_sample_idx": cap_idx,
                "chain_sample_idx": chain_sample_idx,
                "hmc_repeat_idx": int(row.get("hmc_repeat_idx", "0")),
                "quasi_case": int(row.get("quasi_case", "-1")),
                "quasi_case_name": quasi_case_name(int(row.get("quasi_case", "-1"))),
                "online_class": int(row.get("online_class", "-1")),
                "online_class_name": online_class_name(int(row.get("online_class", "-1"))),
                "is_near_case": int(row.get("is_near_case", "-1")),
                "near_rescue_started": int(row.get("near_rescue_started", "-1")),
                "near_rescue_done": int(row.get("near_rescue_done", "-1")),
                "near_fail_fast": int(row.get("near_fail_fast", "0")),
                "near_fail_fast_reason": int(row.get("near_fail_fast_reason", "0")),
                "far_fail_fast": int(row.get("far_fail_fast", "0")),
                "far_fail_fast_reason": int(row.get("far_fail_fast_reason", "0")),
                "trace_valid_fraction": row.get("trace_valid_fraction", ""),
                "trace_progress_ratio": row.get("trace_progress_ratio", ""),
                "trace_regress_ratio": row.get("trace_regress_ratio", ""),
                "trace_best_over_tol": row.get("trace_best_over_tol", ""),
                "d_attempt_flowzr": int(row.get("d_attempt_flowzr", "0")),
                "d_attempt_flowz": int(row.get("d_attempt_flowz", "0")),
                "d_attempt_flow": int(row.get("d_attempt_flow", "0")),
                "d_fail_flowzr": int(row.get("d_fail_flowzr", "0")),
                "d_fail_flowz": int(row.get("d_fail_flowz", "0")),
                "d_fail_flow": int(row.get("d_fail_flow", "0")),
                "d_success_final_resort": int(row.get("d_success_final_resort", "0")),
                "d_fail_final_resort": int(row.get("d_fail_final_resort", "0")),
                "final_resort_budget_hit": int(row.get("final_resort_budget_hit", "-1")),
                "final_resort_budget_used": int(row.get("final_resort_budget_used", "-1")),
                "final_resort_budget_limit": int(row.get("final_resort_budget_limit", "-1")),
                "z0_n": z0_rec.n,
                "delz_n": delz_rec.n,
                "z0_abs_re_min": min(abs_re) if abs_re else 0.0,
                "z0_abs_re_max": max(abs_re) if abs_re else 0.0,
                "z0_abs_im_max": max(abs_im) if abs_im else 0.0,
                "z0_l2_abs_re": l2_norm(abs_re),
                "delz_abs_max": max(abs_delz) if abs_delz else 0.0,
                "delz_l2": l2_norm(delz),
                "z0_re_1": z0[0].real if z0 else 0.0,
                "z0_im_1": z0[0].imag if z0 else 0.0,
                "delz_1": delz[0] if delz else 0.0,
            }
            rows.append(out)

    rows.sort(key=lambda r: (r["chain_sample_idx"], r["hmc_repeat_idx"], r["capture_sample_idx"]))

    print(f"run_dir={Path(args.run_dir).resolve()}")
    print(f"chain={args.chain} sample_window=[{args.sample_from},{args.sample_to}] matched_rows={len(rows)}")
    if rows:
        print(
            "capture_sample_idx,chain_sample_idx,hmc_repeat_idx,quasi_case_name,online_class_name,"
            "is_near_case,near_rescue_started,near_rescue_done,near_fail_fast,near_fail_fast_reason,"
            "far_fail_fast,far_fail_fast_reason,"
            "d_attempt_flowzr,d_attempt_flowz,"
            "d_fail_flowzr,d_fail_flowz,d_success_final_resort,d_fail_final_resort,"
            "final_resort_budget_hit,final_resort_budget_used,final_resort_budget_limit,"
            "z0_abs_re_max,delz_abs_max,delz_l2"
        )
        for r in rows:
            print(
                f"{r['capture_sample_idx']},{r['chain_sample_idx']},{r['hmc_repeat_idx']},"
                f"{r['quasi_case_name']},{r['online_class_name']},"
                f"{r['is_near_case']},{r['near_rescue_started']},{r['near_rescue_done']},"
                f"{r['near_fail_fast']},{r['near_fail_fast_reason']},"
                f"{r['far_fail_fast']},{r['far_fail_fast_reason']},"
                f"{r['d_attempt_flowzr']},{r['d_attempt_flowz']},"
                f"{r['d_fail_flowzr']},{r['d_fail_flowz']},"
                f"{r['d_success_final_resort']},{r['d_fail_final_resort']},"
                f"{r['final_resort_budget_hit']},{r['final_resort_budget_used']},{r['final_resort_budget_limit']},"
                f"{r['z0_abs_re_max']:.6e},{r['delz_abs_max']:.6e},{r['delz_l2']:.6e}"
            )

    if args.out_csv:
        out_path = Path(args.out_csv).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        if rows:
            with out_path.open("w", newline="") as fobj:
                writer = csv.DictWriter(fobj, fieldnames=list(rows[0].keys()))
                writer.writeheader()
                writer.writerows(rows)
        else:
            with out_path.open("w", newline="") as fobj:
                writer = csv.writer(fobj)
                writer.writerow(["no_rows"])
        print(f"wrote_csv={out_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
