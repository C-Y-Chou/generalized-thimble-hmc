#!/usr/bin/env python3
"""Scan DFO-LS policy parameters for Stephanov n=6 with fixed noise mode.

The scan treats maxfun as a censoring budget, not as a solution-distribution
knob.  Each candidate is run with the same large budget and the same fixed
objfun_has_noise value, then attempt-level QN capture is summarized.
"""

import argparse
import csv
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Run a Stephanov n=6 DFO-LS policy scan.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--output-root", default="output/stephanov_dfols_tuning")
    parser.add_argument("--run-group", default="")
    parser.add_argument("--records", default="0,101,202,303")
    parser.add_argument("--cycles", type=int, default=5)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--timeout-sec", type=int, default=7200)
    parser.add_argument("--seed-base", type=int, default=8930000)
    parser.add_argument("--maxfun-budget", type=int, default=1200)
    parser.add_argument("--objfun-has-noise", choices=("0", "1"), default="0")
    parser.add_argument("--capture-limit", type=int, default=0)
    parser.add_argument("--capture-stride", type=int, default=1)
    parser.add_argument("--ladder", default="0,1e-3,3e-3,7e-3,1e-2,1.3e-2,1.6e-2,1.8e-2,2e-2,2.25e-2,2.5e-2,2.75e-2,3e-2")
    parser.add_argument("--init-flow-bank-root", default="output/stephanov_flow_banks/stephanov_n6_tltm_t003_ladder13_dop853_highflow_bank_8x600_20260523_xhist_b100_s5/flow_bank_ladder13_dop853_dense_cache")
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument("--runner", default="codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def resolve_repo_path(repo_root, value):
    path = Path(value)
    if path.is_absolute():
        return path
    return repo_root / path


def candidates(maxfun_budget):
    base = {
        "npt": "0",
        "rhobeg": "0.25",
        "rhoend": "1e-16",
        "model_abs_tol": "1e-26",
        "model_rel_tol": "0",
        "maxfun_budget": str(maxfun_budget),
    }
    rows = []

    def add(label, **updates):
        row = dict(base)
        row.update(updates)
        row["candidate"] = label
        rows.append(row)

    add("base_auto_r025_rho16_abs26")
    add("rhobeg_015", rhobeg="0.15")
    add("rhobeg_035", rhobeg="0.35")
    add("rhoend_1e14", rhoend="1e-14")
    add("rhoend_1e13", rhoend="1e-13")
    add("model_abs_1e30", model_abs_tol="1e-30")
    add("npt_289", npt="289")
    return rows


def read_csv_rows(path):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def to_float(row, key, default=0.0):
    try:
        return float(row.get(key, default))
    except (TypeError, ValueError):
        return default


def to_int(row, key, default=0):
    try:
        return int(float(row.get(key, default)))
    except (TypeError, ValueError):
        return default


def percentile(values, q):
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    pos = (len(ordered) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(ordered) - 1)
    frac = pos - lo
    return ordered[lo] * (1.0 - frac) + ordered[hi] * frac


def fmt(value):
    if isinstance(value, str):
        return value
    if isinstance(value, int):
        return str(value)
    return "{0:.16g}".format(value)


def collect_attempt_rows(candidate, candidate_dir):
    rows = []
    capture_root = candidate_dir / "qn_attempt_capture"
    if not capture_root.exists():
        return rows
    for meta_file in sorted(capture_root.glob("record_*/qn_attempt_meta.csv")):
        record_text = meta_file.parent.name.split("_", 1)[-1]
        for row in read_csv_rows(meta_file):
            out = dict(candidate)
            out["record"] = record_text
            out["meta_file"] = str(meta_file)
            out.update(row)
            rows.append(out)
    return rows


def summarize_candidate(candidate, candidate_dir, elapsed_sec, returncode):
    attempt_rows = collect_attempt_rows(candidate, candidate_dir)
    summary_rows = read_csv_rows(candidate_dir / "tltm_ladder_summary.csv")
    aggregate_rows = read_csv_rows(candidate_dir / "tltm_ladder_aggregate.csv")
    aggregate = aggregate_rows[0] if aggregate_rows else {}

    best = [to_float(row, "best_residual_norm", 0.0) for row in attempt_rows]
    initial = [to_float(row, "initial_residual_norm", 0.0) for row in attempt_rows]
    evals = [to_float(row, "residual_eval_count", 0.0) for row in attempt_rows]
    cpu = [to_float(row, "cpu_seconds", 0.0) for row in attempt_rows]
    xi0 = [to_float(row, "xi0_norm", 0.0) for row in attempt_rows]
    attempts = len(attempt_rows)
    converged = sum(1 for row in attempt_rows if to_int(row, "converged", 0) == 1)

    out = dict(candidate)
    out.update(
        {
            "returncode": returncode,
            "scan_wall_sec": elapsed_sec,
            "record_count": len(summary_rows),
            "attempt_count": attempts,
            "converged_count": converged,
            "converged_fraction": float(converged) / float(attempts) if attempts else 0.0,
            "best_res_min": min(best) if best else 0.0,
            "best_res_p25": percentile(best, 0.25),
            "best_res_median": percentile(best, 0.50),
            "best_res_p75": percentile(best, 0.75),
            "best_res_max": max(best) if best else 0.0,
            "initial_res_median": percentile(initial, 0.50),
            "initial_res_max": max(initial) if initial else 0.0,
            "eval_count_median": percentile(evals, 0.50),
            "eval_count_p75": percentile(evals, 0.75),
            "eval_count_max": max(evals) if evals else 0.0,
            "cpu_sec_median": percentile(cpu, 0.50),
            "cpu_sec_p75": percentile(cpu, 0.75),
            "xi0_norm_median": percentile(xi0, 0.50),
            "count_best_le_1e_minus_2": sum(1 for value in best if value <= 1.0e-2),
            "count_best_le_1e_minus_3": sum(1 for value in best if value <= 1.0e-3),
            "count_best_le_1e_minus_6": sum(1 for value in best if value <= 1.0e-6),
            "count_best_le_1e_minus_13": sum(1 for value in best if value <= 1.0e-13),
            "total_proposal_failure": to_int(aggregate, "total_proposal_failure", 0),
            "total_reverse_gate_reject": to_int(aggregate, "total_reverse_gate_reject", 0),
            "candidate_dir": str(candidate_dir),
        }
    )
    return out, attempt_rows


def write_csv(path, rows):
    if not rows:
        return
    fieldnames = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: fmt(row.get(key, "")) for key in fieldnames})


def run_candidate(args, repo_root, scan_root, candidate):
    runner = resolve_repo_path(repo_root, args.runner)
    candidate_dir = scan_root / candidate["candidate"]
    capture_root = candidate_dir / "qn_attempt_capture"
    env = os.environ.copy()
    env.update(
        {
            "QN_SOLVER_BACKEND": "official_dfols",
            "QN_OFFICIAL_DFOLS_PRESET": "stable_gate77",
            "QN_OFFICIAL_DFOLS_NPT": candidate["npt"],
            "QN_OFFICIAL_DFOLS_MAXFUN": candidate["maxfun_budget"],
            "QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE": args.objfun_has_noise,
            "QN_OFFICIAL_DFOLS_RHOBEG": candidate["rhobeg"],
            "QN_OFFICIAL_DFOLS_RHOEND": candidate["rhoend"],
            "QN_OFFICIAL_DFOLS_MODEL_ABS_TOL": candidate["model_abs_tol"],
            "QN_OFFICIAL_DFOLS_MODEL_REL_TOL": candidate["model_rel_tol"],
            "TLTM_ODE_BACKEND": env.get("TLTM_ODE_BACKEND", "dop853"),
            "TLTM_DOP853_HINIT_ENABLED": env.get("TLTM_DOP853_HINIT_ENABLED", "1"),
            "TLTM_DOP853_STIFFNESS_CHECK_ENABLED": env.get("TLTM_DOP853_STIFFNESS_CHECK_ENABLED", "1"),
            "TLTM_DOP853_STIFFNESS_CHECK_INTERVAL": env.get("TLTM_DOP853_STIFFNESS_CHECK_INTERVAL", "1000"),
            "TLTM_DOP853_STIFFNESS_MAX_HITS": env.get("TLTM_DOP853_STIFFNESS_MAX_HITS", "15"),
            "TLTM_DOP853_STIFFNESS_THRESHOLD": env.get("TLTM_DOP853_STIFFNESS_THRESHOLD", "6.1"),
        }
    )
    cmd = [
        sys.executable,
        str(runner),
        "--repo-root",
        str(repo_root),
        "--base-parameters",
        args.base_parameters,
        "--skip-build",
        "--init-flow-bank-root",
        args.init_flow_bank_root,
        "--records",
        args.records,
        "--cycles",
        str(args.cycles),
        "--jobs",
        str(args.jobs),
        "--threads",
        str(args.threads),
        "--timeout-sec",
        str(args.timeout_sec),
        "--seed-base",
        str(args.seed_base),
        "--ladder",
        args.ladder,
        "--parallel-local-updates",
        "1",
        "--parallel-swaps",
        "1",
        "--enable-quasi-fallback",
        "--qn-attempt-capture-root",
        str(capture_root),
        "--qn-attempt-capture-limit",
        str(args.capture_limit),
        "--qn-attempt-capture-stride",
        str(args.capture_stride),
        "--output-root",
        str(scan_root),
        "--run-name",
        candidate["candidate"],
        "--force",
    ]
    if args.dry_run:
        print(" ".join(cmd))
        return 0, 0.0
    start = time.monotonic()
    proc = subprocess.run(cmd, cwd=str(repo_root), env=env, check=False)
    return proc.returncode, time.monotonic() - start


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root)
    run_group = args.run_group or datetime.now(tz=timezone.utc).strftime("stephanov_n6_dfols_policy_scan_%Y%m%dT%H%M%SZ")
    scan_root = output_root / run_group
    if scan_root.exists():
        if not args.force:
            raise RuntimeError("Scan root exists; use --force: {0}".format(scan_root))
        shutil.rmtree(scan_root)
    scan_root.mkdir(parents=True, exist_ok=True)

    all_attempt_rows = []
    scan_rows = []
    for candidate in candidates(args.maxfun_budget):
        candidate["objfun_has_noise"] = args.objfun_has_noise
        print("[DFOLS_SCAN] start {0}".format(candidate["candidate"]), flush=True)
        returncode, elapsed = run_candidate(args, repo_root, scan_root, candidate)
        candidate_dir = scan_root / candidate["candidate"]
        summary, attempt_rows = summarize_candidate(candidate, candidate_dir, elapsed, returncode)
        scan_rows.append(summary)
        all_attempt_rows.extend(attempt_rows)
        write_csv(scan_root / "dfols_scan_summary.csv", scan_rows)
        write_csv(scan_root / "dfols_scan_attempts.csv", all_attempt_rows)
        print(
            "[DFOLS_SCAN] done {0} rc={1} wall={2:.1f}s attempts={3} converged={4}".format(
                candidate["candidate"],
                returncode,
                elapsed,
                summary["attempt_count"],
                summary["converged_count"],
            ),
            flush=True,
        )
        if returncode != 0:
            raise RuntimeError("Candidate failed: {0}".format(candidate["candidate"]))

    print(scan_root / "dfols_scan_summary.csv")
    print(scan_root / "dfols_scan_attempts.csv")


if __name__ == "__main__":
    raise SystemExit(main())
