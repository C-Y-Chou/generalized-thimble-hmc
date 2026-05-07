#!/usr/bin/env python3
"""Analyze multichain progress logs for heavy tail events.

This script scans `chain_*/logs/generate_markov_chain.log` under a run dir and:
- reports per-chain completion time and largest progress-time jump,
- reports jump events above a threshold with counter deltas,
- prints run-level robust timing stats (median/p90/p95/max).
"""

from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Dict, List, Optional


PROGRESS_RE = re.compile(r"\[PROGRESS\]\s+(\d+)/(\d+).*elapsed=\s*([0-9.]+)s")
NEWTON_RE = re.compile(
    r"newton=(\d+)/(\d+).+quasi=(\d+)/(\d+).+fail=(\d+)/(\d+).+inner_resort=(\d+)"
)
FLOW_RE = re.compile(
    r"inner_fb=(\d+)\s+flowz_fb=(\d+)\s+flowzr_fb=(\d+)\s+unknown_fb=(\d+)\s+unknown_hard_fail=(\d+)"
)
NEAR_RE = re.compile(
    r"near_fail=(\d+)\s+near_try=(\d+)\s+near_ok=(\d+)\s+near_unusable=(\d+)\s+far_fail=(\d+)"
)
CLASS_RE = re.compile(r"quasi_class\s+local=(\d+)\s+mid=(\d+)\s+global=(\d+)")


@dataclass
class Snapshot:
    sample: int
    total: int
    elapsed: float
    counters: Dict[str, int]


@dataclass
class ChainSummary:
    chain: str
    final_elapsed: float
    max_jump: float
    jump_from: int
    jump_to: int


def parse_chain_log(path: Path) -> List[Snapshot]:
    snapshots: List[Snapshot] = []
    current: Optional[Snapshot] = None

    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = PROGRESS_RE.search(line)
            if m:
                if current is not None:
                    snapshots.append(current)
                current = Snapshot(
                    sample=int(m.group(1)),
                    total=int(m.group(2)),
                    elapsed=float(m.group(3)),
                    counters={},
                )
                continue

            if current is None:
                continue

            m = NEWTON_RE.search(line)
            if m:
                current.counters["newton"] = int(m.group(1))
                current.counters["newton_total"] = int(m.group(2))
                current.counters["quasi"] = int(m.group(3))
                current.counters["quasi_total"] = int(m.group(4))
                current.counters["fail"] = int(m.group(5))
                current.counters["fail_total"] = int(m.group(6))
                current.counters["inner_resort"] = int(m.group(7))
                continue

            m = FLOW_RE.search(line)
            if m:
                current.counters["inner_fb"] = int(m.group(1))
                current.counters["flowz_fb"] = int(m.group(2))
                current.counters["flowzr_fb"] = int(m.group(3))
                current.counters["unknown_fb"] = int(m.group(4))
                current.counters["unknown_hard_fail"] = int(m.group(5))
                continue

            m = NEAR_RE.search(line)
            if m:
                current.counters["near_fail"] = int(m.group(1))
                current.counters["near_try"] = int(m.group(2))
                current.counters["near_ok"] = int(m.group(3))
                current.counters["near_unusable"] = int(m.group(4))
                current.counters["far_fail"] = int(m.group(5))
                continue

            m = CLASS_RE.search(line)
            if m:
                current.counters["class_local"] = int(m.group(1))
                current.counters["class_mid"] = int(m.group(2))
                current.counters["class_global"] = int(m.group(3))
                continue

    if current is not None:
        snapshots.append(current)
    return snapshots


def percentile_from_sorted(values: List[float], q: float) -> float:
    if not values:
        return float("nan")
    idx = max(1, min(len(values), int(math.ceil(q * len(values)))))
    return values[idx - 1]


def main() -> int:
    ap = argparse.ArgumentParser(description="Analyze heavy tail progress events from chain logs.")
    ap.add_argument("--run-dir", required=True, help="Run directory under output/multichain_auto/<run>")
    ap.add_argument(
        "--jump-threshold",
        type=float,
        default=30.0,
        help="Report jump events with delta elapsed >= threshold seconds (default: 30)",
    )
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    chain_logs = sorted(run_dir.glob("chain_*/logs/generate_markov_chain.log"))
    if not chain_logs:
        raise SystemExit(f"[ERROR] no chain logs found under: {run_dir}")

    chain_summaries: List[ChainSummary] = []
    events: List[Dict[str, object]] = []

    for log in chain_logs:
        chain = log.parents[1].name
        snapshots = parse_chain_log(log)
        if not snapshots:
            continue

        final_elapsed = snapshots[-1].elapsed
        max_jump = -1.0
        jump_from = -1
        jump_to = -1

        for prev, cur in zip(snapshots, snapshots[1:]):
            jump = cur.elapsed - prev.elapsed
            if jump > max_jump:
                max_jump = jump
                jump_from = prev.sample
                jump_to = cur.sample

            if jump >= args.jump_threshold:
                delta: Dict[str, int] = {}
                for key in (
                    "inner_resort",
                    "flowzr_fb",
                    "flowz_fb",
                    "near_try",
                    "near_ok",
                    "near_unusable",
                    "near_fail",
                    "far_fail",
                    "quasi",
                    "fail",
                    "class_local",
                    "class_mid",
                    "class_global",
                ):
                    if key in prev.counters and key in cur.counters:
                        delta[key] = cur.counters[key] - prev.counters[key]

                events.append(
                    {
                        "chain": chain,
                        "jump_s": jump,
                        "from": prev.sample,
                        "to": cur.sample,
                        "elapsed_from": prev.elapsed,
                        "elapsed_to": cur.elapsed,
                        "delta": delta,
                    }
                )

        chain_summaries.append(
            ChainSummary(
                chain=chain,
                final_elapsed=final_elapsed,
                max_jump=max_jump,
                jump_from=jump_from,
                jump_to=jump_to,
            )
        )

    chain_summaries.sort(key=lambda x: x.final_elapsed, reverse=True)
    final_times = sorted(c.final_elapsed for c in chain_summaries)

    print(f"run_dir={run_dir}")
    print(f"chains={len(chain_summaries)} jump_threshold={args.jump_threshold:.1f}s")
    print(
        "final_elapsed_stats:"
        f" min={final_times[0]:.2f}"
        f" median={median(final_times):.2f}"
        f" p90={percentile_from_sorted(final_times, 0.90):.2f}"
        f" p95={percentile_from_sorted(final_times, 0.95):.2f}"
        f" max={final_times[-1]:.2f}"
    )

    print("\nper_chain_top_by_final_elapsed:")
    print("chain,final_elapsed_s,max_jump_s,jump_from,jump_to")
    for c in chain_summaries:
        print(f"{c.chain},{c.final_elapsed:.2f},{c.max_jump:.2f},{c.jump_from},{c.jump_to}")

    events.sort(key=lambda e: float(e["jump_s"]), reverse=True)
    print(f"\nheavy_events(count={len(events)}):")
    print(
        "chain,jump_s,from,to,elapsed_from,elapsed_to,"
        "d_inner_resort,d_flowzr_fb,d_near_try,d_near_ok,d_near_unusable,d_near_fail,d_far_fail,d_quasi,d_fail"
    )
    for e in events:
        d = e["delta"]
        assert isinstance(d, dict)
        print(
            f"{e['chain']},{float(e['jump_s']):.2f},{e['from']},{e['to']},"
            f"{float(e['elapsed_from']):.2f},{float(e['elapsed_to']):.2f},"
            f"{d.get('inner_resort', 0)},{d.get('flowzr_fb', 0)},"
            f"{d.get('near_try', 0)},{d.get('near_ok', 0)},{d.get('near_unusable', 0)},"
            f"{d.get('near_fail', 0)},{d.get('far_fail', 0)},"
            f"{d.get('quasi', 0)},{d.get('fail', 0)}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

