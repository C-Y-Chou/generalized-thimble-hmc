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
    "bounced_steps",
    "trajectory_steps",
    "max_constraint_residual",
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


def candidate_rows(cycles, grid):
    if grid == "initial":
        rows = initial_candidate_rows(cycles)
    elif grid == "wall_epsilon":
        rows = wall_epsilon_candidate_rows(cycles)
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


def run_candidate(binary, output_root, candidate, parameters_file, base_seed, flow_time, timeout_sec, rg_state_tol, rg_momentum_tol):
    label = candidate["label"]
    summary_path = output_root / (label + "_summary.csv")
    observable_path = output_root / (label + "_observables.csv")
    log_path = output_root / (label + ".log")
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
    })
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
        "parameters_file": str(parameters_file),
        "runtime_sec": runtime_sec,
        "timed_out": int(timed_out),
        "return_code": return_code,
        "summary_path": str(summary_path),
        "observable_path": str(observable_path),
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
        "parameters_file",
        "runtime_sec",
        "timed_out",
        "return_code",
    ] + SUMMARY_FIELDS + ["summary_path", "observable_path", "log_path"]
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
        "",
        "| label | profile | eps | nstep | L | cycles | timeout | accepted | metro rej | RG rej | fail | t mean | t max | phase | sec |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        def cell(key):
            return row.get(key, "")

        lines.append(
            "| {label} | {profile} | {eps} | {nstep} | {length} | {cycles} | {timeout} | {acc} | {metro} | {rg} | {fail} | {tmean} | {tmax} | {phase} | {sec:.3g} |".format(
                label=cell("label"),
                profile=cell("profile"),
                eps=cell("step_size"),
                nstep=cell("num_steps"),
                length=cell("trajectory_length"),
                cycles=cell("cycles_completed"),
                timeout=cell("timed_out"),
                acc=cell("accepted"),
                metro=cell("metropolis_rejected"),
                rg=cell("reverse_gate_rejected"),
                fail=cell("transitions_failed"),
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
    parser.add_argument("--grid", choices=["initial", "wall_epsilon"], default="initial")
    parser.add_argument("--cycles", type=int, default=100)
    parser.add_argument("--timeout-sec", type=float, default=20.0)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--base-seed", type=int, default=3001)
    parser.add_argument("--flow-time", type=float, default=1.0e-5)
    parser.add_argument("--rg-state-tol", type=float, default=1.0e-5)
    parser.add_argument("--rg-momentum-tol", type=float, default=1.0e-3)
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
                )
                futures[future] = idx
            for future in as_completed(futures):
                rows[futures[future]] = future.result()
    csv_path, md_path = write_scan_outputs(rows, output_root)
    print("wrote {0}".format(csv_path))
    print("wrote {0}".format(md_path))


if __name__ == "__main__":
    main()
