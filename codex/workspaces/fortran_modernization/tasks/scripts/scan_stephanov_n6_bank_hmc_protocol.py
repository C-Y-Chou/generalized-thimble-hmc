#!/usr/bin/env python3
"""Scan Stephanov n=6 HMC protocol from fixed t=0 checkpoint-bank records."""

import argparse
import concurrent.futures
import csv
import os
import shutil
import subprocess
import time
from array import array
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Run bank-started Stephanov n=6 HMC protocol scans.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps008_nstep2.dat")
    parser.add_argument(
        "--bank-file",
        default="output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/bank/x_bank.dat",
    )
    parser.add_argument("--output-root", default="output/stephanov_hmc_protocol_scans")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--records", default="0,81")
    parser.add_argument("--stage", choices=("epsilon", "nstep"), required=True)
    parser.add_argument("--flow-time", type=float, default=0.000001)
    parser.add_argument("--epsilon-values", default="0.04,0.05,0.065,0.08,0.10,0.12")
    parser.add_argument("--nstep-values", default="2,3,4,5,6,8,9")
    parser.add_argument("--fixed-nstep", type=int, default=5)
    parser.add_argument("--fixed-epsilon", type=float, default=0.08)
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--timeout-sec", type=int, default=240)
    parser.add_argument("--seed-base", type=int, default=8800000)
    parser.add_argument("--init-mode", choices=("adaptive", "direct"), default="adaptive")
    parser.add_argument("--preflow-L", type=float, default=0.16)
    parser.add_argument("--preflow-nstep", type=int, default=2)
    parser.add_argument("--jobs", type=int, default=1, help="Run independent records concurrently per candidate.")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def parse_int_list(text):
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def parse_float_list(text):
    return [float(item.strip()) for item in text.split(",") if item.strip()]


def label_float(value):
    return str(value).replace(".", "p").replace("-", "m")


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


def write_parameters(base_text, out_path, trajectory_length, nstep, flow_time):
    lines = base_text.splitlines()
    lines = set_param(lines, "trajectory_length", "{0:g}".format(trajectory_length))
    lines = set_param(lines, "integration_steps", str(nstep))
    lines = set_param(lines, "initial_flow_time", "{0:g}".format(flow_time))
    lines = set_param(lines, "enable_quasi_fallback", "false")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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


def read_x_records(path):
    values = array("d")
    size = Path(path).stat().st_size
    with Path(path).open("rb") as handle:
        values.fromfile(handle, size // 8)
    if len(values) % 72 != 0:
        raise RuntimeError("x history width mismatch: {0}".format(path))
    records = []
    for start in range(0, len(values), 72):
        records.append(values[start:start + 72])
    return records


def parse_summary(path):
    out = {
        "accepts": 0,
        "rejects": 0,
        "accept_rate": 0.0,
        "samples": 0,
        "runtime_sec": 0.0,
        "metropolis_reject": 0,
        "proposal_failure": 0,
        "hamiltonian_invalid": 0,
        "delta_h_invalid": 0,
    }
    lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
    next_slot_line = False
    for line in lines:
        if line.startswith("# local_transition_totals"):
            parts = line.replace("=", " ").split()
            for idx, token in enumerate(parts):
                if token in out and idx + 1 < len(parts):
                    out[token] = int(parts[idx + 1])
        if line.startswith("# [slots]"):
            next_slot_line = True
            continue
        if next_slot_line:
            next_slot_line = False
            parts = line.split()
            if len(parts) >= 15:
                out.update(
                    {
                        "accepts": int(parts[3]),
                        "rejects": int(parts[4]),
                        "accept_rate": float(parts[5]),
                        "samples": int(parts[7]),
                        "runtime_sec": float(parts[9]),
                        "metropolis_reject": int(parts[10]),
                        "proposal_failure": int(parts[12]),
                        "hamiltonian_invalid": int(parts[13]),
                        "delta_h_invalid": int(parts[14]),
                    }
                )
    return out


def movement_metrics(x_path):
    records = read_x_records(x_path)
    if len(records) < 2:
        return {"mean_step_norm2": 0.0, "nonzero_step_rate": 0.0, "move_norm2_sum": 0.0}
    moves = []
    nonzero = 0
    for prev, curr in zip(records[:-1], records[1:]):
        norm2 = sum((float(b) - float(a)) ** 2 for a, b in zip(prev, curr))
        moves.append(norm2)
        if norm2 > 0.0:
            nonzero += 1
    return {
        "mean_step_norm2": sum(moves) / float(len(moves)),
        "nonzero_step_rate": nonzero / float(len(moves)),
        "move_norm2_sum": sum(moves),
    }


def run_record_case(repo_root, run_dir, params_file, bank_file, stage, tag, L, nstep, epsilon, record_idx, cycles, timeout_sec,
                    seed_base, init_mode, preflow_L, preflow_nstep, flow_time):
    case_dir = run_dir / stage / tag
    case_dir.mkdir(parents=True, exist_ok=True)
    chain_dir = case_dir / ("record_{0:04d}".format(record_idx))
    chain_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(
        {
            "TLTM_PARAMETERS_FILE": str(params_file),
            "CHAIN_RNG_SEED": str(seed_base + record_idx),
            "TLTM_STAGE2_INITIAL_X_FILE": str(bank_file),
            "TLTM_STAGE2_INITIAL_X_RECORD": str(record_idx),
            "TLTM_STAGE2_INIT_MODE": init_mode,
            "TLTM_STAGE2_INIT_PREFLOW_TRAJECTORY_LENGTH": "{0:g}".format(preflow_L),
            "TLTM_STAGE2_INIT_PREFLOW_INTEGRATION_STEPS": str(preflow_nstep),
            "TLTM_STAGE2_FLOW_TIME_LADDER": "{0:g}".format(flow_time),
            "TLTM_STAGE2_MAX_FLOW_TIME": "{0:g}".format(flow_time),
            "TLTM_STAGE2_NUM_REPLICAS": "1",
            "TLTM_STAGE2_CYCLES": str(cycles),
            "TLTM_STAGE2_LOCAL_UPDATES": "1",
            "TLTM_STAGE2_SWAP_ENABLED": "0",
            "TLTM_STAGE2_HISTORY_STRIDE": "1",
            "TLTM_STAGE2_COLD_X_HISTORY_STRIDE": "1",
            "TLTM_STAGE2_SUMMARY_FILE": str(chain_dir / "summary.dat"),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(chain_dir / "label_trace.dat"),
            "TLTM_STAGE2_COLD_X_HISTORY_FILE": str(chain_dir / "x_history.dat"),
            "TLTM_STAGE2_PHASE_CACHE_STATS_FILE": str(chain_dir / "phase_cache_stats.csv"),
            "TLTM_STAGE2_V1_OUTPUT_DIR": str(chain_dir / "v1"),
            "TLTM_STAGE2_RNG_STREAM_CONTRACT": "stage2_kernel_rng_v2",
            "CONSTRAINT_FAIL_CAPTURE_START_SAMPLE": "2147483647",
        }
    )
    start = time.monotonic()
    status = "done"
    try:
        proc = subprocess.run(
            [str(repo_root / "bin" / "run_tltm_stage2")],
            cwd=str(repo_root),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            timeout=timeout_sec,
            check=False,
        )
        output = proc.stdout
        if proc.returncode != 0:
            status = "failed"
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        status = "timeout"
    elapsed = time.monotonic() - start
    (chain_dir / "run.log").write_text(output, encoding="utf-8", errors="replace")
    summary = {}
    movement = {"mean_step_norm2": 0.0, "nonzero_step_rate": 0.0, "move_norm2_sum": 0.0}
    if status == "done" and (chain_dir / "summary.dat").exists():
        summary = parse_summary(chain_dir / "summary.dat")
        movement = movement_metrics(chain_dir / "x_history.dat")
    return {
        "stage": stage,
        "tag": tag,
        "record": record_idx,
        "L": L,
        "nstep": nstep,
        "epsilon": epsilon,
        "flow_time": flow_time,
        "init_mode": init_mode,
        "preflow_L": preflow_L,
        "preflow_nstep": preflow_nstep,
        "status": status,
        "elapsed_wall_sec": elapsed,
        **summary,
        **movement,
    }


def run_case_records(repo_root, run_dir, params_file, bank_file, stage, tag, L, nstep, epsilon, records, cycles, timeout_sec,
                     seed_base, init_mode, preflow_L, preflow_nstep, flow_time, jobs):
    jobs = max(1, int(jobs))
    if jobs == 1 or len(records) <= 1:
        return [
            run_record_case(
                repo_root, run_dir, params_file, bank_file, stage, tag, L, nstep, epsilon, record_idx,
                cycles, timeout_sec, seed_base, init_mode, preflow_L, preflow_nstep, flow_time,
            )
            for record_idx in records
        ]

    rows_by_record = {}
    with concurrent.futures.ProcessPoolExecutor(max_workers=min(jobs, len(records))) as pool:
        future_to_record = {
            pool.submit(
                run_record_case,
                repo_root, run_dir, params_file, bank_file, stage, tag, L, nstep, epsilon, record_idx,
                cycles, timeout_sec, seed_base, init_mode, preflow_L, preflow_nstep, flow_time,
            ): record_idx
            for record_idx in records
        }
        for future in concurrent.futures.as_completed(future_to_record):
            record_idx = future_to_record[future]
            rows_by_record[record_idx] = future.result()
    return [rows_by_record[record_idx] for record_idx in records]


def aggregate_rows(rows, case_wall_sec=None):
    fields = [
        "stage", "tag", "flow_time", "L", "nstep", "epsilon", "status", "records", "elapsed_wall_sec",
        "init_mode", "preflow_L", "preflow_nstep", "samples_by_record", "accepted", "metropolis_reject", "proposal_failure",
        "hamiltonian_invalid", "delta_h_invalid", "attempt_accept_rate", "valid_proposal_metropolis_accept_rate",
        "proposal_failure_rate", "accepted_per_wall_sec",
        "mean_step_norm2", "nonzero_step_rate", "move_norm2_per_wall_sec", "runtime_sum_sec",
    ]
    if not rows:
        return {}
    status = "done" if all(row["status"] == "done" for row in rows) else ",".join(sorted(set(row["status"] for row in rows)))
    record_wall_sum = sum(row["elapsed_wall_sec"] for row in rows)
    elapsed = case_wall_sec if case_wall_sec is not None else record_wall_sum
    accepts = sum(int(row.get("accepts", 0)) for row in rows)
    rejects = sum(int(row.get("metropolis_reject", 0)) for row in rows)
    failures = sum(int(row.get("proposal_failure", 0)) for row in rows)
    h_invalid = sum(int(row.get("hamiltonian_invalid", 0)) for row in rows)
    dh_invalid = sum(int(row.get("delta_h_invalid", 0)) for row in rows)
    transitions = accepts + rejects + failures
    metropolis_transitions = accepts + rejects
    move_sum = sum(float(row.get("move_norm2_sum", 0.0)) for row in rows)
    move_count = sum(max(0, int(row.get("samples", 0)) - 1) for row in rows)
    nonzero_sum = sum(float(row.get("nonzero_step_rate", 0.0)) * max(0, int(row.get("samples", 0)) - 1) for row in rows)
    return {
        "stage": rows[0]["stage"],
        "tag": rows[0]["tag"],
        "L": rows[0]["L"],
        "nstep": rows[0]["nstep"],
        "epsilon": rows[0]["epsilon"],
        "flow_time": rows[0]["flow_time"],
        "status": status,
        "records": ";".join(str(row["record"]) for row in rows),
        "init_mode": rows[0]["init_mode"],
        "preflow_L": rows[0]["preflow_L"],
        "preflow_nstep": rows[0]["preflow_nstep"],
        "elapsed_wall_sec": elapsed,
        "record_wall_sum_sec": record_wall_sum,
        "samples_by_record": ";".join(str(row.get("samples", 0)) for row in rows),
        "accepted": accepts,
        "metropolis_reject": rejects,
        "proposal_failure": failures,
        "hamiltonian_invalid": h_invalid,
        "delta_h_invalid": dh_invalid,
        "attempt_accept_rate": accepts / float(transitions) if transitions else 0.0,
        "valid_proposal_metropolis_accept_rate": accepts / float(metropolis_transitions) if metropolis_transitions else 0.0,
        "proposal_failure_rate": failures / float(transitions) if transitions else 0.0,
        "accepted_per_wall_sec": accepts / elapsed if elapsed > 0.0 else 0.0,
        "mean_step_norm2": move_sum / float(move_count) if move_count else 0.0,
        "nonzero_step_rate": nonzero_sum / float(move_count) if move_count else 0.0,
        "move_norm2_per_wall_sec": move_sum / elapsed if elapsed > 0.0 else 0.0,
        "runtime_sum_sec": sum(float(row.get("runtime_sec", 0.0)) for row in rows),
    }


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    bank_file = (repo_root / args.bank_file).resolve()
    base_parameters = (repo_root / args.base_parameters).resolve()
    output_root = Path(args.output_root)
    if not output_root.is_absolute():
        output_root = repo_root / output_root
    run_name = args.run_name or datetime.now(tz=timezone.utc).strftime("stephanov_n6_bank_hmc_%Y%m%dT%H%M%SZ")
    run_dir = output_root / run_name
    if run_dir.exists():
        if not args.force:
            raise RuntimeError("Run directory exists; use --force: {0}".format(run_dir))
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    params_dir = run_dir / "params"
    params_dir.mkdir(parents=True, exist_ok=True)
    records = parse_int_list(args.records)
    if args.jobs < 1:
        raise RuntimeError("--jobs must be >= 1")
    run_build(repo_root, args.skip_build)
    base_text = base_parameters.read_text(encoding="utf-8")

    candidates = []
    if args.stage == "epsilon":
        for epsilon in parse_float_list(args.epsilon_values):
            nstep = args.fixed_nstep
            L = epsilon * nstep
            candidates.append(("eps{0}".format(label_float(epsilon)), L, nstep, epsilon))
    else:
        epsilon = args.fixed_epsilon
        for nstep in parse_int_list(args.nstep_values):
            L = epsilon * nstep
            candidates.append(("nstep{0}".format(nstep), L, nstep, epsilon))

    aggregate = []
    detail_rows = []
    plan_rows = []
    for tag, L, nstep, epsilon in candidates:
        for record_idx in records:
            plan_rows.append(
                {
                    "stage": args.stage,
                    "tag": tag,
                    "record": record_idx,
                    "seed": args.seed_base + record_idx,
                    "flow_time": args.flow_time,
                    "L": L,
                    "nstep": nstep,
                    "epsilon": epsilon,
                    "jobs": args.jobs,
                }
            )
    with (run_dir / "scan_plan.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(plan_rows[0].keys()))
        writer.writeheader()
        writer.writerows(plan_rows)
    for tag, L, nstep, epsilon in candidates:
        params_file = params_dir / ("{0}_{1}.dat".format(args.stage, tag))
        write_parameters(base_text, params_file, L, nstep, args.flow_time)
        case_start = time.monotonic()
        rows = run_case_records(
            repo_root, run_dir, params_file, bank_file, args.stage, tag, L, nstep, epsilon, records,
            args.cycles, args.timeout_sec, args.seed_base, args.init_mode, args.preflow_L, args.preflow_nstep,
            args.flow_time, args.jobs,
        )
        case_wall_sec = time.monotonic() - case_start
        detail_rows.extend(rows)
        agg = aggregate_rows(rows, case_wall_sec)
        agg["jobs"] = args.jobs
        aggregate.append(agg)
        print("[SCAN] {0} status={1} attempt_acc={2:.3f} valid_met_acc={3:.3f} move/sec={4:.3f}".format(
            tag,
            agg["status"],
            agg["attempt_accept_rate"],
            agg["valid_proposal_metropolis_accept_rate"],
            agg["move_norm2_per_wall_sec"],
        ), flush=True)

    summary_path = run_dir / ("{0}_summary.csv".format(args.stage))
    fieldnames = list(aggregate[0].keys())
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(aggregate)

    detail_path = run_dir / ("{0}_detail.csv".format(args.stage))
    detail_fields = list(detail_rows[0].keys())
    with detail_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=detail_fields)
        writer.writeheader()
        writer.writerows(detail_rows)

    print(summary_path)


if __name__ == "__main__":
    main()
