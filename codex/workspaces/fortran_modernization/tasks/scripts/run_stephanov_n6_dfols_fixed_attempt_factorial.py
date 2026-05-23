#!/usr/bin/env python3
"""Replay fixed Stephanov n=6 QN attempts over a DFO-LS factorial grid.

This is an offline tuning tool.  It deliberately reuses the same captured QN
attempts for every DFO-LS policy so parameter effects are paired by attempt and
can expose interactions.  It is not a production HMC trajectory runner.
"""

import argparse
import csv
import itertools
import math
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Run fixed-attempt Stephanov n=6 DFO-LS factorial replay.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--capture-root", required=True)
    parser.add_argument("--output-root", default="output/stephanov_dfols_tuning")
    parser.add_argument("--run-group", default="")
    parser.add_argument("--records", default="all", help="'all' or comma-separated record ids, e.g. 0000,0101.")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--max-cases-per-record", type=int, default=0)
    parser.add_argument("--maxfun", type=int, default=1200)
    parser.add_argument("--npts", default="0")
    parser.add_argument("--rhobegs", default="0.15,0.25,0.35")
    parser.add_argument("--rhoends", default="1e-16,1e-13")
    parser.add_argument("--model-abs-tols", default="1e-26,1e-30")
    parser.add_argument("--model-rel-tols", default="0")
    parser.add_argument("--objfun-has-noise", choices=("0", "1"), default="0")
    parser.add_argument("--residual-success-tol", default="1e-13")
    parser.add_argument("--capture-prefix", default="qn_attempt")
    parser.add_argument("--seed-source", choices=("auto", "bridge", "capture"), default="capture")
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


def float_token(value):
    text = str(value).lower()
    text = text.replace("+", "")
    text = text.replace("-", "m")
    text = text.replace(".", "p")
    text = text.replace("e", "e")
    return text


def combo_label(combo):
    return "npt{0}_rb{1}_re{2}_abs{3}_rel{4}_noise{5}".format(
        combo["npt"],
        float_token(combo["rhobeg"]),
        float_token(combo["rhoend"]),
        float_token(combo["model_abs_tol"]),
        float_token(combo["model_rel_tol"]),
        combo["objfun_has_noise"],
    )


def build_grid(args):
    combos = []
    for npt, rhobeg, rhoend, model_abs_tol, model_rel_tol in itertools.product(
        split_csv(args.npts),
        split_csv(args.rhobegs),
        split_csv(args.rhoends),
        split_csv(args.model_abs_tols),
        split_csv(args.model_rel_tols),
    ):
        combo = {
            "npt": npt,
            "rhobeg": rhobeg,
            "rhoend": rhoend,
            "model_abs_tol": model_abs_tol,
            "model_rel_tol": model_rel_tol,
            "objfun_has_noise": args.objfun_has_noise,
            "maxfun": str(args.maxfun),
        }
        combo["candidate"] = combo_label(combo)
        combos.append(combo)
    return combos


def record_dirs(capture_root, records_text):
    if records_text.strip().lower() == "all":
        return sorted(path for path in capture_root.glob("record_*") if path.is_dir())
    selected = []
    for item in split_csv(records_text):
        record = item if item.startswith("record_") else "record_{0}".format(item.zfill(4))
        path = capture_root / record
        if not path.is_dir():
            raise RuntimeError("Missing record capture directory: {0}".format(path))
        selected.append(path)
    return selected


def read_csv_rows(path):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


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


def to_float(row, key, default=float("nan")):
    try:
        text = row.get(key, "")
        if text == "":
            return default
        return float(text)
    except (TypeError, ValueError):
        return default


def to_int(row, key, default=0):
    try:
        text = row.get(key, "")
        if text == "":
            return default
        return int(float(text))
    except (TypeError, ValueError):
        return default


def finite_values(rows, key):
    values = []
    for row in rows:
        value = to_float(row, key)
        if math.isfinite(value):
            values.append(value)
    return values


def percentile(values, q):
    if not values:
        return float("nan")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    pos = (len(ordered) - 1) * q
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(ordered) - 1)
    frac = pos - lo
    return ordered[lo] * (1.0 - frac) + ordered[hi] * frac


def fmt_float(value):
    if not math.isfinite(value):
        return ""
    return "{0:.16g}".format(value)


def run_task(args, repo_root, run_root, combo, record_dir):
    python_bin = args.python or sys.executable
    external_runner = resolve_repo_path(repo_root, args.external_runner)
    bridge_bin = resolve_repo_path(repo_root, args.bridge_bin)
    parameters_file = resolve_repo_path(repo_root, args.parameters_file)
    record = record_dir.name
    combo_dir = run_root / combo["candidate"]
    out_csv = combo_dir / "{0}.csv".format(record)
    log_path = combo_dir / "{0}.log".format(record)
    cmd = [
        python_bin,
        str(external_runner),
        "--repo-root",
        str(repo_root),
        "--case-dir",
        str(record_dir),
        "--bridge-bin",
        str(bridge_bin),
        "--parameters-file",
        str(parameters_file),
        "--capture-prefix",
        args.capture_prefix,
        "--seed-source",
        args.seed_source,
        "--maxfun",
        str(args.maxfun),
        "--npt",
        combo["npt"],
        "--rhobeg",
        combo["rhobeg"],
        "--rhoend",
        combo["rhoend"],
        "--model-abs-tol",
        combo["model_abs_tol"],
        "--model-rel-tol",
        combo["model_rel_tol"],
        "--residual-success-tol",
        args.residual_success_tol,
        "--out-csv",
        str(out_csv),
    ]
    if args.objfun_has_noise == "1":
        cmd.append("--objfun-has-noise")
    if args.max_cases_per_record > 0:
        cmd.extend(["--max-cases", str(args.max_cases_per_record)])

    row = dict(combo)
    row.update({"record": record, "out_csv": str(out_csv), "log": str(log_path), "returncode": "", "wall_sec": ""})
    if args.dry_run:
        row["command"] = " ".join(cmd)
        row["returncode"] = "DRY_RUN"
        return row

    env = os.environ.copy()
    for thread_env_name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        env.setdefault(thread_env_name, "1")
    combo_dir.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log:
        log.write("command={0}\n".format(" ".join(cmd)))
        log.flush()
        proc = subprocess.run(cmd, cwd=str(repo_root), env=env, stdout=log, stderr=subprocess.STDOUT, check=False)
    row["returncode"] = str(proc.returncode)
    row["wall_sec"] = "{0:.3f}".format(time.monotonic() - start)
    return row


def summarize_attempts(combos, run_root):
    all_rows = []
    summary_rows = []
    for combo in combos:
        combo_rows = []
        for path in sorted((run_root / combo["candidate"]).glob("record_*.csv")):
            record = path.stem
            for row in read_csv_rows(path):
                out = dict(combo)
                out["record"] = record
                out.update(row)
                combo_rows.append(out)
                all_rows.append(out)
        n = len(combo_rows)
        success = sum(to_int(row, "residual_success", 0) for row in combo_rows)
        errors = sum(1 for row in combo_rows if row.get("error", "").strip())
        final_res = finite_values(combo_rows, "final_residual_norm")
        nf = finite_values(combo_rows, "dfols_nf")
        log_res = [math.log10(max(value, 1.0e-300)) for value in final_res if value >= 0.0]
        float64_ok = sum(to_int(row, "float64_contract", 0) for row in combo_rows)
        summary = dict(combo)
        summary.update(
            {
                "attempt_count": str(n),
                "success_count": str(success),
                "success_fraction": fmt_float(float(success) / float(n)) if n else "",
                "error_count": str(errors),
                "float64_contract_count": str(float64_ok),
                "final_res_median": fmt_float(percentile(final_res, 0.50)),
                "final_res_p90": fmt_float(percentile(final_res, 0.90)),
                "final_res_max": fmt_float(max(final_res) if final_res else float("nan")),
                "log10_final_res_mean": fmt_float(sum(log_res) / float(len(log_res)) if log_res else float("nan")),
                "log10_final_res_median": fmt_float(percentile(log_res, 0.50)),
                "dfols_nf_median": fmt_float(percentile(nf, 0.50)),
                "dfols_nf_p90": fmt_float(percentile(nf, 0.90)),
                "dfols_nf_max": fmt_float(max(nf) if nf else float("nan")),
                "dfols_nf_mean": fmt_float(sum(nf) / float(len(nf)) if nf else float("nan")),
            }
        )
        summary_rows.append(summary)
    return summary_rows, all_rows


def metric_value(row, metric):
    if metric == "success_fraction":
        return to_float(row, metric)
    return to_float(row, metric)


def interaction_rows(summary_rows, factors):
    metrics = ["success_fraction", "log10_final_res_mean", "dfols_nf_mean"]
    rows = []
    for metric in metrics:
        valid = [row for row in summary_rows if math.isfinite(metric_value(row, metric))]
        if not valid:
            continue
        active_factors = [factor for factor in factors if len(set(row[factor] for row in valid)) > 1]
        grand = sum(metric_value(row, metric) for row in valid) / float(len(valid))
        for factor in active_factors:
            levels = sorted(set(row[factor] for row in valid))
            for level in levels:
                sub = [row for row in valid if row[factor] == level]
                mean = sum(metric_value(row, metric) for row in sub) / float(len(sub))
                rows.append(
                    {
                        "kind": "main",
                        "metric": metric,
                        "factor_a": factor,
                        "level_a": level,
                        "factor_b": "",
                        "level_b": "",
                        "mean": fmt_float(mean),
                        "grand_mean": fmt_float(grand),
                        "effect": fmt_float(mean - grand),
                        "interaction": "",
                    }
                )
        for factor_a, factor_b in itertools.combinations(active_factors, 2):
            levels_a = sorted(set(row[factor_a] for row in valid))
            levels_b = sorted(set(row[factor_b] for row in valid))
            for level_a, level_b in itertools.product(levels_a, levels_b):
                pair = [row for row in valid if row[factor_a] == level_a and row[factor_b] == level_b]
                sub_a = [row for row in valid if row[factor_a] == level_a]
                sub_b = [row for row in valid if row[factor_b] == level_b]
                if not pair or not sub_a or not sub_b:
                    continue
                mean_pair = sum(metric_value(row, metric) for row in pair) / float(len(pair))
                mean_a = sum(metric_value(row, metric) for row in sub_a) / float(len(sub_a))
                mean_b = sum(metric_value(row, metric) for row in sub_b) / float(len(sub_b))
                interaction = mean_pair - mean_a - mean_b + grand
                rows.append(
                    {
                        "kind": "two_factor",
                        "metric": metric,
                        "factor_a": factor_a,
                        "level_a": level_a,
                        "factor_b": factor_b,
                        "level_b": level_b,
                        "mean": fmt_float(mean_pair),
                        "grand_mean": fmt_float(grand),
                        "effect": "",
                        "interaction": fmt_float(interaction),
                    }
                )
    return rows


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    capture_root = resolve_repo_path(repo_root, args.capture_root).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root)
    run_group = args.run_group or datetime.now(tz=timezone.utc).strftime("stephanov_n6_dfols_fixed_attempt_factorial_%Y%m%dT%H%M%SZ")
    run_root = output_root / run_group

    if run_root.exists() and not args.force and not args.dry_run:
        raise RuntimeError("Output root exists; use --force: {0}".format(run_root))
    run_root.mkdir(parents=True, exist_ok=True)

    combos = build_grid(args)
    records = record_dirs(capture_root, args.records)
    tasks = [(combo, record_dir) for combo in combos for record_dir in records]
    plan_rows = []
    for combo, record_dir in tasks:
        row = dict(combo)
        row["record"] = record_dir.name
        row["case_dir"] = str(record_dir)
        plan_rows.append(row)
    write_csv(run_root / "fixed_attempt_factorial_plan.csv", plan_rows)

    task_rows = []
    if args.dry_run:
        for combo, record_dir in tasks:
            task_rows.append(run_task(args, repo_root, run_root, combo, record_dir))
    else:
        workers = max(1, args.workers)
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(run_task, args, repo_root, run_root, combo, record_dir) for combo, record_dir in tasks]
            for future in as_completed(futures):
                row = future.result()
                task_rows.append(row)
                print(
                    "[FIXED_DFOLS] {0} {1} rc={2} wall={3}s".format(
                        row["candidate"], row["record"], row["returncode"], row["wall_sec"]
                    ),
                    flush=True,
                )
    write_csv(run_root / "fixed_attempt_factorial_tasks.csv", task_rows)

    failed = [row for row in task_rows if str(row.get("returncode", "")) not in ("0", "DRY_RUN")]
    if failed:
        print("[ERROR] failed task count={0}".format(len(failed)), file=sys.stderr)
        write_csv(run_root / "fixed_attempt_factorial_failed_tasks.csv", failed)
        return 1

    if not args.dry_run:
        summary_rows, attempt_rows = summarize_attempts(combos, run_root)
        write_csv(run_root / "fixed_attempt_factorial_summary.csv", summary_rows)
        write_csv(run_root / "fixed_attempt_factorial_attempts.csv", attempt_rows)
        factors = ["npt", "rhobeg", "rhoend", "model_abs_tol", "model_rel_tol", "objfun_has_noise"]
        write_csv(run_root / "fixed_attempt_factorial_effects.csv", interaction_rows(summary_rows, factors))
        print(run_root / "fixed_attempt_factorial_summary.csv")
        print(run_root / "fixed_attempt_factorial_effects.csv")
        print(run_root / "fixed_attempt_factorial_attempts.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
