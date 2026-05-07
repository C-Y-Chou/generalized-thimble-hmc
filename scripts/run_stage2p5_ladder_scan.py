#!/usr/bin/env python3

import argparse
import csv
import os
import subprocess
from collections import namedtuple
from pathlib import Path
from typing import Dict, List, Tuple

ScanCase = namedtuple("ScanCase", ["name", "ladder"])


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run stage-2.5 short ladder scan for TLTM.")
    p.add_argument("--repo-root", default=".", help="Path to repo root (default: current directory).")
    p.add_argument("--cycles", type=int, default=40, help="Global cycles per candidate ladder.")
    p.add_argument("--seed", type=int, default=20260421, help="Shared CHAIN_RNG_SEED for all runs.")
    p.add_argument("--local-updates", type=int, default=1, help="TLTM_STAGE2_LOCAL_UPDATES.")
    return p.parse_args()


def default_cases() -> List[ScanCase]:
    return [
        ScanCase("baseline_0_01_02_03", [0.0, 0.1, 0.2, 0.3]),
        ScanCase("cand_a_0_005_01_02_03", [0.0, 0.05, 0.1, 0.2, 0.3]),
        ScanCase("cand_b_0_002_005_01_02_03", [0.0, 0.02, 0.05, 0.1, 0.2, 0.3]),
        ScanCase("cand_c_0_001_003_005_01_02_03", [0.0, 0.01, 0.03, 0.05, 0.1, 0.2, 0.3]),
    ]


def run_case(repo_root: Path, case: ScanCase, cycles: int, seed: int, local_updates: int) -> Tuple[Path, Path, Path]:
    build_dir = repo_root / "build"
    out_dir = repo_root / "output" / "tests" / "stage2p5_scan"
    out_dir.mkdir(parents=True, exist_ok=True)
    log_dir = repo_root / "output" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    summary_file = out_dir / f"{case.name}_summary.dat"
    label_trace_file = out_dir / f"{case.name}_label_trace.dat"
    run_log_file = log_dir / f"tltm_stage2_{case.name}.log"

    env = {
        "CHAIN_RNG_SEED": str(seed),
        "TLTM_STAGE2_NUM_REPLICAS": str(len(case.ladder)),
        "TLTM_STAGE2_FLOW_TIME_LADDER": ",".join(f"{x:g}" for x in case.ladder),
        "TLTM_STAGE2_CYCLES": str(cycles),
        "TLTM_STAGE2_LOCAL_UPDATES": str(local_updates),
        "TLTM_STAGE2_SWAP_ENABLED": "1",
        "TLTM_STAGE2_SUMMARY_FILE": str(summary_file),
        "TLTM_STAGE2_LABEL_TRACE_FILE": str(label_trace_file),
    }

    cmd = ["make", "-C", str(build_dir), "tltm_stage2"]
    proc = subprocess.run(
        cmd,
        env={**os.environ, **env},
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    run_log_file.write_text(proc.stdout)
    if proc.returncode != 0:
        raise RuntimeError(f"Run failed for {case.name}. See {run_log_file}")
    return summary_file, label_trace_file, run_log_file


def parse_summary(summary_file: Path) -> Dict[str, object]:
    pairs: List[Dict[str, object]] = []
    labels: List[Dict[str, object]] = []
    elapsed = 0.0
    total_round_trip = 0
    n_slots = 0
    section = ""

    for raw in summary_file.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("# slots="):
            n_slots = int(line.split("=", 1)[1])
            continue
        if line.startswith("# elapsed_sec="):
            elapsed = float(line.split("=", 1)[1])
            continue
        if line.startswith("# total_round_trip="):
            total_round_trip = int(line.split("=", 1)[1])
            continue
        if line.startswith("# [pairs]"):
            section = "pairs"
            continue
        if line.startswith("# [labels]"):
            section = "labels"
            continue
        if line.startswith("# "):
            continue

        parts = line.split()
        if section == "pairs" and len(parts) >= 8:
            pairs.append(
                {
                    "pair_id": int(parts[0]),
                    "slot_a": int(parts[1]),
                    "slot_b": int(parts[2]),
                    "proposals": int(parts[3]),
                    "accepts": int(parts[4]),
                    "rejects": int(parts[5]),
                    "accept_rate": float(parts[6]),
                    "last_accept_prob": float(parts[7]),
                }
            )
        elif section == "labels" and len(parts) >= 6:
            labels.append(
                {
                    "label_id": int(parts[0]),
                    "current_slot": int(parts[1]),
                    "farthest_slot_reached": int(parts[2]),
                    "round_trip_count": int(parts[3]),
                    "avg_round_trip_cycles": float(parts[4]),
                    "last_extreme": int(parts[5]),
                }
            )

    if not pairs:
        raise RuntimeError(f"No pair stats parsed from {summary_file}")
    if not labels:
        raise RuntimeError(f"No label stats parsed from {summary_file}")

    active_pairs = [p for p in pairs if p["proposals"] > 0]
    min_pair = min(active_pairs, key=lambda x: x["accept_rate"])
    pair0 = next((p for p in pairs if p["pair_id"] == 0), None)
    pair_profile = ";".join(f"{p['pair_id']}:{p['accept_rate']:.3f}" for p in pairs)
    no_zero_bottleneck = all(p["accept_rate"] > 0.0 for p in active_pairs)

    hot_slot = n_slots - 1
    hot_end_hit_count = sum(1 for l in labels if l["farthest_slot_reached"] == hot_slot)
    crossing_labels_count = sum(1 for l in labels if l["farthest_slot_reached"] >= 2)
    cold_label = next((l for l in labels if l["label_id"] == 0), None)
    cold_label_farthest = cold_label["farthest_slot_reached"] if cold_label else -1

    return {
        "slots": n_slots,
        "elapsed_sec": elapsed,
        "pair_acceptance_profile": pair_profile,
        "min_pair": int(min_pair["pair_id"]),
        "min_accept_rate": float(min_pair["accept_rate"]),
        "pair0_accept_rate": float(pair0["accept_rate"]) if pair0 else -1.0,
        "no_zero_acceptance_bottleneck": no_zero_bottleneck,
        "hot_end_hit_count": hot_end_hit_count,
        "total_round_trip": total_round_trip,
        "cold_label_farthest_slot": cold_label_farthest,
        "crossing_labels_count": crossing_labels_count,
    }


def write_reports(repo_root: Path, rows: List[Dict[str, object]]) -> None:
    out_dir = repo_root / "output" / "tests" / "stage2p5_scan"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "candidate_ladder_scan_table.csv"
    md_path = out_dir / "candidate_ladder_scan_summary.md"

    fields = [
        "candidate",
        "ladder",
        "slots",
        "cycles",
        "elapsed_sec",
        "pair_acceptance_profile",
        "min_pair",
        "min_accept_rate",
        "pair0_accept_rate",
        "no_zero_acceptance_bottleneck",
        "crossing_labels_count",
        "cold_label_farthest_slot",
        "hot_end_hit_count",
        "total_round_trip",
        "summary_file",
        "label_trace_file",
        "run_log_file",
    ]
    with csv_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "# Stage-2.5 Candidate Ladder Scan (Short)",
        "",
        "| candidate | ladder | min_pair_accept | pair0_accept | no_zero_bottleneck | crossing_labels | hot_end_hits | total_round_trip |",
        "|---|---|---:|---:|:---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['candidate']} | {r['ladder']} | {r['min_accept_rate']:.3f} | "
            f"{r['pair0_accept_rate']:.3f} | {str(r['no_zero_acceptance_bottleneck']).lower()} | "
            f"{r['crossing_labels_count']} | {r['hot_end_hit_count']} | {r['total_round_trip']} |"
        )
    md_path.write_text("\n".join(lines) + "\n")


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    cases = default_cases()
    rows: List[Dict[str, object]] = []

    for case in cases:
        summary_file, label_trace_file, run_log_file = run_case(
            repo_root=repo_root,
            case=case,
            cycles=args.cycles,
            seed=args.seed,
            local_updates=args.local_updates,
        )
        parsed = parse_summary(summary_file)
        parsed.update(
            {
                "candidate": case.name,
                "ladder": ",".join(f"{x:g}" for x in case.ladder),
                "cycles": args.cycles,
                "summary_file": str(summary_file.relative_to(repo_root)),
                "label_trace_file": str(label_trace_file.relative_to(repo_root)),
                "run_log_file": str(run_log_file.relative_to(repo_root)),
            }
        )
        rows.append(parsed)
        print(
            f"[SCAN] {case.name}: min_accept={parsed['min_accept_rate']:.3f} "
            f"pair0={parsed['pair0_accept_rate']:.3f} hot_hits={parsed['hot_end_hit_count']} "
            f"round_trip={parsed['total_round_trip']}"
        )

    write_reports(repo_root, rows)
    print("[DONE] Wrote:")
    print("  output/tests/stage2p5_scan/candidate_ladder_scan_table.csv")
    print("  output/tests/stage2p5_scan/candidate_ladder_scan_summary.md")


if __name__ == "__main__":
    main()
