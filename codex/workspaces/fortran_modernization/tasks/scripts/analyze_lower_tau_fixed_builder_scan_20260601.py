#!/usr/bin/env python3
"""Summarize lower fixed-tau builder scan candidates."""

import argparse
import csv
import math
from array import array
from pathlib import Path


DEFAULT_OUTPUT_ROOT = Path(
    "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/"
    "lower_tau_fixed_builder_scan_20260601"
)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--batch-name", default="lower_tau_fixed_builder_eps_scan_20260601")
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument("--state-size", type=int, default=72)
    parser.add_argument("--summary-csv", type=Path, default=None)
    parser.add_argument("--summary-md", type=Path, default=None)
    return parser.parse_args()


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def as_float(row, key, default=0.0):
    try:
        text = str(row.get(key, "")).strip()
        return float(text) if text else default
    except ValueError:
        return default


def as_int(row, key, default=0):
    try:
        text = str(row.get(key, "")).strip()
        return int(float(text)) if text else default
    except ValueError:
        return default


def summarize_x_history(path, state_size):
    result = {
        "x_samples": 0,
        "x_mean_step_rms_per_coord": "",
        "x_mean_step_norm": "",
        "x_start_end_rms_per_coord": "",
    }
    if not path.exists():
        return result
    values = array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) < state_size or len(values) % state_size != 0:
        result["x_samples"] = len(values) // state_size
        return result
    samples = len(values) // state_size
    result["x_samples"] = samples
    if samples < 2:
        return result
    step_sq_sum = 0.0
    step_count = 0
    norm_sum = 0.0
    for sample in range(1, samples):
        prev = (sample - 1) * state_size
        curr = sample * state_size
        dx2 = 0.0
        for offset in range(state_size):
            delta = values[curr + offset] - values[prev + offset]
            dx2 += delta * delta
        step_sq_sum += dx2 / float(state_size)
        norm_sum += math.sqrt(dx2)
        step_count += 1
    end_sq = 0.0
    last = (samples - 1) * state_size
    for offset in range(state_size):
        delta = values[last + offset] - values[offset]
        end_sq += delta * delta
    result["x_mean_step_rms_per_coord"] = math.sqrt(step_sq_sum / float(step_count))
    result["x_mean_step_norm"] = norm_sum / float(step_count)
    result["x_start_end_rms_per_coord"] = math.sqrt(end_sq / float(state_size))
    return result


def summarize_run(candidate, state_size):
    run_dir = Path(candidate["run_dir"])
    summary_path = run_dir / "tltm_ladder_summary.csv"
    rows = read_csv(summary_path) if summary_path.exists() else []
    total_accepted = sum(as_int(row, "accepted_local_total") for row in rows)
    total_failure = sum(as_int(row, "proposal_failure_total") for row in rows)
    total_rg = sum(as_int(row, "reverse_gate_reject_total") for row in rows)
    total_metropolis = sum(as_int(row, "metropolis_reject_total") for row in rows)
    attempts = total_accepted + total_failure + total_rg + total_metropolis
    status_counts = {}
    record_wall = []
    movement = []
    x_samples = 0
    for row in rows:
        status = row.get("status", "")
        status_counts[status] = status_counts.get(status, 0) + 1
        record_wall.append(as_float(row, "wall_sec"))
        record = as_int(row, "record")
        x_summary = summarize_x_history(
            run_dir / "records" / "record_{0:04d}".format(record) / "x_history.dat",
            state_size,
        )
        x_samples += int(x_summary["x_samples"])
        if x_summary["x_mean_step_rms_per_coord"] != "":
            movement.append(x_summary)
    movement_count = len(movement)
    mean_step_rms = (
        sum(float(item["x_mean_step_rms_per_coord"]) for item in movement) / float(movement_count)
        if movement_count
        else ""
    )
    mean_step_norm = (
        sum(float(item["x_mean_step_norm"]) for item in movement) / float(movement_count)
        if movement_count
        else ""
    )
    mean_start_end_rms = (
        sum(float(item["x_start_end_rms_per_coord"]) for item in movement) / float(movement_count)
        if movement_count
        else ""
    )
    cycles = as_int(candidate, "cycles")
    records = [item for item in str(candidate.get("records", "")).split(",") if item.strip()]
    row = {
        "candidate_id": candidate.get("candidate_id", ""),
        "tau": candidate.get("tau", ""),
        "epsilon": candidate.get("epsilon", ""),
        "nstep": candidate.get("nstep", ""),
        "hmc_L": candidate.get("hmc_L", ""),
        "cycles": cycles,
        "record_count": len(records),
        "statuses": ";".join("{}:{}".format(key, status_counts[key]) for key in sorted(status_counts)),
        "attempts": attempts,
        "accepted": total_accepted,
        "metropolis_reject": total_metropolis,
        "reverse_gate_reject": total_rg,
        "proposal_failure": total_failure,
        "accept_rate": total_accepted / float(attempts) if attempts else "",
        "metropolis_reject_rate": total_metropolis / float(attempts) if attempts else "",
        "reverse_gate_reject_rate": total_rg / float(attempts) if attempts else "",
        "proposal_failure_rate": total_failure / float(attempts) if attempts else "",
        "max_record_wall_sec": max(record_wall) if record_wall else "",
        "mean_record_wall_sec": sum(record_wall) / float(len(record_wall)) if record_wall else "",
        "max_record_sec_per_cycle": max(record_wall) / float(cycles) if record_wall and cycles else "",
        "x_samples": x_samples,
        "x_mean_step_rms_per_coord": mean_step_rms,
        "x_mean_step_norm": mean_step_norm,
        "x_start_end_rms_per_coord": mean_start_end_rms,
        "run_dir": str(run_dir),
    }
    return row


def write_csv(path, rows):
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def format_value(value):
    if value == "":
        return ""
    try:
        return "{:.6g}".format(float(value))
    except (TypeError, ValueError):
        return str(value)


def write_markdown(path, rows, manifest_path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Lower fixed-tau builder scan",
        "",
        "Source manifest: `{}`".format(manifest_path),
        "",
        "Interpretation rule: proposal failures are treated as a solver/flow safety warning for the proposed lower fixed-tau bank-builder point, not as a production-quality metric.",
        "",
        "| candidate | tau | epsilon | nstep | L | status | accept | proposal fail | reverse gate | step rms/coord | end-start rms/coord | sec/cycle |",
        "|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| {candidate_id} | {tau} | {epsilon} | {nstep} | {hmc_L} | {statuses} | {accept_rate} | {proposal_failure_rate} | {reverse_gate_reject_rate} | {x_mean_step_rms_per_coord} | {x_start_end_rms_per_coord} | {max_record_sec_per_cycle} |".format(
                **{key: format_value(value) for key, value in row.items()}
            )
        )
    lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    manifest = args.manifest or (args.output_root / args.batch_name / "candidate_manifest.csv")
    candidates = read_csv(manifest)
    rows = [summarize_run(candidate, args.state_size) for candidate in candidates]
    out_csv = args.summary_csv or (args.output_root / args.batch_name / "lower_tau_fixed_builder_scan_summary.csv")
    out_md = args.summary_md or (args.output_root / args.batch_name / "lower_tau_fixed_builder_scan_readback.md")
    write_csv(out_csv, rows)
    write_markdown(out_md, rows, manifest)
    print("summary_csv={}".format(out_csv))
    print("summary_md={}".format(out_md))
    for row in rows:
        print(
            "{candidate_id} tau={tau} eps={epsilon} nstep={nstep} L={hmc_L} status={statuses} acc={accept_rate} fail={proposal_failure_rate} step={x_mean_step_rms_per_coord}".format(
                **{key: format_value(value) for key, value in row.items()}
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
