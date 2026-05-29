#!/usr/bin/env python3
"""Run multi-seed dense WV-HMC observable validation candidates."""

from __future__ import print_function

import argparse
import csv
import os
import subprocess
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path


def run_seed(args):
    binary, output_root, parameters_file, seed, cycles, measurement_start_cycle, timeout_sec = args
    summary_path = output_root / "seed_{:05d}_summary.csv".format(seed)
    observable_path = output_root / "seed_{:05d}_observables.csv".format(seed)
    log_path = output_root / "seed_{:05d}.log".format(seed)
    env = os.environ.copy()
    env.update({
        "TLTM_PARAMETERS_FILE": str(parameters_file),
        "WV_HMC_SUMMARY_FILE": str(summary_path),
        "WV_HMC_OBSERVABLE_FILE": str(observable_path),
        "WV_HMC_BASE_SEED": str(seed),
        "WV_HMC_CYCLES": str(cycles),
        "WV_HMC_MEASUREMENT_START_CYCLE": str(measurement_start_cycle),
        "WV_HMC_STEP_SIZE": "0.002",
        "WV_HMC_NUM_STEPS": "2",
        "WV_HMC_FLOW_TIME": "0.005",
        "WV_HMC_T0": "0.005",
        "WV_HMC_T1": "0.2",
        "WV_HMC_D0": "0.005",
        "WV_HMC_D1": "0.05",
        "WV_HMC_MEASUREMENT_T0": "0.005",
        "WV_HMC_MEASUREMENT_T1": "0.2",
        "WV_HMC_INIT_MODE": "random_gaussian",
        "WV_HMC_INIT_SIGMA": "0.8",
        "WV_HMC_W_PROFILE": "paper_wall",
        "WV_HMC_W_GAMMA": "1.0",
        "WV_HMC_W_C0": "1.0",
        "WV_HMC_W_C1": "1.0",
        "WV_HMC_REVERSE_GATE_STATE_TOL": "1.0e-5",
        "WV_HMC_REVERSE_GATE_MOMENTUM_TOL": "1.0e-3",
    })
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
    return {
        "seed": seed,
        "cycles": cycles,
        "measurement_start_cycle": measurement_start_cycle,
        "runtime_sec": runtime_sec,
        "timed_out": timed_out,
        "return_code": return_code,
        "summary_path": str(summary_path),
        "observable_path": str(observable_path),
        "log_path": str(log_path),
        "summary_present": int(summary_path.exists()),
        "observable_present": int(observable_path.exists()),
    }


def write_manifest(rows, output_root):
    path = output_root / "wv_hmc_dense_observable_validation_manifest.csv"
    fieldnames = [
        "seed",
        "cycles",
        "measurement_start_cycle",
        "runtime_sec",
        "timed_out",
        "return_code",
        "summary_present",
        "observable_present",
        "summary_path",
        "observable_path",
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
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--timeout-sec", type=float, default=1200.0)
    args = parser.parse_args()

    binary = Path(args.binary)
    output_root = Path(args.output_root)
    parameters_file = Path(args.parameters_file)
    output_root.mkdir(parents=True, exist_ok=True)

    work = [
        (binary, output_root, parameters_file, args.seed_start + offset, args.cycles, args.measurement_start_cycle,
         args.timeout_sec)
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
    ]
    if failures:
        for row in failures[:20]:
            print("FAILED seed={seed} return_code={return_code} timed_out={timed_out} summary={summary_present} "
                  "observable={observable_present} log={log_path}".format(**row))
        raise SystemExit(3)


if __name__ == "__main__":
    main()
