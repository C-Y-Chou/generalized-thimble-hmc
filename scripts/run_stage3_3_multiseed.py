#!/usr/bin/env python3

import argparse
import csv
import json
import math
import os
import statistics
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


REVERSE_GATE_ROUTE_NAMES = [
    "total",
    "probe_only",
    "full_stage",
    "near_rescue",
    "nonnear_route",
    "class_local",
    "class_mid",
    "class_global",
    "far_skip",
    "far_light",
    "far_anchor",
]

LOCAL_TRANSITION_NAMES = [
    "metropolis_reject",
    "reverse_gate_reject",
    "proposal_failure",
    "hamiltonian_invalid",
    "delta_h_invalid",
    "output_size_mismatch",
]

QN_EVAL_FLOW_STATUS_NAMES = [
    "success",
    "zero_time",
    "stiff_rescue",
    "solver_assist",
    "failure_max_steps",
    "failure_invalid",
    "failure_h_min",
    "unknown",
]

NEWTON_EVAL_FLOW_STATUS_NAMES = QN_EVAL_FLOW_STATUS_NAMES

REVERSE_GATE_REPLAY_STATUS_NAMES = [
    "success",
    "output_size_mismatch",
    "momentum_size_mismatch",
    "initial_force_failed",
    "constraint_failed",
    "final_flow_failed",
    "final_force_failed",
    "final_projection_failed",
    "reverse_gate_rejected",
    "final_flow_max_steps",
    "final_flow_invalid",
    "final_flow_h_min",
    "final_flow_non_strict_success",
    "unknown",
]

CVODE_STAT_NAMES = [
    "calls",
    "success",
    "failure",
    "steps",
    "rhs_evals",
    "error_test_fails",
    "nonlinear_iters",
    "nonlinear_conv_fails",
    "step_solve_fails",
    "final_order_sum",
    "max_final_order",
]

METHOD_SPECS = {
    "no_fb": {
        "fallback_enabled": False,
        "env_overrides": {
            "INTODE_SOLVER_ASSIST_POLICY": "off",
        },
    },
    "fb": {
        "fallback_enabled": True,
        "env_overrides": {
            "INTODE_SOLVER_ASSIST_POLICY": "off",
        },
    },
    "fb_norefine": {
        "fallback_enabled": True,
        "env_overrides": {
            "INTODE_SOLVER_ASSIST_POLICY": "off",
        },
    },
}


def reverse_gate_count_columns():
    columns = []
    for route_name in REVERSE_GATE_ROUTE_NAMES:
        for status_name in ("candidate", "pass", "reject"):
            columns.append("reverse_gate_{0}_{1}_count".format(route_name, status_name))
    return columns


def reverse_gate_aggregate_columns():
    return ["total_{0}".format(column) for column in reverse_gate_count_columns()]


def local_transition_count_columns():
    return ["local_{0}_count".format(name) for name in LOCAL_TRANSITION_NAMES]


def local_transition_aggregate_columns():
    return ["total_{0}".format(column) for column in local_transition_count_columns()]


def stage3_protocol_metadata_columns():
    return [
        "stage2_v1_sidecar_enabled",
        "stage2_v1_output_dir",
        "stage2_v1_manifest_file",
        "stage2_v1_protocol_file",
        "stage2_protocol_audit_json",
        "stage2_protocol_audit_text",
        "stage2_protocol_audit_verdict",
        "stage2_protocol_audit_errors",
        "stage2_protocol_audit_warnings",
        "stage2_protocol_audit_checks",
    ]


def qn_eval_flow_status_count_columns():
    return ["qn_eval_flow_{0}_count".format(name) for name in QN_EVAL_FLOW_STATUS_NAMES]


def qn_eval_flow_status_aggregate_columns():
    return ["total_{0}".format(column) for column in qn_eval_flow_status_count_columns()]


def newton_eval_flow_status_count_columns():
    return ["newton_eval_flow_{0}_count".format(name) for name in NEWTON_EVAL_FLOW_STATUS_NAMES]


def newton_eval_flow_status_aggregate_columns():
    return ["total_{0}".format(column) for column in newton_eval_flow_status_count_columns()]


def reverse_gate_replay_status_count_columns():
    return ["reverse_gate_replay_{0}_count".format(name) for name in REVERSE_GATE_REPLAY_STATUS_NAMES]


def reverse_gate_replay_status_aggregate_columns():
    return ["total_{0}".format(column) for column in reverse_gate_replay_status_count_columns()]


def cvode_stat_columns():
    return ["cvode_{0}".format(name) for name in CVODE_STAT_NAMES]


def cvode_aggregate_columns():
    return ["total_{0}".format(column) for column in cvode_stat_columns()] + [
        "mean_cvode_rhs_per_call",
        "mean_cvode_steps_per_call",
        "mean_cvode_nonlinear_iters_per_call",
        "mean_cvode_error_test_fails_per_call",
    ]


def parse_args():
    def env_choice(name, default, choices):
        value = os.environ.get(name, default).strip().lower()
        return value if value in choices else default

    parser = argparse.ArgumentParser(
        description="Run stage-3.3 multiseed matched-control compare (fallback off vs on)."
    )
    parser.add_argument("--repo-root", default=".", help="Path to repository root.")
    parser.add_argument(
        "--config",
        default="docs/stage_3_3_todo.json",
        help="Path to stage-3.3 protocol JSON (relative to repo root or absolute).",
    )
    parser.add_argument(
        "--max-seeds",
        type=int,
        default=0,
        help="Optional positive cap for seed count (0 means use full frozen list).",
    )
    parser.add_argument(
        "--seed-offset",
        type=int,
        default=0,
        help="Optional zero-based offset into the frozen seed list before applying --max-seeds.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip building run_tltm_stage2/evaluate_expectations before running.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned runs without executing.",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=1,
        help="Parallel worker count (>=1).",
    )
    parser.add_argument(
        "--stage2-threads",
        type=int,
        default=int(os.environ.get("STAGE3_3_STAGE2_THREADS", "1")),
        help="OMP/MKL thread budget for each run_tltm_stage2 process.",
    )
    parser.add_argument(
        "--eval-threads",
        type=int,
        default=int(os.environ.get("STAGE3_3_EVAL_THREADS", "1")),
        help="OMP/MKL thread budget for each evaluate_expectations process.",
    )
    parser.add_argument(
        "--schedule",
        choices=("paired", "task"),
        default=os.environ.get("STAGE3_3_SCHEDULE", "paired"),
        help="paired runs grouped methods for each seed on the same worker; task keeps the legacy flat task queue.",
    )
    parser.add_argument(
        "--pair-order",
        choices=("alternating", "no_fb_first", "fb_first"),
        default=os.environ.get("STAGE3_3_PAIR_ORDER", "alternating"),
        help="Method order inside each seed pair when --schedule=paired.",
    )
    parser.add_argument(
        "--task-method-order",
        choices=("no_fb_first", "fb_first"),
        default=os.environ.get("STAGE3_3_TASK_METHOD_ORDER", "no_fb_first"),
        help="Method ordering for the flat task queue when --schedule=task.",
    )
    parser.add_argument(
        "--methods",
        choices=("both", "no_fb_fbnorefine", "no_fb", "fb", "fb_norefine"),
        default=os.environ.get("STAGE3_3_METHODS", "both"),
        help="Select methods to run. 'both'=no_fb+fb; 'no_fb_fbnorefine'=production comparison pair.",
    )
    parser.add_argument(
        "--allow-oversubscribe",
        action="store_true",
        help="Allow jobs * max(stage2/eval threads) to exceed detected CPU budget.",
    )
    parser.add_argument(
        "--output-subdir",
        default="output/tests/stage3_3",
        help="Output directory relative to repo root, or absolute. Default preserves stage-3.3 behavior.",
    )
    parser.add_argument(
        "--logs-subdir",
        default="output/logs",
        help="Log directory relative to repo root, or absolute. Default preserves stage-3.3 behavior.",
    )
    parser.add_argument(
        "--log-prefix",
        default="stage3_3",
        help="Prefix used in per-seed stage2/eval log filenames.",
    )
    parser.add_argument(
        "--report-title",
        default="TLTM Stage-3.3 Multiseed Report",
        help="Markdown title for the generated report.",
    )
    parser.add_argument(
        "--stage2-v1-sidecars",
        choices=("off", "on"),
        default=env_choice("STAGE3_3_STAGE2_V1_SIDECARS", "off", ("off", "on")),
        help="When on, ask each Stage2 run to write v1alpha sidecars under its per-seed output directory.",
    )
    parser.add_argument(
        "--stage2-protocol-audit",
        choices=("off", "on", "auto"),
        default=env_choice("STAGE3_3_STAGE2_PROTOCOL_AUDIT", "auto", ("off", "on", "auto")),
        help="Run the parser-only Stage2 protocol audit. 'auto' runs it when --stage2-v1-sidecars=on.",
    )
    parser.add_argument(
        "--stage2-protocol-audit-fail-on",
        choices=("error", "warning", "never"),
        default=env_choice("STAGE3_3_STAGE2_PROTOCOL_AUDIT_FAIL_ON", "error", ("error", "warning", "never")),
        help="Failure policy passed to audit_tltm_tempering_protocol.py.",
    )
    return parser.parse_args()


def resolve_repo_path(repo_root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return repo_root / path


def detect_available_cpus():
    nodefile = os.environ.get("PBS_NODEFILE")
    if nodefile:
        try:
            with open(nodefile) as f:
                n_lines = sum(1 for line in f if line.strip())
            if n_lines > 0:
                return n_lines
        except OSError:
            pass

    try:
        return len(os.sched_getaffinity(0))
    except AttributeError:
        pass

    return os.cpu_count() or 1


def validate_resource_budget(jobs, stage2_threads, eval_threads, allow_oversubscribe):
    if jobs < 1:
        raise ValueError("--jobs must be >= 1.")
    if stage2_threads < 1:
        raise ValueError("--stage2-threads must be >= 1.")
    if eval_threads < 1:
        raise ValueError("--eval-threads must be >= 1.")

    available_cpus = detect_available_cpus()
    threads_per_worker = max(stage2_threads, eval_threads)
    requested_cpus = jobs * threads_per_worker
    if requested_cpus > available_cpus and not allow_oversubscribe:
        raise ValueError(
            "Requested CPU budget exceeds detected allocation: "
            "jobs({0}) * max(stage2_threads={1}, eval_threads={2}) = {3}, "
            "available_cpus={4}. Lower --jobs/threads or pass --allow-oversubscribe.".format(
                jobs, stage2_threads, eval_threads, requested_cpus, available_cpus
            )
        )
    return {
        "available_cpus": available_cpus,
        "threads_per_worker": threads_per_worker,
        "requested_cpus": requested_cpus,
    }


def read_protocol(repo_root, config_path):
    config_file = Path(config_path)
    if not config_file.is_absolute():
        config_file = repo_root / config_file
    with config_file.open() as f:
        raw_config = json.load(f)

    if "stage_3_3_todo" in raw_config:
        protocol = raw_config["stage_3_3_todo"]
    elif "stage_3_4_todo" in raw_config:
        protocol = raw_config["stage_3_4_todo"]
    elif len(raw_config) == 1:
        protocol = next(iter(raw_config.values()))
    else:
        raise ValueError("Config must contain stage_3_3_todo or stage_3_4_todo.")

    frozen = protocol.get("frozen_setup", protocol.get("candidate_setup"))
    if frozen is None:
        raise ValueError("Protocol must contain frozen_setup or candidate_setup.")
    sampling = protocol["sampling_plan"]
    observable_def = protocol.get("observable_definition", {})

    seed_list = sampling.get("seed_list")
    if seed_list is None:
        n_generated_seeds = int(sampling.get("n_seeds", 0))
        seed_start = int(sampling.get("seed_start", 0))
        seed_stride = int(sampling.get("seed_stride", 97))
        if n_generated_seeds < 1 or seed_start <= 0:
            raise ValueError(
                "sampling_plan must provide seed_list, or seed_start with positive n_seeds."
            )
        seed_list = [seed_start + seed_stride * i for i in range(n_generated_seeds)]
    if not isinstance(seed_list, list) or len(seed_list) < 1:
        raise ValueError("sampling_plan.seed_list must be a non-empty list.")
    seed_list = [int(x) for x in seed_list]

    cycles = int(sampling["cycles_per_seed"])
    warmup = int(sampling.get("warmup_cycles_optional", 0))
    if cycles < 1:
        raise ValueError("cycles_per_seed must be >= 1.")
    if warmup < 0:
        raise ValueError("warmup_cycles_optional must be >= 0.")
    if warmup != 0:
        raise ValueError(
            "warmup_cycles_optional must be 0 for Stage3 multiseed runs; "
            "run_tltm_stage2 does not discard/evaluate a separate warmup window."
        )

    setup = {
        "ladder": [float(x) for x in frozen["flow_time_ladder"]],
        "max_flow_time": float(frozen.get("max_flow_time", max(float(x) for x in frozen["flow_time_ladder"]))),
        "trajectory_length": float(frozen["trajectory_length_L"]),
        "integration_steps": int(frozen["nstep"]),
        "local_updates_per_cycle": int(frozen["local_updates_per_cycle"]),
        "cycles_per_seed": cycles,
        "warmup_cycles": warmup,
        "seed_list": seed_list,
        "config_file": config_file,
        "observable_exact_re": float(observable_def.get("exact_re", 0.0)),
        "observable_exact_im": float(observable_def.get("exact_im", 0.0)),
        "stage2_init_mode": str(frozen.get("stage2_init_mode", protocol.get("stage2_init_mode", ""))).strip(),
        "stage2_rng_stream_contract": str(
            frozen.get(
                "stage2_rng_stream_contract",
                protocol.get(
                    "stage2_rng_stream_contract",
                    os.environ.get("TLTM_STAGE2_RNG_STREAM_CONTRACT", "stage2_kernel_rng_v2"),
                ),
            )
        ).strip(),
        "write_all_replica_history": bool(
            protocol.get("write_all_replica_history", frozen.get("write_all_replica_history", False))
        ),
    }
    return setup


def run_command(cmd, env, cwd, log_file):
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    log_file.parent.mkdir(parents=True, exist_ok=True)
    log_file.write_text(proc.stdout)
    if proc.returncode != 0:
        raise RuntimeError("Command failed: {0}\nSee log: {1}".format(" ".join(cmd), log_file))


def relpath_text(repo_root, path):
    if not path:
        return ""
    path = Path(path)
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def should_run_protocol_audit(audit_mode, stage2_v1_sidecars_enabled):
    if audit_mode == "on":
        return True
    if audit_mode == "auto":
        return bool(stage2_v1_sidecars_enabled)
    return False


def run_stage2_protocol_audit(
    repo_root,
    summary_file,
    label_trace_file,
    manifest_file=None,
    protocol_file=None,
    stage3_per_seed_file=None,
    seed_id=None,
    method_name=None,
    out_json=None,
    out_text=None,
    fail_on="error",
):
    cmd = [
        sys.executable,
        str(repo_root / "scripts" / "audit_tltm_tempering_protocol.py"),
        "--summary",
        str(summary_file),
        "--label-trace",
        str(label_trace_file),
        "--fail-on",
        fail_on,
    ]
    if manifest_file:
        cmd.extend(["--manifest", str(manifest_file)])
    if protocol_file:
        cmd.extend(["--protocol", str(protocol_file)])
    if stage3_per_seed_file:
        cmd.extend(["--stage3-per-seed", str(stage3_per_seed_file)])
    if seed_id is not None:
        cmd.extend(["--stage3-seed-id", str(seed_id)])
    if method_name:
        cmd.extend(["--stage3-method", str(method_name)])
    if out_json:
        out_json = Path(out_json)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        cmd.extend(["--out-json", str(out_json)])
    if out_text:
        out_text = Path(out_text)
        out_text.parent.mkdir(parents=True, exist_ok=True)
        cmd.extend(["--out-text", str(out_text)])

    proc = subprocess.run(
        cmd,
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        output_hint = ""
        if out_text and Path(out_text).exists():
            output_hint = "\nSee audit report: {0}".format(out_text)
        raise RuntimeError("Stage2 protocol audit failed: {0}\n{1}{2}".format(" ".join(cmd), proc.stdout, output_hint))

    report = {}
    if out_json and Path(out_json).exists():
        report = json.loads(Path(out_json).read_text())
    verdict = report.get("verdict", {}) if isinstance(report, dict) else {}
    return {
        "json_file": "" if out_json is None else str(out_json),
        "text_file": "" if out_text is None else str(out_text),
        "verdict": verdict.get("verdict", ""),
        "errors": verdict.get("errors", ""),
        "warnings": verdict.get("warnings", ""),
        "checks": verdict.get("total", ""),
    }


def build_binaries(repo_root, omp_enabled):
    build_dir = repo_root / "build"
    cmd = [
        "make",
        "-B",
        "-C",
        str(build_dir),
        "OMP={0}".format(1 if omp_enabled else 0),
        "ENABLE_OFFICIAL_DFOLS=1",
        "../bin/run_tltm_stage2",
        "../bin/evaluate_expectations",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError("Failed to build required binaries.\n{0}".format(proc.stdout))


def configure_thread_env(env, n_threads):
    n_threads = max(1, int(n_threads))
    env["OMP_NUM_THREADS"] = str(n_threads)
    env["MKL_NUM_THREADS"] = str(n_threads)
    env.setdefault("OMP_PROC_BIND", "true")
    env.setdefault("OMP_PLACES", "cores")


def selected_manifest_env(env):
    selected = {}
    exact_keys = {
        "CHAIN_RNG_SEED",
        "OMP_NUM_THREADS",
        "MKL_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "NUMEXPR_NUM_THREADS",
        "TLTM_OFFICIAL_DFOLS_PYTHONPATH",
        "TLTM_ODE_BACKEND",
    }
    prefixes = (
        "INTODE_",
        "TLTM_CVODE_",
        "TLTM_LOCAL_",
        "TLTM_RG_",
        "TLTM_STAGE2_",
        "QN_",
        "S1_",
        "CONSTRAINT_",
    )
    for key, value in sorted(env.items()):
        if key in exact_keys or any(key.startswith(prefix) for prefix in prefixes):
            selected[key] = value
    return selected


def render_parameters_text(
    base_parameters_text,
    fallback_enabled,
    trajectory_length,
    integration_steps,
    warmup_cycles,
    x_history_file,
    initial_flow_time=None,
    constraint_tol_override=None,
):
    lines = base_parameters_text.splitlines()

    def set_key(lines_in, key, value):
        out = []
        found = False
        key_l = key.lower()
        for line in lines_in:
            stripped = line.strip().lower()
            if stripped.startswith(key_l + " ") or stripped.startswith(key_l + "="):
                out.append("{0} = {1}".format(key, value))
                found = True
            else:
                out.append(line)
        if not found:
            out.append("{0} = {1}".format(key, value))
        return out

    lines = set_key(lines, "trajectory_length", "{0:g}".format(trajectory_length))
    lines = set_key(lines, "integration_steps", str(integration_steps))
    if initial_flow_time is not None:
        lines = set_key(lines, "initial_flow_time", "{0:g}".format(initial_flow_time))
    lines = set_key(lines, "warmup", str(warmup_cycles))
    if constraint_tol_override is not None:
        lines = set_key(lines, "constraint_tol", "{0:.17e}".format(float(constraint_tol_override)))
        lines = set_key(lines, "cttol", "{0:.17e}".format(float(constraint_tol_override)))
    lines = set_key(lines, "enable_quasi_fallback", "true" if fallback_enabled else "false")
    lines = set_key(lines, "x_history_file", str(x_history_file))
    return "\n".join(lines) + "\n"


def parse_key_value_ints(line):
    out = {}
    parts = line.replace("=", " ").split()
    for i in range(0, len(parts) - 1, 2):
        k = parts[i]
        v = parts[i + 1]
        try:
            out[k] = int(v)
        except ValueError:
            try:
                out[k] = float(v)
            except ValueError:
                out[k] = v
    return out


def parse_stage2_summary(summary_path):
    lines = summary_path.read_text().splitlines()

    elapsed_sec = 0.0
    total_round_trip = 0
    constraint_stats = {"total": 0, "newton": 0, "quasi": 0, "failed": 0}
    quasi_stage_stats = {"probe_attempt": 0, "probe_success": 0, "full_attempt": 0, "full_success": 0}
    quasi_class_stats = {"local": 0, "mid": 0, "global": 0}
    far_route_stats = {"skip": 0, "light": 0, "anchor": 0}
    near_rescue_stats = {"candidate": 0, "attempt": 0, "success": 0, "unusable": 0}
    quasi_watchdog_stats = {"hit": 0, "used_sum": 0, "used_max": 0, "budget_last": 0}
    far_investment_stats = {
        "scope": 0,
        "success": 0,
        "fail": 0,
        "fail_fast": 0,
        "spent_success": 0,
        "spent_fail": 0,
    }
    far_investment_units = {
        "flowzr": 0,
        "final": 0,
        "success_flowzr": 0,
        "success_final": 0,
        "fail_flowzr": 0,
        "fail_final": 0,
    }
    quasi_global_filter_stats = {"candidate": 0, "pass": 0, "reject": 0}
    newton_eval_flow_status_stats = {name: 0 for name in NEWTON_EVAL_FLOW_STATUS_NAMES}
    qn_eval_flow_status_stats = {name: 0 for name in QN_EVAL_FLOW_STATUS_NAMES}
    reverse_gate_replay_status_stats = {name: 0 for name in REVERSE_GATE_REPLAY_STATUS_NAMES}
    cvode_stats = {name: 0 for name in CVODE_STAT_NAMES}
    reverse_gate_route_stats = {
        "candidate": {route_name: 0 for route_name in REVERSE_GATE_ROUTE_NAMES},
        "pass": {route_name: 0 for route_name in REVERSE_GATE_ROUTE_NAMES},
        "reject": {route_name: 0 for route_name in REVERSE_GATE_ROUTE_NAMES},
    }
    local_transition_stats = {name: 0 for name in LOCAL_TRANSITION_NAMES}
    accepted_local_census = {
        "accepted_total": 0,
        "newton_only": 0,
        "quasi": 0,
        "rescue": 0,
        "probe_only": 0,
        "full_stage": 0,
        "near_rescue": 0,
        "nonnear_route": 0,
        "uncategorized": 0,
    }
    accepted_local_routes = {
        "class_local": 0,
        "class_mid": 0,
        "class_global": 0,
        "far_skip": 0,
        "far_light": 0,
        "far_anchor": 0,
    }
    slot_accept_rate = {}
    slot_projection_fail = {}
    pair_accept_rate = {}
    farthest_by_label = {}
    avg_round_trip_by_label = {}

    section = None
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("# elapsed_sec="):
            elapsed_sec = float(line.split("=", 1)[1].strip())
            continue
        if line.startswith("# total_round_trip="):
            total_round_trip = int(line.split("=", 1)[1].strip())
            continue
        if line.startswith("# cvode_stats "):
            kv = parse_key_value_ints(line[len("# cvode_stats ") :])
            for key in cvode_stats:
                if key in kv:
                    cvode_stats[key] = int(kv[key])
            continue
        if line.startswith("# constraint_stats "):
            kv = parse_key_value_ints(line[len("# constraint_stats ") :])
            for key in ("total", "newton", "quasi", "failed"):
                if key in kv:
                    constraint_stats[key] = int(kv[key])
            continue
        if line.startswith("# quasi_stage_stats "):
            kv = parse_key_value_ints(line[len("# quasi_stage_stats ") :])
            for key in ("probe_attempt", "probe_success", "full_attempt", "full_success"):
                if key in kv:
                    quasi_stage_stats[key] = int(kv[key])
            continue
        if line.startswith("# quasi_class_stats "):
            kv = parse_key_value_ints(line[len("# quasi_class_stats ") :])
            for key in quasi_class_stats:
                if key in kv:
                    quasi_class_stats[key] = int(kv[key])
            continue
        if line.startswith("# far_route_stats "):
            kv = parse_key_value_ints(line[len("# far_route_stats ") :])
            for key in far_route_stats:
                if key in kv:
                    far_route_stats[key] = int(kv[key])
            continue
        if line.startswith("# near_rescue_stats "):
            kv = parse_key_value_ints(line[len("# near_rescue_stats ") :])
            for key in near_rescue_stats:
                if key in kv:
                    near_rescue_stats[key] = int(kv[key])
            continue
        if line.startswith("# quasi_watchdog_stats "):
            kv = parse_key_value_ints(line[len("# quasi_watchdog_stats ") :])
            for key in quasi_watchdog_stats:
                if key in kv:
                    quasi_watchdog_stats[key] = int(kv[key])
            continue
        if line.startswith("# far_investment_stats "):
            kv = parse_key_value_ints(line[len("# far_investment_stats ") :])
            for key in far_investment_stats:
                if key in kv:
                    far_investment_stats[key] = int(kv[key])
            continue
        if line.startswith("# far_investment_units "):
            kv = parse_key_value_ints(line[len("# far_investment_units ") :])
            for key in far_investment_units:
                if key in kv:
                    far_investment_units[key] = int(kv[key])
            continue
        if line.startswith("# quasi_global_filter_stats "):
            kv = parse_key_value_ints(line[len("# quasi_global_filter_stats ") :])
            for key in quasi_global_filter_stats:
                if key in kv:
                    quasi_global_filter_stats[key] = int(kv[key])
            continue
        if line.startswith("# newton_eval_flow_status "):
            kv = parse_key_value_ints(line[len("# newton_eval_flow_status ") :])
            for key in newton_eval_flow_status_stats:
                if key in kv:
                    newton_eval_flow_status_stats[key] = int(kv[key])
            continue
        if line.startswith("# qn_eval_flow_status "):
            kv = parse_key_value_ints(line[len("# qn_eval_flow_status ") :])
            for key in qn_eval_flow_status_stats:
                if key in kv:
                    qn_eval_flow_status_stats[key] = int(kv[key])
            continue
        if line.startswith("# reverse_gate_replay_status "):
            kv = parse_key_value_ints(line[len("# reverse_gate_replay_status ") :])
            for key in reverse_gate_replay_status_stats:
                if key in kv:
                    reverse_gate_replay_status_stats[key] = int(kv[key])
            continue
        if line.startswith("# reverse_gate_route_candidates "):
            kv = parse_key_value_ints(line[len("# reverse_gate_route_candidates ") :])
            for key in reverse_gate_route_stats["candidate"]:
                if key in kv:
                    reverse_gate_route_stats["candidate"][key] = int(kv[key])
            continue
        if line.startswith("# reverse_gate_route_pass "):
            kv = parse_key_value_ints(line[len("# reverse_gate_route_pass ") :])
            for key in reverse_gate_route_stats["pass"]:
                if key in kv:
                    reverse_gate_route_stats["pass"][key] = int(kv[key])
            continue
        if line.startswith("# reverse_gate_route_reject "):
            kv = parse_key_value_ints(line[len("# reverse_gate_route_reject ") :])
            for key in reverse_gate_route_stats["reject"]:
                if key in kv:
                    reverse_gate_route_stats["reject"][key] = int(kv[key])
            continue
        if line.startswith("# local_transition_totals "):
            kv = parse_key_value_ints(line[len("# local_transition_totals ") :])
            for key in local_transition_stats:
                if key in kv:
                    local_transition_stats[key] = int(kv[key])
            continue
        if line.startswith("# accepted_local_census_totals "):
            kv = parse_key_value_ints(line[len("# accepted_local_census_totals ") :])
            for key in accepted_local_census:
                if key in kv:
                    accepted_local_census[key] = int(kv[key])
            continue
        if line.startswith("# accepted_local_route_totals "):
            kv = parse_key_value_ints(line[len("# accepted_local_route_totals ") :])
            for key in accepted_local_routes:
                if key in kv:
                    accepted_local_routes[key] = int(kv[key])
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
            slot_id = int(parts[0])
            slot_accept_rate[slot_id] = float(parts[5])
            slot_projection_fail[slot_id] = int(parts[6])
        elif section == "pairs" and len(parts) >= 7:
            pair_id = int(parts[0])
            pair_accept_rate[pair_id] = float(parts[6])
        elif section == "labels" and len(parts) >= 5:
            label_id = int(parts[0])
            farthest_by_label[label_id] = int(parts[2])
            avg_round_trip_by_label[label_id] = float(parts[4])

    projection_failure_count = sum(slot_projection_fail.values())
    fallback_trigger_count = quasi_stage_stats["probe_attempt"] + quasi_stage_stats["full_attempt"]
    local_accept_rate_mean = (
        sum(slot_accept_rate.values()) / float(len(slot_accept_rate)) if slot_accept_rate else 0.0
    )
    observed_avg_rt = [v for v in avg_round_trip_by_label.values() if v > 0.0]
    avg_round_trip_cycles_if_observed = (
        sum(observed_avg_rt) / float(len(observed_avg_rt)) if observed_avg_rt else 0.0
    )

    return {
        "elapsed_sec": elapsed_sec,
        "projection_failure_count": projection_failure_count,
        "unresolved_failure_count": constraint_stats["failed"],
        "fallback_trigger_count": fallback_trigger_count,
        "quasi_probe_success_count": quasi_stage_stats["probe_success"],
        "full_stage_trigger_count": quasi_stage_stats["full_attempt"],
        "full_stage_success_count": quasi_stage_stats["full_success"],
        "quasi_class_local_count": quasi_class_stats["local"],
        "quasi_class_mid_count": quasi_class_stats["mid"],
        "quasi_class_global_count": quasi_class_stats["global"],
        "far_route_skip_count": far_route_stats["skip"],
        "far_route_light_count": far_route_stats["light"],
        "far_route_anchor_count": far_route_stats["anchor"],
        "near_rescue_candidate_count": near_rescue_stats["candidate"],
        "near_rescue_attempt_count": near_rescue_stats["attempt"],
        "near_rescue_success_count": near_rescue_stats["success"],
        "near_rescue_unusable_count": near_rescue_stats["unusable"],
        "quasi_watchdog_hit_count": quasi_watchdog_stats["hit"],
        "quasi_watchdog_used_sum": quasi_watchdog_stats["used_sum"],
        "quasi_watchdog_used_max": quasi_watchdog_stats["used_max"],
        "quasi_watchdog_budget_last": quasi_watchdog_stats["budget_last"],
        "far_investment_scope_count": far_investment_stats["scope"],
        "far_investment_success_count": far_investment_stats["success"],
        "far_investment_fail_count": far_investment_stats["fail"],
        "far_investment_fail_fast_count": far_investment_stats["fail_fast"],
        "far_investment_spent_success_count": far_investment_stats["spent_success"],
        "far_investment_spent_fail_count": far_investment_stats["spent_fail"],
        "far_investment_flowzr_units": far_investment_units["flowzr"],
        "far_investment_final_units": far_investment_units["final"],
        "far_investment_success_flowzr_units": far_investment_units["success_flowzr"],
        "far_investment_success_final_units": far_investment_units["success_final"],
        "far_investment_fail_flowzr_units": far_investment_units["fail_flowzr"],
        "far_investment_fail_final_units": far_investment_units["fail_final"],
        "quasi_global_filter_candidate_count": quasi_global_filter_stats["candidate"],
        "quasi_global_filter_pass_count": quasi_global_filter_stats["pass"],
        "quasi_global_filter_reject_count": quasi_global_filter_stats["reject"],
        **{
            "reverse_gate_{0}_{1}_count".format(route_name, status_name): reverse_gate_route_stats[status_name][
                route_name
            ]
            for route_name in REVERSE_GATE_ROUTE_NAMES
            for status_name in ("candidate", "pass", "reject")
        },
        **{
            "newton_eval_flow_{0}_count".format(name): newton_eval_flow_status_stats[name]
            for name in NEWTON_EVAL_FLOW_STATUS_NAMES
        },
        **{"qn_eval_flow_{0}_count".format(name): qn_eval_flow_status_stats[name] for name in QN_EVAL_FLOW_STATUS_NAMES},
        **{
            "reverse_gate_replay_{0}_count".format(name): reverse_gate_replay_status_stats[name]
            for name in REVERSE_GATE_REPLAY_STATUS_NAMES
        },
        **{"cvode_{0}".format(name): cvode_stats[name] for name in CVODE_STAT_NAMES},
        **{"local_{0}_count".format(name): local_transition_stats[name] for name in LOCAL_TRANSITION_NAMES},
        "accepted_local_total": accepted_local_census["accepted_total"],
        "accepted_local_newton_only_count": accepted_local_census["newton_only"],
        "accepted_local_quasi_count": accepted_local_census["quasi"],
        "accepted_local_rescue_count": accepted_local_census["rescue"],
        "accepted_local_probe_only_count": accepted_local_census["probe_only"],
        "accepted_local_full_stage_count": accepted_local_census["full_stage"],
        "accepted_local_near_rescue_count": accepted_local_census["near_rescue"],
        "accepted_local_nonnear_route_count": accepted_local_census["nonnear_route"],
        "accepted_local_uncategorized_count": accepted_local_census["uncategorized"],
        "accepted_local_class_local_count": accepted_local_routes["class_local"],
        "accepted_local_class_mid_count": accepted_local_routes["class_mid"],
        "accepted_local_class_global_count": accepted_local_routes["class_global"],
        "accepted_local_far_skip_count": accepted_local_routes["far_skip"],
        "accepted_local_far_light_count": accepted_local_routes["far_light"],
        "accepted_local_far_anchor_count": accepted_local_routes["far_anchor"],
        "pair0_accept_rate": pair_accept_rate.get(0, 0.0),
        "total_round_trip": total_round_trip,
        "avg_round_trip_cycles_if_observed": avg_round_trip_cycles_if_observed,
        "slot_accept_rate": slot_accept_rate,
        "pair_accept_rate": pair_accept_rate,
        "farthest_by_label": farthest_by_label,
        "local_accept_rate_mean": local_accept_rate_mean,
    }


def parse_hot_end_hits_label0(label_trace_path):
    records = []
    with label_trace_path.open() as f:
        for raw in f:
            line = raw.strip()
            if (not line) or line.startswith("#"):
                continue
            cycle_idx, label_id, slot_id, round_trip_count = [int(x) for x in line.split()]
            records.append((cycle_idx, label_id, slot_id, round_trip_count))
    if not records:
        return 0
    hot_slot = max(r[2] for r in records)
    return sum(1 for r in records if r[1] == 0 and r[2] == hot_slot)


def parse_multichain_metadata(meta_path):
    kv = {}
    with meta_path.open() as f:
        for raw in f:
            line = raw.strip()
            if (not line) or line.startswith("#") or ("=" not in line):
                continue
            key, value = line.split("=", 1)
            kv[key.strip()] = value.strip()

    def parse_pair(name):
        token = kv.get(name, "")
        parts = token.split()
        if len(parts) < 2:
            raise ValueError("Missing pair field: {0} in {1}".format(name, meta_path))
        return float(parts[0]), float(parts[1])

    def parse_logical(name, default=False):
        token = kv.get(name, "").strip().lower()
        if token in ("t", "true", "1", "yes", "y", "on"):
            return True
        if token in ("f", "false", "0", "no", "n", "off"):
            return False
        return default

    mean_virial_re, mean_virial_im = parse_pair("mean_virial_re_im")
    err_robust_re, err_robust_im = parse_pair("err_robust_virial_re_im")
    err_robust_valid = parse_logical("err_robust_virial_valid", default=False)

    return {
        "mean_virial_re": mean_virial_re,
        "mean_virial_im": mean_virial_im,
        "err_robust_virial_re": err_robust_re,
        "err_robust_virial_im": err_robust_im,
        "err_robust_virial_valid": err_robust_valid,
    }


def safe_zscore(delta, err):
    if not math.isfinite(delta) or (not math.isfinite(err)) or err <= 0.0:
        return float("nan")
    return delta / err


def as_finite_number(value):
    if isinstance(value, (int, float)):
        return float(value) if math.isfinite(value) else None
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            number = float(text)
        except ValueError:
            return None
        return number if math.isfinite(number) else None
    return None


def finite_values(values):
    out = []
    for value in values:
        number = as_finite_number(value)
        if number is not None:
            out.append(number)
    return out


def safe_mean(values):
    vals = finite_values(values)
    return sum(vals) / float(len(vals)) if vals else float("nan")


def safe_median(values):
    vals = finite_values(values)
    return statistics.median(vals) if vals else float("nan")


def coverage_fraction(values, threshold):
    vals = finite_values(values)
    if not vals:
        return float("nan")
    return sum(1 for v in vals if abs(v) <= threshold) / float(len(vals))


def safe_sample_std(values):
    vals = finite_values(values)
    if len(vals) < 2:
        return float("nan")
    return statistics.stdev(vals)


def zmean_from_seed_means(values, exact_value):
    vals = finite_values(values)
    n_vals = len(vals)
    if n_vals < 2:
        return float("nan")

    mean_val = sum(vals) / float(n_vals)
    ss = sum((v - mean_val) ** 2 for v in vals)
    denom_sq = ss / float(n_vals * (n_vals - 1))
    if (not math.isfinite(denom_sq)) or denom_sq <= 0.0:
        return float("nan")

    denom = math.sqrt(denom_sq)
    if (not math.isfinite(denom)) or denom <= 0.0:
        return float("nan")

    delta = mean_val - float(exact_value)
    if not math.isfinite(delta):
        return float("nan")
    return delta / denom


def run_one_seed(
    repo_root,
    setup,
    method_name,
    fallback_enabled,
    seed_id,
    base_parameters_text,
    stage2_threads,
    eval_threads,
    schedule_name,
    out_dir,
    logs_dir,
    log_prefix,
    method_env_overrides=None,
    stage2_v1_sidecars_enabled=False,
    protocol_audit_mode="auto",
    protocol_audit_fail_on="error",
):
    out_root = out_dir / method_name / ("seed_{0}".format(seed_id))
    work_root = out_dir / "_work" / method_name / ("seed_{0}".format(seed_id))
    work_build_dir = work_root / "build"
    work_data_dir = work_root / "data"
    out_root.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    work_build_dir.mkdir(parents=True, exist_ok=True)
    work_data_dir.mkdir(parents=True, exist_ok=True)

    summary_file = out_root / "tltm_stage2_summary.dat"
    label_trace_file = out_root / "tltm_stage2_label_trace.dat"
    eval_run_dir = out_root / "eval_multichain"
    eval_chain_output_dir = eval_run_dir / "chain_001" / "output"
    eval_chain_output_dir.mkdir(parents=True, exist_ok=True)
    cold_z_history_file = eval_chain_output_dir / "z_history.dat"
    cold_phi_history_file = eval_chain_output_dir / "phi_history.dat"
    all_replica_history_dir = out_root / "all_replica_history"
    stage2_v1_output_dir = out_root / "stage2_v1alpha"
    stage2_v1_manifest_file = stage2_v1_output_dir / "manifest.json"
    stage2_v1_protocol_file = stage2_v1_output_dir / "protocol.json"
    protocol_audit_json = out_root / "protocol_audit.json"
    protocol_audit_text = out_root / "protocol_audit.txt"
    capture_base_dir = out_root / "output"
    capture_base_dir.mkdir(parents=True, exist_ok=True)
    x_history_file = capture_base_dir / "x_history.dat"

    stage2_log = logs_dir / ("tltm_{0}_{1}_seed{2}.log".format(log_prefix, method_name, seed_id))
    eval_log = logs_dir / ("eval_{0}_{1}_seed{2}.log".format(log_prefix, method_name, seed_id))
    meta_file = eval_run_dir / "multichain_expectations.dat"
    isolated_params = render_parameters_text(
        base_parameters_text=base_parameters_text,
        fallback_enabled=fallback_enabled,
        trajectory_length=setup["trajectory_length"],
        integration_steps=setup["integration_steps"],
        warmup_cycles=setup["warmup_cycles"],
        x_history_file=x_history_file,
        initial_flow_time=setup.get("max_flow_time"),
        constraint_tol_override=os.environ.get("TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE"),
    )
    (work_data_dir / "parameters.dat").write_text(isolated_params)

    env_stage2 = dict(os.environ)
    configure_thread_env(env_stage2, stage2_threads)
    env_stage2.update(
        {
            "CHAIN_RNG_SEED": str(seed_id),
            "TLTM_STAGE2_FLOW_TIME_LADDER": ",".join("{0:g}".format(x) for x in setup["ladder"]),
            "TLTM_STAGE2_MAX_FLOW_TIME": "{0:g}".format(setup["max_flow_time"]),
            "TLTM_STAGE2_NUM_REPLICAS": str(len(setup["ladder"])),
            "TLTM_STAGE2_CYCLES": str(setup["cycles_per_seed"]),
            "TLTM_STAGE2_LOCAL_UPDATES": str(setup["local_updates_per_cycle"]),
            "TLTM_STAGE2_SWAP_ENABLED": "1",
            "TLTM_STAGE2_SUMMARY_FILE": str(summary_file),
            "TLTM_STAGE2_LABEL_TRACE_FILE": str(label_trace_file),
            "TLTM_STAGE2_COLD_Z_HISTORY_FILE": str(cold_z_history_file),
            "TLTM_STAGE2_COLD_PHI_HISTORY_FILE": str(cold_phi_history_file),
            "TLTM_STAGE2_RNG_STREAM_CONTRACT": setup["stage2_rng_stream_contract"],
            # Keep failure-capture counters off the active window in stage-3.3 production runs.
            "CONSTRAINT_FAIL_CAPTURE_START_SAMPLE": os.environ.get("CONSTRAINT_FAIL_CAPTURE_START_SAMPLE", "2147483647"),
        }
    )
    if method_env_overrides:
        env_stage2.update(method_env_overrides)
    qn_capture_base = os.environ.get("QN_ATTEMPT_CAPTURE_BASE_DIR", "").strip()
    if qn_capture_base:
        qn_capture_dir = Path(qn_capture_base) / method_name / ("seed_{0}".format(seed_id))
        qn_capture_dir.mkdir(parents=True, exist_ok=True)
        env_stage2["QN_ATTEMPT_CAPTURE_DIR"] = str(qn_capture_dir)
    local_transition_audit_base = os.environ.get("TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR", "").strip()
    if local_transition_audit_base:
        local_transition_audit_root = Path(local_transition_audit_base)
        if not local_transition_audit_root.is_absolute():
            local_transition_audit_root = repo_root / local_transition_audit_root
        local_transition_audit_dir = local_transition_audit_root / method_name / ("seed_{0}".format(seed_id))
        local_transition_audit_dir.mkdir(parents=True, exist_ok=True)
        env_stage2["TLTM_LOCAL_TRANSITION_AUDIT_FILE"] = str(local_transition_audit_dir / "local_transition_audit.csv")
    if "CONSTRAINT_FAIL_CAPTURE_LIMIT" in os.environ:
        env_stage2["CONSTRAINT_FAIL_CAPTURE_LIMIT"] = os.environ["CONSTRAINT_FAIL_CAPTURE_LIMIT"]
    if setup.get("stage2_init_mode"):
        env_stage2["TLTM_STAGE2_INIT_MODE"] = setup["stage2_init_mode"]
    if setup.get("write_all_replica_history", False):
        env_stage2["TLTM_STAGE2_ALL_REPLICA_HISTORY_DIR"] = str(all_replica_history_dir)
    if stage2_v1_sidecars_enabled:
        env_stage2["TLTM_STAGE2_V1_OUTPUT_DIR"] = str(stage2_v1_output_dir)

    manifest = {
        "method": method_name,
        "fallback_enabled": bool(fallback_enabled),
        "seed": int(seed_id),
        "config_file": str(setup["config_file"]),
        "schedule": schedule_name,
        "stage2_threads": int(stage2_threads),
        "eval_threads": int(eval_threads),
        "setup": {
            "ladder": setup["ladder"],
            "max_flow_time": setup["max_flow_time"],
            "trajectory_length": setup["trajectory_length"],
            "integration_steps": setup["integration_steps"],
            "local_updates_per_cycle": setup["local_updates_per_cycle"],
            "cycles_per_seed": setup["cycles_per_seed"],
            "warmup_cycles": setup["warmup_cycles"],
            "stage2_rng_stream_contract": setup["stage2_rng_stream_contract"],
        },
        "stage2_env": selected_manifest_env(env_stage2),
        "paths": {
            "summary_file": str(summary_file),
            "label_trace_file": str(label_trace_file),
            "cold_z_history_file": str(cold_z_history_file),
            "cold_phi_history_file": str(cold_phi_history_file),
            "parameters_file": str(work_data_dir / "parameters.dat"),
            "stage2_v1_output_dir": str(stage2_v1_output_dir) if stage2_v1_sidecars_enabled else "",
            "stage2_v1_manifest_file": str(stage2_v1_manifest_file) if stage2_v1_sidecars_enabled else "",
            "stage2_v1_protocol_file": str(stage2_v1_protocol_file) if stage2_v1_sidecars_enabled else "",
            "protocol_audit_json": (
                str(protocol_audit_json)
                if should_run_protocol_audit(protocol_audit_mode, stage2_v1_sidecars_enabled)
                else ""
            ),
            "protocol_audit_text": (
                str(protocol_audit_text)
                if should_run_protocol_audit(protocol_audit_mode, stage2_v1_sidecars_enabled)
                else ""
            ),
        },
    }
    (out_root / "run_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    run_command([str(repo_root / "bin" / "run_tltm_stage2")], env_stage2, work_build_dir, stage2_log)

    audit_result = {
        "json_file": "",
        "text_file": "",
        "verdict": "",
        "errors": "",
        "warnings": "",
        "checks": "",
    }
    if should_run_protocol_audit(protocol_audit_mode, stage2_v1_sidecars_enabled):
        audit_result = run_stage2_protocol_audit(
            repo_root=repo_root,
            summary_file=summary_file,
            label_trace_file=label_trace_file,
            manifest_file=stage2_v1_manifest_file if stage2_v1_sidecars_enabled else None,
            protocol_file=stage2_v1_protocol_file if stage2_v1_sidecars_enabled else None,
            out_json=protocol_audit_json,
            out_text=protocol_audit_text,
            fail_on=protocol_audit_fail_on,
        )

    env_eval = dict(os.environ)
    configure_thread_env(env_eval, eval_threads)
    env_eval["EVAL_MULTICHAIN_RUN_DIR"] = str(eval_run_dir)
    run_command([str(repo_root / "bin" / "evaluate_expectations")], env_eval, work_build_dir, eval_log)

    stage2_metrics = parse_stage2_summary(summary_file)
    hot_end_hit_count = parse_hot_end_hits_label0(label_trace_file)
    obs_metrics = parse_multichain_metadata(meta_file)

    delta_re = obs_metrics["mean_virial_re"] - setup["observable_exact_re"]
    delta_im = obs_metrics["mean_virial_im"] - setup["observable_exact_im"]
    zp_re = safe_zscore(delta_re, obs_metrics["err_robust_virial_re"])
    zp_im = safe_zscore(delta_im, obs_metrics["err_robust_virial_im"])
    if math.isfinite(zp_re) and math.isfinite(zp_im):
        zp_abs_max = max(abs(zp_re), abs(zp_im))
    else:
        zp_abs_max = float("nan")

    row = {
        "seed_id": seed_id,
        "method": method_name,
        "projection_failure_count": stage2_metrics["projection_failure_count"],
        "unresolved_failure_count": stage2_metrics["unresolved_failure_count"],
        "fallback_trigger_count": stage2_metrics["fallback_trigger_count"],
        "quasi_probe_success_count": stage2_metrics["quasi_probe_success_count"],
        "full_stage_trigger_count": stage2_metrics["full_stage_trigger_count"],
        "full_stage_success_count": stage2_metrics["full_stage_success_count"],
        "quasi_class_local_count": stage2_metrics["quasi_class_local_count"],
        "quasi_class_mid_count": stage2_metrics["quasi_class_mid_count"],
        "quasi_class_global_count": stage2_metrics["quasi_class_global_count"],
        "far_route_skip_count": stage2_metrics["far_route_skip_count"],
        "far_route_light_count": stage2_metrics["far_route_light_count"],
        "far_route_anchor_count": stage2_metrics["far_route_anchor_count"],
        "near_rescue_candidate_count": stage2_metrics["near_rescue_candidate_count"],
        "near_rescue_attempt_count": stage2_metrics["near_rescue_attempt_count"],
        "near_rescue_success_count": stage2_metrics["near_rescue_success_count"],
        "near_rescue_unusable_count": stage2_metrics["near_rescue_unusable_count"],
        "quasi_watchdog_hit_count": stage2_metrics["quasi_watchdog_hit_count"],
        "quasi_watchdog_used_sum": stage2_metrics["quasi_watchdog_used_sum"],
        "quasi_watchdog_used_max": stage2_metrics["quasi_watchdog_used_max"],
        "quasi_watchdog_budget_last": stage2_metrics["quasi_watchdog_budget_last"],
        "far_investment_scope_count": stage2_metrics["far_investment_scope_count"],
        "far_investment_success_count": stage2_metrics["far_investment_success_count"],
        "far_investment_fail_count": stage2_metrics["far_investment_fail_count"],
        "far_investment_fail_fast_count": stage2_metrics["far_investment_fail_fast_count"],
        "far_investment_spent_success_count": stage2_metrics["far_investment_spent_success_count"],
        "far_investment_spent_fail_count": stage2_metrics["far_investment_spent_fail_count"],
        "far_investment_flowzr_units": stage2_metrics["far_investment_flowzr_units"],
        "far_investment_final_units": stage2_metrics["far_investment_final_units"],
        "far_investment_success_flowzr_units": stage2_metrics["far_investment_success_flowzr_units"],
        "far_investment_success_final_units": stage2_metrics["far_investment_success_final_units"],
        "far_investment_fail_flowzr_units": stage2_metrics["far_investment_fail_flowzr_units"],
        "far_investment_fail_final_units": stage2_metrics["far_investment_fail_final_units"],
        "quasi_global_filter_candidate_count": stage2_metrics["quasi_global_filter_candidate_count"],
        "quasi_global_filter_pass_count": stage2_metrics["quasi_global_filter_pass_count"],
        "quasi_global_filter_reject_count": stage2_metrics["quasi_global_filter_reject_count"],
        **{column: stage2_metrics[column] for column in reverse_gate_count_columns()},
        **{column: stage2_metrics[column] for column in newton_eval_flow_status_count_columns()},
        **{column: stage2_metrics[column] for column in qn_eval_flow_status_count_columns()},
        **{column: stage2_metrics[column] for column in reverse_gate_replay_status_count_columns()},
        **{column: stage2_metrics[column] for column in cvode_stat_columns()},
        **{column: stage2_metrics[column] for column in local_transition_count_columns()},
        "accepted_local_total": stage2_metrics["accepted_local_total"],
        "accepted_local_newton_only_count": stage2_metrics["accepted_local_newton_only_count"],
        "accepted_local_quasi_count": stage2_metrics["accepted_local_quasi_count"],
        "accepted_local_rescue_count": stage2_metrics["accepted_local_rescue_count"],
        "accepted_local_probe_only_count": stage2_metrics["accepted_local_probe_only_count"],
        "accepted_local_full_stage_count": stage2_metrics["accepted_local_full_stage_count"],
        "accepted_local_near_rescue_count": stage2_metrics["accepted_local_near_rescue_count"],
        "accepted_local_nonnear_route_count": stage2_metrics["accepted_local_nonnear_route_count"],
        "accepted_local_uncategorized_count": stage2_metrics["accepted_local_uncategorized_count"],
        "accepted_local_class_local_count": stage2_metrics["accepted_local_class_local_count"],
        "accepted_local_class_mid_count": stage2_metrics["accepted_local_class_mid_count"],
        "accepted_local_class_global_count": stage2_metrics["accepted_local_class_global_count"],
        "accepted_local_far_skip_count": stage2_metrics["accepted_local_far_skip_count"],
        "accepted_local_far_light_count": stage2_metrics["accepted_local_far_light_count"],
        "accepted_local_far_anchor_count": stage2_metrics["accepted_local_far_anchor_count"],
        "pair0_accept_rate": stage2_metrics["pair0_accept_rate"],
        "total_round_trip": stage2_metrics["total_round_trip"],
        "avg_round_trip_cycles_if_observed": stage2_metrics["avg_round_trip_cycles_if_observed"],
        "hot_end_hit_count": hot_end_hit_count,
        "runtime_total": stage2_metrics["elapsed_sec"],
        "runtime_per_cycle": stage2_metrics["elapsed_sec"] / float(setup["cycles_per_seed"]),
        "stage2_threads": stage2_threads,
        "eval_threads": eval_threads,
        "stage2_init_mode": setup.get("stage2_init_mode", ""),
        "max_flow_time": setup.get("max_flow_time", ""),
        "schedule": schedule_name,
        "Ohat_re": obs_metrics["mean_virial_re"],
        "Ohat_im": obs_metrics["mean_virial_im"],
        "err_Ohat_re": obs_metrics["err_robust_virial_re"],
        "err_Ohat_im": obs_metrics["err_robust_virial_im"],
        "err_Ohat_valid": int(obs_metrics["err_robust_virial_valid"]),
        "Zp_re": zp_re,
        "Zp_im": zp_im,
        "Zp_abs_max": zp_abs_max,
        # keep canonical todo column aliases
        "Ohat": obs_metrics["mean_virial_re"],
        "err_Ohat": obs_metrics["err_robust_virial_re"],
        "Zp": zp_abs_max,
        "local_accept_rate_by_slot": json.dumps(stage2_metrics["slot_accept_rate"], sort_keys=True),
        "pairwise_swap_acceptance_by_pair": json.dumps(stage2_metrics["pair_accept_rate"], sort_keys=True),
        "farthest_slot_reached_by_label": json.dumps(stage2_metrics["farthest_by_label"], sort_keys=True),
        "summary_file": str(summary_file.relative_to(repo_root)),
        "label_trace_file": str(label_trace_file.relative_to(repo_root)),
        "stage2_v1_sidecar_enabled": int(bool(stage2_v1_sidecars_enabled)),
        "stage2_v1_output_dir": relpath_text(
            repo_root, stage2_v1_output_dir if stage2_v1_sidecars_enabled else ""
        ),
        "stage2_v1_manifest_file": relpath_text(
            repo_root, stage2_v1_manifest_file if stage2_v1_sidecars_enabled else ""
        ),
        "stage2_v1_protocol_file": relpath_text(
            repo_root, stage2_v1_protocol_file if stage2_v1_sidecars_enabled else ""
        ),
        "stage2_protocol_audit_json": relpath_text(repo_root, audit_result["json_file"]),
        "stage2_protocol_audit_text": relpath_text(repo_root, audit_result["text_file"]),
        "stage2_protocol_audit_verdict": audit_result["verdict"],
        "stage2_protocol_audit_errors": audit_result["errors"],
        "stage2_protocol_audit_warnings": audit_result["warnings"],
        "stage2_protocol_audit_checks": audit_result["checks"],
        "stage2_log": str(stage2_log.relative_to(repo_root)),
        "eval_log": str(eval_log.relative_to(repo_root)),
        "multichain_meta_file": str(meta_file.relative_to(repo_root)),
        "all_replica_history_dir": (
            str(all_replica_history_dir.relative_to(repo_root)) if setup.get("write_all_replica_history", False) else ""
        ),
    }
    return row


def method_item(name):
    spec = METHOD_SPECS.get(name)
    if spec is None:
        raise ValueError("Unknown method: {0}".format(name))
    env_overrides = dict(spec.get("env_overrides", {}))
    env_overrides.pop("INTODE_SOLVER_ASSIST_ENABLED", None)
    return (name, bool(spec["fallback_enabled"]), env_overrides)


def selected_method_names(methods):
    if methods == "both":
        return ("no_fb", "fb")
    if methods == "no_fb_fbnorefine":
        return ("no_fb", "fb_norefine")
    return (methods,)


def filter_method_items(method_items, methods):
    selected = set(selected_method_names(methods))
    return tuple(item for item in method_items if item[0] in selected)


def method_order_for_seed(seed_index, pair_order, methods="both"):
    method_items_no_fb_first = (method_item("no_fb"), method_item("fb"), method_item("fb_norefine"))
    method_items_fb_first = (method_item("fb"), method_item("fb_norefine"), method_item("no_fb"))
    if pair_order == "no_fb_first":
        return filter_method_items(method_items_no_fb_first, methods)
    if pair_order == "fb_first":
        return filter_method_items(method_items_fb_first, methods)
    if seed_index % 2 == 0:
        return filter_method_items(method_items_no_fb_first, methods)
    return filter_method_items(method_items_fb_first, methods)


def method_order_for_task(task_method_order, methods="both"):
    if task_method_order == "fb_first":
        return method_order_for_seed(1, "fb_first", methods)
    return method_order_for_seed(0, "no_fb_first", methods)


def run_seed_pair(
    repo_root,
    setup,
    seed_index,
    seed_id,
    base_parameters_text,
    stage2_threads,
    eval_threads,
    pair_order,
    methods,
    out_dir,
    logs_dir,
    log_prefix,
    stage2_v1_sidecars_enabled=False,
    protocol_audit_mode="auto",
    protocol_audit_fail_on="error",
):
    rows = []
    for method_name, fallback_enabled, method_env_overrides in method_order_for_seed(seed_index, pair_order, methods):
        print("[RUN] seed={0} method={1}".format(seed_id, method_name))
        sys.stdout.flush()
        rows.append(
            run_one_seed(
                repo_root=repo_root,
                setup=setup,
                method_name=method_name,
                fallback_enabled=fallback_enabled,
                seed_id=seed_id,
                base_parameters_text=base_parameters_text,
                stage2_threads=stage2_threads,
                eval_threads=eval_threads,
                schedule_name="paired",
                out_dir=out_dir,
                logs_dir=logs_dir,
                log_prefix=log_prefix,
                method_env_overrides=method_env_overrides,
                stage2_v1_sidecars_enabled=stage2_v1_sidecars_enabled,
                protocol_audit_mode=protocol_audit_mode,
                protocol_audit_fail_on=protocol_audit_fail_on,
            )
        )
        print("[DONE] seed={0} method={1}".format(seed_id, method_name))
        sys.stdout.flush()
    return rows


def aggregate_rows(rows, observable_exact_re=0.0, observable_exact_im=0.0):
    methods = sorted(set(r["method"] for r in rows))
    out = []
    for method in methods:
        group = [r for r in rows if r["method"] == method]
        zp_joint = [r["Zp_abs_max"] for r in group]
        zp_re = [r["Zp_re"] for r in group]
        zp_im = [r["Zp_im"] for r in group]
        ohat_re_vals = [r["Ohat_re"] for r in group]
        ohat_im_vals = [r["Ohat_im"] for r in group]
        agg = {
            "method": method,
            "n_seeds": len(group),
            "P68_re": coverage_fraction(zp_re, 1.0),
            "P95_re": coverage_fraction(zp_re, 2.0),
            "P68_im": coverage_fraction(zp_im, 1.0),
            "P95_im": coverage_fraction(zp_im, 2.0),
            "P68": coverage_fraction(zp_joint, 1.0),
            "P95": coverage_fraction(zp_joint, 2.0),
            "mean_Zp": safe_mean(zp_joint),
            "median_abs_Zp": safe_median([abs(x) for x in finite_values(zp_joint)]),
            "mean_Zp_re": safe_mean(zp_re),
            "mean_Zp_im": safe_mean(zp_im),
            "mean_Ohat_re": safe_mean(ohat_re_vals),
            "mean_Ohat_im": safe_mean(ohat_im_vals),
            "std_Ohat_re": safe_sample_std(ohat_re_vals),
            "std_Ohat_im": safe_sample_std(ohat_im_vals),
            "Zmean_re": zmean_from_seed_means(ohat_re_vals, observable_exact_re),
            "Zmean_im": zmean_from_seed_means(ohat_im_vals, observable_exact_im),
            "total_unresolved_failure_count": int(
                sum(as_finite_number(r["unresolved_failure_count"]) or 0.0 for r in group)
            ),
            "mean_projection_failure_count": safe_mean([r["projection_failure_count"] for r in group]),
            "mean_unresolved_failure_count": safe_mean([r["unresolved_failure_count"] for r in group]),
            "mean_quasi_probe_success_count": safe_mean([r["quasi_probe_success_count"] for r in group]),
            "mean_full_stage_trigger_count": safe_mean([r["full_stage_trigger_count"] for r in group]),
            "mean_pair0_accept_rate": safe_mean([r["pair0_accept_rate"] for r in group]),
            "mean_total_round_trip": safe_mean([r["total_round_trip"] for r in group]),
            "mean_hot_end_hit_count": safe_mean([r["hot_end_hit_count"] for r in group]),
            "mean_runtime_total": safe_mean([r["runtime_total"] for r in group]),
            "median_runtime_total": safe_median([r["runtime_total"] for r in group]),
        }
        for column in local_transition_count_columns():
            agg["total_{0}".format(column)] = int(sum(as_finite_number(r.get(column)) or 0.0 for r in group))
        for column in newton_eval_flow_status_count_columns():
            agg["total_{0}".format(column)] = int(sum(as_finite_number(r.get(column)) or 0.0 for r in group))
        for column in qn_eval_flow_status_count_columns():
            agg["total_{0}".format(column)] = int(sum(as_finite_number(r.get(column)) or 0.0 for r in group))
        for column in reverse_gate_replay_status_count_columns():
            agg["total_{0}".format(column)] = int(sum(as_finite_number(r.get(column)) or 0.0 for r in group))
        for column in reverse_gate_count_columns():
            agg["total_{0}".format(column)] = int(sum(as_finite_number(r.get(column)) or 0.0 for r in group))
        for column in cvode_stat_columns():
            agg["total_{0}".format(column)] = int(sum(as_finite_number(r.get(column)) or 0.0 for r in group))
        cvode_calls = agg.get("total_cvode_calls", 0)
        if cvode_calls > 0:
            agg["mean_cvode_rhs_per_call"] = agg.get("total_cvode_rhs_evals", 0) / float(cvode_calls)
            agg["mean_cvode_steps_per_call"] = agg.get("total_cvode_steps", 0) / float(cvode_calls)
            agg["mean_cvode_nonlinear_iters_per_call"] = agg.get("total_cvode_nonlinear_iters", 0) / float(cvode_calls)
            agg["mean_cvode_error_test_fails_per_call"] = agg.get("total_cvode_error_test_fails", 0) / float(cvode_calls)
        else:
            agg["mean_cvode_rhs_per_call"] = float("nan")
            agg["mean_cvode_steps_per_call"] = float("nan")
            agg["mean_cvode_nonlinear_iters_per_call"] = float("nan")
            agg["mean_cvode_error_test_fails_per_call"] = float("nan")
        out.append(agg)
    return out


def write_csv(path, rows, columns):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in columns})


def run_stage3_protocol_audit_crosschecks(
    repo_root,
    rows,
    per_seed_csv,
    out_dir,
    stage2_v1_sidecars_enabled,
    protocol_audit_fail_on,
):
    audit_root = out_dir / "protocol_audits" / "stage3_crosscheck"
    summary_rows = []
    for row in rows:
        method_name = str(row["method"])
        seed_id = int(row["seed_id"])
        audit_json = audit_root / method_name / "seed_{0}.json".format(seed_id)
        audit_text = audit_root / method_name / "seed_{0}.txt".format(seed_id)
        manifest_file = resolve_repo_path(repo_root, row.get("stage2_v1_manifest_file", ""))
        protocol_file = resolve_repo_path(repo_root, row.get("stage2_v1_protocol_file", ""))
        result = run_stage2_protocol_audit(
            repo_root=repo_root,
            summary_file=resolve_repo_path(repo_root, row["summary_file"]),
            label_trace_file=resolve_repo_path(repo_root, row["label_trace_file"]),
            manifest_file=manifest_file if stage2_v1_sidecars_enabled else None,
            protocol_file=protocol_file if stage2_v1_sidecars_enabled else None,
            stage3_per_seed_file=per_seed_csv,
            seed_id=seed_id,
            method_name=method_name,
            out_json=audit_json,
            out_text=audit_text,
            fail_on=protocol_audit_fail_on,
        )
        summary_rows.append(
            {
                "seed_id": seed_id,
                "method": method_name,
                "verdict": result["verdict"],
                "errors": result["errors"],
                "warnings": result["warnings"],
                "checks": result["checks"],
                "audit_json": relpath_text(repo_root, result["json_file"]),
                "audit_text": relpath_text(repo_root, result["text_file"]),
            }
        )

    audit_summary_csv = out_dir / "protocol_audit_summary.csv"
    write_csv(
        audit_summary_csv,
        summary_rows,
        ["seed_id", "method", "verdict", "errors", "warnings", "checks", "audit_json", "audit_text"],
    )
    return audit_summary_csv


def write_report(
    repo_root,
    setup,
    rows,
    aggregated_rows,
    report_path,
    resource_policy,
    report_title,
    out_dir,
    protocol_audit_summary_csv=None,
):
    by_method = {}
    for row in aggregated_rows:
        by_method[row["method"]] = row

    no_fb = by_method.get("no_fb")
    fb = by_method.get("fb")
    ladder_text = ",".join("{0:g}".format(x) for x in setup["ladder"])
    seeds_count = len(setup["seed_list"])
    lines = [
        "# {0}".format(report_title),
        "",
        "Protocol freeze:",
        "- ladder: `{0}`; max_flow_time: `{1:g}`".format(ladder_text, setup["max_flow_time"]),
        "- local params: `L={0:g}`, `nstep={1}`, `local_updates={2}`".format(
            setup["trajectory_length"], setup["integration_steps"], setup["local_updates_per_cycle"]
        ),
        "- cycles_per_seed: `{0}`; seeds: `{1}`; init: `{2}`".format(
            setup["cycles_per_seed"], seeds_count, setup.get("stage2_init_mode", "") or "default"
        ),
        "- Stage2 RNG stream contract: `{0}`".format(setup["stage2_rng_stream_contract"]),
        "- observable target: `Re<virial>=0`, `Im<virial>=0`",
        "",
        "Key results (Re/Im analyzed separately):",
        "",
        "| method | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re<O> | mean Im<O> | std Re<O> | std Im<O> | Zmean Re<O> | Zmean Im<O> | failure | rev_rej |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in aggregated_rows:
        lines.append(
            "| {method} | {n_seeds} | {P68_re:.4f} | {P95_re:.4f} | {P68_im:.4f} | {P95_im:.4f} | {mean_Ohat_re:.6g} | {mean_Ohat_im:.6g} | {std_Ohat_re:.6g} | {std_Ohat_im:.6g} | {Zmean_re:.6g} | {Zmean_im:.6g} | {total_unresolved_failure_count} | {total_reverse_gate_total_reject_count} |".format(
                **row
            )
        )

    lines.extend(
        [
            "",
            "Failure / reverse-gate reject breakdown:",
            "",
            "| method | unresolved failures | reverse-gate rejects (total route) |",
            "|---|---:|---:|",
        ]
    )
    for row in aggregated_rows:
        lines.append(
            "| {method} | {total_unresolved_failure_count} | {total_reverse_gate_total_reject_count} |".format(
                **row
            )
        )

    if no_fb and fb:
        lines.extend(
            [
                "",
                "Concise readout:",
                "- Re coverage shift (fb - no_fb): `P68 {0:+.4f}`, `P95 {1:+.4f}`".format(
                    fb["P68_re"] - no_fb["P68_re"], fb["P95_re"] - no_fb["P95_re"]
                ),
                "- Im coverage shift (fb - no_fb): `P68 {0:+.4f}`, `P95 {1:+.4f}`".format(
                    fb["P68_im"] - no_fb["P68_im"], fb["P95_im"] - no_fb["P95_im"]
                ),
                "- Mean observable shift (fb - no_fb): `Re {0:+.6g}`, `Im {1:+.6g}`".format(
                    fb["mean_Ohat_re"] - no_fb["mean_Ohat_re"], fb["mean_Ohat_im"] - no_fb["mean_Ohat_im"]
                ),
                "- Unresolved failures (fb - no_fb): `{0}`".format(
                    fb["total_unresolved_failure_count"] - no_fb["total_unresolved_failure_count"]
                ),
                "- Reverse-gate rejects (fb - no_fb): `{0}`".format(
                    fb["total_reverse_gate_total_reject_count"] - no_fb["total_reverse_gate_total_reject_count"]
                ),
            ]
        )

    lines.extend(
        [
            "",
            "Artifacts:",
            "- `{0}`".format((out_dir / "per_seed_summary_table.csv").relative_to(repo_root)),
            "- `{0}`".format((out_dir / "aggregated_summary_table.csv").relative_to(repo_root)),
            "- `{0}`".format(report_path.relative_to(repo_root)),
        ]
    )
    if protocol_audit_summary_csv:
        lines.append("- `{0}`".format(protocol_audit_summary_csv.relative_to(repo_root)))

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines) + "\n")


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    setup = read_protocol(repo_root, args.config)
    out_dir = resolve_repo_path(repo_root, args.output_subdir)
    logs_dir = resolve_repo_path(repo_root, args.logs_subdir)
    stage2_v1_sidecars_enabled = args.stage2_v1_sidecars == "on"
    protocol_audit_enabled = should_run_protocol_audit(args.stage2_protocol_audit, stage2_v1_sidecars_enabled)
    resource_budget = validate_resource_budget(
        args.jobs,
        args.stage2_threads,
        args.eval_threads,
        args.allow_oversubscribe,
    )

    seeds = list(setup["seed_list"])
    if args.seed_offset < 0:
        raise ValueError("--seed-offset must be >= 0.")
    if args.seed_offset > 0:
        seeds = seeds[args.seed_offset :]
    if args.max_seeds > 0:
        seeds = seeds[: args.max_seeds]
    if not seeds:
        raise ValueError("Selected seed slice is empty.")

    if args.dry_run:
        print("[DRY-RUN] stage-3.3 plan")
        print("  config: {0}".format(setup["config_file"]))
        print("  ladder: {0}".format(",".join("{0:g}".format(x) for x in setup["ladder"])))
        print(
            "  local params: L={0:g} nstep={1} local_updates={2}".format(
                setup["trajectory_length"], setup["integration_steps"], setup["local_updates_per_cycle"]
            )
        )
        print("  cycles={0} warmup={1}".format(setup["cycles_per_seed"], setup["warmup_cycles"]))
        print("  max_flow_time={0:g}".format(setup["max_flow_time"]))
        print("  stage2_init_mode={0}".format(setup.get("stage2_init_mode", "") or "default"))
        print("  stage2_rng_stream_contract={0}".format(setup["stage2_rng_stream_contract"]))
        print("  all_replica_history={0}".format(setup.get("write_all_replica_history", False)))
        print("  seed_offset={0}".format(args.seed_offset))
        print("  seeds({0}): {1}".format(len(seeds), ",".join(str(x) for x in seeds)))
        print("  methods: {0}".format(args.methods))
        print("  output_dir: {0}".format(out_dir))
        print("  logs_dir: {0}".format(logs_dir))
        print("  jobs: {0}".format(args.jobs))
        print("  schedule: {0}".format(args.schedule))
        print("  pair_order: {0}".format(args.pair_order))
        print("  task_method_order: {0}".format(args.task_method_order))
        print("  stage2_threads: {0}".format(args.stage2_threads))
        print("  eval_threads: {0}".format(args.eval_threads))
        print("  stage2_v1_sidecars: {0}".format(args.stage2_v1_sidecars))
        print("  stage2_protocol_audit: {0} (effective={1})".format(args.stage2_protocol_audit, protocol_audit_enabled))
        print("  stage2_protocol_audit_fail_on: {0}".format(args.stage2_protocol_audit_fail_on))
        print("  replica_update_policy: serial-within-stage2-process")
        print("  detected_available_cpus: {0}".format(resource_budget["available_cpus"]))
        print("  requested_cpu_budget: {0}".format(resource_budget["requested_cpus"]))
        return

    if args.stage2_threads > 1:
        print(
            "[WARN] stage2 replica updates are still serial inside each run_tltm_stage2 process; "
            "--stage2-threads only controls OpenMP/MKL-enabled code paths.",
            file=sys.stderr,
        )

    if not args.skip_build:
        omp_enabled = max(args.stage2_threads, args.eval_threads) > 1
        build_binaries(repo_root, omp_enabled=omp_enabled)
    base_parameters_text = (repo_root / "data" / "parameters.dat").read_text()
    rows = []

    if args.schedule == "paired":
        seed_tasks = list(enumerate(seeds))
        setup_for_run = dict(setup, seed_list=seeds)
        if args.jobs == 1:
            for seed_index, seed_id in seed_tasks:
                rows.extend(
                    run_seed_pair(
                        repo_root=repo_root,
                        setup=setup_for_run,
                        seed_index=seed_index,
                        seed_id=seed_id,
                        base_parameters_text=base_parameters_text,
                        stage2_threads=args.stage2_threads,
                        eval_threads=args.eval_threads,
                        pair_order=args.pair_order,
                        methods=args.methods,
                        out_dir=out_dir,
                        logs_dir=logs_dir,
                        log_prefix=args.log_prefix,
                        stage2_v1_sidecars_enabled=stage2_v1_sidecars_enabled,
                        protocol_audit_mode=args.stage2_protocol_audit,
                        protocol_audit_fail_on=args.stage2_protocol_audit_fail_on,
                    )
                )
        else:
            print("[RUN] paired seed workers={0}".format(args.jobs))
            with ThreadPoolExecutor(max_workers=args.jobs) as executor:
                future_map = {}
                for seed_index, seed_id in seed_tasks:
                    future = executor.submit(
                        run_seed_pair,
                        repo_root=repo_root,
                        setup=setup_for_run,
                        seed_index=seed_index,
                        seed_id=seed_id,
                        base_parameters_text=base_parameters_text,
                        stage2_threads=args.stage2_threads,
                        eval_threads=args.eval_threads,
                        pair_order=args.pair_order,
                        methods=args.methods,
                        out_dir=out_dir,
                        logs_dir=logs_dir,
                        log_prefix=args.log_prefix,
                        stage2_v1_sidecars_enabled=stage2_v1_sidecars_enabled,
                        protocol_audit_mode=args.stage2_protocol_audit,
                        protocol_audit_fail_on=args.stage2_protocol_audit_fail_on,
                    )
                    future_map[future] = seed_id

                for future in as_completed(future_map):
                    seed_id = future_map[future]
                    seed_rows = future.result()
                    rows.extend(seed_rows)
                    print("[DONE] seed pair={0}".format(seed_id))
    else:
        tasks = []
        method_items = method_order_for_task(args.task_method_order, args.methods)
        for method_name, fallback_enabled, method_env_overrides in method_items:
            for seed_id in seeds:
                tasks.append((method_name, fallback_enabled, method_env_overrides, seed_id))

        if args.jobs == 1:
            for method_name, fallback_enabled, method_env_overrides, seed_id in tasks:
                print("[RUN] method={0} seed={1}".format(method_name, seed_id))
                row = run_one_seed(
                    repo_root=repo_root,
                    setup=dict(setup, seed_list=seeds),
                    method_name=method_name,
                    fallback_enabled=fallback_enabled,
                    seed_id=seed_id,
                    base_parameters_text=base_parameters_text,
                    stage2_threads=args.stage2_threads,
                    eval_threads=args.eval_threads,
                    schedule_name="task",
                    out_dir=out_dir,
                    logs_dir=logs_dir,
                    log_prefix=args.log_prefix,
                    method_env_overrides=method_env_overrides,
                    stage2_v1_sidecars_enabled=stage2_v1_sidecars_enabled,
                    protocol_audit_mode=args.stage2_protocol_audit,
                    protocol_audit_fail_on=args.stage2_protocol_audit_fail_on,
                )
                rows.append(row)
        else:
            print("[RUN] flat task workers={0}".format(args.jobs))
            with ThreadPoolExecutor(max_workers=args.jobs) as executor:
                future_map = {}
                for method_name, fallback_enabled, method_env_overrides, seed_id in tasks:
                    future = executor.submit(
                        run_one_seed,
                        repo_root=repo_root,
                        setup=dict(setup, seed_list=seeds),
                        method_name=method_name,
                        fallback_enabled=fallback_enabled,
                        seed_id=seed_id,
                        base_parameters_text=base_parameters_text,
                        stage2_threads=args.stage2_threads,
                        eval_threads=args.eval_threads,
                        schedule_name="task",
                        out_dir=out_dir,
                        logs_dir=logs_dir,
                        log_prefix=args.log_prefix,
                        method_env_overrides=method_env_overrides,
                        stage2_v1_sidecars_enabled=stage2_v1_sidecars_enabled,
                        protocol_audit_mode=args.stage2_protocol_audit,
                        protocol_audit_fail_on=args.stage2_protocol_audit_fail_on,
                    )
                    future_map[future] = (method_name, seed_id)

                for future in as_completed(future_map):
                    method_name, seed_id = future_map[future]
                    row = future.result()
                    rows.append(row)
                    print("[DONE] method={0} seed={1}".format(method_name, seed_id))

    rows_sorted = sorted(rows, key=lambda r: (r["method"], int(r["seed_id"])))
    aggregated_rows = aggregate_rows(rows_sorted, setup["observable_exact_re"], setup["observable_exact_im"])

    per_seed_csv = out_dir / "per_seed_summary_table.csv"
    aggregated_csv = out_dir / "aggregated_summary_table.csv"
    report_md = out_dir / "{0}_report.md".format(args.log_prefix)

    per_seed_columns = [
        "seed_id",
        "method",
        "projection_failure_count",
        "unresolved_failure_count",
        "fallback_trigger_count",
        "quasi_probe_success_count",
        "full_stage_trigger_count",
        "full_stage_success_count",
        "quasi_class_local_count",
        "quasi_class_mid_count",
        "quasi_class_global_count",
        "far_route_skip_count",
        "far_route_light_count",
        "far_route_anchor_count",
        "near_rescue_candidate_count",
        "near_rescue_attempt_count",
        "near_rescue_success_count",
        "near_rescue_unusable_count",
        "quasi_watchdog_hit_count",
        "quasi_watchdog_used_sum",
        "quasi_watchdog_used_max",
        "quasi_watchdog_budget_last",
        "far_investment_scope_count",
        "far_investment_success_count",
        "far_investment_fail_count",
        "far_investment_fail_fast_count",
        "far_investment_spent_success_count",
        "far_investment_spent_fail_count",
        "far_investment_flowzr_units",
        "far_investment_final_units",
        "far_investment_success_flowzr_units",
        "far_investment_success_final_units",
        "far_investment_fail_flowzr_units",
        "far_investment_fail_final_units",
        "quasi_global_filter_candidate_count",
        "quasi_global_filter_pass_count",
        "quasi_global_filter_reject_count",
        *reverse_gate_count_columns(),
        *newton_eval_flow_status_count_columns(),
        *qn_eval_flow_status_count_columns(),
        *reverse_gate_replay_status_count_columns(),
        *cvode_stat_columns(),
        *local_transition_count_columns(),
        "accepted_local_total",
        "accepted_local_newton_only_count",
        "accepted_local_quasi_count",
        "accepted_local_rescue_count",
        "accepted_local_probe_only_count",
        "accepted_local_full_stage_count",
        "accepted_local_near_rescue_count",
        "accepted_local_nonnear_route_count",
        "accepted_local_uncategorized_count",
        "accepted_local_class_local_count",
        "accepted_local_class_mid_count",
        "accepted_local_class_global_count",
        "accepted_local_far_skip_count",
        "accepted_local_far_light_count",
        "accepted_local_far_anchor_count",
        "pair0_accept_rate",
        "total_round_trip",
        "avg_round_trip_cycles_if_observed",
        "hot_end_hit_count",
        "runtime_total",
        "runtime_per_cycle",
        "stage2_threads",
        "eval_threads",
        "stage2_init_mode",
        "max_flow_time",
        "schedule",
        "Ohat_re",
        "Ohat_im",
        "err_Ohat_re",
        "err_Ohat_im",
        "err_Ohat_valid",
        "Zp_re",
        "Zp_im",
        "Zp_abs_max",
        "Ohat",
        "err_Ohat",
        "Zp",
        "local_accept_rate_by_slot",
        "pairwise_swap_acceptance_by_pair",
        "farthest_slot_reached_by_label",
        "summary_file",
        "label_trace_file",
        *stage3_protocol_metadata_columns(),
        "stage2_log",
        "eval_log",
        "multichain_meta_file",
        "all_replica_history_dir",
    ]
    aggregated_columns = [
        "method",
        "n_seeds",
        "P68_re",
        "P95_re",
        "P68_im",
        "P95_im",
        "P68",
        "P95",
        "mean_Ohat_re",
        "mean_Ohat_im",
        "std_Ohat_re",
        "std_Ohat_im",
        "Zmean_re",
        "Zmean_im",
        "mean_Zp",
        "median_abs_Zp",
        "mean_Zp_re",
        "mean_Zp_im",
        "total_unresolved_failure_count",
        "mean_projection_failure_count",
        "mean_unresolved_failure_count",
        "mean_quasi_probe_success_count",
        "mean_full_stage_trigger_count",
        "mean_pair0_accept_rate",
        "mean_total_round_trip",
        "mean_hot_end_hit_count",
        "mean_runtime_total",
        "median_runtime_total",
        *reverse_gate_aggregate_columns(),
        *newton_eval_flow_status_aggregate_columns(),
        *qn_eval_flow_status_aggregate_columns(),
        *reverse_gate_replay_status_aggregate_columns(),
        *cvode_aggregate_columns(),
        *local_transition_aggregate_columns(),
    ]

    write_csv(per_seed_csv, rows_sorted, per_seed_columns)
    protocol_audit_summary_csv = None
    if protocol_audit_enabled:
        protocol_audit_summary_csv = run_stage3_protocol_audit_crosschecks(
            repo_root=repo_root,
            rows=rows_sorted,
            per_seed_csv=per_seed_csv,
            out_dir=out_dir,
            stage2_v1_sidecars_enabled=stage2_v1_sidecars_enabled,
            protocol_audit_fail_on=args.stage2_protocol_audit_fail_on,
        )
    write_csv(aggregated_csv, aggregated_rows, aggregated_columns)
    resource_policy = {
        "schedule": args.schedule,
        "jobs": args.jobs,
        "stage2_threads": args.stage2_threads,
        "eval_threads": args.eval_threads,
        "available_cpus": resource_budget["available_cpus"],
        "requested_cpus": resource_budget["requested_cpus"],
    }
    write_report(
        repo_root,
        dict(setup, seed_list=seeds),
        rows_sorted,
        aggregated_rows,
        report_md,
        resource_policy,
        args.report_title,
        out_dir,
        protocol_audit_summary_csv=protocol_audit_summary_csv,
    )

    print("[DONE] stage-3.3 multiseed comparison generated")
    print("  {0}".format(per_seed_csv))
    print("  {0}".format(aggregated_csv))
    print("  {0}".format(report_md))


if __name__ == "__main__":
    main()
