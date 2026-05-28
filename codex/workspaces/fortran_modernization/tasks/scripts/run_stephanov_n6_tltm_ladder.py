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
    parser.add_argument(
        "--bank-index-file",
        default="",
        help="CSV index for bank-file. Defaults to x_bank_index.csv next to the bank file when present.",
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
    parser.add_argument(
        "--blas-threads",
        type=int,
        default=0,
        help=(
            "Thread count for BLAS/LAPACK libraries inside each record process. "
            "Defaults to --threads for backward compatibility; use 1 when OpenMP "
            "is parallelizing replicas/swaps outside BLAS."
        ),
    )
    parser.add_argument("--parallel-local-updates", choices=("0", "1"), default="1")
    parser.add_argument("--parallel-swaps", choices=("0", "1"), default="1")
    parser.add_argument(
        "--swap-enabled",
        choices=("0", "1"),
        default="1",
        help="Enable adjacent replica swaps. Use 0 for fixed-tau single-replica runs.",
    )
    parser.add_argument(
        "--enable-quasi-fallback",
        action="store_true",
        help="Enable the quasi-Newton fallback path for withfb runs.",
    )
    parser.add_argument("--write-cold-observables", action="store_true")
    parser.add_argument("--write-all-replica-observables", action="store_true")
    parser.add_argument("--write-cold-x-history", action="store_true")
    parser.add_argument("--observable-stride", type=int, default=1)
    parser.add_argument("--cold-observable-max-samples", type=int, default=-1)
    parser.add_argument("--all-replica-observable-max-samples", type=int, default=-1)
    parser.add_argument("--write-final-snapshot", action="store_true")
    parser.add_argument(
        "--qn-attempt-capture-root",
        default="",
        help="Optional root for per-record QN attempt capture directories.",
    )
    parser.add_argument("--qn-attempt-capture-limit", type=int, default=0)
    parser.add_argument("--qn-attempt-capture-stride", type=int, default=1)
    parser.add_argument(
        "--local-transition-audit-root",
        default="",
        help="Optional root for per-record local transition audit CSV files.",
    )
    parser.add_argument("--local-transition-audit-max-rows", type=int, default=200000)
    parser.add_argument(
        "--init-snapshot-root",
        default="",
        help="Run root containing records/record_XXXX/final_snapshot.bin files for continuation.",
    )
    parser.add_argument(
        "--init-snapshot-file",
        default="",
        help="Single snapshot file for continuation; valid only when --records contains one record.",
    )
    parser.add_argument(
        "--restart-boundary-policy",
        choices=("skip", "write"),
        default="skip",
        help="For snapshot continuation, skip avoids double-counting the restored boundary cycle.",
    )
    parser.add_argument(
        "--init-flow-bank-root",
        default="",
        help="Flow-bank cache root containing records/record_NNNNNN/slot_NNNNNN.bin files.",
    )
    parser.add_argument("--max-preflow-stages", type=int, default=512)
    parser.add_argument("--max-preflow-shrinks", type=int, default=4096)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def parse_int_list(text):
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def parse_float_list(text):
    return [float(item.strip()) for item in text.split(",") if item.strip()]


def validate_bank_records(bank_file, bank_index_file, records):
    index_path = Path(bank_index_file) if bank_index_file else bank_file.with_name("x_bank_index.csv")
    if not index_path.exists():
        return
    with index_path.open(newline="", encoding="utf-8") as handle:
        count = sum(1 for _row in csv.DictReader(handle))
    if count <= 0:
        raise RuntimeError("Bank index has no records: {0}".format(index_path))
    bad = [record for record in records if record < 0 or record >= count]
    if bad:
        raise RuntimeError(
            "Requested bank records {0} outside valid range 0..{1} from {2}".format(
                ",".join(str(record) for record in bad), count - 1, index_path
            )
        )


def resolve_repo_path(repo_root, value):
    path = Path(value)
    if path.is_absolute():
        return path
    return repo_root / path


def resolve_init_snapshot_file(repo_root, args, record_idx):
    if args.init_snapshot_file:
        return resolve_repo_path(repo_root, args.init_snapshot_file).resolve()
    if args.init_snapshot_root:
        root = resolve_repo_path(repo_root, args.init_snapshot_root).resolve()
        return root / "records" / "record_{0:04d}".format(record_idx) / "final_snapshot.bin"
    return None


def resolve_init_flow_bank_root(repo_root, args):
    if not args.init_flow_bank_root:
        return None
    return resolve_repo_path(repo_root, args.init_flow_bank_root).resolve()


def resolve_qn_capture_dir(repo_root, run_dir, args, record_idx):
    if not args.qn_attempt_capture_root:
        return None
    root = resolve_repo_path(repo_root, args.qn_attempt_capture_root).resolve()
    return root / "record_{0:04d}".format(record_idx)


def resolve_local_transition_audit_file(repo_root, args, record_idx):
    if not args.local_transition_audit_root:
        return None
    root = resolve_repo_path(repo_root, args.local_transition_audit_root).resolve()
    return root / "record_{0:04d}".format(record_idx) / "local_transition_audit.csv"


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
    lines = set_param(lines, "enable_quasi_fallback", "true" if args.enable_quasi_fallback else "false")
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
    init_snapshot_file = resolve_init_snapshot_file(repo_root, args, record_idx)
    init_flow_bank_root = resolve_init_flow_bank_root(repo_root, args)
    final_snapshot_file = chain_dir / "final_snapshot.bin"
    qn_capture_dir = resolve_qn_capture_dir(repo_root, run_dir, args, record_idx)
    local_transition_audit_file = resolve_local_transition_audit_file(repo_root, args, record_idx)
    if init_snapshot_file is not None and not init_snapshot_file.exists():
        raise RuntimeError("Init snapshot file does not exist: {0}".format(init_snapshot_file))
    if init_flow_bank_root is not None and not init_flow_bank_root.exists():
        raise RuntimeError("Init flow-bank root does not exist: {0}".format(init_flow_bank_root))
    env = os.environ.copy()
    thread_text = str(max(1, args.threads))
    blas_thread_text = str(max(1, args.blas_threads if args.blas_threads > 0 else args.threads))
    env.update(
        {
            "OMP_NUM_THREADS": thread_text,
            "OPENBLAS_NUM_THREADS": blas_thread_text,
            "MKL_NUM_THREADS": blas_thread_text,
            "VECLIB_MAXIMUM_THREADS": blas_thread_text,
            "TLTM_PARAMETERS_FILE": str(params_file),
            "CHAIN_RNG_SEED": str(args.seed_base + record_idx + 10000 * chain_idx),
            "QN_REVERSE_GATE_ENABLED": "1",
            "TLTM_STAGE2_PARALLEL_LOCAL_UPDATES": args.parallel_local_updates,
            "TLTM_STAGE2_PARALLEL_SWAPS": args.parallel_swaps,
            "TLTM_STAGE2_FLOW_TIME_LADDER": ",".join("{0:g}".format(value) for value in ladder),
            "TLTM_STAGE2_MAX_FLOW_TIME": "{0:g}".format(max(ladder)),
            "TLTM_STAGE2_NUM_REPLICAS": str(len(ladder)),
            "TLTM_STAGE2_CYCLES": str(args.cycles),
            "TLTM_STAGE2_LOCAL_UPDATES": "1",
            "TLTM_STAGE2_SWAP_ENABLED": args.swap_enabled,
            "TLTM_STAGE2_SUMMARY_FILE": str(chain_dir / "summary.dat"),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(chain_dir / "label_trace.dat"),
            "TLTM_STAGE2_PHASE_CACHE_STATS_FILE": str(chain_dir / "phase_cache_stats.csv"),
            "TLTM_STAGE2_REAL_JAC_CACHE_STATS_FILE": str(chain_dir / "real_jacobian_cache_stats.csv"),
            "TLTM_STAGE2_V1_OUTPUT_DIR": str(chain_dir / "v1"),
            "TLTM_STAGE2_RNG_STREAM_CONTRACT": "stage2_kernel_rng_v2",
            "CONSTRAINT_FAIL_CAPTURE_START_SAMPLE": "2147483647",
        }
    )
    if init_snapshot_file is not None:
        env.update(
            {
                "TLTM_STAGE2_INIT_SNAPSHOT_FILE": str(init_snapshot_file),
                "TLTM_STAGE2_INIT_MODE": "snapshot",
                "TLTM_STAGE2_RESTART_BOUNDARY_POLICY": args.restart_boundary_policy,
            }
        )
    elif init_flow_bank_root is not None:
        env.update(
            {
                "TLTM_STAGE2_INITIAL_FLOW_BANK_DIR": str(init_flow_bank_root),
                "TLTM_STAGE2_INITIAL_FLOW_BANK_RECORD": str(record_idx),
                "TLTM_STAGE2_INIT_MODE": "flow_bank",
            }
        )
    else:
        env.update(
            {
                "TLTM_STAGE2_INITIAL_X_FILE": str(bank_file),
                "TLTM_STAGE2_INITIAL_X_RECORD": str(record_idx),
                "TLTM_STAGE2_INIT_MODE": "adaptive",
                "TLTM_STAGE2_INIT_PREFLOW_TRAJECTORY_LENGTH": "{0:g}".format(args.preflow_L),
                "TLTM_STAGE2_INIT_PREFLOW_INTEGRATION_STEPS": str(args.preflow_nstep),
                "TLTM_STAGE2_INIT_PREFLOW_MAX_STAGES": str(args.max_preflow_stages),
                "TLTM_STAGE2_INIT_PREFLOW_MAX_SHRINKS": str(args.max_preflow_shrinks),
            }
        )
    if args.write_final_snapshot:
        env["TLTM_STAGE2_SNAPSHOT_FILE"] = str(final_snapshot_file)
    if qn_capture_dir is not None:
        qn_capture_dir.mkdir(parents=True, exist_ok=True)
        env["QN_ATTEMPT_CAPTURE_DIR"] = str(qn_capture_dir)
        env["QN_ATTEMPT_CAPTURE_LIMIT"] = str(args.qn_attempt_capture_limit)
        env["QN_ATTEMPT_CAPTURE_STRIDE"] = str(max(1, args.qn_attempt_capture_stride))
    if local_transition_audit_file is not None:
        local_transition_audit_file.parent.mkdir(parents=True, exist_ok=True)
        env["TLTM_LOCAL_TRANSITION_AUDIT_FILE"] = str(local_transition_audit_file)
        env["TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS"] = str(args.local_transition_audit_max_rows)
    if args.write_cold_x_history:
        env["TLTM_STAGE2_COLD_X_HISTORY_FILE"] = str(chain_dir / "x_history.dat")
    if args.write_cold_observables:
        env.update(
            {
                "TLTM_STAGE2_COLD_OBSERVABLE_FILE": str(chain_dir / "observable_history.dat"),
                "TLTM_STAGE2_COLD_OBSERVABLE_STRIDE": str(args.observable_stride),
                "TLTM_STAGE2_COLD_OBSERVABLE_MAX_SAMPLES": str(args.cold_observable_max_samples),
            }
        )
    if args.write_all_replica_observables:
        env.update(
            {
                "TLTM_STAGE2_ALL_REPLICA_OBSERVABLE_DIR": str(chain_dir / "all_replica_observables"),
                "TLTM_STAGE2_ALL_REPLICA_OBSERVABLE_STRIDE": str(args.observable_stride),
                "TLTM_STAGE2_ALL_REPLICA_OBSERVABLE_MAX_SAMPLES": str(args.all_replica_observable_max_samples),
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
        "blas_threads": max(1, args.blas_threads if args.blas_threads > 0 else args.threads),
        "hmc_epsilon": args.hmc_epsilon,
        "hmc_nstep": args.hmc_nstep,
        "hmc_L": hmc_l,
        "enable_quasi_fallback": int(args.enable_quasi_fallback),
        "swap_enabled": int(args.swap_enabled),
        "preflow_L": args.preflow_L,
        "preflow_nstep": args.preflow_nstep,
        **metrics,
        "init_snapshot_file": str(init_snapshot_file) if init_snapshot_file is not None else "",
        "init_flow_bank_root": str(init_flow_bank_root) if init_flow_bank_root is not None else "",
        "init_flow_bank_record": record_idx if init_flow_bank_root is not None else "",
        "final_snapshot_file": str(final_snapshot_file) if args.write_final_snapshot else "",
        "qn_attempt_capture_dir": str(qn_capture_dir) if qn_capture_dir is not None else "",
        "qn_attempt_capture_meta_file": str(qn_capture_dir / "qn_attempt_meta.csv") if qn_capture_dir is not None else "",
        "local_transition_audit_file": str(local_transition_audit_file) if local_transition_audit_file is not None else "",
        "restart_boundary_policy": args.restart_boundary_policy if init_snapshot_file is not None else "",
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
    if len(ladder) < 1:
        raise RuntimeError("TLTM ladder needs at least one replica.")
    if len(ladder) < 2 and args.swap_enabled == "1":
        raise RuntimeError("Single-replica fixed-tau runs require --swap-enabled 0.")
    if args.init_snapshot_file and len(records) != 1:
        raise RuntimeError("--init-snapshot-file is only valid for a single record.")
    if args.init_snapshot_file and args.init_snapshot_root:
        raise RuntimeError("Use either --init-snapshot-file or --init-snapshot-root, not both.")
    if args.init_flow_bank_root and (args.init_snapshot_file or args.init_snapshot_root):
        raise RuntimeError("Use either snapshot initialization or flow-bank initialization, not both.")
    if not (args.init_snapshot_file or args.init_snapshot_root or args.init_flow_bank_root):
        validate_bank_records(bank_file, args.bank_index_file, records)
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
