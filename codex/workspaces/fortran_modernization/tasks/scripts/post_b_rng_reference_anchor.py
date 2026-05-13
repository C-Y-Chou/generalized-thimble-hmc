#!/usr/bin/env python3
"""Validate the post-B route-B RNG reference anchor.

The route-B CV-011 decision intentionally changed finite same-seed trajectories
from the old shared serial RNG stream to per-replica/per-slot local streams plus
a separate swap stream. This gate freezes a tiny deterministic reference for
that new contract so later workspace/thread-safety refactors have a local anchor.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


WORKSPACE_REL = Path("codex/workspaces/fortran_modernization")
REFERENCE_REL = WORKSPACE_REL / "state/POST_B_RNG_REFERENCE_ANCHOR_V1.json"
DEFAULT_OUTPUT_REL = Path("output/tests/post_b_rng_reference_anchor")
CONTRACT = "per_replica_rng_v1"
SEED = "12345"
STAGE1_ENV = {
    "CHAIN_RNG_SEED": SEED,
    "TLTM_STAGE1_NUM_REPLICAS": "2",
    "TLTM_STAGE1_CYCLES": "2",
    "TLTM_STAGE1_LOCAL_UPDATES": "2",
    "TLTM_STAGE1_MAX_FLOW_TIME": "0.1",
}
STAGE2_ENV = {
    "CHAIN_RNG_SEED": SEED,
    "TLTM_STAGE2_RNG_STREAM_CONTRACT": CONTRACT,
    "TLTM_STAGE2_NUM_REPLICAS": "2",
    "TLTM_STAGE2_CYCLES": "2",
    "TLTM_STAGE2_LOCAL_UPDATES": "2",
    "TLTM_STAGE2_MAX_FLOW_TIME": "0.1",
    "TLTM_STAGE2_SWAP_ENABLED": "1",
}
CANONICAL_QN_ENV = {
    "QN_SOLVER_BACKEND": "official_dfols",
    "QN_OFFICIAL_DFOLS_PRESET": "stable_gate77",
    "INTODE_SOLVER_ASSIST_ENABLED": "0",
}
ARTIFACTS = (
    ("stage1_summary", "stage1_summary.dat", True),
    ("stage2_summary", "stage2_summary.dat", True),
    ("stage2_label_trace", "stage2_label_trace.dat", False),
)


def parse_args():
    parser = argparse.ArgumentParser(description="Run the post-B RNG reference anchor gate.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--fc", default=os.environ.get("FC", ""), help="Optional Fortran compiler override.")
    parser.add_argument("--ldflags", default=os.environ.get("LDFLAGS", ""), help="LDFLAGS passed to make.")
    parser.add_argument("--skip-build", action="store_true", help="Skip building Stage1/Stage2 executables.")
    parser.add_argument(
        "--reference",
        default=str(REFERENCE_REL),
        help="Reference JSON path relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--output-root",
        default=str(DEFAULT_OUTPUT_REL),
        help="Output root relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--update-reference",
        action="store_true",
        help="Write the current hashes to the reference JSON instead of comparing them.",
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
    print("[POST-B-RNG][RUN] {0}".format(label))
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
        print("[POST-B-RNG][FAIL] {0}".format(label))
        sys.stdout.write(proc.stdout)
        raise RuntimeError("{0} failed with exit code {1}".format(label, proc.returncode))
    print("[POST-B-RNG][PASS] {0}".format(label))
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


def run_anchor_once(repo_root, output_root, label, base_env):
    run_root = output_root / label
    if run_root.exists():
        shutil.rmtree(run_root)
    run_root.mkdir(parents=True, exist_ok=True)

    env = base_env.copy()
    env.update(CANONICAL_QN_ENV)
    stage1_summary = run_root / "stage1_summary.dat"
    stage1_env = env.copy()
    stage1_env.update(STAGE1_ENV)
    stage1_env["TLTM_STAGE1_SUMMARY_FILE"] = str(stage1_summary)
    run_step(
        "Stage1 tiny deterministic run {0}".format(label),
        [str(repo_root / "bin" / "run_tltm_stage1")],
        repo_root,
        stage1_env,
        run_root / "stage1.log",
    )

    stage2_summary = run_root / "stage2_summary.dat"
    stage2_label_trace = run_root / "stage2_label_trace.dat"
    stage2_env = env.copy()
    stage2_env.update(STAGE2_ENV)
    stage2_env["TLTM_STAGE2_SUMMARY_FILE"] = str(stage2_summary)
    stage2_env["TLTM_STAGE2_LABEL_TRACE_FILE"] = str(stage2_label_trace)
    run_step(
        "Stage2 tiny deterministic run {0}".format(label),
        [str(repo_root / "bin" / "run_tltm_stage2")],
        repo_root,
        stage2_env,
        run_root / "stage2.log",
    )

    require_contains(stage1_summary, "rng_stream_contract={0}".format(CONTRACT))
    require_contains(stage2_summary, "rng_stream_contract={0}".format(CONTRACT))
    require_contains(stage1_summary, "base_seed={0}".format(SEED))
    require_contains(stage2_summary, "base_seed={0}".format(SEED))
    require_contains(stage2_summary, "swap_rng_seed=")

    result = {}
    for artifact_id, filename, normalize_summary in ARTIFACTS:
        artifact_path = run_root / filename
        normalized = normalize_text(artifact_path, normalize_summary)
        normalized_path = run_root / (filename + ".normalized")
        normalized_path.write_text(normalized, encoding="utf-8")
        result[artifact_id] = {
            "path": relpath_text(repo_root, artifact_path),
            "normalized_path": relpath_text(repo_root, normalized_path),
            "normalized_sha256": sha256_text(normalized),
        }
    return result


def build_reference(actual_hashes):
    return {
        "schema": "POST_B_RNG_REFERENCE_ANCHOR_V1",
        "contract": CONTRACT,
        "seed": SEED,
        "stage1": {
            "summary_normalized_sha256": actual_hashes["stage1_summary"],
        },
        "stage2": {
            "summary_normalized_sha256": actual_hashes["stage2_summary"],
            "label_trace_normalized_sha256": actual_hashes["stage2_label_trace"],
        },
        "normalization": [
            "summary elapsed_sec lines are replaced with <elapsed_sec>",
            "summary runtime_sec columns are replaced with <runtime_sec>",
        ],
    }


def load_reference(path):
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def compare_reference(reference, actual_hashes):
    expected = {
        "stage1_summary": reference.get("stage1", {}).get("summary_normalized_sha256"),
        "stage2_summary": reference.get("stage2", {}).get("summary_normalized_sha256"),
        "stage2_label_trace": reference.get("stage2", {}).get("label_trace_normalized_sha256"),
    }
    failures = []
    if reference.get("schema") != "POST_B_RNG_REFERENCE_ANCHOR_V1":
        failures.append("reference schema mismatch: {0}".format(reference.get("schema")))
    if reference.get("contract") != CONTRACT:
        failures.append("reference contract mismatch: {0}".format(reference.get("contract")))
    if reference.get("seed") != SEED:
        failures.append("reference seed mismatch: {0}".format(reference.get("seed")))
    for key in sorted(expected):
        if expected[key] != actual_hashes[key]:
            failures.append("{0}: expected {1}, actual {2}".format(key, expected[key], actual_hashes[key]))
    return failures


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve_path(repo_root, args.output_root)
    reference_path = resolve_path(repo_root, args.reference)
    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    base_env = os.environ.copy()
    base_env.update(infer_official_dfols_env(repo_root))

    if not args.skip_build:
        run_step(
            "build Stage1/Stage2 executables",
            make_cmd(repo_root, args, ["../bin/run_tltm_stage1", "../bin/run_tltm_stage2"]),
            repo_root,
            base_env,
            output_root / "build.log",
        )

    run_a = run_anchor_once(repo_root, output_root, "run_a", base_env)
    run_b = run_anchor_once(repo_root, output_root, "run_b", base_env)

    actual_hashes = {}
    repeat_failures = []
    for artifact_id, _filename, _normalize_summary in ARTIFACTS:
        hash_a = run_a[artifact_id]["normalized_sha256"]
        hash_b = run_b[artifact_id]["normalized_sha256"]
        actual_hashes[artifact_id] = hash_a
        if hash_a != hash_b:
            repeat_failures.append("{0}: run_a {1}, run_b {2}".format(artifact_id, hash_a, hash_b))

    reference_status = "updated" if args.update_reference else "checked"
    reference_failures = []
    if repeat_failures:
        reference_status = "not_checked_repeat_mismatch"
    elif args.update_reference:
        reference_path.parent.mkdir(parents=True, exist_ok=True)
        reference_path.write_text(
            json.dumps(build_reference(actual_hashes), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    else:
        if not reference_path.exists():
            reference_failures.append(
                "Missing reference file {0}; run with --update-reference to create it.".format(
                    relpath_text(repo_root, reference_path)
                )
            )
        else:
            reference_failures = compare_reference(load_reference(reference_path), actual_hashes)

    status = "pass" if not repeat_failures and not reference_failures else "fail"
    manifest = {
        "status": status,
        "schema": "POST_B_RNG_REFERENCE_ANCHOR_MANIFEST_V1",
        "contract": CONTRACT,
        "seed": SEED,
        "reference_path": relpath_text(repo_root, reference_path),
        "reference_status": reference_status,
        "run_a": run_a,
        "run_b": run_b,
        "actual_hashes": actual_hashes,
        "repeat_failures": repeat_failures,
        "reference_failures": reference_failures,
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    manifest_path = output_root / "POST_B_RNG_reference_anchor_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("status={0}".format(status))
    print("manifest={0}".format(relpath_text(repo_root, manifest_path)))
    print("reference={0}".format(relpath_text(repo_root, reference_path)))
    if status != "pass":
        for failure in repeat_failures + reference_failures:
            print("[POST-B-RNG][FAIL] {0}".format(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
