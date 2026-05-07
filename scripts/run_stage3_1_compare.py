#!/usr/bin/env python3

import argparse
import csv
import json
import os
import subprocess
from collections import OrderedDict
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description="Run stage-3.1 matched-control compare (fallback off vs on).")
    p.add_argument("--repo-root", default=".", help="Path to repo root.")
    p.add_argument("--cycles", type=int, default=120, help="Cycle count for both controls.")
    p.add_argument("--seed", type=int, default=20260421, help="Fixed seed for both controls.")
    return p.parse_args()


def read_reference(repo_root):
    ref_path = repo_root / "docs" / "stage_2p5_reference_ladder.json"
    with ref_path.open() as f:
        ref = json.load(f)["stage_2p5_reference_ladder"]
    ladder = ref["flow_time_ladder"]
    local = ref["frozen_global_local_parameters"]
    return ladder, local["trajectory_length_L"], local["integration_steps_nstep"], local["local_updates_per_cycle"], ref_path


def update_parameters_file(parameters_path, fallback_enabled, traj_len, nstep):
    original = parameters_path.read_text()
    lines = original.splitlines()

    def set_key(lines_in, key, value):
        out = []
        found = False
        for line in lines_in:
            stripped = line.strip().lower()
            if stripped.startswith(key + " ") or stripped.startswith(key + "="):
                out.append("{0} = {1}".format(key, value))
                found = True
            else:
                out.append(line)
        if not found:
            out.append("{0} = {1}".format(key, value))
        return out

    lines = set_key(lines, "trajectory_length", str(traj_len))
    lines = set_key(lines, "integration_steps", str(nstep))
    lines = set_key(lines, "enable_quasi_fallback", "true" if fallback_enabled else "false")
    parameters_path.write_text("\n".join(lines) + "\n")
    return original


def run_case(repo_root, mode_name, fallback_enabled, seed, cycles, ladder, local_updates):
    build_dir = repo_root / "build"
    out_dir = repo_root / "output" / "tests" / "stage3_1"
    log_dir = repo_root / "output" / "logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    summary_file = out_dir / (mode_name + "_summary.dat")
    label_trace_file = out_dir / (mode_name + "_label_trace.dat")
    run_log_file = log_dir / ("tltm_stage3_1_" + mode_name + ".log")

    env = dict(os.environ)
    env.update(
        {
            "CHAIN_RNG_SEED": str(seed),
            "TLTM_STAGE2_FLOW_TIME_LADDER": ",".join("{0:g}".format(x) for x in ladder),
            "TLTM_STAGE2_NUM_REPLICAS": str(len(ladder)),
            "TLTM_STAGE2_CYCLES": str(cycles),
            "TLTM_STAGE2_LOCAL_UPDATES": str(local_updates),
            "TLTM_STAGE2_SWAP_ENABLED": "1",
            "TLTM_STAGE2_SUMMARY_FILE": str(summary_file),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(label_trace_file),
        }
    )

    cmd = ["make", "-C", str(build_dir), "tltm_stage2"]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, env=env, check=False)
    run_log_file.write_text(proc.stdout)
    if proc.returncode != 0:
        raise RuntimeError("Run failed for {0}. Check {1}".format(mode_name, run_log_file))

    return summary_file, label_trace_file, run_log_file


def parse_summary(path):
    text = path.read_text().splitlines()
    section = None
    slots = []
    pairs = []
    labels = []
    total_round_trip = 0
    fallback_stats = {
        "calls_total": 0,
        "calls_integrating": 0,
        "fallback_attempts": 0,
        "fallback_success": 0,
        "fallback_failure": 0,
        "fallback_max_steps": 0,
        "fallback_invalid": 0,
        "fallback_h_min": 0,
    }
    constraint_stats = {
        "total": 0,
        "newton": 0,
        "quasi": 0,
        "failed": 0,
    }
    quasi_stage_stats = {
        "probe_attempt": 0,
        "probe_success": 0,
        "full_attempt": 0,
        "full_success": 0,
    }

    for raw in text:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("# total_round_trip="):
            total_round_trip = int(line.split("=", 1)[1])
            continue
        if line.startswith("# fallback_stats "):
            stats_text = line[len("# fallback_stats ") :]
            tokenized = stats_text.replace("=", " ").split()
            pairs_kv = zip(tokenized[0::2], tokenized[1::2])
            for k, v in pairs_kv:
                if k == "attempts":
                    fallback_stats["fallback_attempts"] = int(v)
                elif k == "success":
                    fallback_stats["fallback_success"] = int(v)
                elif k == "failure":
                    fallback_stats["fallback_failure"] = int(v)
                elif k == "max_steps":
                    fallback_stats["fallback_max_steps"] = int(v)
                elif k == "invalid":
                    fallback_stats["fallback_invalid"] = int(v)
                elif k == "h_min":
                    fallback_stats["fallback_h_min"] = int(v)
                elif k == "calls_total":
                    fallback_stats["calls_total"] = int(v)
                elif k == "calls_integrating":
                    fallback_stats["calls_integrating"] = int(v)
            continue
        if line.startswith("# constraint_stats "):
            stats_text = line[len("# constraint_stats ") :]
            tokenized = stats_text.replace("=", " ").split()
            for k, v in zip(tokenized[0::2], tokenized[1::2]):
                if k in constraint_stats:
                    constraint_stats[k] = int(v)
            continue
        if line.startswith("# quasi_stage_stats "):
            stats_text = line[len("# quasi_stage_stats ") :]
            tokenized = stats_text.replace("=", " ").split()
            for k, v in zip(tokenized[0::2], tokenized[1::2]):
                if k in quasi_stage_stats:
                    quasi_stage_stats[k] = int(v)
            continue
        if line.startswith("# [slots]"):
            section = "slots"
            continue
        if line.startswith("# [pairs]"):
            section = "pairs"
            continue
        if line.startswith("# [labels]"):
            section = "labels"
            continue
        if line.startswith("#"):
            continue

        parts = line.split()
        if section == "slots" and len(parts) >= 10:
            slots.append(
                {
                    "slot_id": int(parts[0]),
                    "accepts": int(parts[3]),
                    "rejects": int(parts[4]),
                    "projection_fail": int(parts[6]),
                }
            )
        elif section == "pairs" and len(parts) >= 7:
            pairs.append({"pair_id": int(parts[0]), "accept_rate": float(parts[6])})
        elif section == "labels" and len(parts) >= 4:
            labels.append({"label_id": int(parts[0]), "farthest": int(parts[2]), "round_trip_count": int(parts[3])})

    total_accepts = sum(s["accepts"] for s in slots)
    total_rejects = sum(s["rejects"] for s in slots)
    total_projection_fail = sum(s["projection_fail"] for s in slots)
    local_accept_rate = float(total_accepts) / float(max(1, total_accepts + total_rejects))
    pair0 = next((p["accept_rate"] for p in pairs if p["pair_id"] == 0), 0.0)
    min_pair_accept = min((p["accept_rate"] for p in pairs), default=0.0)
    hot_end_hit_count = sum(1 for l in labels if l["farthest"] == max((x["farthest"] for x in labels), default=0))

    out = OrderedDict()
    out["local_accept_rate"] = local_accept_rate
    out["projection_failure_count"] = total_projection_fail
    out["fallback_trigger_count"] = quasi_stage_stats["probe_attempt"] + quasi_stage_stats["full_attempt"]
    out["unresolved_failure_count"] = constraint_stats["failed"]
    out["intode_fallback_attempts"] = fallback_stats["fallback_attempts"]
    out["pair0_accept_rate"] = pair0
    out["min_pair_accept_rate"] = min_pair_accept
    out["hot_end_hit_count"] = hot_end_hit_count
    out["round_trip_count"] = total_round_trip
    out["farthest_slot_reached_max"] = max((l["farthest"] for l in labels), default=0)
    return out


def write_report(repo_root, no_fb, fb, seed, cycles, ladder, reference_path):
    out_dir = repo_root / "output" / "tests" / "stage3_1"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "s3_1_comparison.csv"
    md_path = out_dir / "s3_1_report.md"

    with csv_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["metric", "no_fb", "fb", "delta_fb_minus_no_fb"])
        for k in no_fb.keys():
            writer.writerow([k, no_fb[k], fb[k], fb[k] - no_fb[k]])

    lines = [
        "# Stage-3.1 Report (Fallback OFF vs ON)",
        "",
        "- ladder: `{0}`".format(",".join("{0:g}".format(x) for x in ladder)),
        "- seed: `{0}`".format(seed),
        "- cycles: `{0}`".format(cycles),
        "- reference: `{0}`".format(reference_path.relative_to(repo_root)),
        "",
        "| metric | no_fb | fb | delta (fb-no_fb) |",
        "|---|---:|---:|---:|",
    ]
    for k in no_fb.keys():
        lines.append("| {0} | {1:.6g} | {2:.6g} | {3:.6g} |".format(k, no_fb[k], fb[k], fb[k] - no_fb[k]))
    lines.append("")
    lines.append("Artifacts:")
    lines.append("- `output/tests/stage3_1/no_fb_summary.dat`")
    lines.append("- `output/tests/stage3_1/fb_summary.dat`")
    lines.append("- `output/logs/tltm_stage3_1_no_fb.log`")
    lines.append("- `output/logs/tltm_stage3_1_fb.log`")
    lines.append("- `output/tests/stage3_1/s3_1_comparison.csv`")
    md_path.write_text("\n".join(lines) + "\n")

    return csv_path, md_path


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    ladder, traj_len, nstep, local_updates, reference_path = read_reference(repo_root)
    params_path = repo_root / "data" / "parameters.dat"

    original = params_path.read_text()
    try:
        update_parameters_file(params_path, False, traj_len, nstep)
        run_case(repo_root, "no_fb", False, args.seed, args.cycles, ladder, local_updates)

        update_parameters_file(params_path, True, traj_len, nstep)
        run_case(repo_root, "fb", True, args.seed, args.cycles, ladder, local_updates)
    finally:
        params_path.write_text(original)

    no_fb = parse_summary(repo_root / "output" / "tests" / "stage3_1" / "no_fb_summary.dat")
    fb = parse_summary(repo_root / "output" / "tests" / "stage3_1" / "fb_summary.dat")
    csv_path, md_path = write_report(repo_root, no_fb, fb, args.seed, args.cycles, ladder, reference_path)

    print("[DONE] stage-3.1 comparison generated")
    print("  {0}".format(csv_path))
    print("  {0}".format(md_path))


if __name__ == "__main__":
    main()
