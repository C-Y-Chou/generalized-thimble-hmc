#!/usr/bin/env python3
"""Run fixed Stephanov n=6 DFO-LS replay as one PBS task per sample.

This is an offline tuning runner.  It deliberately maps each
``(DFO-LS candidate, captured sample_idx)`` to one independent task so a
MAXFUN long tail cannot block other samples from producing CSV output.
"""

import argparse
import csv
import itertools
import math
import os
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description="Run one-sample-per-task Stephanov n=6 DFO-LS replay.")
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument(
        "--case-dir",
        default=(
            "output/stephanov_dfols_tuning/"
            "stephanov_n6_dfols_policy_scan_noisefixed0_parallel_20260524a/"
            "base_auto_r025_rho16_abs26/qn_attempt_capture/record_0505"
        ),
    )
    parser.add_argument("--output-root", default="output/stephanov_dfols_tuning")
    parser.add_argument("--run-group", default="")
    parser.add_argument("--sample-ids", default="all")
    parser.add_argument("--task-index", type=int, default=0, help="1-based task index. 0 means no single-task run.")
    parser.add_argument("--maxfun", type=int, default=1200)
    parser.add_argument("--npts", default="0")
    parser.add_argument("--rhobegs", default="0.20,0.25,0.30,0.35")
    parser.add_argument("--rhoends", default="1e-13")
    parser.add_argument("--model-abs-tols", default="1e-26")
    parser.add_argument("--model-rel-tols", default="0")
    parser.add_argument(
        "--gamma-decs",
        default="default,0.25,0.75",
        help="Comma-separated DFO-LS tr_radius.gamma_dec levels. Use 'default' for the package default.",
    )
    parser.add_argument(
        "--safety-step-threshes",
        default="default",
        help="Comma-separated DFO-LS general.safety_step_thresh levels. Use 'default' for the package default.",
    )
    parser.add_argument(
        "--growing-safety-do-safety-steps",
        default="default",
        help="Comma-separated DFO-LS growing.safety.do_safety_step bool levels. Use 'default' for package default.",
    )
    parser.add_argument(
        "--growing-safety-reduce-deltas",
        default="default",
        help="Comma-separated DFO-LS growing.safety.reduce_delta bool levels. Use 'default' for package default.",
    )
    parser.add_argument(
        "--growing-safety-full-geom-steps",
        default="default",
        help="Comma-separated DFO-LS growing.safety.full_geom_step bool levels. Use 'default' for package default.",
    )
    parser.add_argument("--objfun-has-noise", choices=("0", "1"), default="0")
    parser.add_argument("--residual-success-tol", default="1e-13")
    parser.add_argument("--capture-prefix", default="qn_attempt")
    parser.add_argument("--seed-source", choices=("auto", "bridge", "capture"), default="capture")
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument("--bridge-bin", default="bin/evaluate_btn_residual_case")
    parser.add_argument("--external-runner", default="scripts/run_external_dfols_btn_compare.py")
    parser.add_argument("--python", default="")
    parser.add_argument("--dfols-param", action="append", default=[])
    parser.add_argument("--save-diagnostics", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--write-plan-only", action="store_true")
    parser.add_argument("--summarize-only", action="store_true")
    return parser.parse_args()


def resolve_repo_path(repo_root, value):
    path = Path(value)
    return path if path.is_absolute() else repo_root / path


def split_csv(text):
    return [item.strip() for item in text.split(",") if item.strip()]


def float_token(value):
    text = str(value).lower()
    return text.replace("+", "").replace("-", "m").replace(".", "p")


def bool_token(value):
    text = str(value).strip().lower()
    if text in ("1", "true", "t", "yes", "y", "on"):
        return "true"
    if text in ("0", "false", "f", "no", "n", "off"):
        return "false"
    if text == "default":
        return "default"
    raise ValueError("Invalid bool/default value: {0}".format(value))


def is_true_token(value):
    return bool_token(value) == "true"


def combo_label(combo):
    gamma_dec = combo.get("gamma_dec", "default")
    gamma_label = "gdecdefault" if gamma_dec == "default" else "gdec{0}".format(float_token(gamma_dec))
    label = "npt{0}_rb{1}_re{2}_abs{3}_rel{4}_{5}_noise{6}".format(
        combo["npt"],
        float_token(combo["rhobeg"]),
        float_token(combo["rhoend"]),
        float_token(combo["model_abs_tol"]),
        float_token(combo["model_rel_tol"]),
        gamma_label,
        combo["objfun_has_noise"],
    )
    suffixes = []
    if combo.get("safety_step_thresh", "default") != "default":
        suffixes.append("sst{0}".format(float_token(combo["safety_step_thresh"])))
    if combo.get("growing_safety_do_safety_step", "default") != "default":
        suffixes.append("gsds{0}".format(bool_token(combo["growing_safety_do_safety_step"])[0]))
    if combo.get("growing_safety_reduce_delta", "default") != "default":
        suffixes.append("gsrd{0}".format(bool_token(combo["growing_safety_reduce_delta"])[0]))
    if combo.get("growing_safety_full_geom_step", "default") != "default":
        suffixes.append("gsfg{0}".format(bool_token(combo["growing_safety_full_geom_step"])[0]))
    if suffixes:
        label = "{0}_{1}".format(label, "_".join(suffixes))
    return label


def build_grid(args):
    combos = []
    for (
        npt,
        rhobeg,
        rhoend,
        model_abs_tol,
        model_rel_tol,
        gamma_dec,
        safety_step_thresh,
        growing_safety_do_safety_step,
        growing_safety_reduce_delta,
        growing_safety_full_geom_step,
    ) in itertools.product(
        split_csv(args.npts),
        split_csv(args.rhobegs),
        split_csv(args.rhoends),
        split_csv(args.model_abs_tols),
        split_csv(args.model_rel_tols),
        split_csv(args.gamma_decs),
        split_csv(args.safety_step_threshes),
        split_csv(args.growing_safety_do_safety_steps),
        split_csv(args.growing_safety_reduce_deltas),
        split_csv(args.growing_safety_full_geom_steps),
    ):
        growing_safety_do_safety_step = bool_token(growing_safety_do_safety_step)
        growing_safety_reduce_delta = bool_token(growing_safety_reduce_delta)
        growing_safety_full_geom_step = bool_token(growing_safety_full_geom_step)
        if is_true_token(growing_safety_reduce_delta) and is_true_token(growing_safety_full_geom_step):
            continue
        if not is_true_token(growing_safety_do_safety_step) and growing_safety_do_safety_step != "default":
            if growing_safety_reduce_delta != "default" or growing_safety_full_geom_step != "default":
                continue
        combo = {
            "npt": npt,
            "rhobeg": rhobeg,
            "rhoend": rhoend,
            "model_abs_tol": model_abs_tol,
            "model_rel_tol": model_rel_tol,
            "gamma_dec": gamma_dec,
            "safety_step_thresh": safety_step_thresh,
            "growing_safety_do_safety_step": growing_safety_do_safety_step,
            "growing_safety_reduce_delta": growing_safety_reduce_delta,
            "growing_safety_full_geom_step": growing_safety_full_geom_step,
            "objfun_has_noise": args.objfun_has_noise,
            "maxfun": str(args.maxfun),
        }
        combo["candidate"] = combo_label(combo)
        combos.append(combo)
    return combos


def list_capture_sample_ids(case_dir, capture_prefix):
    path = case_dir / "{0}_z0.dat".format(capture_prefix)
    if not path.exists():
        raise FileNotFoundError("Missing capture file: {0}".format(path))
    sample_ids = []
    with path.open("rb") as handle:
        while True:
            head = handle.read(8)
            if not head:
                break
            if len(head) != 8:
                raise RuntimeError("Truncated stream header in {0}".format(path))
            sample_idx, n_items = struct.unpack("<ii", head)
            if n_items < 0:
                raise RuntimeError("Invalid n={0} in {1}".format(n_items, path))
            payload = handle.read(16 * n_items)
            if len(payload) != 16 * n_items:
                raise RuntimeError("Truncated payload for sample_idx={0} in {1}".format(sample_idx, path))
            sample_ids.append(sample_idx)
    return sample_ids


def selected_sample_ids(args, case_dir):
    if args.sample_ids.strip().lower() == "all":
        return list_capture_sample_ids(case_dir, args.capture_prefix)
    return [int(item) for item in split_csv(args.sample_ids)]


def write_csv(path, rows):
    if not rows:
        return
    fieldnames = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_name("{0}.tmp.{1}".format(path.name, os.getpid()))
    with tmp_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})
    tmp_path.replace(path)


def read_csv_rows(path):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def combo_dfols_params(combo, extra_params):
    params = list(extra_params)
    if combo.get("gamma_dec", "default") != "default":
        params.append("tr_radius.gamma_dec={0}".format(combo["gamma_dec"]))
    if combo.get("safety_step_thresh", "default") != "default":
        params.append("general.safety_step_thresh={0}".format(combo["safety_step_thresh"]))
    if combo.get("growing_safety_do_safety_step", "default") != "default":
        params.append("growing.safety.do_safety_step={0}".format(combo["growing_safety_do_safety_step"]))
    if combo.get("growing_safety_reduce_delta", "default") != "default":
        params.append("growing.safety.reduce_delta={0}".format(combo["growing_safety_reduce_delta"]))
    if combo.get("growing_safety_full_geom_step", "default") != "default":
        params.append("growing.safety.full_geom_step={0}".format(combo["growing_safety_full_geom_step"]))
    return params


def split_param_list(text):
    return [item for item in text.split(";") if item]


def task_rows(args, repo_root, run_root):
    case_dir = resolve_repo_path(repo_root, args.case_dir).resolve()
    samples = selected_sample_ids(args, case_dir)
    rows = []
    task_index = 1
    for combo in build_grid(args):
        candidate_dir = run_root / combo["candidate"]
        dfols_params = combo_dfols_params(combo, args.dfols_param)
        for sample_idx in samples:
            row = dict(combo)
            row.update(
                {
                    "task_index": str(task_index),
                    "sample_idx": str(sample_idx),
                    "case_dir": str(case_dir),
                    "out_csv": str(candidate_dir / "sample_{0:06d}.csv".format(sample_idx)),
                    "log": str(candidate_dir / "sample_{0:06d}.log".format(sample_idx)),
                    "diagnostic_dir": str(candidate_dir / "diagnostics" / "sample_{0:06d}".format(sample_idx)),
                    "dfols_params": ";".join(dfols_params),
                }
            )
            rows.append(row)
            task_index += 1
    return rows


def run_task(args, repo_root, row):
    python_bin = args.python or sys.executable
    external_runner = resolve_repo_path(repo_root, args.external_runner)
    bridge_bin = resolve_repo_path(repo_root, args.bridge_bin)
    parameters_file = resolve_repo_path(repo_root, args.parameters_file)
    out_csv = Path(row["out_csv"])
    log_path = Path(row["log"])
    if out_csv.exists() and not args.force:
        row = dict(row)
        row.update({"returncode": "SKIP_EXISTS", "wall_sec": "0"})
        return row

    cmd = [
        python_bin,
        str(external_runner),
        "--repo-root",
        str(repo_root),
        "--case-dir",
        row["case_dir"],
        "--bridge-bin",
        str(bridge_bin),
        "--parameters-file",
        str(parameters_file),
        "--capture-prefix",
        args.capture_prefix,
        "--seed-source",
        args.seed_source,
        "--sample-ids",
        row["sample_idx"],
        "--maxfun",
        row["maxfun"],
        "--npt",
        row["npt"],
        "--rhobeg",
        row["rhobeg"],
        "--rhoend",
        row["rhoend"],
        "--model-abs-tol",
        row["model_abs_tol"],
        "--model-rel-tol",
        row["model_rel_tol"],
        "--residual-success-tol",
        args.residual_success_tol,
        "--out-csv",
        str(out_csv),
    ]
    if row["objfun_has_noise"] == "1":
        cmd.append("--objfun-has-noise")
    dfols_params = split_param_list(row.get("dfols_params", ""))
    if args.save_diagnostics:
        dfols_params.append("logging.save_diagnostic_info=True")
        cmd.extend(["--diagnostic-dir", row["diagnostic_dir"]])
    for item in dfols_params:
        cmd.extend(["--dfols-param", item])

    row = dict(row)
    row["command"] = " ".join(cmd)
    if args.dry_run:
        row.update({"returncode": "DRY_RUN", "wall_sec": "0"})
        return row

    env = os.environ.copy()
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        env.setdefault(name, "1")
    env.setdefault("TLTM_ODE_BACKEND", "dop853")
    env.setdefault("TLTM_DOP853_HINIT_ENABLED", "1")
    env.setdefault("TLTM_DOP853_STIFFNESS_CHECK_ENABLED", "1")
    env.setdefault("TLTM_DOP853_STIFFNESS_CHECK_INTERVAL", "1000")
    env.setdefault("TLTM_DOP853_STIFFNESS_MAX_HITS", "15")
    env.setdefault("TLTM_DOP853_STIFFNESS_THRESHOLD", "6.1")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log:
        log.write("command={0}\n".format(" ".join(cmd)))
        log.flush()
        proc = subprocess.run(cmd, cwd=str(repo_root), env=env, stdout=log, stderr=subprocess.STDOUT, check=False)
    row["returncode"] = str(proc.returncode)
    row["wall_sec"] = "{0:.3f}".format(time.monotonic() - start)
    return row


def to_float(row, key, default=float("nan")):
    try:
        value = row.get(key, "")
        if value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def to_int(row, key, default=0):
    try:
        value = row.get(key, "")
        if value == "":
            return default
        return int(float(value))
    except (TypeError, ValueError):
        return default


def percentile(values, q):
    clean = [value for value in values if math.isfinite(value)]
    if not clean:
        return float("nan")
    ordered = sorted(clean)
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


def is_success(row):
    return to_int(row, "residual_success", 0) == 1 and not row.get("error", "").strip()


def is_maxfun_exhausted(row, maxfun_limit):
    if "MAXFUN" in row.get("dfols_message", "").upper():
        return True
    nf = to_float(row, "dfols_nf")
    return math.isfinite(nf) and nf >= float(maxfun_limit) and not is_success(row)


def summarize(run_root, planned_rows):
    completed_tasks = []
    task_dir = run_root / "tasks"
    for path in sorted(task_dir.glob("task_*.csv")):
        completed_tasks.extend(read_csv_rows(path))
    task_by_index = {row["task_index"]: row for row in completed_tasks if row.get("task_index")}

    attempt_rows = []
    missing_rows = []
    for task in planned_rows:
        out_csv = Path(task["out_csv"])
        rows = read_csv_rows(out_csv)
        if not rows:
            missing = dict(task)
            missing.update(task_by_index.get(task["task_index"], {}))
            missing_rows.append(missing)
            continue
        for row in rows:
            out = dict(task)
            out.update(task_by_index.get(task["task_index"], {}))
            out.update(row)
            attempt_rows.append(out)

    summary_rows = []
    candidates = sorted(set(row["candidate"] for row in planned_rows))
    for candidate in candidates:
        planned = [row for row in planned_rows if row["candidate"] == candidate]
        rows = [row for row in attempt_rows if row["candidate"] == candidate]
        success_rows = [row for row in rows if is_success(row)]
        maxfun_limit = int(float(planned[0]["maxfun"])) if planned else 0
        nf = [to_float(row, "dfols_nf") for row in rows]
        success_nf = [to_float(row, "dfols_nf") for row in success_rows]
        walls = [to_float(task_by_index.get(row["task_index"], {}), "wall_sec") for row in planned]
        maxfun_hits = sum(1 for row in rows if is_maxfun_exhausted(row, maxfun_limit))
        errors = sum(1 for row in rows if row.get("error", "").strip())
        base = dict(planned[0]) if planned else {"candidate": candidate}
        for noisy_key in ("task_index", "sample_idx", "out_csv", "log", "diagnostic_dir", "case_dir"):
            base.pop(noisy_key, None)
        base.update(
            {
                "planned_count": str(len(planned)),
                "completed_count": str(len(rows)),
                "missing_count": str(len(planned) - len(rows)),
                "success_count": str(len(success_rows)),
                "failure_count": str(len(rows) - len(success_rows)),
                "success_fraction": fmt_float(float(len(success_rows)) / float(len(rows))) if rows else "",
                "maxfun_exhausted_count": str(maxfun_hits),
                "maxfun_exhausted_fraction": fmt_float(float(maxfun_hits) / float(len(rows))) if rows else "",
                "error_count": str(errors),
                "dfols_nf_median": fmt_float(percentile(nf, 0.50)),
                "dfols_nf_p90": fmt_float(percentile(nf, 0.90)),
                "dfols_nf_max": fmt_float(percentile(nf, 1.0)),
                "dfols_nf_mean": fmt_float(sum(v for v in nf if math.isfinite(v)) / float(len([v for v in nf if math.isfinite(v)])))
                if any(math.isfinite(v) for v in nf)
                else "",
                "success_nf_median": fmt_float(percentile(success_nf, 0.50)),
                "success_nf_p90": fmt_float(percentile(success_nf, 0.90)),
                "success_nf_max": fmt_float(percentile(success_nf, 1.0)),
                "wall_sec_median": fmt_float(percentile(walls, 0.50)),
                "wall_sec_p90": fmt_float(percentile(walls, 0.90)),
                "wall_sec_max": fmt_float(percentile(walls, 1.0)),
            }
        )
        summary_rows.append(base)

    write_csv(run_root / "sample_array_attempts.csv", attempt_rows)
    write_csv(run_root / "sample_array_summary.csv", summary_rows)
    write_csv(run_root / "sample_array_missing.csv", missing_rows)
    return summary_rows, attempt_rows, missing_rows


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root)
    run_group = args.run_group or datetime.now(tz=timezone.utc).strftime("stephanov_n6_dfols_sample_array_%Y%m%dT%H%M%SZ")
    run_root = output_root / run_group
    if run_root.exists() and not (args.force or args.summarize_only or args.task_index > 0):
        raise RuntimeError("Output root exists; use --force: {0}".format(run_root))
    run_root.mkdir(parents=True, exist_ok=True)

    rows = task_rows(args, repo_root, run_root)
    write_csv(run_root / "sample_array_plan.csv", rows)
    print("[SAMPLE_ARRAY] plan={0} tasks={1}".format(run_root / "sample_array_plan.csv", len(rows)), flush=True)

    if args.write_plan_only:
        return 0

    if args.summarize_only:
        summary_rows, attempt_rows, missing_rows = summarize(run_root, rows)
        print(run_root / "sample_array_summary.csv")
        print(run_root / "sample_array_attempts.csv")
        print("[SAMPLE_ARRAY] summary_rows={0} attempt_rows={1} missing={2}".format(len(summary_rows), len(attempt_rows), len(missing_rows)))
        return 0

    if args.task_index <= 0:
        raise RuntimeError("--task-index is required unless --write-plan-only or --summarize-only is used.")
    if args.task_index > len(rows):
        raise RuntimeError("--task-index {0} exceeds task count {1}".format(args.task_index, len(rows)))

    row = run_task(args, repo_root, rows[args.task_index - 1])
    task_path = run_root / "tasks" / "task_{0:06d}.csv".format(args.task_index)
    write_csv(task_path, [row])
    print("[SAMPLE_ARRAY] task_index={0} sample={1} candidate={2} rc={3} wall={4}s".format(
        row["task_index"], row["sample_idx"], row["candidate"], row["returncode"], row["wall_sec"]
    ), flush=True)
    return 0 if str(row["returncode"]) in ("0", "DRY_RUN", "SKIP_EXISTS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
