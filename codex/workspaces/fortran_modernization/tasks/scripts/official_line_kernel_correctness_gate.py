#!/usr/bin/env python3
"""Run the official-line kernel correctness gate for CV-001.

This is a local modernization-tree guardrail. It checks the embedded official
DFO-LS line and retained TLTM kernel contracts without submitting production
jobs or claiming production-statistics completion.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


WORKSPACE_REL = Path("codex/workspaces/fortran_modernization")
CLAIM_POLICY_REL = WORKSPACE_REL / "schema/DFOLS_CLAIM_PROVENANCE_POLICY_V1.json"
F14_SCRIPT_REL = WORKSPACE_REL / "tasks/scripts/f14_complete_pre_redo_gate.py"
EXPECTED_DFOLS_VERSION = "1.6.5"
EXPECTED_DFOLS_LICENSE = "GPL-3.0-or-later"


def parse_args():
    parser = argparse.ArgumentParser(description="Run CV-001 official-line kernel correctness gate.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--fc", default=os.environ.get("FC", ""), help="Optional Fortran compiler override.")
    parser.add_argument("--ldflags", default=os.environ.get("LDFLAGS", ""), help="LDFLAGS passed to make.")
    parser.add_argument("--skip-build", action="store_true", help="Skip make targets and validate policy/F14 only.")
    parser.add_argument("--keep-going", action="store_true", help="Continue after failures and report all failures.")
    parser.add_argument(
        "--output-root",
        default="output/tests/official_line_kernel_correctness_gate",
        help="Output root relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--logs-root",
        default="output/logs/official_line_kernel_correctness_gate",
        help="Log root relative to repo root, or absolute.",
    )
    return parser.parse_args()


def jst_now_text():
    jst = timezone(timedelta(hours=9))
    return datetime.now(jst).strftime("%Y-%m-%d %H:%M:%S JST")


def resolve_path(repo_root, path_text):
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


def run_step(label, cmd, cwd, failures, keep_going, env=None):
    print("[CV001][RUN] {0}".format(label))
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
        print("[CV001][FAIL] {0}".format(label))
        if not keep_going:
            sys.stdout.write(proc.stdout)
            raise SystemExit(1)
    else:
        print("[CV001][PASS] {0}".format(label))
    return proc


def assert_condition(label, condition, details, failures, keep_going):
    if condition:
        print("[CV001][PASS] {0}".format(label))
        return
    failures.append({"label": label, "cmd": ["internal-check"], "output": details})
    print("[CV001][FAIL] {0}".format(label))
    if not keep_going:
        print(details)
        raise SystemExit(1)


def infer_official_dfols_env(repo_root):
    env = {}
    venv_python = repo_root / ".venv-dfols" / "bin" / "python"
    if not venv_python.exists():
        return env
    env["PYTHON"] = str(venv_python)
    proc = subprocess.run(
        [str(venv_python), "-c", "import site; print(site.getsitepackages()[0])"],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode == 0:
        env["TLTM_OFFICIAL_DFOLS_PYTHONPATH"] = proc.stdout.strip()
    return env


def collect_dfols_info(python_exe):
    probe_code = r'''
import json
import sys

data = {
    "python_executable": sys.executable,
    "python_version": sys.version.split()[0],
    "import_ok": False,
    "module_file": "",
    "module_version": "",
    "dist_version": "",
    "dist_license": "",
    "error": "",
}

try:
    import dfols
    data["import_ok"] = True
    data["module_file"] = getattr(dfols, "__file__", "") or ""
    data["module_version"] = getattr(dfols, "__version__", "") or ""
except Exception as exc:
    data["error"] = type(exc).__name__ + ": " + str(exc)

try:
    try:
        import importlib.metadata as metadata
    except Exception:
        import importlib_metadata as metadata
    data["dist_version"] = metadata.version("DFO-LS")
    data["dist_license"] = metadata.metadata("DFO-LS").get("License", "") or ""
except Exception as exc:
    if not data["error"]:
        data["error"] = type(exc).__name__ + ": " + str(exc)

print(json.dumps(data, sort_keys=True))
'''
    output = subprocess.check_output([python_exe, "-c", probe_code], universal_newlines=True)
    return json.loads(output)


def validate_dfols_runtime(repo_root, env, failures, keep_going):
    python_exe = env.get("PYTHON", "")
    pythonpath = env.get("TLTM_OFFICIAL_DFOLS_PYTHONPATH", "")
    assert_condition(
        "official DFO-LS runtime path is explicit",
        bool(python_exe and pythonpath),
        "Missing .venv-dfols Python or TLTM_OFFICIAL_DFOLS_PYTHONPATH.",
        failures,
        keep_going,
    )
    if not python_exe:
        return {}
    info = collect_dfols_info(python_exe)
    ok = (
        info.get("import_ok")
        and info.get("dist_version") == EXPECTED_DFOLS_VERSION
        and info.get("dist_license") == EXPECTED_DFOLS_LICENSE
    )
    assert_condition(
        "official DFO-LS package provenance matches expected version/license",
        ok,
        json.dumps(info, indent=2, sort_keys=True),
        failures,
        keep_going,
    )
    info["site_packages"] = pythonpath
    return info


def validate_claim_policy(repo_root, failures, keep_going):
    path = repo_root / CLAIM_POLICY_REL
    if path.exists():
        policy = json.loads(path.read_text(encoding="utf-8"))
    else:
        policy = {}
    labels = policy.get("canonical_backend_labels", {})
    official = labels.get("official_package_dfols", {})
    historical = labels.get("historical_internal_dfols_style", {})
    rules = policy.get("reporting_rules", [])
    forbidden = policy.get("forbidden_claims", [])
    required_runtime = set(official.get("required_runtime_fields", []))
    ok = (
        policy.get("schema_version") == "DFOLS_CLAIM_PROVENANCE_POLICY_V1"
        and official.get("backend_label") == "official_dfols"
        and official.get("package_distribution") == "DFO-LS"
        and official.get("package_version") == EXPECTED_DFOLS_VERSION
        and official.get("package_license") == EXPECTED_DFOLS_LICENSE
        and {"ENABLE_OFFICIAL_DFOLS", "TLTM_OFFICIAL_DFOLS_PYTHONPATH", "QN_SOLVER_BACKEND", "QN_OFFICIAL_DFOLS_PRESET"}.issubset(required_runtime)
        and historical.get("backend_label") == "internal_or_historical_dfols_style"
        and len(rules) >= 3
        and len(forbidden) >= 2
    )
    assert_condition(
        "DFO-LS claim/provenance policy separates official and historical evidence",
        ok,
        json.dumps(policy, indent=2, sort_keys=True),
        failures,
        keep_going,
    )
    return policy


def make_cmd(repo_root, args, targets):
    cmd = ["make", "-C", str(repo_root / "build")]
    if args.fc:
        cmd.append("FC={0}".format(args.fc))
    cmd.append("ENABLE_OFFICIAL_DFOLS=1")
    cmd.append("LDFLAGS={0}".format(args.ldflags))
    cmd.extend(targets)
    return cmd


def run_kernel_targets(repo_root, args, failures, keep_going, env):
    if args.skip_build:
        print("[CV001][INFO] kernel make targets delegated to caller because --skip-build was set")
        return {
            "mode": "delegated",
            "targets": kernel_targets(),
        }
    targets = kernel_targets()
    run_step("official-line retained kernel contracts", make_cmd(repo_root, args, targets), repo_root, failures, keep_going, env)
    return {
        "mode": "executed",
        "targets": targets,
    }


def kernel_targets():
    return [
        "test_odex_assist_policy",
        "test_odex_flow_jacobian_contract",
        "test_official_dfols_preset_contract",
        "test_retained_core_newton_contract",
        "test_retained_core_rattle_rg_contract",
        "test_retained_core_qn_route_contract",
        "test_retained_core_rg_reject_identity",
    ]


def run_f14_gate(repo_root, args, output_root, logs_root, failures, keep_going, env):
    f14_output = output_root / "f14_pre_redo_gate"
    f14_logs = logs_root / "f14_pre_redo_gate"
    if f14_output.exists():
        shutil.rmtree(f14_output)
    if f14_logs.exists():
        shutil.rmtree(f14_logs)
    cmd = [
        sys.executable,
        str(repo_root / F14_SCRIPT_REL),
        "--repo-root",
        str(repo_root),
        "--skip-build",
        "--output-root",
        str(f14_output),
        "--logs-root",
        str(f14_logs),
    ]
    if args.keep_going:
        cmd.append("--keep-going")
    run_step("F14 F3/F4/F7/F8 pre-redo gate", cmd, repo_root, failures, keep_going, env)
    manifest_path = f14_output / "F14_complete_pre_redo_gate_manifest.json"
    manifest = {}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    ok = manifest.get("status") == "pass" and manifest.get("reduced_scope_accepted") is False
    assert_condition(
        "F14 pre-redo manifest passes without reduced scope",
        ok,
        "manifest={0}\n{1}".format(manifest_path, json.dumps(manifest, indent=2, sort_keys=True)),
        failures,
        keep_going,
    )
    return manifest_path, manifest


def write_manifest(repo_root, output_root, dfols_info, claim_policy, kernel_info, f14_manifest_path, f14_manifest):
    manifest = {
        "gate": "CV-001 official-line kernel correctness",
        "status": "pass",
        "updated_jst": jst_now_text(),
        "scope": "modernization-tree kernel correctness, not production redo",
        "canonical_line": {
            "backend": "official_dfols",
            "package_distribution": "DFO-LS",
            "package_version": EXPECTED_DFOLS_VERSION,
            "preset": "stable_gate77",
            "solver_assist": "default_off",
            "route": "Newton -> p28 QN BTN residual -> reverse gate -> Metropolis",
        },
        "dfols_provenance": dfols_info,
        "claim_policy_schema": relpath_text(repo_root, repo_root / CLAIM_POLICY_REL),
        "claim_policy_version": claim_policy.get("schema_version", ""),
        "kernel_contracts": kernel_info,
        "f14_pre_redo_manifest": relpath_text(repo_root, f14_manifest_path),
        "f14_status": f14_manifest.get("status", ""),
        "closed_caveat": "CV-001",
        "not_closed_by_this_gate": ["CV-002", "CV-005", "CV-011"],
    }
    output_root.mkdir(parents=True, exist_ok=True)
    path = output_root / "CV001_official_line_kernel_correctness_manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("[CV001][WRITE] {0}".format(path))
    return path, manifest


def run_gate(args):
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_path(repo_root, args.output_root)
    logs_root = resolve_path(repo_root, args.logs_root)
    output_root.mkdir(parents=True, exist_ok=True)
    logs_root.mkdir(parents=True, exist_ok=True)
    failures = []

    env = os.environ.copy()
    env.update(infer_official_dfols_env(repo_root))

    dfols_info = validate_dfols_runtime(repo_root, env, failures, args.keep_going)
    claim_policy = validate_claim_policy(repo_root, failures, args.keep_going)
    kernel_info = run_kernel_targets(repo_root, args, failures, args.keep_going, env)
    f14_manifest_path, f14_manifest = run_f14_gate(repo_root, args, output_root, logs_root, failures, args.keep_going, env)

    if failures:
        print("[CV001][SUMMARY] {0} failure(s)".format(len(failures)))
        for failure in failures:
            print("[CV001][FAILURE] {0}".format(failure["label"]))
            print("  cmd: {0}".format(" ".join(failure["cmd"])))
            print(failure["output"][-4000:])
        return 1

    manifest_path, _ = write_manifest(repo_root, output_root, dfols_info, claim_policy, kernel_info, f14_manifest_path, f14_manifest)
    print("[CV001][SUMMARY] official-line kernel correctness gate passed")
    print("[CV001][ARTIFACT] {0}".format(relpath_text(repo_root, manifest_path)))
    return 0


def main():
    return run_gate(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
