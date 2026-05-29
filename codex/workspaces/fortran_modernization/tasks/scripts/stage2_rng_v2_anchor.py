#!/usr/bin/env python3
"""Validate the Stage2 kernel RNG v2 deterministic anchor."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_OUTPUT_REL = Path("output/tests/stage2_rng_v2_anchor")
CONTRACT = "stage2_kernel_rng_v2"
SEED = "12345"
STAGE2_ENV = {
    "CHAIN_RNG_SEED": SEED,
    "TLTM_STAGE2_NUM_REPLICAS": "2",
    "TLTM_STAGE2_CYCLES": "2",
    "TLTM_STAGE2_LOCAL_UPDATES": "2",
    "TLTM_STAGE2_MAX_FLOW_TIME": "1e-4",
    "TLTM_STAGE2_SWAP_ENABLED": "1",
}
CANONICAL_QN_ENV = {
    "QN_SOLVER_BACKEND": "official_dfols",
    "QN_OFFICIAL_DFOLS_PRESET": "stable_gate77",
    "INTODE_SOLVER_ASSIST_ENABLED": "0",
}
ARTIFACTS = (
    ("stage2_summary", "stage2_summary.dat", True),
    ("stage2_label_trace", "stage2_label_trace.dat", False),
)


def parse_args():
    parser = argparse.ArgumentParser(description="Run the Stage2 kernel RNG v2 deterministic anchor.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--fc", default=os.environ.get("FC", ""), help="Optional Fortran compiler override.")
    parser.add_argument("--ldflags", default=os.environ.get("LDFLAGS", ""), help="LDFLAGS passed to make.")
    parser.add_argument("--skip-build", action="store_true", help="Skip building Stage2 executable.")
    parser.add_argument(
        "--output-root",
        default=str(DEFAULT_OUTPUT_REL),
        help="Output root relative to repo root, or absolute.",
    )
    return parser.parse_args()


def resolve_path(repo_root, raw_path):
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return repo_root / path


def relpath_text(repo_root, path):
    path = Path(path)
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def run_step(label, cmd, cwd, env=None, log_path=None):
    print("[STAGE2-RNG-V2][RUN] {0}".format(label))
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        check=False,
    )
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(proc.stdout, encoding="utf-8")
    if proc.returncode != 0:
        print("[STAGE2-RNG-V2][FAIL] {0}".format(label))
        sys.stdout.write(proc.stdout)
        raise RuntimeError("{0} failed with exit code {1}".format(label, proc.returncode))
    print("[STAGE2-RNG-V2][PASS] {0}".format(label))
    return proc


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


def normalize_text(path, normalize_summary):
    text = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
    normalized = []
    runtime_index = None
    for raw_line in text:
        line = raw_line.rstrip()
        stripped = line.strip()
        if normalize_summary and stripped.startswith("# elapsed_sec="):
            normalized.append("# elapsed_sec=<elapsed_sec>")
            runtime_index = None
            continue
        if normalize_summary and (
            stripped.startswith("# production_timing ") or stripped.startswith("# production_subtiming ")
        ):
            tokens = stripped.split()
            telemetry_key = tokens[1] if len(tokens) > 1 and tokens[0] == "#" else tokens[0].lstrip("#")
            normalized.append("#{0}=<runtime_dependent_production_telemetry>".format(telemetry_key))
            runtime_index = None
            continue
        if stripped.startswith("#"):
            tokens = stripped[1:].strip().split()
            if tokens and tokens[0].startswith("[") and tokens[0].endswith("]"):
                tokens = tokens[1:]
            if normalize_summary and "runtime_sec" in tokens:
                runtime_index = tokens.index("runtime_sec")
            else:
                runtime_index = None
            normalized.append(line)
            continue
        if normalize_summary and runtime_index is not None and stripped:
            tokens = line.split()
            if len(tokens) > runtime_index:
                tokens[runtime_index] = "<runtime_sec>"
                normalized.append(" ".join(tokens))
                continue
        normalized.append(line)
    return "\n".join(normalized) + "\n"


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def require_contains(path, needle):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    if needle not in text:
        raise RuntimeError("{0} missing required text: {1}".format(path, needle))


def run_stage2_once(repo_root, output_root, label, base_env, explicit_contract):
    run_root = output_root / label
    if run_root.exists():
        shutil.rmtree(run_root)
    run_root.mkdir(parents=True, exist_ok=True)

    env = base_env.copy()
    env.update(CANONICAL_QN_ENV)
    env.update(STAGE2_ENV)
    if explicit_contract:
        env["TLTM_STAGE2_RNG_STREAM_CONTRACT"] = CONTRACT
    else:
        env.pop("TLTM_STAGE2_RNG_STREAM_CONTRACT", None)

    stage2_summary = run_root / "stage2_summary.dat"
    stage2_label_trace = run_root / "stage2_label_trace.dat"
    env["TLTM_STAGE2_SUMMARY_FILE"] = str(stage2_summary)
    env["TLTM_STAGE2_LABEL_TRACE_FILE"] = str(stage2_label_trace)
    run_step(
        "Stage2 {0} deterministic run".format(label),
        [str(repo_root / "bin" / "run_tltm_stage2")],
        repo_root,
        env,
        run_root / "stage2.log",
    )

    require_contains(stage2_summary, "rng_stream_contract={0}".format(CONTRACT))
    require_contains(stage2_summary, "base_seed={0}".format(SEED))

    hashes = {}
    for artifact_name, filename, normalize_summary in ARTIFACTS:
        artifact_path = run_root / filename
        if not artifact_path.exists():
            raise RuntimeError("missing artifact: {0}".format(artifact_path))
        hashes[artifact_name] = sha256_text(normalize_text(artifact_path, normalize_summary))
    return {
        "label": label,
        "explicit_contract": explicit_contract,
        "root": relpath_text(repo_root, run_root),
        "hashes": hashes,
    }


def assert_same_hashes(left, right):
    if left["hashes"] != right["hashes"]:
        raise RuntimeError(
            "Stage2 RNG v2 hashes differ between {0} and {1}:\n{2}\n{3}".format(
                left["label"],
                right["label"],
                json.dumps(left["hashes"], indent=2, sort_keys=True),
                json.dumps(right["hashes"], indent=2, sort_keys=True),
            )
        )


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_path(repo_root, args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        run_step(
            "Build run_tltm_stage2",
            make_cmd(repo_root, args, ["../bin/run_tltm_stage2"]),
            repo_root,
        )

    base_env = os.environ.copy()
    base_env.update(infer_official_dfols_env(repo_root))

    explicit_a = run_stage2_once(repo_root, output_root, "explicit_a", base_env, True)
    explicit_b = run_stage2_once(repo_root, output_root, "explicit_b", base_env, True)
    default_run = run_stage2_once(repo_root, output_root, "default_contract", base_env, False)
    assert_same_hashes(explicit_a, explicit_b)
    assert_same_hashes(explicit_a, default_run)

    manifest = {
        "schema_version": "tltm.stage2_rng_v2_anchor.v1",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "contract": CONTRACT,
        "seed": SEED,
        "runs": [explicit_a, explicit_b, default_run],
        "hashes": explicit_a["hashes"],
    }
    manifest_path = output_root / "STAGE2_RNG_V2_anchor_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("[STAGE2-RNG-V2][PASS] manifest={0}".format(relpath_text(repo_root, manifest_path)))


if __name__ == "__main__":
    main()
