#!/usr/bin/env python3
"""Run a local Stephanov n=6 TLTM ladder from the t=0 checkpoint bank."""

import argparse
import concurrent.futures
import csv
import os
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Run a Stephanov n=6 TLTM ladder from bank records.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument(
        "--bank-file",
        default="output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/bank/x_bank.dat",
    )
    parser.add_argument("--output-root", default="output/stephanov_tltm_ladders")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--ladder", default="0,3e-5,1e-4,3e-4,1e-3,3e-3,1e-2,2e-2,3e-2")
    parser.add_argument("--records", default="0,81,162,243")
    parser.add_argument("--cycles", type=int, default=250)
    parser.add_argument("--timeout-sec", type=int, default=3600)
    parser.add_argument("--seed-base", type=int, default=8930000)
    parser.add_argument("--preflow-L", type=float, default=0.16)
    parser.add_argument("--preflow-nstep", type=int, default=2)
    parser.add_argument("--hmc-epsilon", type=float, default=0.04)
    parser.add_argument("--hmc-nstep", type=int, default=4)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--parallel-local-updates", choices=("0", "1"), default="1")
    parser.add_argument("--parallel-swaps", choices=("0", "1"), default="1")
    parser.add_argument("--max-preflow-stages", type=int, default=512)
    parser.add_argument("--max-preflow-shrinks", type=int, default=4096)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def parse_int_list(text):
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def parse_float_list(text):
    return [float(item.strip()) for item in text.split(",") if item.strip()]


def set_param(lines, key, value):
    out = []
    found = False
    key_l = key.lower()
    for line in lines:
        stripped = line.strip().lower()
        if stripped.startswith(key_l + " ") or stripped.startswith(key_l + "="):
            out.append("{0} = {1}".format(key, value))
            found = True
        else:
            out.append(line)
    if not found:
        out.append("{0} = {1}".format(key, value))
    return out


def write_parameters(base_text, out_path, ladder, args):
    lines = base_text.splitlines()
    hmc_l = args.hmc_epsilon * args.hmc_nstep
    lines = set_param(lines, "trajectory_length", "{0:g}".format(hmc_l))
    lines = set_param(lines, "integration_steps", str(args.hmc_nstep))
    lines = set_param(lines, "initial_flow_time", "{0:g}".format(max(ladder)))
    lines = set_param(lines, "enable_quasi_fallback", "false")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return hmc_l


def run_build(repo_root, skip_build):
    if skip_build:
        return
    proc = subprocess.run(
        ["make", "-C", str(repo_root / "build"), "../bin/run_tltm_stage2"],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        print(proc.stdout)
        raise RuntimeError("Stage2 build failed")


def parse_summary(path):
    metrics = {
        "elapsed_sec": 0.0,
        "pair0_accept_rate": 0.0,
        "min_pair_accept_rate": 0.0,
        "min_pair_id": -1,
        "pair_accept_rates": "",
        "total_round_trip": 0,
        "max_slot_runtime_sec": 0.0,
        "accepted_local_total": 0,
        "proposal_failure_total": 0,
        "reverse_gate_reject_total": 0,
        "metropolis_reject_total": 0,
    }
    if not path.exists():
        return metrics
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    section = ""
    pair_rates = []
    for line in lines:
        if line.startswith("# elapsed_sec="):
            metrics["elapsed_sec"] = float(line.split("=", 1)[1].strip())
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
        metrics["min_pair_id"] = min_pair_id
        metrics["min_pair_accept_rate"] = min_pair_rate
        metrics["pair_accept_rates"] = ";".join(
            "{0}:{1:.6g}".format(pair_id, rate) for pair_id, rate in pair_rates
        )
    return metrics


def mean_pair_accept_rates(rows):
    sums = {}
    counts = {}
    for row in rows:
        for item in str(row.get("pair_accept_rates", "")).split(";"):
            if not item:
                continue
            pair_text, rate_text = item.split(":", 1)
            pair_id = int(pair_text)
            sums[pair_id] = sums.get(pair_id, 0.0) + float(rate_text)
            counts[pair_id] = counts.get(pair_id, 0) + 1
    return ";".join(
        "{0}:{1:.6g}".format(pair_id, sums[pair_id] / float(counts[pair_id]))
        for pair_id in sorted(sums)
    )


def run_record(repo_root, run_dir, params_file, bank_file, ladder, record_idx, chain_idx, args, hmc_l):
    chain_dir = run_dir / "records" / "record_{0:04d}".format(record_idx)
    chain_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    thread_text = str(max(1, args.threads))
    env.update(
        {
            "OMP_NUM_THREADS": thread_text,
            "OPENBLAS_NUM_THREADS": thread_text,
            "MKL_NUM_THREADS": thread_text,
            "VECLIB_MAXIMUM_THREADS": thread_text,
            "TLTM_PARAMETERS_FILE": str(params_file),
            "CHAIN_RNG_SEED": str(args.seed_base + record_idx + 10000 * chain_idx),
            "QN_REVERSE_GATE_ENABLED": "1",
            "TLTM_STAGE2_PARALLEL_LOCAL_UPDATES": args.parallel_local_updates,
            "TLTM_STAGE2_PARALLEL_SWAPS": args.parallel_swaps,
            "TLTM_STAGE2_INITIAL_X_FILE": str(bank_file),
            "TLTM_STAGE2_INITIAL_X_RECORD": str(record_idx),
            "TLTM_STAGE2_INIT_MODE": "adaptive",
            "TLTM_STAGE2_INIT_PREFLOW_TRAJECTORY_LENGTH": "{0:g}".format(args.preflow_L),
            "TLTM_STAGE2_INIT_PREFLOW_INTEGRATION_STEPS": str(args.preflow_nstep),
            "TLTM_STAGE2_INIT_PREFLOW_MAX_STAGES": str(args.max_preflow_stages),
            "TLTM_STAGE2_INIT_PREFLOW_MAX_SHRINKS": str(args.max_preflow_shrinks),
            "TLTM_STAGE2_FLOW_TIME_LADDER": ",".join("{0:g}".format(value) for value in ladder),
            "TLTM_STAGE2_MAX_FLOW_TIME": "{0:g}".format(max(ladder)),
            "TLTM_STAGE2_NUM_REPLICAS": str(len(ladder)),
            "TLTM_STAGE2_CYCLES": str(args.cycles),
            "TLTM_STAGE2_LOCAL_UPDATES": "1",
            "TLTM_STAGE2_SWAP_ENABLED": "1",
            "TLTM_STAGE2_SUMMARY_FILE": str(chain_dir / "summary.dat"),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(chain_dir / "label_trace.dat"),
            "TLTM_STAGE2_PHASE_CACHE_STATS_FILE": str(chain_dir / "phase_cache_stats.csv"),
            "TLTM_STAGE2_REAL_JAC_CACHE_STATS_FILE": str(chain_dir / "real_jacobian_cache_stats.csv"),
            "TLTM_STAGE2_V1_OUTPUT_DIR": str(chain_dir / "v1"),
            "TLTM_STAGE2_RNG_STREAM_CONTRACT": "stage2_kernel_rng_v2",
            "CONSTRAINT_FAIL_CAPTURE_START_SAMPLE": "2147483647",
        }
    )
    start = time.monotonic()
    status = "done"
    log_file = chain_dir / "run.log"
    with log_file.open("w", encoding="utf-8", errors="replace") as log_handle:
        proc = subprocess.Popen(
            [str(repo_root / "bin" / "run_tltm_stage2")],
            cwd=str(repo_root),
            env=env,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        try:
            proc.wait(timeout=args.timeout_sec)
        except subprocess.TimeoutExpired:
            status = "timeout"
            proc.kill()
            proc.wait()
        if status != "timeout" and proc.returncode != 0:
            status = "failed"
    wall = time.monotonic() - start
    metrics = parse_summary(chain_dir / "summary.dat")
    return {
        "record": record_idx,
        "chain_idx": chain_idx,
        "status": status,
        "wall_sec": wall,
        "cycles": args.cycles,
        "ladder": ",".join("{0:g}".format(value) for value in ladder),
        "threads": args.threads,
        "hmc_epsilon": args.hmc_epsilon,
        "hmc_nstep": args.hmc_nstep,
        "hmc_L": hmc_l,
        "preflow_L": args.preflow_L,
        "preflow_nstep": args.preflow_nstep,
        **metrics,
        "summary_file": str(chain_dir / "summary.dat"),
        "log_file": str(log_file),
    }


def write_csv(path, rows):
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main():
    args = parse_args()
    if args.jobs < 1:
        raise RuntimeError("--jobs must be >= 1")
    repo_root = Path(args.repo_root).resolve()
    params_file = (repo_root / args.base_parameters).resolve()
    bank_file = (repo_root / args.bank_file).resolve()
    output_root = Path(args.output_root)
    if not output_root.is_absolute():
        output_root = repo_root / output_root
    run_name = args.run_name or datetime.now(tz=timezone.utc).strftime("stephanov_n6_tltm_ladder_%Y%m%dT%H%M%SZ")
    run_dir = output_root / run_name
    if run_dir.exists():
        if not args.force:
            raise RuntimeError("Run directory exists; use --force: {0}".format(run_dir))
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    records = parse_int_list(args.records)
    ladder = parse_float_list(args.ladder)
    if len(ladder) < 2:
        raise RuntimeError("TLTM ladder needs at least two replicas.")
    run_build(repo_root, args.skip_build)
    params_out = run_dir / "parameters.dat"
    hmc_l = write_parameters(params_file.read_text(encoding="utf-8"), params_out, ladder, args)
    rows = []
    tasks = [(chain_idx, record_idx) for chain_idx, record_idx in enumerate(records)]
    start = time.monotonic()
    if args.jobs == 1 or len(tasks) <= 1:
        for chain_idx, record_idx in tasks:
            row = run_record(repo_root, run_dir, params_out, bank_file, ladder, record_idx, chain_idx, args, hmc_l)
            rows.append(row)
            print("[TLTM] record={0} status={1} wall={2:.1f}s pair0={3:.3f} min_pair={4:.3f} rt={5}".format(
                record_idx, row["status"], row["wall_sec"], row["pair0_accept_rate"],
                row["min_pair_accept_rate"], row["total_round_trip"],
            ), flush=True)
    else:
        with concurrent.futures.ProcessPoolExecutor(max_workers=min(args.jobs, len(tasks))) as pool:
            future_to_record = {
                pool.submit(run_record, repo_root, run_dir, params_out, bank_file, ladder, record_idx, chain_idx, args, hmc_l): record_idx
                for chain_idx, record_idx in tasks
            }
            by_record = {}
            for future in concurrent.futures.as_completed(future_to_record):
                row = future.result()
                by_record[row["record"]] = row
                print("[TLTM] record={0} status={1} wall={2:.1f}s pair0={3:.3f} min_pair={4:.3f} rt={5}".format(
                    row["record"], row["status"], row["wall_sec"], row["pair0_accept_rate"],
                    row["min_pair_accept_rate"], row["total_round_trip"],
                ), flush=True)
            rows = [by_record[record_idx] for _chain_idx, record_idx in tasks]
    total_wall = time.monotonic() - start
    write_csv(run_dir / "tltm_ladder_summary.csv", rows)
    aggregate = {
        "records": ";".join(str(record) for record in records),
        "statuses": ";".join(row["status"] for row in rows),
        "wall_sec": total_wall,
        "max_record_wall_sec": max((row["wall_sec"] for row in rows), default=0.0),
        "mean_pair0_accept_rate": sum(row["pair0_accept_rate"] for row in rows) / float(len(rows)) if rows else 0.0,
        "mean_min_pair_accept_rate": sum(row["min_pair_accept_rate"] for row in rows) / float(len(rows)) if rows else 0.0,
        "mean_pair_accept_rates": mean_pair_accept_rates(rows),
        "total_round_trip": sum(row["total_round_trip"] for row in rows),
        "total_proposal_failure": sum(row["proposal_failure_total"] for row in rows),
        "total_reverse_gate_reject": sum(row["reverse_gate_reject_total"] for row in rows),
    }
    write_csv(run_dir / "tltm_ladder_aggregate.csv", [aggregate])
    print(run_dir / "tltm_ladder_summary.csv")
    print(run_dir / "tltm_ladder_aggregate.csv")


if __name__ == "__main__":
    main()
