#!/usr/bin/env python3
"""Benchmark Stage2 swap reflow cache modes on a fixed Stephanov n=6 ladder."""

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


DEFAULT_LADDER = "0,0.001,0.003,0.007,0.010,0.013,0.016,0.018,0.020,0.0225,0.025,0.0275,0.030"
DEFAULT_BANK = "output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/bank/x_bank.dat"
CASE_DEFS = (
    ("direct", "direct", "none"),
    ("continue_none", "continue_cache", "none"),
    ("continue_lower", "continue_cache", "lower_neighbor"),
)
KV_RE = re.compile(r"([A-Za-z0-9_]+)=\s*([^\s]+)")


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(
        description="Run a controlled direct/continue-cache swap reflow benchmark."
    )
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument("--bank-file", default=DEFAULT_BANK)
    parser.add_argument("--output-root", default="output/tests")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--ladder", default=DEFAULT_LADDER)
    parser.add_argument("--records", default="0,40")
    parser.add_argument("--cycles", type=int, default=20)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--timeout-sec", type=int, default=2400)
    parser.add_argument("--init-mode", choices=("flow_bank", "adaptive"), default="flow_bank")
    parser.add_argument("--preflow-L", type=float, default=0.16)
    parser.add_argument("--preflow-nstep", type=int, default=2)
    parser.add_argument("--hmc-epsilon", type=float, default=0.04)
    parser.add_argument("--hmc-nstep", type=int, default=4)
    parser.add_argument("--seed-base", type=int, default=8950000)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--force-flow-bank",
        action="store_true",
        help="Rebuild the flow-bank even if the target directory exists.",
    )
    parser.add_argument(
        "--cases",
        default=",".join(case[0] for case in CASE_DEFS),
        help="Comma-separated case names: direct,continue_none,continue_lower.",
    )
    return parser.parse_args()


def parse_int_list(text):
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def parse_float_list(text):
    return [float(item.strip()) for item in text.split(",") if item.strip()]


def resolve_repo_path(repo_root, value):
    path = Path(value)
    if path.is_absolute():
        return path
    return repo_root / path


def shell_join(args):
    return " ".join(str(arg) for arg in args)


def run_checked(cmd, cwd, env=None, log_path=None, timeout=None):
    start = time.monotonic()
    if log_path is None:
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
    else:
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
    wall = time.monotonic() - start
    if proc.returncode != 0:
        if log_path is not None:
            output = log_path.read_text(encoding="utf-8", errors="replace")
        raise RuntimeError(
            "Command failed with exit {0}: {1}\n{2}".format(proc.returncode, shell_join(cmd), output[-4000:])
        )
    return wall, output


def build_executables(repo_root, skip_build):
    if skip_build:
        return
    cmd = [
        "make",
        "-C",
        str(repo_root / "build"),
        "FC=gfortran",
        "LDFLAGS=",
        "../bin/build_flow_bank_dense",
        "../bin/run_tltm_stage2",
    ]
    run_checked(cmd, repo_root)


def arithmetic_progression(records):
    if not records:
        raise RuntimeError("--records must not be empty")
    if len(records) == 1:
        return records[0], 1, 1
    stride = records[1] - records[0]
    if stride <= 0:
        raise RuntimeError("--records must be strictly increasing")
    expected = [records[0] + stride * idx for idx in range(len(records))]
    if expected != records:
        raise RuntimeError("Flow-bank builder requires arithmetic-progression records; got {0}".format(records))
    return records[0], len(records), stride


def build_flow_bank(repo_root, params_file, bank_file, flow_bank_dir, ladder_text, records, force):
    start, count, stride = arithmetic_progression(records)
    manifest = flow_bank_dir / "manifest.txt"
    if flow_bank_dir.exists() and force:
        shutil.rmtree(flow_bank_dir)
    if manifest.exists() and not force:
        return 0.0, "reused"
    flow_bank_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(repo_root / "bin" / "build_flow_bank_dense"),
        str(bank_file),
        str(flow_bank_dir),
        ladder_text,
        str(start),
        str(count),
        str(stride),
    ]
    env = dop853_env(os.environ.copy())
    env["TLTM_PARAMETERS_FILE"] = str(params_file)
    wall, _output = run_checked(cmd, repo_root, env=env, log_path=flow_bank_dir / "build_flow_bank.log")
    return wall, "built"


def require_complete_flow_bank(flow_bank_dir, records, target_count):
    diagnostics = flow_bank_dir / "diagnostics.csv"
    if not diagnostics.exists():
        raise RuntimeError("Missing flow-bank diagnostics: {0}".format(diagnostics))
    available = {record: 0 for record in records}
    with diagnostics.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            record = int(row["source_record"])
            if record in available and int(row["available"]) == 1:
                available[record] += 1
    bad = {record: count for record, count in available.items() if count != target_count}
    if bad:
        details = "; ".join("{0}:{1}/{2}".format(record, count, target_count) for record, count in bad.items())
        raise RuntimeError("Incomplete flow-bank for requested records: {0}".format(details))


def dop853_env(base_env):
    env = base_env.copy()
    env.update(
        {
            "TLTM_ODE_BACKEND": "dop853",
            "TLTM_DOP853_HINIT_ENABLED": "1",
            "TLTM_DOP853_STIFFNESS_CHECK_ENABLED": "1",
            "TLTM_DOP853_STIFFNESS_CHECK_INTERVAL": "1000",
            "TLTM_DOP853_STIFFNESS_MAX_HITS": "15",
            "TLTM_DOP853_STIFFNESS_THRESHOLD": "6.1",
        }
    )
    return env


def parse_value(text):
    if text in {"T", "F"}:
        return text
    try:
        if any(ch in text for ch in (".", "E", "e")):
            return float(text)
        return int(text)
    except ValueError:
        return text


def parse_kv_line(line):
    return {key: parse_value(value) for key, value in KV_RE.findall(line)}


def parse_summary(path):
    metrics = {
        "elapsed_sec": 0.0,
        "local_update_sweep_sec": 0.0,
        "swap_sweep_sec": 0.0,
        "accounted_loop_sec": 0.0,
        "unaccounted_loop_sec": 0.0,
        "swap_reflow_sec": 0.0,
        "action_logdet_sec": 0.0,
        "action_logdet_compute_count": 0,
        "local_reflow_cache_seed_sec": 0.0,
        "local_reflow_cache_seed_attempts": 0,
        "local_reflow_cache_seed_targets": 0,
        "local_reflow_cache_seed_stores": 0,
        "local_reflow_cache_seed_failures": 0,
        "swap_reflow_cache_hits": 0,
        "swap_reflow_cache_misses": 0,
        "swap_reflow_cache_stores": 0,
        "swap_reflow_cache_flow_calls": 0,
        "swap_reflow_cache_flow_failures": 0,
        "effective_energy_cache_hits": 0,
        "effective_energy_cache_misses": 0,
        "total_round_trip": 0,
        "pair0_accept_rate": 0.0,
        "min_pair_accept_rate": 0.0,
        "pair_accept_rates": "",
        "accepted_local_total": 0,
        "metropolis_reject_total": 0,
        "reverse_gate_reject_total": 0,
        "proposal_failure_total": 0,
        "max_slot_runtime_sec": 0.0,
        "swap_reflow_backend": "",
        "local_reflow_cache_mode": "",
    }
    if not path.exists():
        return metrics

    section = ""
    pair_rates = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("# elapsed_sec="):
            metrics["elapsed_sec"] = float(line.split("=", 1)[1].strip())
        elif line.startswith("# production_cache_controls"):
            values = parse_kv_line(line)
            metrics["swap_reflow_backend"] = str(values.get("swap_reflow_backend", ""))
            metrics["local_reflow_cache_mode"] = str(values.get("local_reflow_cache_mode", ""))
        elif line.startswith("# production_timing"):
            values = parse_kv_line(line)
            for key in (
                "local_update_sweep_sec",
                "swap_sweep_sec",
                "accounted_loop_sec",
                "unaccounted_loop_sec",
            ):
                metrics[key] = float(values.get(key, metrics[key]))
        elif line.startswith("# production_subtiming"):
            values = parse_kv_line(line)
            metrics["swap_reflow_sec"] = float(values.get("swap_reflow_sec", 0.0))
            metrics["action_logdet_sec"] = float(values.get("action_logdet_sec", 0.0))
            metrics["action_logdet_compute_count"] = int(values.get("action_logdet_compute_count", 0))
        elif line.startswith("# local_reflow_cache_seed"):
            values = parse_kv_line(line)
            metrics["local_reflow_cache_seed_sec"] = float(values.get("sec", 0.0))
            metrics["local_reflow_cache_seed_attempts"] = int(values.get("attempts", 0))
            metrics["local_reflow_cache_seed_targets"] = int(values.get("targets", 0))
            metrics["local_reflow_cache_seed_stores"] = int(values.get("stores", 0))
            metrics["local_reflow_cache_seed_failures"] = int(values.get("failures", 0))
        elif line.startswith("# swap_reflow_cache"):
            values = parse_kv_line(line)
            metrics["swap_reflow_cache_hits"] = int(values.get("hits", 0))
            metrics["swap_reflow_cache_misses"] = int(values.get("misses", 0))
            metrics["swap_reflow_cache_stores"] = int(values.get("stores", 0))
            metrics["swap_reflow_cache_flow_calls"] = int(values.get("flow_calls", 0))
            metrics["swap_reflow_cache_flow_failures"] = int(values.get("flow_failures", 0))
        elif line.startswith("# effective_energy_cache"):
            values = parse_kv_line(line)
            metrics["effective_energy_cache_hits"] = int(values.get("hits", 0))
            metrics["effective_energy_cache_misses"] = int(values.get("misses", 0))
        elif line.startswith("# total_round_trip="):
            metrics["total_round_trip"] = int(line.split("=", 1)[1].strip())
        elif line.startswith("# [slots]"):
            section = "slots"
            continue
        elif line.startswith("# [pairs]"):
            section = "pairs"
            continue
        elif line.startswith("# ["):
            section = ""
            continue

        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if section == "slots" and len(parts) >= 16:
            metrics["accepted_local_total"] += int(parts[3])
            metrics["metropolis_reject_total"] += int(parts[10])
            metrics["reverse_gate_reject_total"] += int(parts[11])
            metrics["proposal_failure_total"] += int(parts[12])
            metrics["max_slot_runtime_sec"] = max(metrics["max_slot_runtime_sec"], float(parts[9]))
        elif section == "pairs" and len(parts) >= 7:
            pair_id = int(parts[0])
            rate = float(parts[6])
            pair_rates.append((pair_id, rate))
            if pair_id == 0:
                metrics["pair0_accept_rate"] = rate

    if pair_rates:
        min_pair_id, min_pair_rate = min(pair_rates, key=lambda item: item[1])
        metrics["min_pair_accept_rate"] = min_pair_rate
        metrics["min_pair_id"] = min_pair_id
        metrics["pair_accept_rates"] = ";".join(
            "{0}:{1:.6g}".format(pair_id, rate) for pair_id, rate in pair_rates
        )
    metrics["combined_reflow_cache_sec"] = (
        metrics["swap_reflow_sec"] + metrics["local_reflow_cache_seed_sec"]
    )
    return metrics


def write_csv(path, rows, fieldnames=None):
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def run_case(repo_root, args, run_root, flow_bank_dir, case_name, backend, local_mode):
    case_dir = run_root / "cases" / case_name
    if case_dir.exists():
        shutil.rmtree(case_dir)
    env = dop853_env(os.environ.copy())
    env.update(
        {
            "TLTM_STAGE2_SWAP_REFLOW_BACKEND": backend,
            "TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE": local_mode,
        }
    )
    cmd = [
        sys.executable,
        str(repo_root / "codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py"),
        "--repo-root",
        str(repo_root),
        "--base-parameters",
        args.base_parameters,
        "--bank-file",
        args.bank_file,
        "--output-root",
        str(run_root / "cases"),
        "--run-name",
        case_name,
        "--ladder",
        args.ladder,
        "--records",
        args.records,
        "--cycles",
        str(args.cycles),
        "--timeout-sec",
        str(args.timeout_sec),
        "--seed-base",
        str(args.seed_base),
        "--hmc-epsilon",
        str(args.hmc_epsilon),
        "--hmc-nstep",
        str(args.hmc_nstep),
        "--jobs",
        str(args.jobs),
        "--threads",
        str(args.threads),
        "--parallel-local-updates",
        "1",
        "--parallel-swaps",
        "1",
        "--skip-build",
        "--force",
    ]
    if args.init_mode == "flow_bank":
        cmd.extend(["--init-flow-bank-root", str(flow_bank_dir)])
    else:
        cmd.extend(
            [
                "--preflow-L",
                str(args.preflow_L),
                "--preflow-nstep",
                str(args.preflow_nstep),
            ]
        )
    start = time.monotonic()
    proc = subprocess.run(
        cmd,
        cwd=str(repo_root),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        timeout=max(args.timeout_sec * max(1, len(parse_int_list(args.records))) + 120, args.timeout_sec + 120),
        check=False,
    )
    case_wall = time.monotonic() - start
    case_dir.mkdir(parents=True, exist_ok=True)
    (case_dir / "benchmark_driver.log").write_text(proc.stdout, encoding="utf-8")
    if proc.returncode != 0:
        raise RuntimeError(
            "Case {0} failed with exit {1}\n{2}".format(case_name, proc.returncode, proc.stdout[-4000:])
        )
    runner_summary = case_dir / "tltm_ladder_summary.csv"
    if runner_summary.exists():
        with runner_summary.open(newline="", encoding="utf-8") as handle:
            bad = [row for row in csv.DictReader(handle) if row.get("status") != "done"]
        if bad:
            statuses = ",".join("{0}:{1}".format(row.get("record"), row.get("status")) for row in bad)
            raise RuntimeError("Case {0} has failed runner records: {1}".format(case_name, statuses))

    record_rows = []
    for record in parse_int_list(args.records):
        summary_file = case_dir / "records" / "record_{0:04d}".format(record) / "summary.dat"
        row = {
            "case": case_name,
            "backend": backend,
            "local_reflow_cache_mode_requested": local_mode,
            "record": record,
            "summary_file": str(summary_file),
        }
        row.update(parse_summary(summary_file))
        record_rows.append(row)
    return case_wall, record_rows


def load_runner_aggregate(case_dir):
    path = case_dir / "tltm_ladder_aggregate.csv"
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    return rows[0] if rows else {}


def aggregate_case(case_name, backend, local_mode, case_wall, record_rows, case_dir, cycles):
    runner = load_runner_aggregate(case_dir)
    total = lambda key: sum(float(row.get(key, 0.0)) for row in record_rows)
    total_int = lambda key: sum(int(row.get(key, 0)) for row in record_rows)
    n_rows = max(1, len(record_rows))
    return {
        "case": case_name,
        "backend": backend,
        "local_reflow_cache_mode": local_mode,
        "records": ";".join(str(row["record"]) for row in record_rows),
        "cycles": cycles,
        "case_wall_sec": case_wall,
        "runner_wall_sec": float(runner.get("wall_sec", case_wall) or case_wall),
        "max_record_wall_sec": float(runner.get("max_record_wall_sec", 0.0) or 0.0),
        "total_elapsed_sec": total("elapsed_sec"),
        "total_local_update_sweep_sec": total("local_update_sweep_sec"),
        "total_swap_sweep_sec": total("swap_sweep_sec"),
        "total_swap_reflow_sec": total("swap_reflow_sec"),
        "total_local_reflow_cache_seed_sec": total("local_reflow_cache_seed_sec"),
        "total_combined_reflow_cache_sec": total("combined_reflow_cache_sec"),
        "total_action_logdet_sec": total("action_logdet_sec"),
        "swap_reflow_cache_hits": total_int("swap_reflow_cache_hits"),
        "swap_reflow_cache_misses": total_int("swap_reflow_cache_misses"),
        "swap_reflow_cache_stores": total_int("swap_reflow_cache_stores"),
        "swap_reflow_cache_flow_calls": total_int("swap_reflow_cache_flow_calls"),
        "swap_reflow_cache_flow_failures": total_int("swap_reflow_cache_flow_failures"),
        "local_reflow_cache_seed_attempts": total_int("local_reflow_cache_seed_attempts"),
        "local_reflow_cache_seed_targets": total_int("local_reflow_cache_seed_targets"),
        "local_reflow_cache_seed_stores": total_int("local_reflow_cache_seed_stores"),
        "local_reflow_cache_seed_failures": total_int("local_reflow_cache_seed_failures"),
        "mean_pair0_accept_rate": sum(float(row["pair0_accept_rate"]) for row in record_rows) / n_rows,
        "mean_min_pair_accept_rate": sum(float(row["min_pair_accept_rate"]) for row in record_rows) / n_rows,
        "total_round_trip": total_int("total_round_trip"),
        "accepted_local_total": total_int("accepted_local_total"),
        "proposal_failure_total": total_int("proposal_failure_total"),
        "reverse_gate_reject_total": total_int("reverse_gate_reject_total"),
        "metropolis_reject_total": total_int("metropolis_reject_total"),
    }


def fmt_float(value):
    return "{0:.6g}".format(float(value))


def write_conclusion(path, args, run_root, flow_bank_dir, flow_bank_status, flow_bank_wall, case_rows):
    direct = next((row for row in case_rows if row["case"] == "direct"), None)
    cont_none = next((row for row in case_rows if row["case"] == "continue_none"), None)
    cont_lower = next((row for row in case_rows if row["case"] == "continue_lower"), None)
    protocol_lines = [
        "# Swap Reflow Cache Mode Benchmark",
        "",
        "Status: complete for this controlled engineering gate.",
        "",
        "## Protocol",
        "",
        "- Model: Stephanov n=6.",
        "- Parameter file: `{0}`.".format(args.base_parameters),
        "- Ladder: `{0}`.".format(args.ladder),
        "- Bank file: `{0}`.".format(args.bank_file),
        "- Bank records: `{0}`.".format(args.records),
        "- Cycles per record: `{0}`.".format(args.cycles),
        "- Local HMC: epsilon `{0:g}`, nstep `{1}`.".format(args.hmc_epsilon, args.hmc_nstep),
        "- Initialization mode: `{0}`.".format(args.init_mode),
    ]
    if args.init_mode == "flow_bank":
        protocol_lines += [
            "- Initialization: shared dense flow-bank `{0}`.".format(flow_bank_dir),
            "- Flow-bank status: `{0}`, build wall `{1}` sec.".format(flow_bank_status, fmt_float(flow_bank_wall)),
        ]
    else:
        protocol_lines.append("- Adaptive preflow: L `{0:g}`, nstep `{1}`.".format(args.preflow_L, args.preflow_nstep))
    protocol_lines += [
        "- Output root: `{0}`.".format(run_root),
        "",
        "## Aggregate Results",
        "",
        "| case | wall sec | swap reflow sec | local seed sec | combined reflow/cache sec | cache hits | cache misses | flow calls | flow failures | mean pair0 acc | mean min pair acc | round trips |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    lines = protocol_lines
    for row in case_rows:
        lines.append(
            "| {case} | {wall} | {swap} | {seed} | {combined} | {hits} | {misses} | {flows} | {failures} | {pair0} | {minpair} | {rt} |".format(
                case=row["case"],
                wall=fmt_float(row["case_wall_sec"]),
                swap=fmt_float(row["total_swap_reflow_sec"]),
                seed=fmt_float(row["total_local_reflow_cache_seed_sec"]),
                combined=fmt_float(row["total_combined_reflow_cache_sec"]),
                hits=row["swap_reflow_cache_hits"],
                misses=row["swap_reflow_cache_misses"],
                flows=row["swap_reflow_cache_flow_calls"],
                failures=row["swap_reflow_cache_flow_failures"],
                pair0=fmt_float(row["mean_pair0_accept_rate"]),
                minpair=fmt_float(row["mean_min_pair_accept_rate"]),
                rt=row["total_round_trip"],
            )
        )
    lines += ["", "## Decision", ""]

    if direct is None:
        lines.append("- `direct` did not run, so no replacement decision is possible.")
    else:
        winner = direct
        candidates = [row for row in (cont_none, cont_lower) if row is not None]
        faster_candidates = [
            row
            for row in candidates
            if float(row["total_combined_reflow_cache_sec"]) < float(direct["total_swap_reflow_sec"])
            and float(row["case_wall_sec"]) <= float(direct["case_wall_sec"])
            and int(row["swap_reflow_cache_flow_failures"]) == int(direct["swap_reflow_cache_flow_failures"])
        ]
        if faster_candidates:
            winner = min(faster_candidates, key=lambda row: float(row["case_wall_sec"]))
            lines.append(
                "- `{0}` is eligible to replace `direct` for this ladder-size gate: it reduced the measured reflow/cache subtotal and did not increase wall time or flow failures.".format(
                    winner["case"]
                )
            )
        else:
            lines.append(
                "- Keep `direct` as the production default. In this gate, the continuation/cache variants did not simultaneously reduce the measured reflow/cache subtotal and total wall time without extra failure pressure."
            )

    if cont_none is not None:
        lines.append(
            "- `continue_cache+none` is still useful as a diagnostic backend: it tests endpoint continuation equivalence without paying local lower-neighbor seeding cost."
        )
    if cont_lower is not None:
        lines.append(
            "- `continue_cache+lower_neighbor` should remain opt-in unless a longer production-like gate shows a clear walltime win. It buys cache hits by adding dense-target work after accepted local HMC moves."
        )
    lines.append(
        "- Dense multi-target flow-bank construction remains the right default for initialization/cache building when the selected bank records are reachable to the full ladder. It is a separate gate from production swap-reflow replacement."
    )
    lines += [
        "",
        "Artifacts:",
        "",
        "- `case_summary.csv` contains per-case aggregate counters.",
        "- `record_metrics.csv` contains per-record parsed Stage2 summary counters.",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    params_file = resolve_repo_path(repo_root, args.base_parameters).resolve()
    bank_file = resolve_repo_path(repo_root, args.bank_file).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root).resolve()
    run_name = args.run_name or datetime.now(tz=timezone.utc).strftime(
        "swap_reflow_cache_modes_%Y%m%dT%H%M%SZ"
    )
    run_root = output_root / run_name
    if run_root.exists():
        if not args.force:
            raise RuntimeError("Run root exists; use --force: {0}".format(run_root))
        shutil.rmtree(run_root)
    run_root.mkdir(parents=True, exist_ok=True)

    records = parse_int_list(args.records)
    ladder = parse_float_list(args.ladder)
    if len(ladder) < 2:
        raise RuntimeError("Need at least two ladder entries.")
    if not bank_file.exists():
        raise RuntimeError("Bank file does not exist: {0}".format(bank_file))
    if not params_file.exists():
        raise RuntimeError("Parameter file does not exist: {0}".format(params_file))

    selected_cases = [item.strip() for item in args.cases.split(",") if item.strip()]
    case_map = {name: (name, backend, mode) for name, backend, mode in CASE_DEFS}
    unknown = [name for name in selected_cases if name not in case_map]
    if unknown:
        raise RuntimeError("Unknown cases: {0}".format(",".join(unknown)))

    build_executables(repo_root, args.skip_build)

    flow_bank_dir = run_root / "flow_bank_ladder{0}_records_{1}".format(
        len(ladder), "_".join(str(record) for record in records)
    )
    flow_bank_wall = 0.0
    flow_bank_status = "not_used"
    if args.init_mode == "flow_bank":
        flow_bank_wall, flow_bank_status = build_flow_bank(
            repo_root, params_file, bank_file, flow_bank_dir, args.ladder, records, args.force_flow_bank
        )
        require_complete_flow_bank(flow_bank_dir, records, len(ladder))

    record_rows = []
    case_rows = []
    for case_name in selected_cases:
        name, backend, local_mode = case_map[case_name]
        case_wall, rows = run_case(repo_root, args, run_root, flow_bank_dir, name, backend, local_mode)
        record_rows.extend(rows)
        case_rows.append(aggregate_case(name, backend, local_mode, case_wall, rows, run_root / "cases" / name, args.cycles))
        print(
            "[BENCH] {0}: wall={1:.2f}s combined_reflow_cache={2:.2f}s hits={3} misses={4} flow_calls={5}".format(
                name,
                case_rows[-1]["case_wall_sec"],
                case_rows[-1]["total_combined_reflow_cache_sec"],
                case_rows[-1]["swap_reflow_cache_hits"],
                case_rows[-1]["swap_reflow_cache_misses"],
                case_rows[-1]["swap_reflow_cache_flow_calls"],
            ),
            flush=True,
        )

    case_fieldnames = list(case_rows[0].keys()) if case_rows else []
    record_fieldnames = list(record_rows[0].keys()) if record_rows else []
    write_csv(run_root / "case_summary.csv", case_rows, case_fieldnames)
    write_csv(run_root / "record_metrics.csv", record_rows, record_fieldnames)
    write_conclusion(
        run_root / "CONCLUSION.md",
        args,
        run_root,
        flow_bank_dir,
        flow_bank_status,
        flow_bank_wall,
        case_rows,
    )
    print(run_root / "case_summary.csv")
    print(run_root / "record_metrics.csv")
    print(run_root / "CONCLUSION.md")


if __name__ == "__main__":
    main()
