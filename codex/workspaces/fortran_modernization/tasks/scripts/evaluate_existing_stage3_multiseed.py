#!/usr/bin/env python3
"""Evaluate existing stage-3 multiseed outputs without rerunning stage2."""

import importlib.util
import sys
from pathlib import Path


def repo_root_from_argv(argv):
    for idx, arg in enumerate(argv):
        if arg == "--repo-root" and idx + 1 < len(argv):
            return Path(argv[idx + 1]).resolve()
        if arg.startswith("--repo-root="):
            return Path(arg.split("=", 1)[1]).resolve()
    return Path(".").resolve()


def load_driver(repo_root):
    driver_path = repo_root / "scripts" / "run_stage3_3_multiseed.py"
    if not driver_path.exists():
        raise RuntimeError("Missing multiseed driver: {0}".format(driver_path))
    spec = importlib.util.spec_from_file_location("run_stage3_3_multiseed", str(driver_path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_existing_stage2(env):
    required_keys = (
        "TLTM_STAGE2_SUMMARY_FILE",
        "TLTM_STAGE2_LABEL_TRACE_FILE",
        "TLTM_STAGE2_COLD_Z_HISTORY_FILE",
        "TLTM_STAGE2_COLD_PHI_HISTORY_FILE",
    )
    missing = []
    for key in required_keys:
        value = env.get(key, "")
        path = Path(value)
        if (not value) or (not path.exists()) or path.stat().st_size <= 0:
            missing.append("{0}={1}".format(key, value or "<unset>"))
    if missing:
        raise RuntimeError("Cannot reuse incomplete stage2 output: {0}".format(", ".join(missing)))


def append_skip_log(log_file):
    log_file.parent.mkdir(parents=True, exist_ok=True)
    prefix = "\n" if log_file.exists() and log_file.stat().st_size > 0 else ""
    with log_file.open("a") as handle:
        handle.write(prefix)
        handle.write("[SKIP] Reused existing run_tltm_stage2 output; evaluation/report only.\n")


def main():
    repo_root = repo_root_from_argv(sys.argv[1:])
    driver = load_driver(repo_root)
    original_run_command = driver.run_command

    def run_command_reusing_stage2(cmd, env, cwd, log_file):
        executable = Path(cmd[0]).name
        if executable == "run_tltm_stage2":
            validate_existing_stage2(env)
            append_skip_log(Path(log_file))
            return
        return original_run_command(cmd, env, cwd, log_file)

    driver.run_command = run_command_reusing_stage2
    driver.main()


if __name__ == "__main__":
    main()
