#!/usr/bin/env python3
"""Benchmark nofb TLTM node-throughput layouts for Stephanov n=6."""

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_LADDER = "0,1e-3,3e-3,7e-3,1e-2,1.3e-2,1.6e-2,1.8e-2,2e-2,2.25e-2,2.5e-2,2.75e-2,3e-2"
DEFAULT_FLOW_BANK = (
    "output/stephanov_flow_banks/"
    "stephanov_n6_tltm_t003_ladder13_dop853_highflow_bank_8x600_20260523_xhist_b100_s5/"
    "flow_bank_ladder13_dop853_dense_cache"
)
KV_RE = re.compile(r"([A-Za-z0-9_]+)=\s*([^\s]+)")


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument("--output-root", default="output/stephanov_runtime_benchmarks")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--records", default="0:1:2:3:4:5:6:7:8:9:10:11:12:13:14:15:16:17:18:19:20:21:22:23:24:25:26:27:28:29:30:31")
    parser.add_argument("--cycles", type=int, default=40)
    parser.add_argument("--layouts", default="32x1,16x2,8x4,4x8,2x16,1x32")
    parser.add_argument("--blas-threads", type=int, default=1)
    parser.add_argument("--total-ncpus", type=int, default=32)
    parser.add_argument("--timeout-sec", type=int, default=3600)
    parser.add_argument("--seed-base", type=int, default=8930000)
    parser.add_argument("--ladder", default=DEFAULT_LADDER)
    parser.add_argument("--init-flow-bank-root", default=DEFAULT_FLOW_BANK)
    parser.add_argument("--swap-reflow-backend", default="direct")
    parser.add_argument("--local-reflow-cache-mode", default="none")
    parser.add_argument(
        "--omp-proc-bind",
        default="false",
        help=(
            "OpenMP binding policy. Default is false to match production "
            "record-parallel jobs; binding each independent process to "
            "OMP_PLACES=cores can pin every process to the first core."
        ),
    )
    parser.add_argument(
        "--omp-places",
        default="",
        help="Optional OMP_PLACES value. Leave empty for production-like process-parallel benchmarks.",
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def parse_records(text):
    return [int(item) for item in text.replace(",", ":").split(":") if item.strip()]


def parse_layouts(text):
    layouts = []
    for item in text.split(","):
        item = item.strip().lower()
        if not item:
            continue
        if "x" not in item:
            raise RuntimeError("layout must be jobsxthreads: {0}".format(item))
        jobs_text, threads_text = item.split("x", 1)
        jobs = int(jobs_text)
        threads = int(threads_text)
        if jobs < 1 or threads < 1:
            raise RuntimeError("layout values must be positive: {0}".format(item))
        layouts.append((item, jobs, threads))
    if not layouts:
        raise RuntimeError("no layouts requested")
    return layouts


def resolve_path(root, value):
    path = Path(value)
    if path.is_absolute():
        return path
    return root / path


def run_checked(cmd, cwd, env=None, log_path=None, timeout=None):
    start = time.monotonic()
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8", errors="replace") as handle:
            proc = subprocess.run(
                cmd,
                cwd=str(cwd),
                env=env,
                stdout=handle,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                timeout=timeout,
                check=False,
            )
        output = ""
    else:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            timeout=timeout,
            check=False,
        )
        output = proc.stdout
    wall = time.monotonic() - start
    if proc.returncode != 0:
        if log_path is not None and log_path.exists():
            output = log_path.read_text(encoding="utf-8", errors="replace")
        raise RuntimeError("command failed ({0}): {1}\n{2}".format(proc.returncode, " ".join(cmd), output[-4000:]))
    return wall, output


def build_stage2(repo_root, skip_build):
    if skip_build:
        return
    cmd = [
        "make",
        "-C",
        str(repo_root / "build"),
        "OMP=1",
        "ENABLE_OFFICIAL_DFOLS=1",
    ]
    for name in ("PYTHON", "PYTHON_EMBED_CFLAGS", "PYTHON_EMBED_LDFLAGS"):
        value = os.environ.get(name)
        if value:
            cmd.append("{0}={1}".format(name, value))
    cmd.append("../bin/run_tltm_stage2")
    run_checked(cmd, repo_root, timeout=3600)


def parse_value(value):
    if value in ("T", "F"):
        return value
    try:
        if any(ch in value for ch in (".", "E", "e")):
            return float(value)
        return int(value)
    except ValueError:
        return value


def parse_kv(line):
    return {key: parse_value(value) for key, value in KV_RE.findall(line)}


def parse_summary(path):
    metrics = {
        "elapsed_sec": 0.0,
        "local_update_sweep_sec": 0.0,
        "swap_sweep_sec": 0.0,
        "swap_reflow_sec": 0.0,
        "action_logdet_sec": 0.0,
        "measure_slots_sec": 0.0,
        "history_io_sec": 0.0,
        "label_trace_sec": 0.0,
        "progress_log_sec": 0.0,
        "accounted_loop_sec": 0.0,
        "unaccounted_loop_sec": 0.0,
        "swap_reflow_cache_flow_calls": 0,
        "swap_reflow_cache_flow_failures": 0,
        "accepted_local_total": 0,
        "proposal_failure_total": 0,
        "reverse_gate_reject_total": 0,
        "metropolis_reject_total": 0,
        "max_slot_runtime_sec": 0.0,
        "total_round_trip": 0,
    }
    section = ""
    if not path.exists():
        return metrics
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("# elapsed_sec="):
            metrics["elapsed_sec"] = float(line.split("=", 1)[1].strip())
        elif line.startswith("# production_timing"):
            values = parse_kv(line)
            for key in (
                "local_update_sweep_sec",
                "swap_sweep_sec",
                "measure_slots_sec",
                "history_io_sec",
                "label_trace_sec",
                "progress_log_sec",
                "accounted_loop_sec",
                "unaccounted_loop_sec",
            ):
                metrics[key] = float(values.get(key, metrics[key]))
        elif line.startswith("# production_subtiming"):
            values = parse_kv(line)
            metrics["swap_reflow_sec"] = float(values.get("swap_reflow_sec", 0.0))
            metrics["action_logdet_sec"] = float(values.get("action_logdet_sec", 0.0))
        elif line.startswith("# swap_reflow_cache"):
            values = parse_kv(line)
            metrics["swap_reflow_cache_flow_calls"] = int(values.get("flow_calls", 0))
            metrics["swap_reflow_cache_flow_failures"] = int(values.get("flow_failures", 0))
        elif line.startswith("# total_round_trip="):
            metrics["total_round_trip"] = int(line.split("=", 1)[1].strip())
        elif line.startswith("# [slots]"):
            section = "slots"
            continue
        elif line.startswith("# [pairs]") or line.startswith("# [labels]") or line.startswith("# [accepted"):
            section = ""
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if section == "slots" and len(parts) >= 13:
            metrics["accepted_local_total"] += int(parts[3])
            metrics["metropolis_reject_total"] += int(parts[10])
            metrics["reverse_gate_reject_total"] += int(parts[11])
            metrics["proposal_failure_total"] += int(parts[12])
            metrics["max_slot_runtime_sec"] = max(metrics["max_slot_runtime_sec"], float(parts[9]))
    return metrics


def mean(rows, key):
    vals = [float(row[key]) for row in rows if key in row]
    return sum(vals) / float(len(vals)) if vals else 0.0


def max_value(rows, key):
    vals = [float(row[key]) for row in rows if key in row]
    return max(vals) if vals else 0.0


def run_layout(repo_root, args, run_dir, layout_name, jobs, threads, records):
    selected = records[:jobs]
    if len(selected) < jobs:
        raise RuntimeError("layout {0} needs {1} records, got {2}".format(layout_name, jobs, len(selected)))
    case_name = "layout_{0}".format(layout_name)
    case_dir = run_dir / "cases" / case_name
    if case_dir.exists():
        shutil.rmtree(case_dir)
    env = os.environ.copy()
    env.update(
        {
            "TLTM_ODE_BACKEND": "dop853",
            "TLTM_DOP853_HINIT_ENABLED": "1",
            "TLTM_DOP853_STIFFNESS_CHECK_ENABLED": "1",
            "TLTM_DOP853_STIFFNESS_CHECK_INTERVAL": "1000",
            "TLTM_DOP853_STIFFNESS_MAX_HITS": "15",
            "TLTM_DOP853_STIFFNESS_THRESHOLD": "6.1",
            "TLTM_STAGE2_SWAP_REFLOW_BACKEND": args.swap_reflow_backend,
            "TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE": args.local_reflow_cache_mode,
            "OMP_DYNAMIC": "FALSE",
            "MKL_DYNAMIC": "FALSE",
            "OMP_PROC_BIND": args.omp_proc_bind,
        }
    )
    if args.omp_places:
        env["OMP_PLACES"] = args.omp_places
    cmd = [
        sys.executable,
        str(repo_root / "codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py"),
        "--repo-root",
        str(repo_root),
        "--base-parameters",
        args.base_parameters,
        "--output-root",
        str(run_dir / "cases"),
        "--run-name",
        case_name,
        "--ladder",
        args.ladder,
        "--records",
        ",".join(str(record) for record in selected),
        "--cycles",
        str(args.cycles),
        "--jobs",
        str(jobs),
        "--threads",
        str(threads),
        "--blas-threads",
        str(args.blas_threads),
        "--timeout-sec",
        str(args.timeout_sec),
        "--seed-base",
        str(args.seed_base),
        "--parallel-local-updates",
        "1",
        "--parallel-swaps",
        "1",
        "--init-flow-bank-root",
        str(resolve_path(repo_root, args.init_flow_bank_root)),
        "--write-cold-observables",
        "--observable-stride",
        "1",
        "--write-final-snapshot",
        "--skip-build",
        "--force",
    ]
    wall, _output = run_checked(
        cmd,
        repo_root,
        env=env,
        log_path=run_dir / "logs" / "{0}.log".format(case_name),
        timeout=args.timeout_sec * max(1, jobs) + 300,
    )
    record_rows = []
    for record in selected:
        summary_file = case_dir / "records" / "record_{0:04d}".format(record) / "summary.dat"
        row = {"layout": layout_name, "record": record, "summary_file": str(summary_file)}
        row.update(parse_summary(summary_file))
        record_rows.append(row)
    record_cycles = len(selected) * args.cycles
    mean_elapsed_sec = mean(record_rows, "elapsed_sec")
    max_elapsed_sec = max_value(record_rows, "elapsed_sec")
    return {
        "layout": layout_name,
        "jobs": jobs,
        "threads": threads,
        "blas_threads": args.blas_threads,
        "requested_cores": jobs * threads,
        "total_ncpus": args.total_ncpus,
        "records": len(selected),
        "cycles_per_record": args.cycles,
        "record_cycles": record_cycles,
        "case_wall_sec": wall,
        "record_cycles_per_wall_sec": record_cycles / wall if wall > 0.0 else 0.0,
        "record_cycles_per_core_sec": record_cycles / (wall * max(1, jobs * threads)) if wall > 0.0 else 0.0,
        "mean_elapsed_sec": mean_elapsed_sec,
        "max_elapsed_sec": max_elapsed_sec,
        "record_cycles_per_mean_elapsed_sec": record_cycles / mean_elapsed_sec if mean_elapsed_sec > 0.0 else 0.0,
        "record_cycles_per_max_elapsed_sec": record_cycles / max_elapsed_sec if max_elapsed_sec > 0.0 else 0.0,
        "mean_local_update_sweep_sec": mean(record_rows, "local_update_sweep_sec"),
        "mean_swap_sweep_sec": mean(record_rows, "swap_sweep_sec"),
        "mean_swap_reflow_sec": mean(record_rows, "swap_reflow_sec"),
        "mean_measure_slots_sec": mean(record_rows, "measure_slots_sec"),
        "mean_history_io_sec": mean(record_rows, "history_io_sec"),
        "mean_label_trace_sec": mean(record_rows, "label_trace_sec"),
        "mean_max_slot_runtime_sec": mean(record_rows, "max_slot_runtime_sec"),
        "mean_swap_reflow_flow_calls": mean(record_rows, "swap_reflow_cache_flow_calls"),
        "mean_swap_reflow_flow_failures": mean(record_rows, "swap_reflow_cache_flow_failures"),
        "case_dir": str(case_dir),
    }


def write_csv(path, rows):
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_readme(path, rows, args):
    best = max(rows, key=lambda row: row["record_cycles_per_wall_sec"]) if rows else None
    lines = [
        "# Stephanov n=6 nofb runtime layout benchmark",
        "",
        "Generated: `{0}`".format(datetime.now(timezone.utc).isoformat()),
        "",
        "This benchmark compares node-throughput layouts. The primary metric is `record_cycles_per_wall_sec`, not single-chain wall time.",
        "",
        "- cycles per record: `{0}`".format(args.cycles),
        "- layouts: `{0}`".format(args.layouts),
        "- BLAS threads: `{0}`".format(args.blas_threads),
        "- swap reflow backend: `{0}`".format(args.swap_reflow_backend),
        "- local reflow cache mode: `{0}`".format(args.local_reflow_cache_mode),
        "",
        "## Summary",
        "",
        "| layout | cores | records | wall s | record-cycles/s | local s/rec | swap s/rec |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| {layout} | {requested_cores} | {records} | {case_wall_sec:.3f} | {record_cycles_per_wall_sec:.6f} | {mean_local_update_sweep_sec:.3f} | {mean_swap_sweep_sec:.3f} |".format(
                **row
            )
        )
    if best is not None:
        lines.extend(
            [
                "",
                "Best observed throughput layout: `{0}` with `{1:.6f}` record-cycles/s.".format(
                    best["layout"], best["record_cycles_per_wall_sec"]
                ),
                "",
                "`record_cycles_per_wall_sec` includes build-independent runner overhead, flow-bank loading, and startup I/O. "
                "`record_cycles_per_max_elapsed_sec` in `benchmark_summary.csv` excludes Stage2 initialization and is the cleaner production-loop metric for long chunks.",
            ]
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_path(repo_root, args.output_root)
    run_name = args.run_name or datetime.now(timezone.utc).strftime("stephanov_n6_nofb_runtime_layouts_%Y%m%dT%H%M%SZ")
    run_dir = output_root / run_name
    if run_dir.exists():
        if not args.force:
            raise RuntimeError("run directory exists; use --force: {0}".format(run_dir))
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    records = parse_records(args.records)
    layouts = parse_layouts(args.layouts)
    build_stage2(repo_root, args.skip_build)
    rows = []
    for layout_name, jobs, threads in layouts:
        rows.append(run_layout(repo_root, args, run_dir, layout_name, jobs, threads, records))
        write_csv(run_dir / "benchmark_summary.csv", rows)
        write_readme(run_dir / "README.md", rows, args)
    print(run_dir / "benchmark_summary.csv")
    print(run_dir / "README.md")


if __name__ == "__main__":
    main()
