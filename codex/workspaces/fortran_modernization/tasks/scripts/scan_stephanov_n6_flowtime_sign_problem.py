#!/usr/bin/env python3
"""Run a local Stephanov n=6 flow-time sign-problem ladder from a t=0 bank."""

import argparse
import csv
import os
import shutil
import subprocess
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
    parser = argparse.ArgumentParser(description="Run Stephanov n=6 flow-time sign-problem scans.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument(
        "--bank-file",
        default="output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/bank/x_bank.dat",
    )
    parser.add_argument("--output-root", default="output/stephanov_flowtime_sign_problem")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--flow-times", default="0,1e-7,3e-7,1e-6,3e-6")
    parser.add_argument("--records", default="0,81,162,243")
    parser.add_argument("--cycles", type=int, default=1000)
    parser.add_argument("--burn", type=int, default=100)
    parser.add_argument("--timeout-sec", type=int, default=900)
    parser.add_argument("--seed-base", type=int, default=8820000)
    parser.add_argument("--preflow-L", type=float, default=0.16)
    parser.add_argument("--preflow-nstep", type=int, default=2)
    parser.add_argument("--hmc-epsilon", type=float, default=None)
    parser.add_argument("--hmc-nstep", type=int, default=None)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def parse_int_list(text):
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def parse_float_list(text):
    return [float(item.strip()) for item in text.split(",") if item.strip()]


def label_float(value):
    return "{0:g}".format(value).replace(".", "p").replace("-", "m")


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


def write_parameters(base_text, out_path, flow_time, args):
    lines = base_text.splitlines()
    hmc_L = ""
    hmc_nstep = ""
    hmc_epsilon = ""
    if (args.hmc_epsilon is None) != (args.hmc_nstep is None):
        raise RuntimeError("--hmc-epsilon and --hmc-nstep must be supplied together")
    if args.hmc_epsilon is not None:
        if args.hmc_epsilon <= 0.0:
            raise RuntimeError("--hmc-epsilon must be positive")
        if args.hmc_nstep < 1:
            raise RuntimeError("--hmc-nstep must be >= 1")
        hmc_L = args.hmc_epsilon * args.hmc_nstep
        hmc_nstep = args.hmc_nstep
        hmc_epsilon = args.hmc_epsilon
        lines = set_param(lines, "trajectory_length", "{0:g}".format(hmc_L))
        lines = set_param(lines, "integration_steps", str(hmc_nstep))
    lines = set_param(lines, "initial_flow_time", "{0:g}".format(flow_time))
    lines = set_param(lines, "enable_quasi_fallback", "false")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return hmc_L, hmc_nstep, hmc_epsilon


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
    out = {
        "accepts": 0,
        "metropolis_reject": 0,
        "proposal_failure": 0,
        "hamiltonian_invalid": 0,
        "delta_h_invalid": 0,
        "samples": 0,
        "runtime_sec": 0.0,
    }
    if not Path(path).exists():
        return out
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
                out["accepts"] = int(parts[3])
                out["samples"] = int(parts[7])
                out["runtime_sec"] = float(parts[9])
                out["metropolis_reject"] = int(parts[10])
                out["proposal_failure"] = int(parts[12])
                out["hamiltonian_invalid"] = int(parts[13])
                out["delta_h_invalid"] = int(parts[14])
    return out


def read_x_records(path):
    values = array("d")
    file_size = Path(path).stat().st_size
    with Path(path).open("rb") as handle:
        values.fromfile(handle, file_size // 8)
    if len(values) % 72 != 0:
        raise RuntimeError("x history width mismatch: {0}".format(path))
    records = []
    for start in range(0, len(values), 72):
        records.append(values[start:start + 72])
    return records


def movement_metrics(x_path):
    if not Path(x_path).exists():
        return {"mean_step_norm2": 0.0, "nonzero_step_rate": 0.0, "move_norm2_sum": 0.0}
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


def read_observable_stream(path):
    values = array("d")
    file_size = Path(path).stat().st_size
    with Path(path).open("rb") as handle:
        values.fromfile(handle, file_size // 8)
    width = 2 * (1 + len(OBSERVABLE_NAMES))
    if len(values) % width != 0:
        raise RuntimeError("observable stream width mismatch: {0}".format(path))
    rows = []
    for start in range(0, len(values), width):
        record = values[start:start + width]
        phi = complex(float(record[0]), float(record[1]))
        obs = []
        for idx in range(len(OBSERVABLE_NAMES)):
            offset = 2 + 2 * idx
            obs.append(complex(float(record[offset]), float(record[offset + 1])))
        rows.append((phi, obs))
    return rows


def ratio_mean(phi_values, obs_values):
    den = sum(phi_values, complex(0.0, 0.0))
    if abs(den) == 0.0:
        return complex(float("nan"), float("nan"))
    num = sum((phi * obs for phi, obs in zip(phi_values, obs_values)), complex(0.0, 0.0))
    return num / den


def jackknife_error(values):
    n = len(values)
    if n < 2:
        return 0.0, 0.0
    mean_re = sum(value.real for value in values) / float(n)
    mean_im = sum(value.imag for value in values) / float(n)
    scale = (n - 1) / float(n)
    err_re = (scale * sum((value.real - mean_re) ** 2 for value in values)) ** 0.5
    err_im = (scale * sum((value.imag - mean_im) ** 2 for value in values)) ** 0.5
    return err_re, err_im


def jackknife_scalar_error(values):
    n = len(values)
    if n < 2:
        return 0.0
    mean_value = sum(values) / float(n)
    scale = (n - 1) / float(n)
    return (scale * sum((value - mean_value) ** 2 for value in values)) ** 0.5


def analyze_chains(chain_rows, burn):
    chain_stats = []
    total_phi = complex(0.0, 0.0)
    total_abs_phi = 0.0
    total_count = 0
    total_obs_num = [complex(0.0, 0.0) for _ in OBSERVABLE_NAMES]
    chain_phi_sums = []
    chain_phi_abs_sums = []
    chain_obs_nums = []

    for row in chain_rows:
        samples = read_observable_stream(row["observable_file"])
        used = samples[min(burn, len(samples)):]
        phi_values = [sample[0] for sample in used]
        obs_by_index = [[sample[1][idx] for sample in used] for idx in range(len(OBSERVABLE_NAMES))]
        phi_sum = sum(phi_values, complex(0.0, 0.0))
        abs_sum = sum(abs(phi) for phi in phi_values)
        obs_nums = [
            sum((phi * obs for phi, obs in zip(phi_values, obs_by_index[idx])), complex(0.0, 0.0))
            for idx in range(len(OBSERVABLE_NAMES))
        ]
        coherence = abs(phi_sum) / abs_sum if abs_sum > 0.0 else 0.0
        chiral = ratio_mean(phi_values, obs_by_index[0])
        density = ratio_mean(phi_values, obs_by_index[1])
        chain_stats.append(
            {
                **row,
                "raw_samples": len(samples),
                "used_samples": len(used),
                "phase_coherence": coherence,
                "phase_eff_frac": coherence * coherence,
                "phase_eff_n": len(used) * coherence * coherence,
                "chiral_re": chiral.real,
                "chiral_im": chiral.imag,
                "density_re": density.real,
                "density_im": density.imag,
            }
        )
        total_phi += phi_sum
        total_abs_phi += abs_sum
        total_count += len(used)
        for idx in range(len(OBSERVABLE_NAMES)):
            total_obs_num[idx] += obs_nums[idx]
        chain_phi_sums.append(phi_sum)
        chain_phi_abs_sums.append(abs_sum)
        chain_obs_nums.append(obs_nums)

    phase_coherence = abs(total_phi) / total_abs_phi if total_abs_phi > 0.0 else 0.0
    obs_means = [num / total_phi if abs(total_phi) > 0.0 else complex(float("nan"), float("nan")) for num in total_obs_num]

    phase_jk_values = []
    obs_jk_values = [[] for _ in OBSERVABLE_NAMES]
    n_chain = len(chain_phi_sums)
    for leave_out in range(n_chain):
        phi_sum = total_phi - chain_phi_sums[leave_out]
        abs_sum = total_abs_phi - chain_phi_abs_sums[leave_out]
        phase_jk_values.append(abs(phi_sum) / abs_sum if abs_sum > 0.0 else 0.0)
        for idx in range(len(OBSERVABLE_NAMES)):
            num = total_obs_num[idx] - chain_obs_nums[leave_out][idx]
            obs_jk_values[idx].append(num / phi_sum if abs(phi_sum) > 0.0 else complex(float("nan"), float("nan")))

    chiral_err_re, chiral_err_im = jackknife_error(obs_jk_values[0])
    density_err_re, density_err_im = jackknife_error(obs_jk_values[1])

    transitions = sum(row["accepts"] + row["metropolis_reject"] + row["proposal_failure"] for row in chain_stats)
    metropolis_transitions = sum(row["accepts"] + row["metropolis_reject"] for row in chain_stats)
    accepted = sum(row["accepts"] for row in chain_stats)
    proposal_failures = sum(row["proposal_failure"] for row in chain_stats)
    move_count = sum(max(0, int(row.get("samples", 0)) - 1) for row in chain_stats)
    move_sum = sum(float(row.get("move_norm2_sum", 0.0)) for row in chain_stats)
    nonzero_sum = sum(float(row.get("nonzero_step_rate", 0.0)) * max(0, int(row.get("samples", 0)) - 1) for row in chain_stats)
    return chain_stats, {
        "used_samples": total_count,
        "phase_coherence": phase_coherence,
        "phase_jk_err": jackknife_scalar_error(phase_jk_values),
        "phase_eff_frac": phase_coherence * phase_coherence,
        "phase_eff_n": total_count * phase_coherence * phase_coherence,
        "attempt_accept_rate": accepted / float(transitions) if transitions else 0.0,
        "valid_proposal_metropolis_accept_rate": accepted / float(metropolis_transitions) if metropolis_transitions else 0.0,
        "proposal_failure": proposal_failures,
        "proposal_failure_rate": proposal_failures / float(transitions) if transitions else 0.0,
        "accepted": accepted,
        "metropolis_reject": sum(row["metropolis_reject"] for row in chain_stats),
        "runtime_max_sec": max((row["runtime_sec"] for row in chain_stats), default=0.0),
        "mean_step_norm2": move_sum / float(move_count) if move_count else 0.0,
        "nonzero_step_rate": nonzero_sum / float(move_count) if move_count else 0.0,
        "chiral_re": obs_means[0].real,
        "chiral_im": obs_means[0].imag,
        "chiral_err_re": chiral_err_re,
        "chiral_err_im": chiral_err_im,
        "density_re": obs_means[1].real,
        "density_im": obs_means[1].imag,
        "density_err_re": density_err_re,
        "density_err_im": density_err_im,
    }


def run_chain(repo_root, run_dir, params_file, bank_file, flow_time, record_idx, chain_idx, args, hmc_L, hmc_nstep, hmc_epsilon):
    chain_dir = run_dir / ("t_{0}".format(label_float(flow_time))) / ("record_{0:04d}".format(record_idx))
    chain_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(
        {
            "TLTM_PARAMETERS_FILE": str(params_file),
            "CHAIN_RNG_SEED": str(args.seed_base + record_idx + 10000 * chain_idx),
            "TLTM_STAGE2_INITIAL_X_FILE": str(bank_file),
            "TLTM_STAGE2_INITIAL_X_RECORD": str(record_idx),
            "TLTM_STAGE2_INIT_MODE": "adaptive",
            "TLTM_STAGE2_INIT_PREFLOW_TRAJECTORY_LENGTH": "{0:g}".format(args.preflow_L),
            "TLTM_STAGE2_INIT_PREFLOW_INTEGRATION_STEPS": str(args.preflow_nstep),
            "TLTM_STAGE2_FLOW_TIME_LADDER": "{0:g}".format(flow_time),
            "TLTM_STAGE2_MAX_FLOW_TIME": "{0:g}".format(flow_time),
            "TLTM_STAGE2_NUM_REPLICAS": "1",
            "TLTM_STAGE2_CYCLES": str(args.cycles),
            "TLTM_STAGE2_LOCAL_UPDATES": "1",
            "TLTM_STAGE2_SWAP_ENABLED": "0",
            "TLTM_STAGE2_SUMMARY_FILE": str(chain_dir / "summary.dat"),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(chain_dir / "label_trace.dat"),
            "TLTM_STAGE2_COLD_OBSERVABLE_FILE": str(chain_dir / "observable_history.dat"),
            "TLTM_STAGE2_COLD_OBSERVABLE_STRIDE": "1",
            "TLTM_STAGE2_COLD_X_HISTORY_FILE": str(chain_dir / "x_history.dat"),
            "TLTM_STAGE2_COLD_X_HISTORY_STRIDE": "1",
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
            timeout=args.timeout_sec,
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
    summary = parse_summary(chain_dir / "summary.dat")
    movement = movement_metrics(chain_dir / "x_history.dat")
    return {
        "flow_time": flow_time,
        "record": record_idx,
        "chain_idx": chain_idx,
        "status": status,
        "elapsed_wall_sec": elapsed,
        "hmc_L": hmc_L,
        "hmc_nstep": hmc_nstep,
        "hmc_epsilon": hmc_epsilon,
        "observable_file": str(chain_dir / "observable_history.dat"),
        **summary,
        **movement,
    }


def write_csv(path, rows):
    if not rows:
        return
    with Path(path).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    params_file = (repo_root / args.base_parameters).resolve()
    bank_file = (repo_root / args.bank_file).resolve()
    output_root = Path(args.output_root)
    if not output_root.is_absolute():
        output_root = repo_root / output_root
    run_name = args.run_name or datetime.now(tz=timezone.utc).strftime("stephanov_n6_flowtime_%Y%m%dT%H%M%SZ")
    run_dir = output_root / run_name
    if run_dir.exists():
        if not args.force:
            raise RuntimeError("Run directory exists; use --force: {0}".format(run_dir))
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    params_dir = run_dir / "params"
    params_dir.mkdir(parents=True, exist_ok=True)
    records = parse_int_list(args.records)
    flow_times = parse_float_list(args.flow_times)
    run_build(repo_root, args.skip_build)
    base_text = params_file.read_text(encoding="utf-8")

    aggregate_rows = []
    detail_rows = []
    for flow_time in flow_times:
        flow_params_file = params_dir / ("flow_t_{0}.dat".format(label_float(flow_time)))
        hmc_L, hmc_nstep, hmc_epsilon = write_parameters(base_text, flow_params_file, flow_time, args)
        chain_rows = []
        for chain_idx, record_idx in enumerate(records):
            row = run_chain(
                repo_root, run_dir, flow_params_file, bank_file, flow_time, record_idx, chain_idx, args,
                hmc_L, hmc_nstep, hmc_epsilon,
            )
            chain_rows.append(row)
            detail_rows.append(row)
        if all(row["status"] == "done" and Path(row["observable_file"]).exists() for row in chain_rows):
            chain_stats, aggregate = analyze_chains(chain_rows, args.burn)
            detail_rows[-len(chain_rows):] = chain_stats
            status = "done"
        else:
            aggregate = {}
            status = ",".join(sorted(set(row["status"] for row in chain_rows)))
        aggregate_row = {
            "flow_time": flow_time,
            "status": status,
            "records": ";".join(str(record) for record in records),
            "cycles": args.cycles,
            "burn": args.burn,
            "preflow_L": args.preflow_L,
            "preflow_nstep": args.preflow_nstep,
            "hmc_L": hmc_L,
            "hmc_nstep": hmc_nstep,
            "hmc_epsilon": hmc_epsilon,
            **aggregate,
        }
        aggregate_rows.append(aggregate_row)
        print(
            "[FLOW] t={0:g} status={1} phase={2:.5f} attempt_acc={3:.3f} valid_met_acc={4:.3f} move={5:.3f} pfail={6}".format(
                flow_time,
                status,
                float(aggregate_row.get("phase_coherence", 0.0)),
                float(aggregate_row.get("attempt_accept_rate", 0.0)),
                float(aggregate_row.get("valid_proposal_metropolis_accept_rate", 0.0)),
                float(aggregate_row.get("mean_step_norm2", 0.0)),
                int(aggregate_row.get("proposal_failure", 0)),
            ),
            flush=True,
        )

    summary_path = run_dir / "flowtime_summary.csv"
    detail_path = run_dir / "flowtime_detail.csv"
    write_csv(summary_path, aggregate_rows)
    write_csv(detail_path, detail_rows)
    print(summary_path)


if __name__ == "__main__":
    main()
