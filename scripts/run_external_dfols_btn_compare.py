#!/usr/bin/env python3
"""Replay TLTM BTN residual cases through the official Python DFO-LS package.

This is an offline comparison tool, not a production HMC path.  TLTM remains
responsible for the BTN residual oracle and seed construction; DFO-LS only sees
an ``objfun(x) -> residual_vector`` callback in double precision.
"""

from __future__ import annotations

import argparse
import csv
import os
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

for thread_env_name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(thread_env_name, "1")

import numpy as np


@dataclass(frozen=True)
class BridgeSeed:
    sample_idx: int
    n: int
    z_recompute_inf: float
    seed_norm: float
    xi0: np.ndarray


@dataclass(frozen=True)
class BridgeResidual:
    sample_idx: int
    n: int
    z_recompute_inf: float
    residual_norm: float
    flow_im_norm: float
    a_norm: float
    jl_norm: float
    fq: np.ndarray


class BridgeError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run official DFO-LS against TLTM captured BTN residual cases. "
            "Requires a capture directory containing PREFIX_z0/delz/x0.dat files."
        )
    )
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--case-dir", type=Path, required=True)
    parser.add_argument("--bridge-bin", type=Path, default=Path("bin/evaluate_btn_residual_case"))
    parser.add_argument(
        "--parameters-file",
        type=Path,
        default=None,
        help="Optional TLTM parameter file passed to the bridge residual oracle.",
    )
    parser.add_argument("--capture-prefix", default="constraint_solver_fail")
    parser.add_argument(
        "--seed-source",
        choices=("auto", "bridge", "capture"),
        default="auto",
        help="Use bridge-computed seed, captured PREFIX_xi0.dat seed, or captured seed when available.",
    )
    parser.add_argument("--sample-ids", default="all", help="'all' or comma-separated capture sample_idx values.")
    parser.add_argument("--max-cases", type=int, default=0, help="Limit number of cases after sample-id selection; 0 means no limit.")
    parser.add_argument("--maxfun", type=int, default=28, help="DFO-LS maximum objective evaluations.")
    parser.add_argument("--npt", type=int, default=0, help="DFO-LS interpolation point count; 0 uses package default.")
    parser.add_argument("--rhobeg", type=float, default=None, help="DFO-LS initial trust-region radius. Omit to use package default.")
    parser.add_argument("--rhoend", type=float, default=1.0e-13, help="DFO-LS final trust-region radius.")
    parser.add_argument(
        "--objfun-has-noise",
        action="store_true",
        help="Enable official DFO-LS noise-aware/restart defaults. This does not add external wrapper logic.",
    )
    parser.add_argument(
        "--model-abs-tol",
        type=float,
        default=None,
        help="Optional DFO-LS least-squares objective absolute tolerance, e.g. 1e-26 for residual ~1e-13.",
    )
    parser.add_argument(
        "--model-rel-tol",
        type=float,
        default=None,
        help="Optional DFO-LS least-squares objective relative tolerance.",
    )
    parser.add_argument(
        "--residual-success-tol",
        type=float,
        default=1.0e-12,
        help="Residual-norm gate used by the comparison CSV; independent of DFO-LS package flags.",
    )
    parser.add_argument(
        "--dfols-param",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Official DFO-LS user_params override; repeatable. Values parse as bool/int/float/string.",
    )
    parser.add_argument("--numpy-seed", type=int, default=20260511, help="Base NumPy seed for deterministic DFO-LS replay.")
    parser.add_argument("--out-csv", type=Path, required=True)
    parser.add_argument("--diagnostic-dir", type=Path, default=None)
    parser.add_argument("--print-progress", action="store_true")
    return parser.parse_args()


def parse_dfols_param_value(raw_value: str) -> object:
    value = raw_value.strip()
    lowered = value.lower()
    if lowered in {"true", "t", "yes", "y", "1", "on"}:
        return True
    if lowered in {"false", "f", "no", "n", "0", "off"}:
        return False
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        return value


def parse_dfols_params(raw_params: list[str]) -> dict[str, object]:
    params: dict[str, object] = {}
    for item in raw_params:
        if "=" not in item:
            raise ValueError(f"Expected --dfols-param KEY=VALUE, got {item!r}")
        key, raw_value = item.split("=", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"Empty DFO-LS parameter name in {item!r}")
        params[key] = parse_dfols_param_value(raw_value)
    return params


def resolve_repo_path(repo_root: Path, path: Path) -> Path:
    return path if path.is_absolute() else repo_root / path


def list_capture_sample_ids(case_dir: Path, capture_prefix: str) -> list[int]:
    z0_path = case_dir / f"{capture_prefix}_z0.dat"
    if not z0_path.exists():
        raise FileNotFoundError(f"Missing capture file: {z0_path}")
    sample_ids: list[int] = []
    with z0_path.open("rb") as fobj:
        while True:
            head = fobj.read(8)
            if not head:
                break
            if len(head) != 8:
                raise RuntimeError(f"Truncated stream header in {z0_path}")
            sample_idx, n_items = struct.unpack("<ii", head)
            if n_items < 0:
                raise RuntimeError(f"Invalid n={n_items} in {z0_path}")
            payload = fobj.read(16 * n_items)
            if len(payload) != 16 * n_items:
                raise RuntimeError(f"Truncated stream payload in {z0_path} for sample_idx={sample_idx}")
            sample_ids.append(sample_idx)
    return sample_ids


def select_sample_ids(case_dir: Path, capture_prefix: str, selector: str, max_cases: int) -> list[int]:
    if selector.strip().lower() == "all":
        sample_ids = list_capture_sample_ids(case_dir, capture_prefix)
    else:
        sample_ids = [int(part) for part in selector.split(",") if part.strip()]
    if max_cases > 0:
        sample_ids = sample_ids[:max_cases]
    if not sample_ids:
        raise RuntimeError("No capture cases selected.")
    return sample_ids


def format_float64(value: float) -> str:
    return f"{np.float64(value):.17e}"


def run_bridge(
    repo_root: Path,
    bridge_bin: Path,
    case_dir: Path,
    capture_prefix: str,
    parameters_file: Path | None,
    mode: str,
    sample_idx: int,
    xi: np.ndarray | None = None,
) -> list[str]:
    cmd = [str(bridge_bin), mode, str(case_dir), str(sample_idx)]
    if xi is not None:
        if xi.dtype != np.float64:
            raise TypeError(f"Expected xi dtype float64, got {xi.dtype}")
        cmd.extend(format_float64(v) for v in xi)

    env = os.environ.copy()
    env["BTN_CAPTURE_PREFIX"] = capture_prefix
    if parameters_file is not None:
        env["TLTM_PARAMETERS_FILE"] = str(parameters_file)
    proc = subprocess.run(cmd, cwd=repo_root, text=True, capture_output=True, check=False, env=env)
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    result_lines = [line for line in lines if line.startswith("OK ") or line.startswith("ERROR ")]
    if proc.returncode != 0 or not result_lines or result_lines[-1].startswith("ERROR "):
        raise BridgeError(
            "Bridge evaluation failed\n"
            f"command: {' '.join(cmd[:4])} ...\n"
            f"returncode: {proc.returncode}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )
    return result_lines[-1].split()


def bridge_seed(
    repo_root: Path,
    bridge_bin: Path,
    case_dir: Path,
    capture_prefix: str,
    parameters_file: Path | None,
    sample_idx: int,
) -> BridgeSeed:
    parts = run_bridge(repo_root, bridge_bin, case_dir, capture_prefix, parameters_file, "seed", sample_idx)
    if len(parts) < 6 or parts[1] != "seed":
        raise BridgeError(f"Unexpected seed output: {' '.join(parts)}")
    n = int(parts[3])
    xi0 = np.asarray([float(x) for x in parts[6:]], dtype=np.float64)
    if xi0.shape != (2 * n,):
        raise BridgeError(f"Seed length mismatch for sample {sample_idx}: got {xi0.shape}, expected {(2 * n,)}")
    return BridgeSeed(
        sample_idx=int(parts[2]),
        n=n,
        z_recompute_inf=float(parts[4]),
        seed_norm=float(parts[5]),
        xi0=xi0,
    )


def bridge_residual(
    repo_root: Path,
    bridge_bin: Path,
    case_dir: Path,
    capture_prefix: str,
    parameters_file: Path | None,
    sample_idx: int,
    xi: np.ndarray,
) -> BridgeResidual:
    xi = np.asarray(xi, dtype=np.float64)
    parts = run_bridge(repo_root, bridge_bin, case_dir, capture_prefix, parameters_file, "residual", sample_idx, xi)
    if len(parts) < 9 or parts[1] != "residual":
        raise BridgeError(f"Unexpected residual output: {' '.join(parts)}")
    n = int(parts[3])
    fq = np.asarray([float(x) for x in parts[9:]], dtype=np.float64)
    if fq.shape != (2 * n,):
        raise BridgeError(f"Residual length mismatch for sample {sample_idx}: got {fq.shape}, expected {(2 * n,)}")
    return BridgeResidual(
        sample_idx=int(parts[2]),
        n=n,
        z_recompute_inf=float(parts[4]),
        residual_norm=float(parts[5]),
        flow_im_norm=float(parts[6]),
        a_norm=float(parts[7]),
        jl_norm=float(parts[8]),
        fq=fq,
    )


def read_real_stream_record(path: Path, sample_idx: int) -> np.ndarray:
    with path.open("rb") as fobj:
        while True:
            head = fobj.read(8)
            if not head:
                break
            if len(head) != 8:
                raise RuntimeError(f"Truncated stream header in {path}")
            record_sample_idx, n_items = struct.unpack("<ii", head)
            if n_items < 0:
                raise RuntimeError(f"Invalid n={n_items} in {path}")
            payload = fobj.read(8 * n_items)
            if len(payload) != 8 * n_items:
                raise RuntimeError(f"Truncated stream payload in {path} for sample_idx={record_sample_idx}")
            if record_sample_idx == sample_idx:
                return np.asarray(struct.unpack("<" + "d" * n_items, payload), dtype=np.float64)
    raise KeyError(f"sample_idx={sample_idx} not found in {path}")


def resolve_seed(
    repo_root: Path,
    bridge_bin: Path,
    case_dir: Path,
    capture_prefix: str,
    parameters_file: Path | None,
    seed_source: str,
    sample_idx: int,
) -> BridgeSeed:
    bridge = bridge_seed(repo_root, bridge_bin, case_dir, capture_prefix, parameters_file, sample_idx)
    xi0_path = case_dir / f"{capture_prefix}_xi0.dat"
    use_capture = seed_source == "capture" or (seed_source == "auto" and xi0_path.exists())
    if not use_capture:
        return bridge
    xi0 = read_real_stream_record(xi0_path, sample_idx)
    if xi0.shape != (2 * bridge.n,):
        raise BridgeError(f"Captured xi0 length mismatch for sample {sample_idx}: got {xi0.shape}, expected {(2 * bridge.n,)}")
    return BridgeSeed(
        sample_idx=bridge.sample_idx,
        n=bridge.n,
        z_recompute_inf=bridge.z_recompute_inf,
        seed_norm=float(np.linalg.norm(xi0)),
        xi0=xi0,
    )


def import_dfols():
    try:
        import dfols  # type: ignore[import-not-found]
    except ImportError as exc:
        raise SystemExit(
            "Missing official DFO-LS package. Install in an isolated environment, e.g.\n"
            "  python3 -m venv .venv-dfols\n"
            "  .venv-dfols/bin/python -m pip install DFO-LS\n"
            "  .venv-dfols/bin/python scripts/run_external_dfols_btn_compare.py ..."
        ) from exc
    return dfols


def solution_objective(soln) -> np.float64:
    if hasattr(soln, "obj"):
        return np.float64(soln.obj)
    return np.dot(np.asarray(soln.resid, dtype=np.float64), np.asarray(soln.resid, dtype=np.float64))


def write_rows(path: Path, rows: Iterable[dict[str, object]]) -> None:
    fieldnames = [
        "sample_idx",
        "n",
        "dfols_version",
        "dfols_flag",
        "dfols_message",
        "dfols_nf",
        "dfols_nx",
        "dfols_nruns",
        "initial_residual_norm",
        "final_residual_norm",
        "residual_success",
        "final_objective",
        "final_flow_im_norm",
        "final_a_norm",
        "final_jl_norm",
        "z_recompute_inf",
        "xi0_norm",
        "solution_norm",
        "float64_contract",
        "error",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fobj:
        writer = csv.DictWriter(fobj, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    case_dir = resolve_repo_path(repo_root, args.case_dir).resolve()
    bridge_bin = resolve_repo_path(repo_root, args.bridge_bin).resolve()
    parameters_file = resolve_repo_path(repo_root, args.parameters_file).resolve() if args.parameters_file else None
    out_csv = resolve_repo_path(repo_root, args.out_csv)
    diagnostic_dir = resolve_repo_path(repo_root, args.diagnostic_dir) if args.diagnostic_dir else None

    dfols = import_dfols()
    sample_ids = select_sample_ids(case_dir, args.capture_prefix, args.sample_ids, args.max_cases)
    rows: list[dict[str, object]] = []

    for case_offset, sample_idx in enumerate(sample_ids):
        row: dict[str, object] = {
            "sample_idx": sample_idx,
            "dfols_version": getattr(dfols, "__version__", "unknown"),
            "error": "",
        }
        call_dtypes: list[np.dtype] = []
        try:
            seed = resolve_seed(
                repo_root,
                bridge_bin,
                case_dir,
                args.capture_prefix,
                parameters_file,
                args.seed_source,
                sample_idx,
            )
            initial = bridge_residual(repo_root, bridge_bin, case_dir, args.capture_prefix, parameters_file, sample_idx, seed.xi0)
            if seed.xi0.dtype != np.float64 or initial.fq.dtype != np.float64:
                raise TypeError("Bridge seed/residual dtype is not float64.")

            def objfun(x: np.ndarray) -> np.ndarray:
                if x.dtype != np.float64:
                    raise TypeError(f"DFO-LS passed non-float64 x dtype: {x.dtype}")
                call_dtypes.append(x.dtype)
                residual = bridge_residual(repo_root, bridge_bin, case_dir, args.capture_prefix, parameters_file, sample_idx, x).fq
                if residual.dtype != np.float64:
                    raise TypeError(f"Bridge returned non-float64 residual dtype: {residual.dtype}")
                return residual

            np.random.seed(args.numpy_seed + case_offset)
            solve_kwargs: dict[str, object] = {
                "maxfun": args.maxfun,
                "rhoend": np.float64(args.rhoend),
                "objfun_has_noise": args.objfun_has_noise,
                "do_logging": False,
                "print_progress": args.print_progress,
            }
            if args.npt > 0:
                solve_kwargs["npt"] = args.npt
            if args.rhobeg is not None:
                solve_kwargs["rhobeg"] = np.float64(args.rhobeg)
            user_params: dict[str, object] = parse_dfols_params(args.dfols_param)
            if args.model_abs_tol is not None:
                user_params["model.abs_tol"] = np.float64(args.model_abs_tol)
            if args.model_rel_tol is not None:
                user_params["model.rel_tol"] = np.float64(args.model_rel_tol)
            if user_params:
                solve_kwargs["user_params"] = user_params

            soln = dfols.solve(objfun, seed.xi0, **solve_kwargs)
            solution = np.asarray(soln.x, dtype=np.float64)
            final = bridge_residual(repo_root, bridge_bin, case_dir, args.capture_prefix, parameters_file, sample_idx, solution)
            float64_contract = (
                seed.xi0.dtype == np.float64
                and all(dtype == np.float64 for dtype in call_dtypes)
                and np.asarray(soln.x).dtype == np.float64
                and np.asarray(soln.resid).dtype == np.float64
                and np.asarray(soln.jacobian).dtype == np.float64
                and final.fq.dtype == np.float64
            )

            if diagnostic_dir is not None and hasattr(soln, "diagnostic_info"):
                diagnostic_dir.mkdir(parents=True, exist_ok=True)
                diag = soln.diagnostic_info
                if diag is not None and hasattr(diag, "to_csv"):
                    diag.to_csv(diagnostic_dir / f"sample_{sample_idx:06d}_dfols_diagnostic.csv", index=False)

            row.update(
                {
                    "n": seed.n,
                    "dfols_flag": int(soln.flag),
                    "dfols_message": str(soln.msg),
                    "dfols_nf": int(soln.nf),
                    "dfols_nx": int(soln.nx),
                    "dfols_nruns": int(soln.nruns),
                    "initial_residual_norm": format_float64(initial.residual_norm),
                    "final_residual_norm": format_float64(final.residual_norm),
                    "residual_success": int(final.residual_norm <= args.residual_success_tol),
                    "final_objective": format_float64(solution_objective(soln)),
                    "final_flow_im_norm": format_float64(final.flow_im_norm),
                    "final_a_norm": format_float64(final.a_norm),
                    "final_jl_norm": format_float64(final.jl_norm),
                    "z_recompute_inf": format_float64(max(seed.z_recompute_inf, initial.z_recompute_inf, final.z_recompute_inf)),
                    "xi0_norm": format_float64(seed.seed_norm),
                    "solution_norm": format_float64(np.linalg.norm(solution)),
                    "float64_contract": int(float64_contract),
                }
            )
        except Exception as exc:  # Keep batch comparisons inspectable case-by-case.
            row.update(
                {
                    "n": "",
                    "dfols_flag": "",
                    "dfols_message": "",
                    "dfols_nf": "",
                    "dfols_nx": "",
                    "dfols_nruns": "",
                    "initial_residual_norm": "",
                    "final_residual_norm": "",
                    "residual_success": 0,
                    "final_objective": "",
                    "final_flow_im_norm": "",
                    "final_a_norm": "",
                    "final_jl_norm": "",
                    "z_recompute_inf": "",
                    "xi0_norm": "",
                    "solution_norm": "",
                    "float64_contract": 0,
                    "error": repr(exc),
                }
            )
        rows.append(row)

    write_rows(out_csv, rows)
    print(f"[DONE] wrote {len(rows)} row(s) to {out_csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
