#!/usr/bin/env python3
"""Run the tiny assist-regression reproducer at one or more commits.

The script intentionally uses the checked-out commit's own stage-3 runner so
method-level env semantics move with the code under test.
"""

from __future__ import annotations

import argparse
import csv
import os
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_CONFIG_PATH = REPO_ROOT / "codex/workspaces/assist_regression_bisect/configs/tiny_1seed_200cycle_p28_rg.json"
RESULT_ROOT = REPO_ROOT / "output/assist_regression_bisect"
LOG_ROOT = REPO_ROOT / "output/logs/assist_regression_bisect"
PYTHON_DFOLS = Path("/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/bin/python")
DFOLS_SITE = Path("/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/lib/python3.11/site-packages")


BASE_ENV = {
    "TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE": "1e-13",
    "QN_REVERSE_GATE_ENABLED": "1",
    "QN_REVERSE_GATE_TOL": "1e-8",
    "QN_S1_PROBE_MAX_ITER": "28",
    "QN_S1_NEAR_RESCUE_ENABLED": "0",
    "QN_S1_NONNEAR_RESCUE_ENABLED": "0",
    "QN_QUASI_GLOBAL_FALLBACK_ENABLED": "0",
    "QN_QUASI_TOL_OVERRIDE": "1e-13",
    "QN_SOLVER_BACKEND": "official_dfols",
    "QN_OFFICIAL_DFOLS_PRESET": "stable_gate77",
    "ENABLE_OFFICIAL_DFOLS": "1",
    "OMP_NUM_THREADS": "1",
    "MKL_NUM_THREADS": "1",
    "OPENBLAS_NUM_THREADS": "1",
    "VECLIB_MAXIMUM_THREADS": "1",
    "NUMEXPR_NUM_THREADS": "1",
}


RESULT_COLUMNS = [
    "label",
    "commit",
    "commit_short",
    "commit_subject",
    "method",
    "status",
    "assist_override",
    "mean_Ohat_re",
    "mean_Ohat_im",
    "total_unresolved_failure_count",
    "total_reverse_gate_total_reject_count",
    "mean_quasi_probe_success_count",
    "mean_full_stage_trigger_count",
    "total_newton_eval_flow_success_count",
    "total_newton_eval_flow_solver_assist_count",
    "total_newton_eval_flow_failure_max_steps_count",
    "total_newton_eval_flow_failure_invalid_count",
    "total_newton_eval_flow_failure_h_min_count",
    "total_qn_eval_flow_success_count",
    "total_qn_eval_flow_solver_assist_count",
    "total_qn_eval_flow_failure_max_steps_count",
    "total_qn_eval_flow_failure_invalid_count",
    "total_qn_eval_flow_failure_h_min_count",
    "output_dir",
    "log_dir",
]


def run(cmd: list[str], env: dict[str, str] | None = None, cwd: Path = REPO_ROOT) -> str:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError("command failed ({0}):\n{1}".format(" ".join(cmd), proc.stdout))
    return proc.stdout


def current_commit() -> str:
    return run(["git", "rev-parse", "HEAD"]).strip()


def commit_subject(commit: str) -> str:
    return run(["git", "show", "--no-patch", "--format=%s", commit]).strip()


def checkout_commit(commit: str) -> str:
    run(["git", "checkout", "--detach", commit])
    return current_commit()


def clean_build() -> None:
    run(["make", "-C", "build", "clean"])


def build_binaries(env: dict[str, str]) -> None:
    run(
        [
            "make",
            "-C",
            "build",
            "OMP=0",
            "ENABLE_OFFICIAL_DFOLS=1",
            "../bin/run_tltm_stage2",
            "../bin/evaluate_expectations",
        ],
        env=env,
    )


def solve_flow_has_typed_policy() -> bool:
    text = (REPO_ROOT / "src/physics/solve_flow.f90").read_text(errors="replace")
    return "INTODE_SOLVER_ASSIST_POLICY" in text and "all_navigation_diagnostic" in text


def stage_runner_for_label(label: str, force_navigation_assist: bool) -> Path:
    runner = REPO_ROOT / "scripts/run_stage3_3_multiseed.py"
    if not force_navigation_assist or not solve_flow_has_typed_policy():
        return runner

    text = runner.read_text(errors="replace")
    text = text.replace(
        '"INTODE_SOLVER_ASSIST_POLICY": "off"',
        '"INTODE_SOLVER_ASSIST_POLICY": "all_navigation_diagnostic"',
    )
    text = text.replace(
        '"INTODE_SOLVER_ASSIST_POLICY": "qn_navigation"',
        '"INTODE_SOLVER_ASSIST_POLICY": "all_navigation_diagnostic"',
    )
    text = text.replace(
        '"INTODE_SOLVER_ASSIST_POLICY": "nt_strict_qn_navassist_cert_strict_rg_metropolis_v1"',
        '"INTODE_SOLVER_ASSIST_POLICY": "all_navigation_diagnostic"',
    )
    patched = RESULT_ROOT / "patched_runners" / label / "run_stage3_3_multiseed.py"
    patched.parent.mkdir(parents=True, exist_ok=True)
    patched.write_text(text)
    return patched


def runner_supports_skip_build(runner_script: Path) -> bool:
    text = runner_script.read_text(errors="replace")
    return "--skip-build" in text


def run_method(label: str, method: str, env: dict[str, str], config_path: Path, runner_script: Path) -> dict[str, str]:
    out_dir = RESULT_ROOT / "runs" / label / method
    logs_dir = LOG_ROOT / "runs" / label / method
    if out_dir.exists():
        shutil.rmtree(out_dir)
    if logs_dir.exists():
        shutil.rmtree(logs_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        sys.executable,
        str(runner_script),
        "--config",
        str(config_path),
        "--methods",
        method,
        "--max-seeds",
        "1",
        "--jobs",
        "1",
        "--stage2-threads",
        "1",
        "--eval-threads",
        "1",
        "--pair-order",
        "no_fb_first",
        "--output-subdir",
        str(out_dir),
        "--logs-subdir",
        str(logs_dir),
        "--log-prefix",
        "assist_regression_tiny",
        "--report-title",
        "Assist Regression Tiny Reproducer",
    ]
    if runner_supports_skip_build(runner_script):
        cmd.append("--skip-build")
    run(cmd, env=env)

    aggregate_path = out_dir / "aggregated_summary_table.csv"
    with aggregate_path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise RuntimeError("expected exactly one aggregate row in {0}, found {1}".format(aggregate_path, len(rows)))
    row = rows[0]
    row["output_dir"] = str(out_dir)
    row["log_dir"] = str(logs_dir)
    return row


def write_results(rows: list[dict[str, str]]) -> Path:
    out = RESULT_ROOT / "results" / "tiny_results.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    existing: list[dict[str, str]] = []
    if out.exists():
        with out.open(newline="") as f:
            existing = list(csv.DictReader(f))
    merged_by_key = {}
    for row in existing + rows:
        key = (row.get("label", ""), row.get("commit", ""), row.get("method", ""))
        merged_by_key[key] = row
    merged = list(merged_by_key.values())
    with out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=RESULT_COLUMNS)
        writer.writeheader()
        for row in merged:
            writer.writerow({key: row.get(key, "") for key in RESULT_COLUMNS})
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("commits", nargs="+", help="Commits or refs to test.")
    parser.add_argument("--label-prefix", default="", help="Optional label prefix.")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG_PATH, help="Tiny reproducer JSON config.")
    parser.add_argument(
        "--force-navigation-assist",
        action="store_true",
        help="Force legacy NT+QN navigation assist: legacy commits get INTODE_SOLVER_ASSIST_ENABLED=1; typed-policy commits get all_navigation_diagnostic.",
    )
    args = parser.parse_args()

    config_path = args.config
    if not config_path.is_absolute():
        config_path = REPO_ROOT / config_path
    if not config_path.exists():
        raise SystemExit("missing config: {0}".format(config_path))
    if not PYTHON_DFOLS.exists():
        raise SystemExit("missing DFO-LS Python: {0}".format(PYTHON_DFOLS))
    if not DFOLS_SITE.exists():
        raise SystemExit("missing DFO-LS site-packages: {0}".format(DFOLS_SITE))

    env = os.environ.copy()
    env.update(BASE_ENV)
    env["PYTHON"] = str(PYTHON_DFOLS)
    env["TLTM_OFFICIAL_DFOLS_PYTHONPATH"] = str(DFOLS_SITE)
    if args.force_navigation_assist:
        env["INTODE_SOLVER_ASSIST_ENABLED"] = "1"

    produced: list[dict[str, str]] = []
    for raw_commit in args.commits:
        commit = checkout_commit(raw_commit)
        short = commit[:7]
        label = "{0}{1}".format(args.label_prefix, short)
        subject = commit_subject(commit)
        typed_policy = solve_flow_has_typed_policy()
        assist_override = "none"
        if args.force_navigation_assist:
            assist_override = "INTODE_SOLVER_ASSIST_ENABLED=1"
            if typed_policy:
                env["INTODE_SOLVER_ASSIST_POLICY"] = "all_navigation_diagnostic"
                assist_override = "INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic"
            else:
                env.pop("INTODE_SOLVER_ASSIST_POLICY", None)
        runner_script = stage_runner_for_label(label, args.force_navigation_assist)
        print("[COMMIT] {0} {1}".format(short, subject), flush=True)
        if assist_override != "none":
            print("[ASSIST] {0}".format(assist_override), flush=True)
        clean_build()
        build_binaries(env)
        for method in ("no_fb", "fb_norefine"):
            print("[RUN] {0} {1}".format(short, method), flush=True)
            try:
                row = run_method(label, method, env, config_path, runner_script)
                row.update(
                    {
                        "label": label,
                        "commit": commit,
                        "commit_short": short,
                        "commit_subject": subject,
                        "status": "ok",
                        "assist_override": assist_override,
                    }
                )
            except Exception as exc:
                row = {
                    "label": label,
                    "commit": commit,
                    "commit_short": short,
                    "commit_subject": subject,
                    "method": method,
                    "status": "failed: {0}".format(exc),
                    "assist_override": assist_override,
                }
            produced.append(row)
        results_path = write_results(produced)
        print("[RESULTS] {0}".format(results_path), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
