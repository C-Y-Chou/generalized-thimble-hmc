#!/usr/bin/env python3
"""Run a small dense WV-HMC pilot scan before matrix-free wiring."""

from __future__ import print_function

import argparse
import csv
import os
import subprocess
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path


SUMMARY_FIELDS = [
    "cycles_completed",
    "accepted",
    "rejected",
    "metropolis_rejected",
    "reverse_gate_rejected",
    "transitions_failed",
    "accept_probability_mean",
    "delta_hamiltonian_mean",
    "flow_time_min",
    "flow_time_max",
    "flow_time_mean",
    "accepted_jump_count",
    "accepted_x_jump_sq_mean",
    "accepted_z_jump_sq_mean",
    "accepted_flow_time_jump_abs_mean",
    "effective_x_jump_sq_mean",
    "effective_z_jump_sq_mean",
    "effective_flow_time_jump_abs_mean",
    "max_x_jump_sq",
    "max_z_jump_sq",
    "max_flow_time_jump_abs",
    "bounced_steps",
    "trajectory_steps",
    "solver_iterations",
    "reverse_trajectory_steps",
    "reverse_solver_iterations",
    "last_solver_stop_reason",
    "last_reverse_solver_stop_reason",
    "solver_stop_converged",
    "solver_stop_max_iter",
    "solver_stop_divergence",
    "solver_stop_stagnation",
    "solver_stop_not_run",
    "solver_stop_failure",
    "reverse_solver_stop_converged",
    "reverse_solver_stop_max_iter",
    "reverse_solver_stop_divergence",
    "reverse_solver_stop_stagnation",
    "reverse_solver_stop_not_run",
    "reverse_solver_stop_failure",
    "max_constraint_residual",
    "reverse_max_constraint_residual",
    "last_reverse_gate_state_error",
    "last_reverse_gate_momentum_error",
    "measurement_phase_coherence",
    "odex_calls",
    "odex_failure",
]


def initial_candidate_rows(cycles):
    return [
        {
            "label": "flat_eps0p0005_s5",
            "profile": "zero",
            "step_size": 0.0005,
            "num_steps": 5,
            "cycles": cycles,
            "t0": 0.0,
            "t1": 0.2,
            "d0": 0.0,
            "d1": 0.0,
            "gamma": 0.0,
        },
        {
            "label": "flat_eps0p001_s5",
            "profile": "zero",
            "step_size": 0.001,
            "num_steps": 5,
            "cycles": cycles,
            "t0": 0.0,
            "t1": 0.2,
            "d0": 0.0,
            "d1": 0.0,
            "gamma": 0.0,
        },
        {
            "label": "flat_eps0p003_s1",
            "profile": "zero",
            "step_size": 0.003,
            "num_steps": 1,
            "cycles": cycles,
            "t0": 0.0,
            "t1": 0.2,
            "d0": 0.0,
            "d1": 0.0,
            "gamma": 0.0,
        },
        {
            "label": "wall_g0p2_eps0p0005_s5",
            "profile": "paper_wall",
            "step_size": 0.0005,
            "num_steps": 5,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 0.2,
        },
        {
            "label": "wall_g1_eps0p0005_s5",
            "profile": "paper_wall",
            "step_size": 0.0005,
            "num_steps": 5,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 1.0,
        },
        {
            "label": "wall_g1_eps0p001_s5",
            "profile": "paper_wall",
            "step_size": 0.001,
            "num_steps": 5,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 1.0,
        },
        {
            "label": "wall_g1_eps0p001_s1",
            "profile": "paper_wall",
            "step_size": 0.001,
            "num_steps": 1,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 1.0,
        },
        {
            "label": "wall_g1_eps0p003_s1",
            "profile": "paper_wall",
            "step_size": 0.003,
            "num_steps": 1,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 1.0,
        },
    ]


def wall_epsilon_candidate_rows(cycles):
    rows = []
    for label, step_size, num_steps in [
        ("wall_g1_eps0p001_s1", 0.001, 1),
        ("wall_g1_eps0p002_s1", 0.002, 1),
        ("wall_g1_eps0p003_s1", 0.003, 1),
        ("wall_g1_eps0p005_s1", 0.005, 1),
        ("wall_g1_eps0p008_s1", 0.008, 1),
        ("wall_g1_eps0p002_s2", 0.002, 2),
        ("wall_g1_eps0p003_s2", 0.003, 2),
        ("wall_g1_eps0p005_s2", 0.005, 2),
    ]:
        rows.append({
            "label": label,
            "profile": "paper_wall",
            "step_size": step_size,
            "num_steps": num_steps,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 1.0,
            "grid": "wall_epsilon",
        })
    return rows


def wall_epsilon_acceptance_candidate_rows(cycles):
    rows = []
    for label, step_size, num_steps in [
        ("wall_g1_eps0p006_s2", 0.006, 2),
        ("wall_g1_eps0p010_s2", 0.010, 2),
        ("wall_g1_eps0p015_s2", 0.015, 2),
        ("wall_g1_eps0p020_s2", 0.020, 2),
        ("wall_g1_eps0p030_s2", 0.030, 2),
        ("wall_g1_eps0p040_s2", 0.040, 2),
        ("wall_g1_eps0p060_s2", 0.060, 2),
        ("wall_g1_eps0p080_s2", 0.080, 2),
        ("wall_g1_eps0p010_s4", 0.010, 4),
        ("wall_g1_eps0p015_s4", 0.015, 4),
        ("wall_g1_eps0p020_s4", 0.020, 4),
        ("wall_g1_eps0p030_s4", 0.030, 4),
    ]:
        rows.append({
            "label": label,
            "profile": "paper_wall",
            "step_size": step_size,
            "num_steps": num_steps,
            "cycles": cycles,
            "t0": 0.005,
            "t1": 0.2,
            "d0": 0.005,
            "d1": 0.05,
            "gamma": 1.0,
            "grid": "wall_epsilon_acceptance",
        })
    return rows


def candidate_rows(cycles, grid):
    if grid == "initial":
        rows = initial_candidate_rows(cycles)
    elif grid == "wall_epsilon":
        rows = wall_epsilon_candidate_rows(cycles)
    elif grid == "wall_epsilon_acceptance":
        rows = wall_epsilon_acceptance_candidate_rows(cycles)
    else:
        raise ValueError("unknown grid {0}".format(grid))
    for row in rows:
        row.setdefault("grid", grid)
    return rows


def read_one_row_csv(path):
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError("expected one row in {0}".format(path))
    return rows[0]


def run_candidate(binary, output_root, candidate, parameters_file, base_seed, flow_time, timeout_sec, rg_state_tol,
                  rg_momentum_tol, init_mode, init_sigma, init_bank_file, init_bank_record, newton_trace_enabled,
                  adaptive_newton_stop_enabled, constraint_tol, constraint_max_iter):
    label = candidate["label"]
    summary_path = output_root / (label + "_summary.csv")
    observable_path = output_root / (label + "_observables.csv")
    log_path = output_root / (label + ".log")
    newton_trace_path = output_root / (label + "_newton_trace.csv")
    env = os.environ.copy()
    env.update({
        "TLTM_PARAMETERS_FILE": str(parameters_file),
        "WV_HMC_SUMMARY_FILE": str(summary_path),
        "WV_HMC_OBSERVABLE_FILE": str(observable_path),
        "WV_HMC_BASE_SEED": str(base_seed),
        "WV_HMC_CYCLES": str(candidate["cycles"]),
        "WV_HMC_STEP_SIZE": str(candidate["step_size"]),
        "WV_HMC_NUM_STEPS": str(candidate["num_steps"]),
        "WV_HMC_FLOW_TIME": str(max(flow_time, candidate["t0"])),
        "WV_HMC_T0": str(candidate["t0"]),
        "WV_HMC_T1": str(candidate["t1"]),
        "WV_HMC_D0": str(candidate["d0"]),
        "WV_HMC_D1": str(candidate["d1"]),
        "WV_HMC_W_PROFILE": candidate["profile"],
        "WV_HMC_W_GAMMA": str(candidate["gamma"]),
        "WV_HMC_W_C0": "1.0",
        "WV_HMC_W_C1": "1.0",
        "WV_HMC_REVERSE_GATE_STATE_TOL": str(rg_state_tol),
        "WV_HMC_REVERSE_GATE_MOMENTUM_TOL": str(rg_momentum_tol),
        "WV_HMC_INIT_MODE": init_mode,
        "WV_HMC_INIT_SIGMA": str(init_sigma),
        "WV_HMC_ADAPTIVE_NEWTON_STOP_ENABLED": "1" if adaptive_newton_stop_enabled else "0",
        "WV_HMC_CONSTRAINT_TOL": str(constraint_tol),
        "WV_HMC_CONSTRAINT_MAX_ITER": str(constraint_max_iter),
    })
    if newton_trace_enabled:
        env["WV_HMC_NEWTON_TRACE_FILE"] = str(newton_trace_path)
    if init_bank_file:
        env["WV_HMC_INIT_BANK_FILE"] = str(init_bank_file)
    if init_bank_record >= 0:
        env["WV_HMC_INIT_BANK_RECORD"] = str(init_bank_record)
    start = time.time()
    timed_out = False
    return_code = None
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
            timed_out = True
            return_code = 124
            log_handle.write("\nTIMEOUT after {0} seconds\n".format(timeout_sec))
    runtime_sec = time.time() - start
    row = {
        "label": label,
        "grid": candidate["grid"],
        "profile": candidate["profile"],
        "step_size": candidate["step_size"],
        "num_steps": candidate["num_steps"],
        "trajectory_length": candidate["step_size"] * candidate["num_steps"],
        "cycles_requested": candidate["cycles"],
        "t1": candidate["t1"],
        "t0": candidate["t0"],
        "d0": candidate["d0"],
        "d1": candidate["d1"],
        "gamma": candidate["gamma"],
        "base_seed": base_seed,
        "init_mode": init_mode,
        "init_sigma": init_sigma,
        "init_bank_file": str(init_bank_file) if init_bank_file else "",
        "init_bank_record": init_bank_record,
        "parameters_file": str(parameters_file),
        "runtime_sec": runtime_sec,
        "timed_out": int(timed_out),
        "return_code": return_code,
        "summary_path": str(summary_path),
        "observable_path": str(observable_path),
        "newton_trace_path": str(newton_trace_path) if newton_trace_enabled else "",
        "log_path": str(log_path),
    }
    if summary_path.exists():
        summary = read_one_row_csv(summary_path)
        for key in SUMMARY_FIELDS:
            row[key] = summary.get(key, "")
    else:
        for key in SUMMARY_FIELDS:
            row[key] = ""
    return row


def int_value(row, key):
    try:
        return int(row.get(key, ""))
    except (TypeError, ValueError):
        return 0


def rate(numerator, denominator):
    if denominator <= 0:
        return ""
    return "{0:.6g}".format(float(numerator) / float(denominator))


def add_acceptance_rates(row):
    cycles = int_value(row, "cycles_completed")
    accepted = int_value(row, "accepted")
    metropolis_rejected = int_value(row, "metropolis_rejected")
    reverse_gate_rejected = int_value(row, "reverse_gate_rejected")
    transitions_failed = int_value(row, "transitions_failed")
    constructed = max(0, cycles - transitions_failed)
    reversible = max(0, constructed - reverse_gate_rejected)
    row["movement_accept_rate"] = rate(accepted, cycles)
    row["metropolis_reject_rate"] = rate(metropolis_rejected, cycles)
    row["reverse_gate_reject_rate"] = rate(reverse_gate_rejected, cycles)
    row["construction_failure_rate"] = rate(transitions_failed, cycles)
    row["constructed_movement_rate"] = rate(accepted, constructed)
    row["metropolis_accept_rate_after_rg"] = rate(accepted, reversible)
    return row


def write_scan_outputs(rows, output_root):
    csv_path = output_root / "dense_pilot_scan_summary.csv"
    fieldnames = [
        "label",
        "grid",
        "profile",
        "step_size",
        "num_steps",
        "trajectory_length",
        "cycles_requested",
        "t1",
        "t0",
        "d0",
        "d1",
        "gamma",
        "base_seed",
        "init_mode",
        "init_sigma",
        "init_bank_file",
        "init_bank_record",
        "parameters_file",
        "runtime_sec",
        "timed_out",
        "return_code",
        "newton_trace_path",
    ] + SUMMARY_FIELDS + [
        "movement_accept_rate",
        "metropolis_reject_rate",
        "reverse_gate_reject_rate",
        "construction_failure_rate",
        "constructed_movement_rate",
        "metropolis_accept_rate_after_rg",
        "summary_path",
        "observable_path",
        "log_path",
    ]
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    md_path = output_root / "dense_pilot_scan_readback.md"
    lines = [
        "# WV-HMC Dense Pilot Scan",
        "",
        "Scope: Stephanov n=2 dense backend, production reverse gate enabled.",
        "Grid: `{0}`.".format(rows[0].get("grid", "unknown") if rows else "unknown"),
        "Initialization: `{0}`, sigma `{1}`.".format(
            rows[0].get("init_mode", "unknown") if rows else "unknown",
            rows[0].get("init_sigma", "unknown") if rows else "unknown",
        ),
        "",
        "| label | profile | eps | nstep | L | cycles | timeout | move acc | metro rej/cyc | RG rej/cyc | fail/cyc | eff x2 | eff z2 | acc x2 | acc z2 | fwd it | rev it | fwd maxiter | rev maxiter | t mean | t max | phase | sec |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        def cell(key):
            return row.get(key, "")

        lines.append(
            "| {label} | {profile} | {eps} | {nstep} | {length} | {cycles} | {timeout} | {move_acc} | {metro_rate} | {rg_rate} | {fail_rate} | {eff_x2} | {eff_z2} | {acc_x2} | {acc_z2} | {solver_it} | {reverse_solver_it} | {solver_maxiter} | {reverse_solver_maxiter} | {tmean} | {tmax} | {phase} | {sec:.3g} |".format(
                label=cell("label"),
                profile=cell("profile"),
                eps=cell("step_size"),
                nstep=cell("num_steps"),
                length=cell("trajectory_length"),
                cycles=cell("cycles_completed"),
                timeout=cell("timed_out"),
                move_acc=cell("movement_accept_rate"),
                metro_rate=cell("metropolis_reject_rate"),
                rg_rate=cell("reverse_gate_reject_rate"),
                fail_rate=cell("construction_failure_rate"),
                eff_x2=cell("effective_x_jump_sq_mean"),
                eff_z2=cell("effective_z_jump_sq_mean"),
                acc_x2=cell("accepted_x_jump_sq_mean"),
                acc_z2=cell("accepted_z_jump_sq_mean"),
                solver_it=cell("solver_iterations"),
                reverse_solver_it=cell("reverse_solver_iterations"),
                solver_maxiter=cell("solver_stop_max_iter"),
                reverse_solver_maxiter=cell("reverse_solver_stop_max_iter"),
                tmean=cell("flow_time_mean"),
                tmax=cell("flow_time_max"),
                phase=cell("measurement_phase_coherence"),
                sec=float(row.get("runtime_sec", 0.0)),
            )
        )
    lines.extend([
        "",
        "Operational note: flat `W(t)` is expected to concentrate samples near small flow time.",
        "Tilted wall cases must retune `epsilon` and `L` rather than inheriting flat-W parameters.",
        "Tuning note: choose `epsilon` from Metropolis/movement behavior, while reverse-gate and construction failures are diagnostics for unusable points, not the primary target.",
        "",
        "Artifacts:",
        "- `{0}`".format(csv_path),
    ])
    md_path.write_text("\n".join(lines) + "\n")
    return csv_path, md_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="bin/run_wv_hmc")
    parser.add_argument("--output-root", default="output/wv_hmc_pilot_20260529/dense_scan")
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n2_smoke.dat")
    parser.add_argument("--grid", choices=["initial", "wall_epsilon", "wall_epsilon_acceptance"], default="initial")
    parser.add_argument("--cycles", type=int, default=100)
    parser.add_argument("--timeout-sec", type=float, default=20.0)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--base-seed", type=int, default=3001)
    parser.add_argument("--flow-time", type=float, default=1.0e-5)
    parser.add_argument("--rg-state-tol", type=float, default=1.0e-5)
    parser.add_argument("--rg-momentum-tol", type=float, default=1.0e-3)
    parser.add_argument("--init-mode", default="random_gaussian")
    parser.add_argument("--init-sigma", type=float, default=0.8)
    parser.add_argument("--init-bank-file", default="")
    parser.add_argument("--init-bank-record", type=int, default=-1)
    parser.add_argument("--newton-trace-enabled", action="store_true")
    parser.add_argument("--adaptive-newton-stop-enabled", action="store_true")
    parser.add_argument("--constraint-tol", type=float, default=1.0e-8)
    parser.add_argument("--constraint-max-iter", type=int, default=16)
    args = parser.parse_args()

    binary = Path(args.binary)
    parameters_file = Path(args.parameters_file)
    output_root = Path(args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    candidates = candidate_rows(args.cycles, args.grid)
    if args.jobs <= 1:
        rows = []
        for candidate in candidates:
            rows.append(
                run_candidate(
                    binary,
                    output_root,
                    candidate,
                    parameters_file,
                    args.base_seed,
                    args.flow_time,
                    args.timeout_sec,
                    args.rg_state_tol,
                    args.rg_momentum_tol,
                    args.init_mode,
                    args.init_sigma,
                    args.init_bank_file,
                    args.init_bank_record,
                    args.newton_trace_enabled,
                    args.adaptive_newton_stop_enabled,
                    args.constraint_tol,
                    args.constraint_max_iter,
                )
            )
    else:
        rows = [None] * len(candidates)
        with ProcessPoolExecutor(max_workers=args.jobs) as executor:
            futures = {}
            for idx, candidate in enumerate(candidates):
                future = executor.submit(
                    run_candidate,
                    binary,
                    output_root,
                    candidate,
                    parameters_file,
                    args.base_seed,
                    args.flow_time,
                    args.timeout_sec,
                    args.rg_state_tol,
                    args.rg_momentum_tol,
                    args.init_mode,
                    args.init_sigma,
                    args.init_bank_file,
                    args.init_bank_record,
                    args.newton_trace_enabled,
                    args.adaptive_newton_stop_enabled,
                    args.constraint_tol,
                    args.constraint_max_iter,
                )
                futures[future] = idx
            for future in as_completed(futures):
                rows[futures[future]] = future.result()
    rows = [add_acceptance_rates(row) for row in rows]
    csv_path, md_path = write_scan_outputs(rows, output_root)
    print("wrote {0}".format(csv_path))
    print("wrote {0}".format(md_path))


if __name__ == "__main__":
    main()
