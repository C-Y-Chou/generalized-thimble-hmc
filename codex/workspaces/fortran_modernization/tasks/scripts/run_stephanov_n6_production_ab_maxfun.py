#!/usr/bin/env python3
"""Run short production-path Stephanov n=6 nofb/withfb maxfun AB tests."""

import argparse
import csv
import math
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


KV_RE = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")


def parse_args():
    repo_root = Path(__file__).resolve().parents[5]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=str(repo_root))
    parser.add_argument("--output-root", default="output/stephanov_dfols_tuning")
    parser.add_argument("--run-group", default="")
    parser.add_argument("--records", default="0,101,202,303,404,505,606,707")
    parser.add_argument("--cycles", type=int, default=5)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--timeout-sec", type=int, default=7200)
    parser.add_argument("--seed-base", type=int, default=8930000)
    parser.add_argument("--candidate", default="all", help="Candidate label, comma list, or all.")
    parser.add_argument("--task-index", type=int, default=0, help="1-based candidate index for PBS arrays.")
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat")
    parser.add_argument("--runner", default="codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py")
    parser.add_argument("--ladder", default="0,1e-3,3e-3,7e-3,1e-2,1.3e-2,1.6e-2,1.8e-2,2e-2,2.25e-2,2.5e-2,2.75e-2,3e-2")
    parser.add_argument("--init-flow-bank-root", default="output/stephanov_flow_banks/stephanov_n6_tltm_t003_ladder13_dop853_highflow_bank_8x600_20260523_xhist_b100_s5/flow_bank_ladder13_dop853_dense_cache")
    parser.add_argument("--capture-limit", type=int, default=0)
    parser.add_argument("--capture-stride", type=int, default=1)
    parser.add_argument("--write-plan-only", action="store_true")
    parser.add_argument("--merge-only", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def resolve_repo_path(repo_root, value):
    path = Path(value)
    return path if path.is_absolute() else repo_root / path


def candidates():
    base = {
        "enable_quasi_fallback": "1",
        "npt": "0",
        "rhobeg": "0.20",
        "rhoend": "1e-13",
        "model_abs_tol": "1e-26",
        "model_rel_tol": "0",
        "objfun_has_noise": "0",
        "tr_alpha1": "",
        "tr_alpha2": "",
        "safety_step_thresh": "",
    }
    rows = [
        {
            "candidate": "nofb",
            "enable_quasi_fallback": "0",
            "npt": "",
            "rhobeg": "",
            "rhoend": "",
            "model_abs_tol": "",
            "model_rel_tol": "",
            "objfun_has_noise": "",
            "tr_alpha1": "",
            "tr_alpha2": "",
            "safety_step_thresh": "",
            "maxfun": "",
        },
        dict(base, candidate="default_mf800", maxfun="800"),
    ]
    for maxfun in (400, 500, 600, 650, 700, 800):
        rows.append(
            dict(
                base,
                candidate="tuned_mf{0}".format(maxfun),
                maxfun=str(maxfun),
                tr_alpha1="0.05",
                safety_step_thresh="0.35",
            )
        )
    return rows


def select_candidates(selection):
    all_rows = candidates()
    text = selection.strip()
    if not text or text == "all":
        return all_rows
    wanted = set(item.strip() for item in text.split(",") if item.strip())
    selected = [row for row in all_rows if row["candidate"] in wanted]
    missing = wanted.difference(row["candidate"] for row in selected)
    if missing:
        raise RuntimeError("Unknown candidate(s): {0}".format(",".join(sorted(missing))))
    return selected


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


def to_float(row, key, default=float("nan")):
    try:
        value = row.get(key, "")
        if value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def to_int(row, key, default=0):
    value = to_float(row, key)
    return int(value) if math.isfinite(value) else default


def percentile(values, q):
    clean = sorted(value for value in values if math.isfinite(value))
    if not clean:
        return float("nan")
    if len(clean) == 1:
        return clean[0]
    pos = (len(clean) - 1) * q
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(clean) - 1)
    frac = pos - lo
    return clean[lo] * (1.0 - frac) + clean[hi] * frac


def fmt(value):
    if isinstance(value, str):
        return value
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            return ""
        return "{0:.16g}".format(value)
    return str(value)


def parse_numeric(value):
    try:
        return float(value)
    except ValueError:
        return float("nan")


def add_prefixed_kvs(out, prefix, line):
    for key, raw in KV_RE.findall(line):
        if key.startswith("ratio_"):
            continue
        value = parse_numeric(raw)
        if not math.isfinite(value):
            continue
        out["{0}_{1}".format(prefix, key)] = out.get("{0}_{1}".format(prefix, key), 0.0) + value


def parse_record_summary_headers(path):
    out = {}
    if not path.exists():
        return out
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line.startswith("# constraint_stats "):
            add_prefixed_kvs(out, "constraint", line)
        elif line.startswith("# quasi_stage_stats "):
            add_prefixed_kvs(out, "quasi_stage", line)
        elif line.startswith("# qn_eval_flow_status "):
            add_prefixed_kvs(out, "qn_flow", line)
        elif line.startswith("# newton_eval_flow_status "):
            add_prefixed_kvs(out, "newton_flow", line)
        elif line.startswith("# reverse_gate_replay_status "):
            add_prefixed_kvs(out, "rg_replay", line)
        elif line.startswith("# odex_context_flowzr "):
            add_prefixed_kvs(out, "odex_flowzr", line)
        elif line.startswith("# odex_context_flowz "):
            add_prefixed_kvs(out, "odex_flowz", line)
        elif line.startswith("# odex_context_flow "):
            add_prefixed_kvs(out, "odex_flow", line)
        elif line.startswith("# odex_stats "):
            add_prefixed_kvs(out, "odex", line)
    return out


def collect_record_header_sums(candidate_dir):
    sums = {}
    for summary_path in sorted(candidate_dir.glob("records/record_*/summary.dat")):
        row = parse_record_summary_headers(summary_path)
        for key, value in row.items():
            sums[key] = sums.get(key, 0.0) + value
    return sums


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
    record_rows = read_csv_rows(candidate_dir / "tltm_ladder_summary.csv")
    aggregate_rows = read_csv_rows(candidate_dir / "tltm_ladder_aggregate.csv")
    aggregate = aggregate_rows[0] if aggregate_rows else {}
    attempt_rows = collect_attempt_rows(candidate, candidate_dir)
    evals = [to_float(row, "residual_eval_count") for row in attempt_rows]
    cpu = [to_float(row, "cpu_seconds") for row in attempt_rows]
    best = [to_float(row, "best_residual_norm") for row in attempt_rows]
    converged_rows = [row for row in attempt_rows if to_int(row, "converged") == 1]
    converged = len(converged_rows)
    maxfun = to_int(candidate, "maxfun", 0)
    maxfun_hits = sum(
        1 for row in attempt_rows
        if maxfun > 0 and to_int(row, "converged") == 0 and to_float(row, "residual_eval_count") >= maxfun
    )
    record_wall = [to_float(row, "wall_sec") for row in record_rows]
    out = dict(candidate)
    out.update(
        {
            "returncode": str(returncode),
            "candidate_wall_sec": elapsed_sec,
            "record_count": len(record_rows),
            "record_statuses": ";".join(row.get("status", "") for row in record_rows),
            "max_record_wall_sec": max(record_wall) if record_wall else 0.0,
            "mean_record_wall_sec": sum(record_wall) / float(len(record_wall)) if record_wall else 0.0,
            "attempt_count": len(attempt_rows),
            "converged_count": converged,
            "converged_fraction": float(converged) / float(len(attempt_rows)) if attempt_rows else "",
            "maxfun_hit_count": maxfun_hits,
            "eval_count_median": percentile(evals, 0.50),
            "eval_count_p90": percentile(evals, 0.90),
            "eval_count_max": percentile(evals, 1.0),
            "converged_eval_count_p90": percentile([to_float(row, "residual_eval_count") for row in converged_rows], 0.90),
            "converged_eval_count_max": percentile([to_float(row, "residual_eval_count") for row in converged_rows], 1.0),
            "attempt_cpu_sec_median": percentile(cpu, 0.50),
            "attempt_cpu_sec_p90": percentile(cpu, 0.90),
            "best_residual_median": percentile(best, 0.50),
            "best_residual_p90": percentile(best, 0.90),
            "total_round_trip": to_int(aggregate, "total_round_trip", 0),
            "total_proposal_failure": to_int(aggregate, "total_proposal_failure", 0),
            "total_reverse_gate_reject": to_int(aggregate, "total_reverse_gate_reject", 0),
            "candidate_dir": str(candidate_dir),
        }
    )
    out.update(collect_record_header_sums(candidate_dir))
    return out, attempt_rows


def env_set_or_unset(env, name, value):
    if str(value).strip():
        env[name] = str(value)
    else:
        env.pop(name, None)


def run_candidate(args, repo_root, run_root, candidate):
    runner = resolve_repo_path(repo_root, args.runner)
    candidate_dir = run_root / candidate["candidate"]
    capture_root = candidate_dir / "qn_attempt_capture"
    env = os.environ.copy()
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        env[name] = str(max(1, args.threads))
    env.update(
        {
            "TLTM_ODE_BACKEND": "dop853",
            "TLTM_DOP853_HINIT_ENABLED": "1",
            "TLTM_DOP853_STIFFNESS_CHECK_ENABLED": "1",
            "TLTM_DOP853_STIFFNESS_CHECK_INTERVAL": "1000",
            "TLTM_DOP853_STIFFNESS_MAX_HITS": "15",
            "TLTM_DOP853_STIFFNESS_THRESHOLD": "6.1",
            "TLTM_STAGE2_SWAP_REFLOW_BACKEND": "direct",
            "TLTM_STAGE2_LOCAL_REFLOW_CACHE_MODE": "none",
        }
    )
    if candidate["enable_quasi_fallback"] == "1":
        env.update(
            {
                "QN_SOLVER_BACKEND": "official_dfols",
                "QN_OFFICIAL_DFOLS_PRESET": "stable_gate77",
                "QN_OFFICIAL_DFOLS_NPT": candidate["npt"],
                "QN_OFFICIAL_DFOLS_MAXFUN": candidate["maxfun"],
                "QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE": candidate["objfun_has_noise"],
                "QN_OFFICIAL_DFOLS_RHOBEG": candidate["rhobeg"],
                "QN_OFFICIAL_DFOLS_RHOEND": candidate["rhoend"],
                "QN_OFFICIAL_DFOLS_MODEL_ABS_TOL": candidate["model_abs_tol"],
                "QN_OFFICIAL_DFOLS_MODEL_REL_TOL": candidate["model_rel_tol"],
            }
        )
        env_set_or_unset(env, "QN_OFFICIAL_DFOLS_TR_ALPHA1", candidate["tr_alpha1"])
        env_set_or_unset(env, "QN_OFFICIAL_DFOLS_TR_ALPHA2", candidate["tr_alpha2"])
        env_set_or_unset(env, "QN_OFFICIAL_DFOLS_SAFETY_STEP_THRESH", candidate["safety_step_thresh"])
    else:
        for key in (
            "QN_SOLVER_BACKEND",
            "QN_OFFICIAL_DFOLS_PRESET",
            "QN_OFFICIAL_DFOLS_NPT",
            "QN_OFFICIAL_DFOLS_MAXFUN",
            "QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE",
            "QN_OFFICIAL_DFOLS_RHOBEG",
            "QN_OFFICIAL_DFOLS_RHOEND",
            "QN_OFFICIAL_DFOLS_MODEL_ABS_TOL",
            "QN_OFFICIAL_DFOLS_MODEL_REL_TOL",
            "QN_OFFICIAL_DFOLS_TR_ALPHA1",
            "QN_OFFICIAL_DFOLS_TR_ALPHA2",
            "QN_OFFICIAL_DFOLS_SAFETY_STEP_THRESH",
        ):
            env.pop(key, None)

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
        "--output-root",
        str(run_root),
        "--run-name",
        candidate["candidate"],
        "--force",
    ]
    if candidate["enable_quasi_fallback"] == "1":
        cmd.extend(
            [
                "--enable-quasi-fallback",
                "--qn-attempt-capture-root",
                str(capture_root),
                "--qn-attempt-capture-limit",
                str(args.capture_limit),
                "--qn-attempt-capture-stride",
                str(args.capture_stride),
            ]
        )
    if args.dry_run:
        print(" ".join(cmd))
        return 0, 0.0
    start = time.monotonic()
    proc = subprocess.run(cmd, cwd=str(repo_root), env=env, check=False)
    return proc.returncode, time.monotonic() - start


def sidecar_summary_path(run_root, candidate_label):
    return run_root / "summaries" / "{0}_summary.csv".format(candidate_label)


def sidecar_attempts_path(run_root, candidate_label):
    return run_root / "attempts" / "{0}_attempts.csv".format(candidate_label)


def write_plan(run_root, selected):
    rows = []
    for idx, row in enumerate(selected, start=1):
        out = dict(row)
        out["task_index"] = idx
        rows.append(out)
    write_csv(run_root / "production_ab_plan.csv", rows)
    print("[PROD_AB] plan={0} tasks={1}".format(run_root / "production_ab_plan.csv", len(rows)), flush=True)
    return rows


def merge_sidecars(run_root, plan_rows):
    summary_rows = []
    attempt_rows = []
    for row in plan_rows:
        summary_rows.extend(read_csv_rows(sidecar_summary_path(run_root, row["candidate"])))
        attempt_rows.extend(read_csv_rows(sidecar_attempts_path(run_root, row["candidate"])))
    nofb = next((row for row in summary_rows if row.get("candidate") == "nofb"), None)
    if nofb:
        base_wall = to_float(nofb, "candidate_wall_sec")
        base_max_record = to_float(nofb, "max_record_wall_sec")
        for row in summary_rows:
            wall = to_float(row, "candidate_wall_sec")
            max_record_wall = to_float(row, "max_record_wall_sec")
            row["wall_factor_vs_nofb"] = wall / base_wall if base_wall > 0.0 else ""
            row["max_record_wall_factor_vs_nofb"] = max_record_wall / base_max_record if base_max_record > 0.0 else ""
    write_csv(run_root / "production_ab_summary.csv", summary_rows)
    write_csv(run_root / "production_ab_attempts.csv", attempt_rows)
    print(run_root / "production_ab_summary.csv")
    print(run_root / "production_ab_attempts.csv")
    print("[PROD_AB] summary_rows={0} attempt_rows={1}".format(len(summary_rows), len(attempt_rows)), flush=True)
    return summary_rows, attempt_rows


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root)
    run_group = args.run_group or datetime.now(tz=timezone.utc).strftime("stephanov_n6_production_ab_%Y%m%dT%H%M%SZ")
    run_root = output_root / run_group
    selected = select_candidates(args.candidate)
    if run_root.exists() and not (args.force or args.merge_only or args.task_index > 0):
        raise RuntimeError("Run root exists; use --force: {0}".format(run_root))
    run_root.mkdir(parents=True, exist_ok=True)
    plan_rows = write_plan(run_root, selected)

    if args.write_plan_only:
        return 0
    if args.merge_only:
        merge_sidecars(run_root, plan_rows)
        return 0
    if args.task_index > 0:
        if args.task_index > len(plan_rows):
            raise RuntimeError("--task-index {0} exceeds task count {1}".format(args.task_index, len(plan_rows)))
        plan_rows = [plan_rows[args.task_index - 1]]

    summary_rows = []
    attempt_rows = []
    for candidate in plan_rows:
        print("[PROD_AB] start {0}".format(candidate["candidate"]), flush=True)
        rc, elapsed = run_candidate(args, repo_root, run_root, candidate)
        candidate_dir = run_root / candidate["candidate"]
        summary, attempts = summarize_candidate(candidate, candidate_dir, elapsed, rc)
        write_csv(sidecar_summary_path(run_root, candidate["candidate"]), [summary])
        write_csv(sidecar_attempts_path(run_root, candidate["candidate"]), attempts)
        summary_rows.append(summary)
        attempt_rows.extend(attempts)
        print(
            "[PROD_AB] done {0} rc={1} wall={2:.1f}s attempts={3} converged={4}".format(
                candidate["candidate"], rc, elapsed, summary["attempt_count"], summary["converged_count"]
            ),
            flush=True,
        )
        if rc != 0:
            raise RuntimeError("Candidate failed: {0}".format(candidate["candidate"]))

    if args.task_index <= 0:
        merge_sidecars(run_root, selected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
