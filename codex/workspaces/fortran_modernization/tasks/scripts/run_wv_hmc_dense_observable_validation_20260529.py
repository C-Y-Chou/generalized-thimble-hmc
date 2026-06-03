#!/usr/bin/env python3
"""Run multi-seed dense WV-HMC observable validation candidates."""

from __future__ import print_function

import argparse
import csv
import os
import re
import subprocess
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path


INIT_LOG_RE = re.compile(
    r"\bWV_HMC_INIT\b.*\bflow_time\s+([-+0-9.Ee]+).*"
    r"\binit_bank_record\s+(-?\d+)\s+init_bank_record_count\s+(\d+)"
)


def parse_init_log(log_path):
    info = {
        "init_bank_record_actual": "",
        "init_bank_record_count_actual": "",
        "initial_flow_time_actual": "",
    }
    if not log_path.exists():
        return info
    try:
        with log_path.open() as handle:
            for line in handle:
                match = INIT_LOG_RE.search(line)
                if not match:
                    continue
                info["initial_flow_time_actual"] = match.group(1)
                info["init_bank_record_actual"] = match.group(2)
                info["init_bank_record_count_actual"] = match.group(3)
                return info
    except OSError:
        return info
    return info


def run_seed(args):
    (binary, output_root, parameters_file, seed, cycles, measurement_start_cycle, timeout_sec,
     step_size, num_steps, init_mode, init_sigma, init_bank_file, init_bank_record,
     init_bank_record_mode, seed_offset,
     reverse_gate_state_tol, reverse_gate_momentum_tol, constraint_tol, constraint_max_iter,
     adaptive_newton_stop_enabled, large_residual_stop_enabled, large_residual_threshold,
     large_residual_min_iter, large_residual_patience, large_residual_min_rel_improvement,
     sampler_t0, sampler_t1, d0, d1, measurement_t0, measurement_t1,
     initial_flow_time, w_profile, boundary_policy, w_gamma, w_c0, w_c1, write_final_state, newton_trace_dir,
     write_observable_history, write_x_history, write_state_history, history_stride,
     write_cyclic_snapshot, snapshot_interval, snapshot_slots) = args
    effective_init_bank_record = init_bank_record
    if init_bank_record_mode == "seed_offset":
        effective_init_bank_record = seed_offset if init_bank_record < 0 else init_bank_record + seed_offset
    elif init_bank_record_mode == "fixed":
        effective_init_bank_record = init_bank_record
    else:
        raise ValueError("unknown init bank record mode: {0}".format(init_bank_record_mode))
    summary_path = output_root / "seed_{:05d}_summary.csv".format(seed)
    observable_path = output_root / "seed_{:05d}_observables.csv".format(seed)
    final_state_path = output_root / "seed_{:05d}_final_state.bin".format(seed)
    observable_history_path = output_root / "seed_{:05d}_observable_history.csv".format(seed)
    x_history_path = output_root / "seed_{:05d}_x_history.dat".format(seed)
    state_history_path = output_root / "seed_{:05d}_state_history.dat".format(seed)
    snapshot_prefix = output_root / "seed_{:05d}_snapshot".format(seed)
    snapshot_index_path = output_root / "seed_{:05d}_snapshot_index.csv".format(seed)
    newton_trace_path = None
    if newton_trace_dir:
        newton_trace_dir = Path(newton_trace_dir)
        newton_trace_dir.mkdir(parents=True, exist_ok=True)
        newton_trace_path = newton_trace_dir / "seed_{:05d}_newton_trace.csv".format(seed)
    log_path = output_root / "seed_{:05d}.log".format(seed)
    env = os.environ.copy()
    env.update({
        "TLTM_PARAMETERS_FILE": str(parameters_file),
        "WV_HMC_SUMMARY_FILE": str(summary_path),
        "WV_HMC_OBSERVABLE_FILE": str(observable_path),
        "WV_HMC_BASE_SEED": str(seed),
        "WV_HMC_CYCLES": str(cycles),
        "WV_HMC_MEASUREMENT_START_CYCLE": str(measurement_start_cycle),
        "WV_HMC_STEP_SIZE": str(step_size),
        "WV_HMC_NUM_STEPS": str(num_steps),
        "WV_HMC_FLOW_TIME": str(initial_flow_time),
        "WV_HMC_BOUNDARY_POLICY": boundary_policy,
        "WV_HMC_T0": str(sampler_t0),
        "WV_HMC_T1": str(sampler_t1),
        "WV_HMC_D0": str(d0),
        "WV_HMC_D1": str(d1),
        "WV_HMC_MEASUREMENT_T0": str(measurement_t0),
        "WV_HMC_MEASUREMENT_T1": str(measurement_t1),
        "WV_HMC_INIT_MODE": init_mode,
        "WV_HMC_INIT_SIGMA": str(init_sigma),
        "WV_HMC_W_PROFILE": w_profile,
        "WV_HMC_W_GAMMA": str(w_gamma),
        "WV_HMC_W_C0": str(w_c0),
        "WV_HMC_W_C1": str(w_c1),
        "WV_HMC_REVERSE_GATE_STATE_TOL": str(reverse_gate_state_tol),
        "WV_HMC_REVERSE_GATE_MOMENTUM_TOL": str(reverse_gate_momentum_tol),
        "WV_HMC_CONSTRAINT_TOL": str(constraint_tol),
        "WV_HMC_CONSTRAINT_MAX_ITER": str(constraint_max_iter),
        "WV_HMC_ADAPTIVE_NEWTON_STOP_ENABLED": "1" if adaptive_newton_stop_enabled else "0",
        "WV_HMC_LARGE_RESIDUAL_STOP_ENABLED": "1" if large_residual_stop_enabled else "0",
        "WV_HMC_LARGE_RESIDUAL_THRESHOLD": str(large_residual_threshold),
        "WV_HMC_LARGE_RESIDUAL_MIN_ITER": str(large_residual_min_iter),
        "WV_HMC_LARGE_RESIDUAL_PATIENCE": str(large_residual_patience),
        "WV_HMC_LARGE_RESIDUAL_MIN_REL_IMPROVEMENT": str(large_residual_min_rel_improvement),
        "WV_HMC_HISTORY_STRIDE": str(history_stride),
    })
    if init_bank_file:
        env["WV_HMC_INIT_BANK_FILE"] = str(init_bank_file)
    if effective_init_bank_record >= 0:
        env["WV_HMC_INIT_BANK_RECORD"] = str(effective_init_bank_record)
    if write_final_state:
        env["WV_HMC_FINAL_STATE_FILE"] = str(final_state_path)
    if write_observable_history:
        env["WV_HMC_OBSERVABLE_HISTORY_FILE"] = str(observable_history_path)
    if write_x_history:
        env["WV_HMC_X_HISTORY_FILE"] = str(x_history_path)
    if write_state_history:
        env["WV_HMC_STATE_HISTORY_FILE"] = str(state_history_path)
    if write_cyclic_snapshot:
        env["WV_HMC_SNAPSHOT_PREFIX"] = str(snapshot_prefix)
        env["WV_HMC_SNAPSHOT_INDEX_FILE"] = str(snapshot_index_path)
        env["WV_HMC_SNAPSHOT_INTERVAL"] = str(snapshot_interval)
        env["WV_HMC_SNAPSHOT_SLOTS"] = str(snapshot_slots)
    if newton_trace_path is not None:
        env["WV_HMC_NEWTON_TRACE_FILE"] = str(newton_trace_path)
    start = time.time()
    timed_out = 0
    return_code = 0
    with log_path.open("w") as log_handle:
        try:
            completed = subprocess.run(
                [str(binary)],
                env=env,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                timeout=timeout_sec,
            )
            return_code = completed.returncode
        except subprocess.TimeoutExpired:
            timed_out = 1
            return_code = 124
            log_handle.write("\nTIMEOUT after {0} seconds\n".format(timeout_sec))
    runtime_sec = time.time() - start
    init_info = parse_init_log(log_path)
    snapshot_slot_count = 0
    if write_cyclic_snapshot:
        snapshot_slot_count = len(list(output_root.glob("seed_{:05d}_snapshot_slot_*.bin".format(seed))))
    return {
        "seed": seed,
        "cycles": cycles,
        "measurement_start_cycle": measurement_start_cycle,
        "step_size": step_size,
        "num_steps": num_steps,
        "trajectory_length": step_size * num_steps,
        "init_mode": init_mode,
        "init_sigma": init_sigma,
        "init_bank_file": str(init_bank_file) if init_bank_file else "",
        "init_bank_record": effective_init_bank_record,
        "init_bank_record_mode": init_bank_record_mode,
        "init_bank_record_actual": init_info["init_bank_record_actual"],
        "init_bank_record_count_actual": init_info["init_bank_record_count_actual"],
        "reverse_gate_state_tol": reverse_gate_state_tol,
        "reverse_gate_momentum_tol": reverse_gate_momentum_tol,
        "constraint_tol": constraint_tol,
        "constraint_max_iter": constraint_max_iter,
        "adaptive_newton_stop_enabled": int(adaptive_newton_stop_enabled),
        "large_residual_stop_enabled": int(large_residual_stop_enabled),
        "large_residual_threshold": large_residual_threshold,
        "large_residual_min_iter": large_residual_min_iter,
        "large_residual_patience": large_residual_patience,
        "large_residual_min_rel_improvement": large_residual_min_rel_improvement,
        "sampler_t0": sampler_t0,
        "sampler_t1": sampler_t1,
        "d0": d0,
        "d1": d1,
        "measurement_t0": measurement_t0,
        "measurement_t1": measurement_t1,
        "initial_flow_time": initial_flow_time,
        "initial_flow_time_actual": init_info["initial_flow_time_actual"],
        "w_profile": w_profile,
        "boundary_policy": boundary_policy,
        "w_gamma": w_gamma,
        "w_c0": w_c0,
        "w_c1": w_c1,
        "runtime_sec": runtime_sec,
        "timed_out": timed_out,
        "return_code": return_code,
        "history_stride": history_stride,
        "cyclic_snapshot_enabled": int(write_cyclic_snapshot),
        "snapshot_interval": snapshot_interval,
        "snapshot_slots": snapshot_slots,
        "summary_path": str(summary_path),
        "observable_path": str(observable_path),
        "final_state_path": str(final_state_path) if write_final_state else "",
        "observable_history_path": str(observable_history_path) if write_observable_history else "",
        "x_history_path": str(x_history_path) if write_x_history else "",
        "state_history_path": str(state_history_path) if write_state_history else "",
        "snapshot_prefix": str(snapshot_prefix) if write_cyclic_snapshot else "",
        "snapshot_index_path": str(snapshot_index_path) if write_cyclic_snapshot else "",
        "newton_trace_path": str(newton_trace_path) if newton_trace_path is not None else "",
        "log_path": str(log_path),
        "summary_present": int(summary_path.exists()),
        "observable_present": int(observable_path.exists()),
        "final_state_present": int(final_state_path.exists()) if write_final_state else 0,
        "observable_history_present": int(observable_history_path.exists()) if write_observable_history else 0,
        "x_history_present": int(x_history_path.exists()) if write_x_history else 0,
        "state_history_present": int(state_history_path.exists()) if write_state_history else 0,
        "snapshot_index_present": int(snapshot_index_path.exists()) if write_cyclic_snapshot else 0,
        "snapshot_slot_count": snapshot_slot_count,
        "newton_trace_present": int(newton_trace_path.exists()) if newton_trace_path is not None else 0,
    }


def write_manifest(rows, output_root):
    path = output_root / "wv_hmc_dense_observable_validation_manifest.csv"
    fieldnames = [
        "seed",
        "cycles",
        "measurement_start_cycle",
        "step_size",
        "num_steps",
        "trajectory_length",
        "init_mode",
        "init_sigma",
        "init_bank_file",
        "init_bank_record",
        "init_bank_record_mode",
        "init_bank_record_actual",
        "init_bank_record_count_actual",
        "reverse_gate_state_tol",
        "reverse_gate_momentum_tol",
        "constraint_tol",
        "constraint_max_iter",
        "adaptive_newton_stop_enabled",
        "large_residual_stop_enabled",
        "large_residual_threshold",
        "large_residual_min_iter",
        "large_residual_patience",
        "large_residual_min_rel_improvement",
        "sampler_t0",
        "sampler_t1",
        "d0",
        "d1",
        "measurement_t0",
        "measurement_t1",
        "initial_flow_time",
        "initial_flow_time_actual",
        "w_profile",
        "boundary_policy",
        "w_gamma",
        "w_c0",
        "w_c1",
        "runtime_sec",
        "timed_out",
        "return_code",
        "history_stride",
        "cyclic_snapshot_enabled",
        "snapshot_interval",
        "snapshot_slots",
        "summary_present",
        "observable_present",
        "final_state_present",
        "observable_history_present",
        "x_history_present",
        "state_history_present",
        "snapshot_index_present",
        "snapshot_slot_count",
        "newton_trace_present",
        "summary_path",
        "observable_path",
        "final_state_path",
        "observable_history_path",
        "x_history_path",
        "state_history_path",
        "snapshot_prefix",
        "snapshot_index_path",
        "newton_trace_path",
        "log_path",
    ]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="bin/run_wv_hmc")
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n2_smoke.dat")
    parser.add_argument("--seed-start", type=int, default=4001)
    parser.add_argument("--seed-count", type=int, default=64)
    parser.add_argument("--cycles", type=int, default=4000)
    parser.add_argument("--measurement-start-cycle", type=int, default=1001)
    parser.add_argument("--step-size", type=float, default=0.002)
    parser.add_argument("--num-steps", type=int, default=2)
    parser.add_argument("--init-mode", default="random_gaussian")
    parser.add_argument("--init-sigma", type=float, default=0.8)
    parser.add_argument("--init-bank-file", default="")
    parser.add_argument("--init-bank-record", type=int, default=-1)
    parser.add_argument("--init-bank-record-mode", default="fixed", choices=("fixed", "seed_offset"),
                        help="fixed uses --init-bank-record for every seed; seed_offset maps seed offset to bank record")
    parser.add_argument("--reverse-gate-state-tol", type=float, default=1.0e-5)
    parser.add_argument("--reverse-gate-momentum-tol", type=float, default=1.0e-3)
    parser.add_argument("--constraint-tol", type=float, default=1.0e-10)
    parser.add_argument("--constraint-max-iter", type=int, default=48)
    parser.add_argument("--adaptive-newton-stop-enabled", type=int, choices=(0, 1), default=0)
    parser.add_argument("--large-residual-stop-enabled", type=int, choices=(0, 1), default=0)
    parser.add_argument("--large-residual-threshold", type=float, default=1.0e-4)
    parser.add_argument("--large-residual-min-iter", type=int, default=8)
    parser.add_argument("--large-residual-patience", type=int, default=4)
    parser.add_argument("--large-residual-min-rel-improvement", type=float, default=5.0e-4)
    parser.add_argument("--sampler-t0", type=float, default=0.0)
    parser.add_argument("--sampler-t1", type=float, default=0.2)
    parser.add_argument("--d0", type=float, default=0.005)
    parser.add_argument("--d1", type=float, default=0.05)
    parser.add_argument("--measurement-t0", type=float, default=None)
    parser.add_argument("--measurement-t1", type=float, default=None)
    parser.add_argument("--initial-flow-time", type=float, default=None)
    parser.add_argument("--w-profile", default="paper_wall")
    parser.add_argument("--boundary-policy", default="paper_full_flip",
                        choices=("paper_full_flip", "full_flip", "normal_reflect", "normal_reflection",
                                 "legacy_normal", "legacy"))
    parser.add_argument("--w-gamma", type=float, default=1.0)
    parser.add_argument("--w-c0", type=float, default=1.0)
    parser.add_argument("--w-c1", type=float, default=1.0)
    parser.add_argument("--write-final-state", action="store_true")
    parser.add_argument("--newton-trace-dir", default="")
    parser.add_argument("--write-observable-history", action="store_true")
    parser.add_argument("--write-x-history", action="store_true")
    parser.add_argument("--write-state-history", action="store_true")
    parser.add_argument("--history-stride", type=int, default=1)
    parser.add_argument("--write-cyclic-snapshot", action="store_true")
    parser.add_argument("--snapshot-interval", type=int, default=500)
    parser.add_argument("--snapshot-slots", type=int, default=8)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--timeout-sec", type=float, default=1200.0)
    args = parser.parse_args()

    binary = Path(args.binary)
    output_root = Path(args.output_root)
    parameters_file = Path(args.parameters_file)
    output_root.mkdir(parents=True, exist_ok=True)
    measurement_t0 = args.sampler_t0 if args.measurement_t0 is None else args.measurement_t0
    measurement_t1 = args.sampler_t1 if args.measurement_t1 is None else args.measurement_t1
    initial_flow_time = args.sampler_t0 if args.initial_flow_time is None else args.initial_flow_time
    if args.history_stride < 1:
        raise SystemExit("--history-stride must be >= 1")
    if args.write_cyclic_snapshot and args.snapshot_interval < 1:
        raise SystemExit("--snapshot-interval must be >= 1 when --write-cyclic-snapshot is used")
    if args.write_cyclic_snapshot and args.snapshot_slots < 1:
        raise SystemExit("--snapshot-slots must be >= 1 when --write-cyclic-snapshot is used")

    work = [
        (binary, output_root, parameters_file, args.seed_start + offset, args.cycles, args.measurement_start_cycle,
         args.timeout_sec, args.step_size, args.num_steps, args.init_mode, args.init_sigma, args.init_bank_file,
         args.init_bank_record, args.init_bank_record_mode, offset,
         args.reverse_gate_state_tol, args.reverse_gate_momentum_tol, args.constraint_tol,
         args.constraint_max_iter, bool(args.adaptive_newton_stop_enabled),
         bool(args.large_residual_stop_enabled), args.large_residual_threshold, args.large_residual_min_iter,
         args.large_residual_patience, args.large_residual_min_rel_improvement, args.sampler_t0, args.sampler_t1,
         args.d0, args.d1, measurement_t0, measurement_t1, initial_flow_time, args.w_profile, args.boundary_policy,
         args.w_gamma,
         args.w_c0, args.w_c1, args.write_final_state, args.newton_trace_dir, args.write_observable_history,
         args.write_x_history, args.write_state_history, args.history_stride, args.write_cyclic_snapshot,
         args.snapshot_interval, args.snapshot_slots)
        for offset in range(args.seed_count)
    ]
    rows = [None] * len(work)
    if args.jobs <= 1:
        for idx, item in enumerate(work):
            rows[idx] = run_seed(item)
    else:
        with ProcessPoolExecutor(max_workers=args.jobs) as executor:
            futures = {executor.submit(run_seed, item): idx for idx, item in enumerate(work)}
            for future in as_completed(futures):
                rows[futures[future]] = future.result()

    manifest = write_manifest(rows, output_root)
    print("manifest={0}".format(manifest))
    failures = [
        row for row in rows
        if row["return_code"] != 0 or row["summary_present"] != 1 or row["observable_present"] != 1
        or (args.write_final_state and row["final_state_present"] != 1)
        or (args.write_observable_history and row["observable_history_present"] != 1)
        or (args.write_x_history and row["x_history_present"] != 1)
        or (args.write_state_history and row["state_history_present"] != 1)
        or (args.write_cyclic_snapshot and row["snapshot_index_present"] != 1)
        or (args.write_cyclic_snapshot and row["snapshot_slot_count"] < 1)
        or (args.newton_trace_dir and row["newton_trace_present"] != 1)
    ]
    if failures:
        for row in failures[:20]:
            print("FAILED seed={seed} return_code={return_code} timed_out={timed_out} summary={summary_present} "
                  "observable={observable_present} log={log_path}".format(**row))
        raise SystemExit(3)


if __name__ == "__main__":
    main()
