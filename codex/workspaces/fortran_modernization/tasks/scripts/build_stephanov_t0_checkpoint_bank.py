#!/usr/bin/env python3
"""Build a local t=0 Stephanov checkpoint bank from Stage2 chains."""

import argparse
import csv
import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import time
from array import array
from datetime import datetime, timezone
from pathlib import Path


OBSERVABLE_NAMES = [
    "chiral_condensate",
    "number_density",
    "logdet_dirac",
    "phase_factor",
    "min_singular_ba_m2",
]


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Build a Stephanov n=6 t=0 checkpoint bank.")
    parser.add_argument("--repo-root", default=str(repo_root), help="Repository root.")
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t0.dat")
    parser.add_argument("--stage2-bin", default="bin/run_tltm_stage2")
    parser.add_argument("--output-root", default="output/stephanov_checkpoint_banks")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--chains", type=int, default=4)
    parser.add_argument("--cycles", type=int, default=1000)
    parser.add_argument("--history-stride", type=int, default=10)
    parser.add_argument("--burn-records", type=int, default=20)
    parser.add_argument("--seed-base", type=int, default=8606000)
    parser.add_argument("--init-sigma", type=float, default=0.1)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    return parser.parse_args()


def relpath(repo_root, path):
    try:
        return str(Path(path).relative_to(repo_root))
    except ValueError:
        return str(path)


def run_build(repo_root, skip_build):
    if skip_build:
        return
    cmd = ["make", "-C", str(repo_root / "build"), "../bin/run_tltm_stage2"]
    proc = subprocess.run(
        cmd,
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        sys.stdout.write(proc.stdout)
        raise RuntimeError("Stage2 build failed")


def start_chain(repo_root, stage2_bin, base_parameters, run_dir, chain_id, seed, args):
    chain_dir = run_dir / "chains" / ("chain_{0:02d}".format(chain_id))
    chain_dir.mkdir(parents=True, exist_ok=True)
    log_path = chain_dir / "run.log"
    env = os.environ.copy()
    env.update(
        {
            "TLTM_PARAMETERS_FILE": str(base_parameters),
            "CHAIN_RNG_SEED": str(seed),
            "TLTM_STAGE2_FLOW_TIME_LADDER": "0.0",
            "TLTM_STAGE2_MAX_FLOW_TIME": "0.0",
            "TLTM_STAGE2_NUM_REPLICAS": "1",
            "TLTM_STAGE2_CYCLES": str(args.cycles),
            "TLTM_STAGE2_LOCAL_UPDATES": "1",
            "TLTM_STAGE2_INIT_SIGMA": "{0:g}".format(args.init_sigma),
            "TLTM_STAGE2_SWAP_ENABLED": "0",
            "TLTM_STAGE2_HISTORY_STRIDE": str(args.history_stride),
            "TLTM_STAGE2_OBSERVABLE_STRIDE": str(args.history_stride),
            "TLTM_STAGE2_SUMMARY_FILE": str(chain_dir / "summary.dat"),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(chain_dir / "label_trace.dat"),
            "TLTM_STAGE2_COLD_X_HISTORY_FILE": str(chain_dir / "x_history.dat"),
            "TLTM_STAGE2_COLD_Z_HISTORY_FILE": str(chain_dir / "z_history.dat"),
            "TLTM_STAGE2_COLD_PHI_HISTORY_FILE": str(chain_dir / "phi_history.dat"),
            "TLTM_STAGE2_COLD_OBSERVABLE_FILE": str(chain_dir / "observable_history.dat"),
            "TLTM_STAGE2_V1_OUTPUT_DIR": str(chain_dir / "v1"),
            "TLTM_STAGE2_RNG_STREAM_CONTRACT": "stage2_kernel_rng_v2",
            "CONSTRAINT_FAIL_CAPTURE_START_SAMPLE": "2147483647",
        }
    )
    log_handle = log_path.open("w", encoding="utf-8")
    proc = subprocess.Popen(
        [str(stage2_bin)],
        cwd=str(repo_root),
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return {
        "chain_id": chain_id,
        "seed": seed,
        "dir": chain_dir,
        "log": log_path,
        "process": proc,
        "log_handle": log_handle,
        "start": time.monotonic(),
    }


def wait_chains(chains):
    alive = set(range(len(chains)))
    while alive:
        finished = []
        for idx in list(alive):
            proc = chains[idx]["process"]
            code = proc.poll()
            if code is not None:
                chains[idx]["returncode"] = code
                chains[idx]["elapsed"] = time.monotonic() - chains[idx]["start"]
                chains[idx]["log_handle"].close()
                finished.append(idx)
        for idx in finished:
            alive.remove(idx)
        if alive:
            counts = []
            for chain in chains:
                x_file = chain["dir"] / "x_history.dat"
                counts.append(sample_count_from_bytes(x_file, 72, 8) if x_file.exists() else 0)
            print("[BANK][PROGRESS] samples_by_chain={0}".format(",".join(str(x) for x in counts)), flush=True)
            time.sleep(10.0)
    failures = [chain for chain in chains if chain.get("returncode", 0) != 0]
    if failures:
        for chain in failures:
            print("[BANK][FAIL] chain={0} returncode={1} log={2}".format(
                chain["chain_id"], chain.get("returncode"), chain["log"]
            ))
        raise RuntimeError("One or more bank chains failed")


def sample_count_from_bytes(path, values_per_record, bytes_per_value):
    size = Path(path).stat().st_size
    record_bytes = values_per_record * bytes_per_value
    if record_bytes <= 0 or size % record_bytes != 0:
        raise RuntimeError("Unexpected file size for {0}: {1}".format(path, size))
    return size // record_bytes


def read_real_records(path, width):
    values = array("d")
    with Path(path).open("rb") as handle:
        values.fromfile(handle, Path(path).stat().st_size // 8)
    if len(values) % width != 0:
        raise RuntimeError("Real stream width mismatch for {0}".format(path))
    out = []
    for start in range(0, len(values), width):
        out.append(list(values[start:start + width]))
    return out


def read_complex_records(path, complex_width):
    values = array("d")
    with Path(path).open("rb") as handle:
        values.fromfile(handle, Path(path).stat().st_size // 8)
    width = 2 * complex_width
    if len(values) % width != 0:
        raise RuntimeError("Complex stream width mismatch for {0}".format(path))
    out = []
    for start in range(0, len(values), width):
        row = []
        for idx in range(complex_width):
            row.append(complex(values[start + 2 * idx], values[start + 2 * idx + 1]))
        out.append(row)
    return out


def mean(values):
    if not values:
        return None
    return sum(values) / float(len(values))


def stdev(values):
    if len(values) < 2:
        return None
    return statistics.stdev(values)


def quantile(values, q):
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    pos = q * (len(ordered) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return ordered[lo]
    frac = pos - lo
    return (1.0 - frac) * ordered[lo] + frac * ordered[hi]


def rhat(chains):
    nonempty = [list(chain) for chain in chains if len(chain) >= 2]
    if len(nonempty) < 2:
        return None
    n = min(len(chain) for chain in nonempty)
    if n < 2:
        return None
    trimmed = [chain[-n:] for chain in nonempty]
    means = [mean(chain) for chain in trimmed]
    variances = [statistics.variance(chain) for chain in trimmed]
    w = mean(variances)
    if w is None or w <= 0.0:
        return None
    mean_all = mean(means)
    b = n * sum((m - mean_all) ** 2 for m in means) / float(len(means) - 1)
    var_hat = ((n - 1.0) / n) * w + b / n
    if var_hat < 0.0:
        return None
    return math.sqrt(var_hat / w)


def parse_slot_summary(summary_path):
    lines = Path(summary_path).read_text(encoding="utf-8", errors="replace").splitlines()
    for idx, line in enumerate(lines):
        if line.startswith("# [slots]") and idx + 1 < len(lines):
            parts = lines[idx + 1].split()
            if len(parts) >= 15:
                return {
                    "accepts": int(parts[3]),
                    "rejects": int(parts[4]),
                    "accept_rate": float(parts[5]),
                    "samples": int(parts[7]),
                    "runtime_sec": float(parts[9]),
                    "metropolis_reject": int(parts[10]),
                    "proposal_failure": int(parts[12]),
                }
    return {}


def summarize_and_write_bank(repo_root, run_dir, chains, args):
    bank_dir = run_dir / "bank"
    bank_dir.mkdir(parents=True, exist_ok=True)
    x_bank_file = bank_dir / "x_bank.dat"
    index_file = bank_dir / "x_bank_index.csv"
    summary_csv = bank_dir / "bank_summary.csv"
    coverage_json = bank_dir / "coverage_summary.json"

    scalar_by_chain = {
        "x_norm2": [],
        "chiral_re": [],
        "chiral_im": [],
        "density_re": [],
        "density_im": [],
        "logdet_re": [],
        "logdet_im": [],
        "min_singular_re": [],
    }
    chain_rows = []
    selected_total = 0
    pooled = {key: [] for key in scalar_by_chain}
    phase_values = []

    with x_bank_file.open("wb") as x_out, index_file.open("w", newline="", encoding="utf-8") as idx_handle:
        idx_writer = csv.DictWriter(idx_handle, fieldnames=["bank_index", "chain_id", "seed", "record_index", "cycle"])
        idx_writer.writeheader()
        for chain in chains:
            chain_id = chain["chain_id"]
            seed = chain["seed"]
            chain_dir = chain["dir"]
            x_records = read_real_records(chain_dir / "x_history.dat", 72)
            obs_records = read_complex_records(chain_dir / "observable_history.dat", 1 + len(OBSERVABLE_NAMES))
            if len(x_records) != len(obs_records):
                raise RuntimeError("x/observable sample mismatch for chain {0}".format(chain_id))
            start_record = min(max(0, args.burn_records), len(x_records))
            selected_x = x_records[start_record:]
            selected_obs = obs_records[start_record:]
            chain_scalars = {key: [] for key in scalar_by_chain}
            chain_phase = []
            for local_idx, (x_row, obs_row) in enumerate(zip(selected_x, selected_obs)):
                record_index = start_record + local_idx
                x_array = array("d", x_row)
                x_array.tofile(x_out)
                idx_writer.writerow(
                    {
                        "bank_index": selected_total,
                        "chain_id": chain_id,
                        "seed": seed,
                        "record_index": record_index,
                        "cycle": record_index * args.history_stride,
                    }
                )
                selected_total += 1
                phi = obs_row[0]
                obs = obs_row[1:]
                scalars = {
                    "x_norm2": sum(x * x for x in x_row),
                    "chiral_re": obs[0].real,
                    "chiral_im": obs[0].imag,
                    "density_re": obs[1].real,
                    "density_im": obs[1].imag,
                    "logdet_re": obs[2].real,
                    "logdet_im": obs[2].imag,
                    "min_singular_re": obs[4].real,
                }
                for key, value in scalars.items():
                    chain_scalars[key].append(value)
                    pooled[key].append(value)
                chain_phase.append(phi)
                phase_values.append(phi)
            for key in scalar_by_chain:
                scalar_by_chain[key].append(chain_scalars[key])
            slot_summary = parse_slot_summary(chain_dir / "summary.dat")
            phase_mean = sum(chain_phase, complex(0.0, 0.0)) / float(len(chain_phase)) if chain_phase else complex(0.0, 0.0)
            chain_rows.append(
                {
                    "chain_id": chain_id,
                    "seed": seed,
                    "raw_records": len(x_records),
                    "used_records": len(selected_x),
                    "accept_rate": slot_summary.get("accept_rate", ""),
                    "proposal_failure": slot_summary.get("proposal_failure", ""),
                    "runtime_sec": slot_summary.get("runtime_sec", ""),
                    "phase_coherence": abs(phase_mean),
                    "x_norm2_mean": mean(chain_scalars["x_norm2"]),
                    "x_norm2_q05": quantile(chain_scalars["x_norm2"], 0.05),
                    "x_norm2_q50": quantile(chain_scalars["x_norm2"], 0.50),
                    "x_norm2_q95": quantile(chain_scalars["x_norm2"], 0.95),
                    "chiral_re_mean": mean(chain_scalars["chiral_re"]),
                    "density_re_mean": mean(chain_scalars["density_re"]),
                    "min_singular_q05": quantile(chain_scalars["min_singular_re"], 0.05),
                }
            )

    with summary_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(chain_rows[0].keys()))
        writer.writeheader()
        for row in chain_rows:
            writer.writerow(row)

    phase_mean = sum(phase_values, complex(0.0, 0.0)) / float(len(phase_values)) if phase_values else complex(0.0, 0.0)
    tail_checks = {}
    for key, values in pooled.items():
        q05 = quantile(values, 0.05)
        q95 = quantile(values, 0.95)
        deviations = []
        for chain_values in scalar_by_chain[key]:
            if not chain_values:
                continue
            below = sum(1 for value in chain_values if value < q05) / float(len(chain_values))
            above = sum(1 for value in chain_values if value > q95) / float(len(chain_values))
            deviations.append(max(abs(below - 0.05), abs(above - 0.05)))
        tail_checks[key] = {
            "q05": q05,
            "q50": quantile(values, 0.50),
            "q95": q95,
            "max_tail_occupancy_deviation": max(deviations) if deviations else None,
        }

    coverage = {
        "schema": "stephanov_t0_checkpoint_bank.v1",
        "created_utc": datetime.now(tz=timezone.utc).isoformat(),
        "run_dir": relpath(repo_root, run_dir),
        "x_bank_file": relpath(repo_root, x_bank_file),
        "index_file": relpath(repo_root, index_file),
        "summary_csv": relpath(repo_root, summary_csv),
        "n_state": 72,
        "chains": args.chains,
        "cycles": args.cycles,
        "history_stride": args.history_stride,
        "burn_records": args.burn_records,
        "selected_checkpoints": selected_total,
        "phase_coherence": abs(phase_mean),
        "rhat": {key: rhat(values) for key, values in scalar_by_chain.items()},
        "tail_checks": tail_checks,
        "chain_rows": chain_rows,
    }
    coverage_json.write_text(json.dumps(coverage, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return coverage


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    base_parameters = (repo_root / args.base_parameters).resolve()
    stage2_bin = (repo_root / args.stage2_bin).resolve()
    output_root = Path(args.output_root)
    if not output_root.is_absolute():
        output_root = repo_root / output_root
    run_name = args.run_name or datetime.now(tz=timezone.utc).strftime("stephanov_n6_t0_bank_%Y%m%dT%H%M%SZ")
    run_dir = output_root / run_name
    if run_dir.exists():
        if not args.force:
            raise RuntimeError("Run directory exists; use --force: {0}".format(run_dir))
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)

    if args.chains < 1:
        raise RuntimeError("--chains must be >= 1")
    if args.cycles < 1:
        raise RuntimeError("--cycles must be >= 1")
    if args.history_stride < 1:
        raise RuntimeError("--history-stride must be >= 1")

    run_build(repo_root, args.skip_build)
    chains = []
    for chain_id in range(args.chains):
        seed = args.seed_base + chain_id
        chains.append(start_chain(repo_root, stage2_bin, base_parameters, run_dir, chain_id, seed, args))
    wait_chains(chains)
    coverage = summarize_and_write_bank(repo_root, run_dir, chains, args)
    print(json.dumps({
        "run_dir": coverage["run_dir"],
        "x_bank_file": coverage["x_bank_file"],
        "selected_checkpoints": coverage["selected_checkpoints"],
        "phase_coherence": coverage["phase_coherence"],
        "rhat": coverage["rhat"],
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
