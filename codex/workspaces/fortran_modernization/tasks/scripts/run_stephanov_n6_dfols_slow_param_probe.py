#!/usr/bin/env python3
"""Probe official DFO-LS slow-progress settings on selected fixed QN attempts.

This is a small policy probe, not a production HMC run and not a full replay.
It targets a few known easy, late, and failing attempts so DFO-LS parameters can
be screened without letting hard cases burn to a large maxfun ceiling.
"""

import argparse
import csv
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Run Stephanov n=6 DFO-LS slow-progress parameter probe.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--case-dir", default="output/stephanov_dfols_tuning/stephanov_n6_dfols_policy_scan_noisefixed0_parallel_20260524a/base_auto_r025_rho16_abs26/qn_attempt_capture/record_0505")
    parser.add_argument("--output-root", default="output/stephanov_dfols_tuning")
    parser.add_argument("--run-group", default="")
    parser.add_argument("--sample-ids", default="1,2,3,4,5,7,8,9,15,16,19,21")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--maxfun", type=int, default=1200)
    parser.add_argument("--rhobegs", default="0.25,0.35")
    parser.add_argument("--rhoend", default="1e-13")
    parser.add_argument("--model-abs-tol", default="1e-26")
    parser.add_argument("--model-rel-tol", default="0")
    parser.add_argument("--residual-success-tol", default="1e-13")
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument("--bridge-bin", default="bin/evaluate_btn_residual_case")
    parser.add_argument("--external-runner", default="scripts/run_external_dfols_btn_compare.py")
    parser.add_argument("--python", default="")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def resolve_repo_path(repo_root, value):
    path = Path(value)
    return path if path.is_absolute() else repo_root / path


def split_csv(text):
    return [item.strip() for item in text.split(",") if item.strip()]


def candidate_specs():
    base = [
        ("slow10_t1e4", {"slow.max_slow_iters": "10", "slow.history_for_slow": "5", "slow.thresh_for_slow": "1e-4"}),
        ("slow20_t1e4", {"slow.max_slow_iters": "20", "slow.history_for_slow": "5", "slow.thresh_for_slow": "1e-4"}),
        ("slow40_t1e4", {"slow.max_slow_iters": "40", "slow.history_for_slow": "5", "slow.thresh_for_slow": "1e-4"}),
        ("slow80_t1e4", {"slow.max_slow_iters": "80", "slow.history_for_slow": "5", "slow.thresh_for_slow": "1e-4"}),
        ("slow40_t1e3", {"slow.max_slow_iters": "40", "slow.history_for_slow": "5", "slow.thresh_for_slow": "1e-3"}),
        ("slow80_t1e3", {"slow.max_slow_iters": "80", "slow.history_for_slow": "5", "slow.thresh_for_slow": "1e-3"}),
        (
            "slow40_t1e4_gdec025",
            {
                "slow.max_slow_iters": "40",
                "slow.history_for_slow": "5",
                "slow.thresh_for_slow": "1e-4",
                "tr_radius.gamma_dec": "0.25",
            },
        ),
        (
            "slow80_t1e4_gdec025",
            {
                "slow.max_slow_iters": "80",
                "slow.history_for_slow": "5",
                "slow.thresh_for_slow": "1e-4",
                "tr_radius.gamma_dec": "0.25",
            },
        ),
    ]
    return base


def write_csv(path, rows):
    if not rows:
        return
    fieldnames = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def read_csv_rows(path):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def to_float(row, key, default=0.0):
    try:
        text = row.get(key, "")
        return default if text == "" else float(text)
    except (TypeError, ValueError):
        return default


def to_int(row, key, default=0):
    try:
        text = row.get(key, "")
        return default if text == "" else int(float(text))
    except (TypeError, ValueError):
        return default


def percentile(values, q):
    if not values:
        return ""
    ordered = sorted(values)
    if len(ordered) == 1:
        return "{0:.16g}".format(ordered[0])
    pos = (len(ordered) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(ordered) - 1)
    frac = pos - lo
    value = ordered[lo] * (1.0 - frac) + ordered[hi] * frac
    return "{0:.16g}".format(value)


def task_label(candidate, rhobeg):
    return "rb{0}_{1}".format(rhobeg.replace(".", "p"), candidate)


def run_task(args, repo_root, run_root, candidate, params, rhobeg):
    python_bin = args.python or sys.executable
    external_runner = resolve_repo_path(repo_root, args.external_runner)
    case_dir = resolve_repo_path(repo_root, args.case_dir)
    bridge_bin = resolve_repo_path(repo_root, args.bridge_bin)
    parameters_file = resolve_repo_path(repo_root, args.parameters_file)
    label = task_label(candidate, rhobeg)
    out_csv = run_root / label / "attempts.csv"
    log_path = run_root / label / "run.log"
    cmd = [
        python_bin,
        str(external_runner),
        "--repo-root",
        str(repo_root),
        "--case-dir",
        str(case_dir),
        "--bridge-bin",
        str(bridge_bin),
        "--parameters-file",
        str(parameters_file),
        "--capture-prefix",
        "qn_attempt",
        "--seed-source",
        "capture",
        "--sample-ids",
        args.sample_ids,
        "--maxfun",
        str(args.maxfun),
        "--npt",
        "0",
        "--rhobeg",
        rhobeg,
        "--rhoend",
        args.rhoend,
        "--model-abs-tol",
        args.model_abs_tol,
        "--model-rel-tol",
        args.model_rel_tol,
        "--residual-success-tol",
        args.residual_success_tol,
        "--out-csv",
        str(out_csv),
    ]
    for key, value in sorted(params.items()):
        cmd.extend(["--dfols-param", "{0}={1}".format(key, value)])
    row = {
        "candidate": candidate,
        "rhobeg": rhobeg,
        "rhoend": args.rhoend,
        "out_csv": str(out_csv),
        "log": str(log_path),
        "returncode": "",
        "wall_sec": "",
        "dfols_params": ";".join("{0}={1}".format(k, v) for k, v in sorted(params.items())),
    }
    if args.dry_run:
        row["command"] = " ".join(cmd)
        row["returncode"] = "DRY_RUN"
        return row

    env = os.environ.copy()
    for thread_env_name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        env.setdefault(thread_env_name, "1")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log:
        log.write("command={0}\n".format(" ".join(cmd)))
        log.flush()
        proc = subprocess.run(cmd, cwd=str(repo_root), env=env, stdout=log, stderr=subprocess.STDOUT, check=False)
    row["returncode"] = str(proc.returncode)
    row["wall_sec"] = "{0:.3f}".format(time.monotonic() - start)
    return row


def summarize(run_root, task_rows):
    summary_rows = []
    attempt_rows = []
    for task in task_rows:
        rows = read_csv_rows(Path(task["out_csv"]))
        for row in rows:
            out = dict(task)
            out.update(row)
            attempt_rows.append(out)
        n = len(rows)
        success_rows = [row for row in rows if to_int(row, "residual_success", 0) == 1 and not row.get("error", "").strip()]
        failed_rows = [row for row in rows if row not in success_rows]
        nf_all = [to_float(row, "dfols_nf") for row in rows if row.get("dfols_nf", "") != ""]
        nf_success = [to_float(row, "dfols_nf") for row in success_rows if row.get("dfols_nf", "") != ""]
        maxfun_hits = sum(1 for row in rows if "MAXFUN" in row.get("dfols_message", "").upper())
        summary = {
            "candidate": task["candidate"],
            "rhobeg": task["rhobeg"],
            "rhoend": task["rhoend"],
            "dfols_params": task["dfols_params"],
            "returncode": task["returncode"],
            "wall_sec": task["wall_sec"],
            "attempt_count": str(n),
            "success_count": str(len(success_rows)),
            "failure_count": str(len(failed_rows)),
            "success_fraction": "{0:.16g}".format(float(len(success_rows)) / float(n)) if n else "",
            "maxfun_hit_count": str(maxfun_hits),
            "nf_all_mean": "{0:.16g}".format(sum(nf_all) / float(len(nf_all))) if nf_all else "",
            "nf_all_p50": percentile(nf_all, 0.50),
            "nf_all_p90": percentile(nf_all, 0.90),
            "nf_all_max": percentile(nf_all, 1.0),
            "nf_success_mean": "{0:.16g}".format(sum(nf_success) / float(len(nf_success))) if nf_success else "",
            "nf_success_p50": percentile(nf_success, 0.50),
            "nf_success_p90": percentile(nf_success, 0.90),
            "nf_success_max": percentile(nf_success, 1.0),
        }
        summary_rows.append(summary)
    write_csv(run_root / "slow_param_probe_summary.csv", summary_rows)
    write_csv(run_root / "slow_param_probe_attempts.csv", attempt_rows)
    return summary_rows, attempt_rows


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root)
    run_group = args.run_group or datetime.now(tz=timezone.utc).strftime("stephanov_n6_dfols_slow_param_probe_%Y%m%dT%H%M%SZ")
    run_root = output_root / run_group
    if run_root.exists() and not args.force and not args.dry_run:
        raise RuntimeError("Output root exists; use --force: {0}".format(run_root))
    run_root.mkdir(parents=True, exist_ok=True)

    tasks = []
    for candidate, params in candidate_specs():
        for rhobeg in split_csv(args.rhobegs):
            tasks.append((candidate, params, rhobeg))
    write_csv(
        run_root / "slow_param_probe_plan.csv",
        [
            {
                "candidate": candidate,
                "rhobeg": rhobeg,
                "rhoend": args.rhoend,
                "sample_ids": args.sample_ids,
                "dfols_params": ";".join("{0}={1}".format(k, v) for k, v in sorted(params.items())),
            }
            for candidate, params, rhobeg in tasks
        ],
    )

    task_rows = []
    if args.dry_run:
        for candidate, params, rhobeg in tasks:
            task_rows.append(run_task(args, repo_root, run_root, candidate, params, rhobeg))
    else:
        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
            futures = [pool.submit(run_task, args, repo_root, run_root, candidate, params, rhobeg) for candidate, params, rhobeg in tasks]
            for future in as_completed(futures):
                row = future.result()
                task_rows.append(row)
                print("[SLOW_PROBE] {0} rb={1} rc={2} wall={3}s".format(row["candidate"], row["rhobeg"], row["returncode"], row["wall_sec"]), flush=True)
    write_csv(run_root / "slow_param_probe_tasks.csv", task_rows)
    failed = [row for row in task_rows if str(row.get("returncode", "")) not in ("0", "DRY_RUN")]
    if failed:
        write_csv(run_root / "slow_param_probe_failed_tasks.csv", failed)
        print("[ERROR] failed task count={0}".format(len(failed)), file=sys.stderr)
        return 1
    if not args.dry_run:
        summarize(run_root, task_rows)
        print(run_root / "slow_param_probe_summary.csv")
        print(run_root / "slow_param_probe_attempts.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
