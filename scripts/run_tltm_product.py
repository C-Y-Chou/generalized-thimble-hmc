#!/usr/bin/env python3
"""Product-facing runner for generalized thimble simulations.

The wrapper exposes the current public surface:

* canonical TLTM execution through the Stage3 multiseed driver;
* dense explicit-J WV-HMC execution through ``bin/run_wv_hmc``;
* build and validation commands used by the public README.

It intentionally keeps research campaign selectors out of the user-facing
interface.  Internal scripts remain available for reproducibility work, but a
new user should be able to start here.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Mapping


DEFAULT_PARAMETERS = "data/parameters_stephanov_n6_mu06_t0.dat"
DEFAULT_OUTPUT_ROOT = "output/product"
DEFAULT_WV_T0 = 1.0e-4
DEFAULT_WV_T1 = 3.0e-2
DEFAULT_WV_D0 = 1.0e-4
DEFAULT_WV_D1 = 5.0e-3
DEFAULT_WV_STEP_SIZE = 1.6e-2
DEFAULT_WV_STEPS = 10
DEFAULT_WV_GAMMA = 55.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build, test, and run the product-facing generalized thimble workflows."
    )
    parser.add_argument("--repo-root", default=".", help="Repository root. Defaults to the current directory.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build", help="Build public executables.")
    build.add_argument(
        "--target",
        action="append",
        default=[],
        help="Additional build target. Defaults to run_wv_hmc and run_wv_hmc_smoke.",
    )
    build.add_argument("--fast", action="store_true", help="Use debug-friendly Fortran flags.")
    build.add_argument("--dry-run", action="store_true", help="Print commands without executing.")

    test = subparsers.add_parser("test", help="Run public validation targets.")
    test.add_argument(
        "--target",
        action="append",
        default=[],
        help="Additional test target. Defaults to WV-HMC math/constraint and model derivative tests.",
    )
    test.add_argument("--dry-run", action="store_true", help="Print commands without executing.")

    tltm = subparsers.add_parser("tltm", help="Run canonical TLTM through the multiseed driver.")
    tltm.add_argument("--config", required=True, help="Stage3 protocol JSON.")
    tltm.add_argument("--output-dir", default=f"{DEFAULT_OUTPUT_ROOT}/tltm", help="Output directory.")
    tltm.add_argument("--logs-dir", default="output/logs/product/tltm", help="Log directory.")
    tltm.add_argument("--seed-offset", type=int, default=0, help="First selected seed offset.")
    tltm.add_argument("--max-seeds", type=int, default=0, help="Maximum selected seeds; 0 means all.")
    tltm.add_argument("--jobs", type=int, default=1, help="Parallel worker count.")
    tltm.add_argument("--skip-build", action="store_true", help="Do not rebuild delegated executables.")
    tltm.add_argument("--dry-run", action="store_true", help="Print the delegated plan without executing.")

    wv = subparsers.add_parser("wv-hmc", help="Run dense explicit-J WV-HMC.")
    wv.add_argument("--parameters", default=DEFAULT_PARAMETERS, help="Parameters file.")
    wv.add_argument("--output-dir", default=f"{DEFAULT_OUTPUT_ROOT}/wv_hmc", help="Output directory.")
    wv.add_argument("--seed", type=int, default=20260529, help="Base RNG seed.")
    wv.add_argument("--cycles", type=int, default=100, help="Number of Markov cycles.")
    wv.add_argument("--step-size", type=float, default=DEFAULT_WV_STEP_SIZE, help="Leapfrog step size.")
    wv.add_argument("--num-steps", type=int, default=DEFAULT_WV_STEPS, help="Leapfrog step count.")
    wv.add_argument("--t0", type=float, default=DEFAULT_WV_T0, help="Sampler lower flow-time boundary.")
    wv.add_argument("--t1", type=float, default=DEFAULT_WV_T1, help="Sampler upper flow-time boundary.")
    wv.add_argument("--d0", type=float, default=DEFAULT_WV_D0, help="Lower soft-wall width.")
    wv.add_argument("--d1", type=float, default=DEFAULT_WV_D1, help="Upper soft-wall width.")
    wv.add_argument("--measurement-t0", type=float, default=None, help="Measurement lower flow-time boundary.")
    wv.add_argument("--measurement-t1", type=float, default=None, help="Measurement upper flow-time boundary.")
    wv.add_argument("--measurement-start-cycle", type=int, default=1, help="First measured cycle.")
    wv.add_argument("--w-profile", default="paper_wall", choices=("paper_wall", "zero", "polynomial"), help="Flow-time potential profile.")
    wv.add_argument("--w-gamma", type=float, default=DEFAULT_WV_GAMMA, help="Flow-time potential strength.")
    wv.add_argument("--w-c0", type=float, default=1.0, help="Lower wall coefficient.")
    wv.add_argument("--w-c1", type=float, default=1.0, help="Upper wall coefficient.")
    wv.add_argument(
        "--init-mode",
        default="deterministic",
        choices=("deterministic", "zero", "gaussian", "random_gaussian", "bank", "state_bank"),
        help="Initial state source.",
    )
    wv.add_argument("--init-sigma", type=float, default=0.8, help="Gaussian initial-state scale.")
    wv.add_argument("--init-bank-file", default="", help="Initial bank path for bank modes.")
    wv.add_argument("--init-bank-record", type=int, default=-1, help="Bank record index; -1 chooses from the seed.")
    wv.add_argument("--constraint-tol", type=float, default=1.0e-10, help="Newton projection tolerance.")
    wv.add_argument("--constraint-max-iter", type=int, default=192, help="Newton projection iteration cap.")
    wv.add_argument("--reverse-state-tol", type=float, default=1.0e-6, help="Reverse trajectory state tolerance.")
    wv.add_argument("--reverse-momentum-tol", type=float, default=1.0e-4, help="Reverse trajectory momentum tolerance.")
    wv.add_argument("--history", action="store_true", help="Write observable and state histories.")
    wv.add_argument("--history-stride", type=int, default=1, help="History stride in cycles.")
    wv.add_argument("--snapshot-interval", type=int, default=0, help="Write cyclic snapshots every N cycles; 0 disables.")
    wv.add_argument("--snapshot-slots", type=int, default=4, help="Number of cyclic snapshot slots.")
    wv.add_argument("--skip-build", action="store_true", help="Do not build bin/run_wv_hmc first.")
    wv.add_argument("--dry-run", action="store_true", help="Print command and environment without executing.")

    return parser.parse_args()


def repo_root_from(args: argparse.Namespace) -> Path:
    return Path(args.repo_root).resolve()


def as_repo_path(repo_root: Path, path_text: str) -> Path:
    path = Path(path_text)
    return path if path.is_absolute() else repo_root / path


def relpath(repo_root: Path, path: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo_root))
    except ValueError:
        return str(path)


def run_command(cmd: List[str], cwd: Path, dry_run: bool, env: Mapping[str, str] | None = None) -> int:
    if dry_run:
        print("$ " + " ".join(cmd))
        if env:
            for key in sorted(env):
                print(f"{key}={env[key]}")
        return 0
    if env is None:
        return subprocess.call(cmd, cwd=str(cwd))
    run_env = os.environ.copy()
    run_env.update(env)
    return subprocess.call(cmd, cwd=str(cwd), env=run_env)


def make_command(repo_root: Path, targets: Iterable[str], fast: bool = False) -> List[str]:
    cmd = ["make", "-C", str(repo_root / "build")]
    if fast:
        cmd.append("fast")
    cmd.extend(targets)
    return cmd


def product_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_manifest(path: Path, payload: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def command_build(repo_root: Path, args: argparse.Namespace) -> int:
    targets = args.target or ["../bin/run_wv_hmc", "../bin/run_wv_hmc_smoke"]
    return run_command(make_command(repo_root, targets, fast=args.fast), repo_root, args.dry_run)


def command_test(repo_root: Path, args: argparse.Namespace) -> int:
    targets = args.target or [
        "test_wv_hmc_math_kernels",
        "test_wv_hmc_constraint_kernels",
        "test2",
    ]
    return run_command(make_command(repo_root, targets), repo_root, args.dry_run)


def command_tltm(repo_root: Path, args: argparse.Namespace) -> int:
    config_path = as_repo_path(repo_root, args.config)
    if not config_path.exists():
        print(f"ERROR config does not exist: {config_path}", file=sys.stderr)
        return 2

    cmd = [
        sys.executable,
        str(repo_root / "scripts" / "run_stage3_3_multiseed.py"),
        "--repo-root",
        str(repo_root),
        "--config",
        str(config_path),
        "--methods",
        "no_fb",
        "--seed-offset",
        str(args.seed_offset),
        "--max-seeds",
        str(args.max_seeds),
        "--jobs",
        str(args.jobs),
        "--output-subdir",
        args.output_dir,
        "--logs-subdir",
        args.logs_dir,
        "--log-prefix",
        "tltm_product",
        "--report-title",
        "Canonical TLTM Product Run",
        "--stage2-v1-sidecars",
        "on",
        "--stage2-protocol-audit",
        "auto",
        "--stage2-protocol-audit-fail-on",
        "error",
    ]
    if args.skip_build:
        cmd.append("--skip-build")
    if args.dry_run:
        cmd.append("--dry-run")

    status = run_command(cmd, repo_root, args.dry_run)
    if status == 0 and not args.dry_run:
        out_dir = as_repo_path(repo_root, args.output_dir)
        write_manifest(
            out_dir / "product_run_manifest.json",
            {
                "schema_version": "gtm.product.run.v1",
                "sampler": "tltm",
                "generated_at_utc": product_timestamp(),
                "config": relpath(repo_root, config_path),
                "output_dir": relpath(repo_root, out_dir),
                "logs_dir": args.logs_dir,
                "driver": relpath(repo_root, repo_root / "scripts" / "run_stage3_3_multiseed.py"),
                "stage2_sidecars": "on",
                "protocol_audit": "auto",
            },
        )
    return status


def wv_env(repo_root: Path, args: argparse.Namespace, out_dir: Path) -> Dict[str, str]:
    env = {
        "TLTM_PARAMETERS_FILE": str(as_repo_path(repo_root, args.parameters)),
        "TLTM_ODE_BACKEND": "dop853",
        "WV_HMC_BASE_SEED": str(args.seed),
        "WV_HMC_CYCLES": str(args.cycles),
        "WV_HMC_STEP_SIZE": str(args.step_size),
        "WV_HMC_NUM_STEPS": str(args.num_steps),
        "WV_HMC_T0": str(args.t0),
        "WV_HMC_T1": str(args.t1),
        "WV_HMC_D0": str(args.d0),
        "WV_HMC_D1": str(args.d1),
        "WV_HMC_W_PROFILE": args.w_profile,
        "WV_HMC_W_GAMMA": str(args.w_gamma),
        "WV_HMC_W_C0": str(args.w_c0),
        "WV_HMC_W_C1": str(args.w_c1),
        "WV_HMC_INIT_MODE": args.init_mode,
        "WV_HMC_INIT_SIGMA": str(args.init_sigma),
        "WV_HMC_INIT_BANK_RECORD": str(args.init_bank_record),
        "WV_HMC_CONSTRAINT_TOL": str(args.constraint_tol),
        "WV_HMC_CONSTRAINT_MAX_ITER": str(args.constraint_max_iter),
        "WV_HMC_REVERSE_GATE_STATE_TOL": str(args.reverse_state_tol),
        "WV_HMC_REVERSE_GATE_MOMENTUM_TOL": str(args.reverse_momentum_tol),
        "WV_HMC_MEASUREMENT_START_CYCLE": str(args.measurement_start_cycle),
        "WV_HMC_SUMMARY_FILE": str(out_dir / "summary.csv"),
        "WV_HMC_OBSERVABLE_FILE": str(out_dir / "observables.csv"),
        "WV_HMC_FINAL_STATE_FILE": str(out_dir / "final_state.bin"),
    }
    if args.measurement_t0 is not None:
        env["WV_HMC_MEASUREMENT_T0"] = str(args.measurement_t0)
    if args.measurement_t1 is not None:
        env["WV_HMC_MEASUREMENT_T1"] = str(args.measurement_t1)
    if args.init_bank_file:
        env["WV_HMC_INIT_BANK_FILE"] = str(as_repo_path(repo_root, args.init_bank_file))
    if args.history:
        env["WV_HMC_HISTORY_STRIDE"] = str(args.history_stride)
        env["WV_HMC_OBSERVABLE_HISTORY_FILE"] = str(out_dir / "observable_history.csv")
        env["WV_HMC_X_HISTORY_FILE"] = str(out_dir / "x_history.dat")
        env["WV_HMC_STATE_HISTORY_FILE"] = str(out_dir / "state_history.dat")
    if args.snapshot_interval > 0:
        env["WV_HMC_SNAPSHOT_INTERVAL"] = str(args.snapshot_interval)
        env["WV_HMC_SNAPSHOT_SLOTS"] = str(args.snapshot_slots)
        env["WV_HMC_SNAPSHOT_PREFIX"] = str(out_dir / "snapshots" / "snapshot")
        env["WV_HMC_SNAPSHOT_INDEX_FILE"] = str(out_dir / "snapshot_index.csv")
    return env


def command_wv_hmc(repo_root: Path, args: argparse.Namespace) -> int:
    parameters_path = as_repo_path(repo_root, args.parameters)
    if not parameters_path.exists():
        print(f"ERROR parameters file does not exist: {parameters_path}", file=sys.stderr)
        return 2

    out_dir = as_repo_path(repo_root, args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    if args.snapshot_interval > 0:
        (out_dir / "snapshots").mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        status = run_command(make_command(repo_root, ["../bin/run_wv_hmc"]), repo_root, args.dry_run)
        if status != 0:
            return status

    env = wv_env(repo_root, args, out_dir)
    cmd = [str(repo_root / "bin" / "run_wv_hmc")]
    status = run_command(cmd, repo_root, args.dry_run, env=env)
    if status != 0 or args.dry_run:
        return status

    write_manifest(
        out_dir / "product_run_manifest.json",
        {
            "schema_version": "gtm.product.run.v1",
            "sampler": "wv_hmc_dense_explicit_j",
            "generated_at_utc": product_timestamp(),
            "parameters": relpath(repo_root, parameters_path),
            "output_dir": relpath(repo_root, out_dir),
            "cycles": args.cycles,
            "seed": args.seed,
            "step_size": args.step_size,
            "num_steps": args.num_steps,
            "t0": args.t0,
            "t1": args.t1,
            "d0": args.d0,
            "d1": args.d1,
            "measurement_t0": args.measurement_t0 if args.measurement_t0 is not None else args.t0,
            "measurement_t1": args.measurement_t1 if args.measurement_t1 is not None else args.t1,
            "measurement_start_cycle": args.measurement_start_cycle,
            "w_profile": args.w_profile,
            "w_gamma": args.w_gamma,
            "init_mode": args.init_mode,
            "ode_backend": "dop853",
            "outputs": {
                "summary": relpath(repo_root, out_dir / "summary.csv"),
                "observables": relpath(repo_root, out_dir / "observables.csv"),
                "final_state": relpath(repo_root, out_dir / "final_state.bin"),
                "observable_history": relpath(repo_root, out_dir / "observable_history.csv")
                if args.history
                else "",
                "snapshot_index": relpath(repo_root, out_dir / "snapshot_index.csv")
                if args.snapshot_interval > 0
                else "",
            },
        },
    )
    return 0


def main() -> int:
    args = parse_args()
    repo_root = repo_root_from(args)
    if args.command == "build":
        return command_build(repo_root, args)
    if args.command == "test":
        return command_test(repo_root, args)
    if args.command == "tltm":
        return command_tltm(repo_root, args)
    if args.command == "wv-hmc":
        return command_wv_hmc(repo_root, args)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
