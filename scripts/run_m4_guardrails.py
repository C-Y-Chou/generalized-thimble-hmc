#!/usr/bin/env python3
"""Run the local M4 modernization guardrail suite.

This script is intentionally small-run only. It does not submit production jobs
or generate official datasets. Its purpose is to make the current ad hoc
build/audit/smoke checks repeatable before wider M5 refactors.
"""

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

GUARDRAIL_SOURCE_ROOTS = (
    "src",
    "tests",
    "scripts",
    "codex/tasks",
    "codex/workspaces/fortran_modernization/tasks",
    "build",
)


def parse_args():
    parser = argparse.ArgumentParser(description="Run TLTM M4 local modernization guardrails.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--fc", default=os.environ.get("FC", ""), help="Optional Fortran compiler override.")
    parser.add_argument(
        "--ldflags",
        default=os.environ.get("M4_GUARDRAIL_LDFLAGS", os.environ.get("LDFLAGS", "")),
        help="LDFLAGS passed to make. Defaults to M4_GUARDRAIL_LDFLAGS, then LDFLAGS, then empty.",
    )
    parser.add_argument("--skip-build", action="store_true", help="Skip Fortran build/test guardrails.")
    parser.add_argument("--keep-going", action="store_true", help="Continue after failures and report all failures.")
    parser.add_argument(
        "--output-root",
        default="output/tests/m4_guardrails",
        help="Guardrail output root relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--logs-root",
        default="output/logs/m4_guardrails",
        help="Guardrail log root relative to repo root, or absolute.",
    )
    return parser.parse_args()


def resolve_repo_path(repo_root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return repo_root / path


def relpath_text(repo_root, path):
    path = Path(path)
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def git_lines(repo_root, git_args):
    proc = subprocess.run(
        ["git"] + git_args,
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return [line for line in proc.stdout.splitlines() if line.strip()]


def find_untracked_guardrail_files(repo_root):
    lines = git_lines(repo_root, ["ls-files", "--others", "--exclude-standard", "--"] + list(GUARDRAIL_SOURCE_ROOTS))
    if lines is None:
        return []
    return sorted(lines)


def iter_guardrail_fortran_paths(repo_root):
    tracked = git_lines(repo_root, ["ls-files", "--cached", "--", "src", "tests"])
    if tracked is not None:
        for rel_text in tracked:
            if not rel_text.lower().endswith(".f90"):
                continue
            path = repo_root / rel_text
            if path.exists():
                yield path
        return

    for source_root in ("src", "tests"):
        root = repo_root / source_root
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.f90")):
            yield path


def run_step(label, cmd, cwd, failures, keep_going, env=None):
    print("[M4][RUN] {0}".format(label))
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        failures.append({"label": label, "cmd": cmd, "output": proc.stdout})
        print("[M4][FAIL] {0}".format(label))
        if not keep_going:
            sys.stdout.write(proc.stdout)
            raise SystemExit(1)
    else:
        print("[M4][PASS] {0}".format(label))
    return proc


def write_tiny_stage3_config(path):
    config = {
        "stage_3_3_todo": {
            "frozen_setup": {
                "flow_time_ladder": [0.0, 0.05],
                "max_flow_time": 0.05,
                "trajectory_length_L": 0.2,
                "nstep": 2,
                "local_updates_per_cycle": 1,
                "stage2_init_mode": "direct",
            },
            "observable_definition": {"exact_re": 0.0, "exact_im": 0.0},
            "sampling_plan": {
                "seed_list": [20260421],
                "cycles_per_seed": 4,
                "warmup_cycles_optional": 0,
            },
        }
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2, sort_keys=True) + "\n")


def read_first_csv_row(path):
    with Path(path).open(newline="") as f:
        return next(csv.DictReader(f))


def assert_condition(label, condition, details, failures, keep_going):
    if condition:
        print("[M4][PASS] {0}".format(label))
        return
    failures.append({"label": label, "cmd": ["internal-check"], "output": details})
    print("[M4][FAIL] {0}".format(label))
    if not keep_going:
        print(details)
        raise SystemExit(1)


def find_uncentralized_env_reads(repo_root):
    allowed = {Path("src/config/runtime_env_mod.f90")}
    hits = []
    for path in iter_guardrail_fortran_paths(repo_root):
        rel = path.relative_to(repo_root)
        if rel in allowed:
            continue
        for line_no, line in enumerate(path.read_text(errors="replace").splitlines(), start=1):
            if "get_environment_variable" in line.lower():
                hits.append("{0}:{1}: {2}".format(rel, line_no, line.strip()))
    return hits


def make_cmd(repo_root, args, targets):
    cmd = ["make", "-C", str(repo_root / "build")]
    if args.fc:
        cmd.append("FC={0}".format(args.fc))
    cmd.append("LDFLAGS={0}".format(args.ldflags))
    cmd.extend(targets)
    return cmd


def infer_official_dfols_env(repo_root):
    env = {}
    venv_python = repo_root / ".venv-dfols" / "bin" / "python"
    if not venv_python.exists():
        return env
    env["PYTHON"] = str(venv_python)
    proc = subprocess.run(
        [
            str(venv_python),
            "-c",
            "import site; print(site.getsitepackages()[0])",
        ],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode == 0:
        env["TLTM_OFFICIAL_DFOLS_PYTHONPATH"] = proc.stdout.strip()
    return env


def run_stage3_smoke(repo_root, config_path, output_root, logs_root, label, sidecars_enabled, failures, keep_going, env=None):
    out_subdir = output_root / label
    logs_subdir = logs_root / label
    if out_subdir.exists():
        shutil.rmtree(out_subdir)
    if logs_subdir.exists():
        shutil.rmtree(logs_subdir)

    cmd = [
        sys.executable,
        str(repo_root / "scripts" / "run_stage3_3_multiseed.py"),
        "--repo-root",
        str(repo_root),
        "--config",
        str(config_path),
        "--skip-build",
        "--max-seeds",
        "1",
        "--methods",
        "no_fb",
        "--output-subdir",
        str(out_subdir),
        "--logs-subdir",
        str(logs_subdir),
        "--log-prefix",
        label,
        "--allow-oversubscribe",
    ]
    if sidecars_enabled:
        cmd.extend(["--stage2-v1-sidecars", "on", "--stage2-protocol-audit", "auto"])
    stage_env = env
    if sidecars_enabled:
        stage_env = (env or os.environ).copy()
        stage_env["TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR"] = str(out_subdir / "local_transition_audit")
        stage_env["TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS"] = "200"

    run_step("Stage3 tiny smoke {0}".format(label), cmd, repo_root, failures, keep_going, stage_env)
    return out_subdir


def run_guardrails(args):
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_repo_path(repo_root, args.output_root)
    logs_root = resolve_repo_path(repo_root, args.logs_root)
    output_root.mkdir(parents=True, exist_ok=True)
    logs_root.mkdir(parents=True, exist_ok=True)
    failures = []
    guardrail_env = os.environ.copy()
    official_env = infer_official_dfols_env(repo_root)
    guardrail_env.update(official_env)
    if official_env.get("TLTM_OFFICIAL_DFOLS_PYTHONPATH"):
        print(
            "[M4][INFO] official DFO-LS python={0}".format(
                official_env.get("PYTHON", "")
            )
        )
        print(
            "[M4][INFO] official DFO-LS pythonpath={0}".format(
                official_env.get("TLTM_OFFICIAL_DFOLS_PYTHONPATH", "")
            )
        )

    untracked_guardrail_files = find_untracked_guardrail_files(repo_root)
    assert_condition(
        "source/task boundary has no untracked files",
        not untracked_guardrail_files,
        "Untracked files under guardrail-controlled source/task roots must be staged intentionally "
        "or moved out of the modernization worktree before M4 evidence is accepted:\n"
        + "\n".join(untracked_guardrail_files[:80]),
        failures,
        args.keep_going,
    )

    run_step(
        "Python compile",
        [
            sys.executable,
            "-m",
            "py_compile",
            "scripts/run_stage3_3_multiseed.py",
            "scripts/merge_stage3_multiseed_chunks.py",
            "scripts/audit_tltm_tempering_protocol.py",
            "scripts/run_m4_guardrails.py",
            "codex/workspaces/fortran_modernization/tasks/scripts/odex_assist_revalidation.py",
            "codex/workspaces/fortran_modernization/tasks/scripts/odex_official_assist_onoff_readback.py",
            "codex/workspaces/fortran_modernization/tasks/scripts/odex_official_assist_observable_degeneracy.py",
            "codex/workspaces/fortran_modernization/tasks/scripts/official_dfols_small_assist_degeneracy.py",
            "codex/workspaces/fortran_modernization/tasks/scripts/official_dfols_provenance_readback.py",
            "codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py",
        ],
        repo_root,
        failures,
        args.keep_going,
        guardrail_env,
    )
    run_step("git diff --check", ["git", "diff", "--check"], repo_root, failures, args.keep_going, guardrail_env)
    env_read_hits = find_uncentralized_env_reads(repo_root)
    assert_condition(
        "direct env reads centralized",
        not env_read_hits,
        "Direct get_environment_variable calls outside src/config/runtime_env_mod.f90:\n"
        + "\n".join(env_read_hits[:50]),
        failures,
        args.keep_going,
    )

    if not args.skip_build:
        run_step(
            "build Stage2/eval and run ODEX/swap tests",
            make_cmd(
                repo_root,
                args,
                [
                    "../bin/run_tltm_stage2",
                    "../bin/evaluate_expectations",
                    "test_odex_solver",
                    "test_odex_foundation_contract",
                    "test_odex_assist_policy",
                    "test_odex_result_contract",
                    "test_odex_flow_jacobian_contract",
                    "test_odex_backend_package_contract",
                    "test_official_dfols_preset_contract",
                    "test_tltm_swap_kernel_contract",
                    "test_retained_core_newton_contract",
                    "test_retained_core_rattle_rg_contract",
                    "test_retained_core_qn_route_contract",
                    "test_retained_core_rg_reject_identity",
                ],
            ),
            repo_root,
            failures,
            args.keep_going,
            guardrail_env,
        )

    run_step(
        "Stage3 sidecar dry-run",
        [
            sys.executable,
            "scripts/run_stage3_3_multiseed.py",
            "--repo-root",
            ".",
            "--config",
            "docs/stage_3_3_todo.json",
            "--max-seeds",
            "1",
            "--methods",
            "no_fb",
            "--dry-run",
            "--stage2-v1-sidecars",
            "on",
            "--stage2-protocol-audit",
            "auto",
            "--allow-oversubscribe",
        ],
        repo_root,
        failures,
        args.keep_going,
        guardrail_env,
    )

    fixture_summary = repo_root / "output" / "tests" / "tltm_stage2_summary.dat"
    if fixture_summary.exists():
        audit_cmd = [
            sys.executable,
            "scripts/audit_tltm_tempering_protocol.py",
            "--summary",
            str(fixture_summary),
            "--fail-on",
            "error",
        ]
        fixture_label_trace = repo_root / "output" / "tests" / "tltm_stage2_label_trace.dat"
        if fixture_label_trace.exists():
            audit_cmd.extend(["--label-trace", str(fixture_label_trace)])
        run_step("existing Stage2 protocol audit smoke", audit_cmd, repo_root, failures, args.keep_going, guardrail_env)

    tiny_config = output_root / "tiny_stage3_guardrail.json"
    write_tiny_stage3_config(tiny_config)

    sidecar_out = run_stage3_smoke(
        repo_root,
        tiny_config,
        output_root,
        logs_root,
        "stage3_sidecar_on",
        True,
        failures,
        args.keep_going,
        guardrail_env,
    )
    sidecar_row = read_first_csv_row(sidecar_out / "per_seed_summary_table.csv")
    assert_condition(
        "sidecar-on row records v1 sidecar",
        sidecar_row.get("stage2_v1_sidecar_enabled") == "1"
        and sidecar_row.get("stage2_protocol_audit_verdict") == "pass",
        json.dumps(sidecar_row, indent=2, sort_keys=True),
        failures,
        args.keep_going,
    )
    assert_condition(
        "sidecar-on cross-check audit summary exists",
        (sidecar_out / "protocol_audit_summary.csv").exists(),
        "Missing {0}".format(sidecar_out / "protocol_audit_summary.csv"),
        failures,
        args.keep_going,
    )
    sidecar_manifest = resolve_repo_path(repo_root, sidecar_row.get("stage2_v1_manifest_file", ""))
    if sidecar_manifest.exists():
        manifest_data = json.loads(sidecar_manifest.read_text())
        env_overrides = manifest_data.get("env_overrides", {})
        required_official_env = [
            "QN_SOLVER_BACKEND",
            "QN_OFFICIAL_DFOLS_PRESET",
            "QN_OFFICIAL_DFOLS_NPT",
            "QN_OFFICIAL_DFOLS_MAXFUN",
            "QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE",
            "QN_OFFICIAL_DFOLS_RHOBEG",
            "QN_OFFICIAL_DFOLS_RHOEND",
            "QN_OFFICIAL_DFOLS_MODEL_ABS_TOL",
            "QN_OFFICIAL_DFOLS_MODEL_REL_TOL",
            "TLTM_OFFICIAL_DFOLS_PYTHONPATH",
        ]
        missing_official_env = [key for key in required_official_env if key not in env_overrides]
    else:
        env_overrides = {}
        missing_official_env = ["manifest_missing"]
    assert_condition(
        "stage2 sidecar records official DFO-LS provenance env",
        not missing_official_env,
        "Manifest {0} missing official DFO-LS env keys: {1}\n{2}".format(
            sidecar_manifest,
            ", ".join(missing_official_env),
            json.dumps(env_overrides, indent=2, sort_keys=True),
        ),
        failures,
        args.keep_going,
    )

    run_step(
        "F14 complete pre-redo gate validates F3/F4/F7/F8",
        [
            sys.executable,
            "codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py",
            "--repo-root",
            ".",
            "--skip-build",
            "--existing-stage3-output",
            str(sidecar_out),
            "--output-root",
            str(output_root / "f14_complete_pre_redo_gate"),
            "--logs-root",
            str(logs_root / "f14_complete_pre_redo_gate"),
        ],
        repo_root,
        failures,
        args.keep_going,
        guardrail_env,
    )

    no_sidecar_out = run_stage3_smoke(
        repo_root,
        tiny_config,
        output_root,
        logs_root,
        "stage3_sidecar_off",
        False,
        failures,
        args.keep_going,
        guardrail_env,
    )
    no_sidecar_row = read_first_csv_row(no_sidecar_out / "per_seed_summary_table.csv")
    assert_condition(
        "sidecar-off row keeps sidecars disabled",
        no_sidecar_row.get("stage2_v1_sidecar_enabled") == "0"
        and no_sidecar_row.get("stage2_protocol_audit_verdict") == ""
        and not (no_sidecar_out / "protocol_audit_summary.csv").exists(),
        json.dumps(no_sidecar_row, indent=2, sort_keys=True),
        failures,
        args.keep_going,
    )

    merge_root = output_root / "stage3_sidecar_merge"
    if merge_root.exists():
        shutil.rmtree(merge_root)
    chunk_dir = merge_root / "chunk_000"
    shutil.copytree(sidecar_out, chunk_dir)
    run_step(
        "Stage3 chunk merge preserves sidecar metadata",
        [
            sys.executable,
            str(repo_root / "scripts" / "merge_stage3_multiseed_chunks.py"),
            "--repo-root",
            str(repo_root),
            "--config",
            str(tiny_config),
            "--output-subdir",
            str(merge_root),
            "--chunk-glob",
            "chunk_*",
            "--log-prefix",
            "m4_guardrail_merge",
            "--report-title",
            "M4 guardrail merge smoke",
            "--expected-rows",
            "1",
            "--jobs-label",
            "guardrail",
            "--requested-cpus",
            "1",
        ],
        repo_root,
        failures,
        args.keep_going,
        guardrail_env,
    )
    merge_row = read_first_csv_row(merge_root / "per_seed_summary_table.csv")
    assert_condition(
        "merged row preserves sidecar metadata",
        merge_row.get("stage2_v1_sidecar_enabled") == "1"
        and merge_row.get("stage2_protocol_audit_verdict") == "pass"
        and (merge_root / "protocol_audit_summary.csv").exists(),
        json.dumps(merge_row, indent=2, sort_keys=True),
        failures,
        args.keep_going,
    )

    if failures:
        print("[M4][SUMMARY] {0} failure(s)".format(len(failures)))
        for failure in failures:
            print("[M4][FAILURE] {0}".format(failure["label"]))
            print("  cmd: {0}".format(" ".join(failure["cmd"])))
            print(failure["output"][-4000:])
        return 1

    print("[M4][SUMMARY] all guardrails passed")
    print("[M4][ARTIFACTS] {0}".format(relpath_text(repo_root, output_root)))
    return 0


def main():
    args = parse_args()
    return run_guardrails(args)


if __name__ == "__main__":
    raise SystemExit(main())
