#!/usr/bin/env python3
"""Run multiple generate_markov_chain processes and auto-terminate on targets.

Each chain runs in an isolated working directory with its own parameters.dat and
output files. The wrapper periodically inspects stream file sizes to estimate
sample counts and stops all running chains once stop criteria are met.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class ChainRuntime:
    chain_id: int
    seed: int
    work_dir: Path
    data_dir: Path
    out_dir: Path
    log_path: Path
    param_path: Path
    process: subprocess.Popen[str]
    log_handle: Any
    last_samples: int = 0
    exit_code: int | None = None


def configure_stdio_line_buffering() -> None:
    """Ensure progress prints are flushed quickly when stdout is redirected."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if not callable(reconfigure):
            continue
        try:
            reconfigure(line_buffering=True, write_through=True)
        except TypeError:
            reconfigure(line_buffering=True)


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Launch multiple chains and auto-terminate when targets are reached."
    )
    parser.add_argument("--chains", type=int, default=4, help="Number of chains to launch.")
    parser.add_argument(
        "--bin",
        type=Path,
        default=repo_root / "bin" / "generate_markov_chain",
        help="Path to generate_markov_chain executable.",
    )
    parser.add_argument(
        "--base-parameters",
        type=Path,
        default=repo_root / "data" / "parameters.dat",
        help="Template parameters.dat to copy and patch per chain.",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=repo_root / "output" / "multichain_auto",
        help="Root directory for multichain runs.",
    )
    parser.add_argument(
        "--run-name",
        type=str,
        default="",
        help="Optional run directory name. Defaults to UTC timestamp.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Remove existing run directory if it already exists.",
    )
    parser.add_argument(
        "--seed-base",
        type=int,
        default=0,
        help="Base seed. If 0, a random base is selected.",
    )
    parser.add_argument(
        "--chain-length",
        type=int,
        default=0,
        help="Override chain_length in parameters.dat (0 keeps template value).",
    )
    parser.add_argument(
        "--quasi-fallback",
        type=str,
        choices=("auto", "on", "off"),
        default="auto",
        help="Override enable_quasi_fallback in parameters.dat (auto keeps template value).",
    )
    parser.add_argument(
        "--target-samples-per-chain",
        type=int,
        default=0,
        help="Terminate when every chain reaches this sample count (<=0 disables).",
    )
    parser.add_argument(
        "--target-total-samples",
        type=int,
        default=0,
        help="Terminate when total samples across chains reaches this count (<=0 disables).",
    )
    parser.add_argument(
        "--max-wall-seconds",
        type=int,
        default=0,
        help="Hard wall-clock limit in seconds (<=0 disables).",
    )
    parser.add_argument(
        "--check-interval",
        type=float,
        default=5.0,
        help="Polling interval in seconds.",
    )
    parser.add_argument(
        "--terminate-grace-seconds",
        type=float,
        default=8.0,
        help="Grace period after SIGTERM before SIGKILL.",
    )
    parser.add_argument(
        "--stop-rhat-max",
        type=float,
        default=0.0,
        help="Terminate when split-Rhat for observable Re/Im is <= this value (<=0 disables).",
    )
    parser.add_argument(
        "--stop-ess-bulk-min",
        type=float,
        default=0.0,
        help="Terminate when ESS_bulk for observable Re/Im is >= this value (<=0 disables).",
    )
    parser.add_argument(
        "--stop-ess-tail-min",
        type=float,
        default=0.0,
        help="Terminate when ESS_tail for observable Re/Im is >= this value (<=0 disables).",
    )
    parser.add_argument(
        "--mode-diag-component",
        type=str,
        choices=("re", "im"),
        default="re",
        help="Mode diagnostic scalar component of the observable.",
    )
    parser.add_argument(
        "--mode-diag-threshold",
        type=float,
        default=0.0,
        help="Threshold for binary mode indicator (component > threshold => mode 1).",
    )
    parser.add_argument(
        "--stop-mode-occupancy-delta-max",
        type=float,
        default=0.0,
        help="Terminate when max per-chain occupancy deviation from pooled occupancy is <= this value (<=0 disables).",
    )
    parser.add_argument(
        "--stop-mode-indicator-rhat-max",
        type=float,
        default=0.0,
        help="Terminate when Rhat of mode indicator is <= this value (<=0 disables).",
    )
    parser.add_argument(
        "--stop-mode-indicator-ess-min",
        type=float,
        default=0.0,
        help="Terminate when ESS_bulk of mode indicator is >= this value (<=0 disables).",
    )
    parser.add_argument(
        "--stop-mode-crossings-min-per-chain",
        type=int,
        default=0,
        help="Terminate when each chain has at least this many mode crossings (<=0 disables).",
    )
    parser.add_argument(
        "--stop-mode-roundtrips-min-per-chain",
        type=int,
        default=0,
        help="Terminate when each chain has at least this many round trips (<=0 disables).",
    )
    parser.add_argument(
        "--diag-min-samples-per-chain",
        type=int,
        default=400,
        help="Minimum samples per chain required before convergence diagnostics are evaluated.",
    )
    parser.add_argument(
        "--diag-window-samples",
        type=int,
        default=20000,
        help="Fixed mode: use at most this many tail samples per chain for diagnostics.",
    )
    parser.add_argument(
        "--diag-window-mode",
        type=str,
        choices=("fixed", "adaptive"),
        default="fixed",
        help="Diagnostic window mode: fixed cap or adaptive growth with chain length.",
    )
    parser.add_argument(
        "--diag-window-min",
        type=int,
        default=20000,
        help="Adaptive mode: minimum tail samples per chain for diagnostics.",
    )
    parser.add_argument(
        "--diag-window-max",
        type=int,
        default=0,
        help="Adaptive mode: maximum tail samples per chain (<=0 means no cap).",
    )
    parser.add_argument(
        "--diag-window-fraction",
        type=float,
        default=1.0,
        help="Adaptive mode: use floor(fraction * min_chain_samples).",
    )
    parser.add_argument(
        "--diag-max-lag",
        type=int,
        default=512,
        help="Maximum lag for tau/ESS diagnostics.",
    )
    parser.add_argument(
        "--diag-every",
        type=int,
        default=3,
        help="Compute expensive diagnostics every N status checks.",
    )
    return parser.parse_args()


def strip_inline_comment(raw: str) -> str:
    hash_pos = raw.find("#")
    bang_pos = raw.find("!")
    cut_pos = -1
    if hash_pos >= 0 and bang_pos >= 0:
        cut_pos = min(hash_pos, bang_pos)
    elif hash_pos >= 0:
        cut_pos = hash_pos
    elif bang_pos >= 0:
        cut_pos = bang_pos
    if cut_pos >= 0:
        return raw[:cut_pos]
    return raw


def parse_kv_lines(path: Path) -> dict[str, tuple[str, str]]:
    kv: dict[str, tuple[str, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        body = strip_inline_comment(line).strip()
        if not body or "=" not in body:
            continue
        key, value = body.split("=", 1)
        key_norm = key.strip().lower()
        kv[key_norm] = (key.strip(), value.strip())
    return kv


def update_parameters_text(template_text: str, updates: dict[str, str]) -> str:
    lines = template_text.splitlines()
    applied = {k.lower(): False for k in updates}
    out_lines: list[str] = []

    for line in lines:
        body = strip_inline_comment(line)
        if "=" not in body:
            out_lines.append(line)
            continue
        key, _value = body.split("=", 1)
        key_norm = key.strip().lower()
        if key_norm in updates:
            out_lines.append(f"{key.strip()} = {updates[key_norm]}")
            applied[key_norm] = True
        else:
            out_lines.append(line)

    missing = [k for k, done in applied.items() if not done]
    if missing:
        out_lines.append("")
        out_lines.append("# Added by run_multichain_auto.py")
        for key_norm in missing:
            out_lines.append(f"{key_norm} = {updates[key_norm]}")
    out_lines.append("")
    return "\n".join(out_lines)


def parse_positive_int(kv: dict[str, tuple[str, str]], key: str) -> int:
    key_norm = key.lower()
    if key_norm not in kv:
        raise ValueError(f"Missing required key '{key}' in parameters template.")
    raw = kv[key_norm][1].strip()
    value = int(raw)
    if value <= 0:
        raise ValueError(f"Expected positive integer for '{key}', got {raw}.")
    return value


def parse_fortran_float(text: str) -> float:
    return float(text.strip().replace("D", "E").replace("d", "e"))


def parse_logical_value(text: str) -> bool:
    v = text.strip().strip("'").strip('"').lower()
    if v in (".true.", "true", "t", "yes", "y", "on", "1"):
        return True
    if v in (".false.", "false", "f", "no", "n", "off", "0"):
        return False
    raise ValueError(f"Cannot parse logical value: {text}")


def parse_fortran_complex(text: str) -> complex:
    v = text.strip()
    if v.startswith("(") and v.endswith(")") and "," in v:
        inner = v[1:-1]
        real_s, imag_s = inner.split(",", 1)
        return complex(parse_fortran_float(real_s), parse_fortran_float(imag_s))
    return complex(parse_fortran_float(v), 0.0)


def get_kv_bool(kv: dict[str, tuple[str, str]], key: str, default: bool) -> bool:
    item = kv.get(key.lower())
    if item is None:
        return default
    return parse_logical_value(item[1])


def get_kv_complex(kv: dict[str, tuple[str, str]], key: str, default: complex) -> complex:
    item = kv.get(key.lower())
    if item is None:
        return default
    return parse_fortran_complex(item[1])


def now_utc_stamp() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S")


def safe_file_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except FileNotFoundError:
        return 0


def estimate_sample_count(out_dir: Path, z_size: int) -> int:
    x_path = out_dir / "x_history.dat"
    z_path = out_dir / "z_history.dat"
    phi_path = out_dir / "phi_history.dat"

    # Stream format from Fortran writer:
    # x: real(dp) -> 8 bytes per sample
    # z: complex(dp) vector length z_size -> 16 * z_size bytes per sample
    # phi: complex(dp) -> 16 bytes per sample
    x_count = safe_file_size(x_path) // 8
    z_sample_bytes = max(1, 16 * z_size)
    z_count = safe_file_size(z_path) // z_sample_bytes
    phi_count = safe_file_size(phi_path) // 16
    return int(min(x_count, z_count, phi_count))


def terminate_processes(chains: list[ChainRuntime], grace_seconds: float) -> None:
    alive = [c for c in chains if c.process.poll() is None]
    if not alive:
        return

    for chain in alive:
        try:
            chain.process.terminate()
        except ProcessLookupError:
            pass

    deadline = time.monotonic() + max(0.0, grace_seconds)
    while time.monotonic() < deadline:
        if all(c.process.poll() is not None for c in alive):
            return
        time.sleep(0.2)

    for chain in alive:
        if chain.process.poll() is None:
            try:
                chain.process.kill()
            except ProcessLookupError:
                pass


def build_run_dir(output_root: Path, run_name: str, force: bool) -> Path:
    run_dir = output_root / (run_name if run_name else now_utc_stamp())
    if run_dir.exists():
        if not force:
            raise FileExistsError(f"Run directory already exists: {run_dir}")
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def launch_chain(
    chain_id: int,
    seed: int,
    run_dir: Path,
    exe_path: Path,
    base_template_text: str,
    chain_length_override: int,
    quasi_fallback_override: str,
) -> ChainRuntime:
    chain_name = f"chain_{chain_id:03d}"
    work_dir = run_dir / chain_name
    data_dir = work_dir / "data"
    out_dir = work_dir / "output"
    logs_dir = work_dir / "logs"
    data_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    updates = {
        "x_history_file": "./output/x_history.dat",
        "z_history_file": "./output/z_history.dat",
        "phi_history_file": "./output/phi_history.dat",
    }
    if chain_length_override > 0:
        updates["chain_length"] = str(chain_length_override)
    if quasi_fallback_override == "on":
        updates["enable_quasi_fallback"] = "true"
    elif quasi_fallback_override == "off":
        updates["enable_quasi_fallback"] = "false"
    param_text = update_parameters_text(base_template_text, updates)
    param_path = data_dir / "parameters.dat"
    param_path.write_text(param_text, encoding="utf-8")

    log_path = logs_dir / "generate_markov_chain.log"
    log_handle = log_path.open("w", encoding="utf-8")
    env = os.environ.copy()
    env["CHAIN_RNG_SEED"] = str(seed)

    proc = subprocess.Popen(
        [str(exe_path)],
        cwd=work_dir,
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )

    return ChainRuntime(
        chain_id=chain_id,
        seed=seed,
        work_dir=work_dir,
        data_dir=data_dir,
        out_dir=out_dir,
        log_path=log_path,
        param_path=param_path,
        process=proc,
        log_handle=log_handle,
    )


def compute_targets_met(
    sample_counts: list[int],
    target_per_chain: int,
    target_total: int,
) -> bool:
    if target_per_chain <= 0 and target_total <= 0:
        return False
    per_chain_ok = True
    total_ok = True
    if target_per_chain > 0:
        per_chain_ok = all(x >= target_per_chain for x in sample_counts)
    if target_total > 0:
        total_ok = sum(sample_counts) >= target_total
    return per_chain_ok and total_ok


def _require_numpy() -> Any:
    try:
        import numpy as np  # type: ignore
    except Exception as exc:  # pragma: no cover - explicit runtime guard
        raise RuntimeError("numpy is required for convergence-based stop criteria.") from exc
    return np


def _observable_from_z(z_tail: Any, tra2_mode: bool, alpha: complex, beta: complex) -> Any:
    if tra2_mode:
        return z_tail.sum(axis=1)
    # Pole-free virial identity equivalent in expectation to z*S'(z)-1.
    z_shift = z_tail - 1j * beta
    return (-1j * (z_shift * (z_tail**2 + alpha)) - 2.0).sum(axis=1)


def _load_observable_and_phi_tail(
    np: Any,
    out_dir: Path,
    z_size: int,
    n_use: int,
    tra2_mode: bool,
    alpha: complex,
    beta: complex,
) -> tuple[Any, Any] | None:
    z_path = out_dir / "z_history.dat"
    phi_path = out_dir / "phi_history.dat"
    if not z_path.exists() or not phi_path.exists():
        return None
    z_file_size = z_path.stat().st_size
    phi_file_size = phi_path.stat().st_size
    z_sample_bytes = 16 * z_size
    phi_sample_bytes = 16
    if z_sample_bytes <= 0 or z_file_size < z_sample_bytes or phi_file_size < phi_sample_bytes:
        return None
    n_z_samples = z_file_size // z_sample_bytes
    n_phi_samples = phi_file_size // phi_sample_bytes
    n_samples = min(n_z_samples, n_phi_samples)
    if n_samples < n_use:
        return None
    z_map = np.memmap(z_path, dtype=np.complex128, mode="r", shape=(n_samples, z_size))
    z_tail = np.array(z_map[n_samples - n_use : n_samples, :], dtype=np.complex128, copy=True)
    del z_map
    phi_map = np.memmap(phi_path, dtype=np.complex128, mode="r", shape=(n_samples,))
    phi_tail = np.array(phi_map[n_samples - n_use : n_samples], dtype=np.complex128, copy=True)
    del phi_map
    obs_tail = _observable_from_z(z_tail, tra2_mode, alpha, beta)
    return obs_tail, phi_tail


def _tau_ips(np: Any, values: Any, max_lag_cap: int) -> float:
    n = int(values.size)
    if n < 4 or max_lag_cap < 1:
        return 1.0
    centered = values - np.mean(values)
    gamma0 = float(np.dot(centered, centered) / n)
    if gamma0 <= np.finfo(np.float64).tiny:
        return 1.0
    max_lag = min(max_lag_cap, n - 1)
    tau = 1.0
    lag = 1
    used_any = False
    while lag <= max_lag:
        if lag == max_lag:
            gamma_l = float(np.dot(centered[:-lag], centered[lag:]) / (n - lag))
            rho_l = gamma_l / gamma0
            if rho_l > 0.0:
                tau += 2.0 * rho_l
                used_any = True
            break
        gamma_l = float(np.dot(centered[:-lag], centered[lag:]) / (n - lag))
        gamma_lp1 = float(np.dot(centered[: -(lag + 1)], centered[(lag + 1) :]) / (n - lag - 1))
        pair_sum = (gamma_l + gamma_lp1) / gamma0
        if pair_sum <= 0.0:
            break
        tau += 2.0 * pair_sum
        used_any = True
        lag += 2
    if not used_any:
        return 1.0
    return max(1.0, tau)


def _tau_ics(np: Any, values: Any, max_lag_cap: int) -> float:
    n = int(values.size)
    if n < 6 or max_lag_cap < 2:
        return 1.0
    centered = values - np.mean(values)
    gamma0 = float(np.dot(centered, centered) / n)
    if gamma0 <= np.finfo(np.float64).tiny:
        return 1.0
    max_lag = min(max_lag_cap, n - 1)
    n_pairs = max_lag // 2
    if n_pairs < 1:
        return 1.0
    pair_raw: list[float] = []
    for pair_idx in range(1, n_pairs + 1):
        lag1 = 2 * pair_idx - 1
        lag2 = 2 * pair_idx
        gamma1 = float(np.dot(centered[:-lag1], centered[lag1:]) / (n - lag1))
        gamma2 = float(np.dot(centered[:-lag2], centered[lag2:]) / (n - lag2))
        val = (gamma1 + gamma2) / gamma0
        if val <= 0.0:
            break
        pair_raw.append(val)
    if not pair_raw:
        return 1.0
    pair_ics = pair_raw[:]
    for i in range(1, len(pair_ics)):
        pair_ics[i] = max(0.0, min(pair_ics[i - 1], pair_ics[i]))
    if len(pair_ics) >= 3:
        slopes = [pair_ics[i + 1] - pair_ics[i] for i in range(len(pair_ics) - 1)]
        for i in range(1, len(slopes)):
            slopes[i] = max(slopes[i], slopes[i - 1])
        for i in range(len(slopes)):
            slopes[i] = min(0.0, slopes[i])
        for i in range(1, len(pair_ics)):
            pair_ics[i] = pair_ics[i - 1] + slopes[i - 1]
            if pair_ics[i] > pair_ics[i - 1]:
                pair_ics[i] = pair_ics[i - 1]
            if pair_ics[i] < 0.0:
                pair_ics[i] = 0.0
    n_use = 0
    for i, val in enumerate(pair_ics):
        if val <= 0.0:
            break
        n_use = i + 1
    if n_use < 1:
        return 1.0
    tau = 1.0 + 2.0 * sum(pair_ics[:n_use])
    return max(1.0, tau)


def _tau_obm(np: Any, values: Any, max_lag_cap: int) -> float:
    n = int(values.size)
    if n < 16:
        return 1.0
    centered = values - np.mean(values)
    var0 = float(np.dot(centered, centered) / n)
    if var0 <= np.finfo(np.float64).tiny:
        return 1.0
    prefix = np.concatenate(([0.0], np.cumsum(centered)))
    max_block = min(n // 32, max(2, 8 * max_lag_cap))
    if max_block < 2:
        max_block = max(2, n // 8)
    b_center = min(max_block, max(4, max_lag_cap))
    cands = [max(2, b_center // 2), b_center, min(max_block, 2 * b_center)]
    uniq: list[int] = []
    for b in cands:
        if b >= 2 and b not in uniq:
            uniq.append(b)
    tau_cands: list[float] = []
    for b in uniq:
        n_windows = n - b + 1
        if n_windows < 32:
            continue
        # overlapping batch means using prefix sums
        means = (prefix[b:] - prefix[:-b]) / b
        sum_sq = float(np.dot(means, means))
        denom = max(np.finfo(np.float64).tiny, float(n_windows * max(1, n_windows - 1)))
        sigma2 = float(n * b) * sum_sq / denom
        tau = sigma2 / max(var0, np.finfo(np.float64).tiny)
        if tau >= 1.0 and math.isfinite(tau):
            tau_cands.append(tau)
    if not tau_cands:
        return 1.0
    tau_cands.sort()
    tau_mid = tau_cands[len(tau_cands) // 2]
    return max(1.0, min(0.5 * n, tau_mid))


def _tau_robust(np: Any, values: Any, max_lag_cap: int) -> float:
    return max(_tau_ips(np, values, max_lag_cap), _tau_ics(np, values, max_lag_cap), _tau_obm(np, values, max_lag_cap))


def _rhat_basic(np: Any, matrix: Any) -> float:
    # matrix shape: [n_chain, n_draw]
    n_chain, n_draw = int(matrix.shape[0]), int(matrix.shape[1])
    if n_chain < 2 or n_draw < 2:
        return float("inf")
    chain_means = np.mean(matrix, axis=1)
    chain_vars = np.var(matrix, axis=1, ddof=1)
    w = float(np.mean(chain_vars))
    if w <= np.finfo(np.float64).tiny:
        return 1.0
    b = float(n_draw * np.var(chain_means, ddof=1))
    var_hat = ((n_draw - 1) / n_draw) * w + b / n_draw
    if var_hat <= 0.0:
        return 1.0
    return float(math.sqrt(max(1.0, var_hat / w)))


def _split_chain_matrix(np: Any, matrix: Any) -> Any | None:
    # Split each chain in half along draw axis; drop one draw if odd length.
    n_chain, n_draw = int(matrix.shape[0]), int(matrix.shape[1])
    n_even = n_draw - (n_draw % 2)
    n_half = n_even // 2
    if n_chain < 1 or n_half < 2:
        return None
    first_half = matrix[:, :n_half]
    second_half = matrix[:, n_half:n_even]
    return np.vstack((first_half, second_half))


def _rank_normalize_matrix(np: Any, matrix: Any) -> Any:
    # Rank-normalization using Blom offset, then inverse normal CDF.
    flat = np.asarray(matrix, dtype=np.float64).reshape(-1)
    n = int(flat.size)
    if n < 2:
        return np.array(matrix, dtype=np.float64, copy=True)

    order = np.argsort(flat, kind="mergesort")
    ranks = np.empty(n, dtype=np.float64)
    sorted_vals = flat[order]
    start = 0
    while start < n:
        end = start
        while end + 1 < n and sorted_vals[end + 1] == sorted_vals[start]:
            end += 1
        avg_rank = 0.5 * (start + end) + 1.0
        ranks[order[start : end + 1]] = avg_rank
        start = end + 1

    p = (ranks - 0.375) / (n + 0.25)
    eps = np.finfo(np.float64).tiny
    p = np.clip(p, eps, 1.0 - eps)
    inv_cdf = np.frompyfunc(statistics.NormalDist().inv_cdf, 1, 1)
    z = np.array(inv_cdf(p), dtype=np.float64)
    return z.reshape(matrix.shape)


def _split_rhat(np: Any, matrix: Any) -> float:
    # Modern rank-normalized split-Rhat with folded variant (Vehtari et al., 2021).
    split_matrix = _split_chain_matrix(np, matrix)
    if split_matrix is None:
        return float("inf")

    z_split = _rank_normalize_matrix(np, split_matrix)
    rhat_rank = _rhat_basic(np, z_split)

    center = float(np.median(split_matrix.reshape(-1)))
    folded = np.abs(split_matrix - center)
    z_folded = _rank_normalize_matrix(np, folded)
    rhat_folded = _rhat_basic(np, z_folded)
    return float(max(rhat_rank, rhat_folded))


def _ess_bulk(np: Any, matrix: Any, max_lag_cap: int) -> float:
    # Conservative aggregation: total draws / max per-chain tau.
    n_chain, n_draw = int(matrix.shape[0]), int(matrix.shape[1])
    if n_chain < 1 or n_draw < 2:
        return 1.0
    taus = [_tau_robust(np, matrix[i, :], max_lag_cap) for i in range(n_chain)]
    tau_use = max(1.0, max(taus))
    ess = (n_chain * n_draw) / tau_use
    return float(max(1.0, min(n_chain * n_draw, ess)))


def _ess_tail(np: Any, matrix: Any, max_lag_cap: int) -> float:
    n_chain, n_draw = int(matrix.shape[0]), int(matrix.shape[1])
    if n_chain < 1 or n_draw < 4:
        return 1.0
    flat = matrix.reshape(-1)
    q_low = float(np.quantile(flat, 0.05))
    q_high = float(np.quantile(flat, 0.95))
    taus_low: list[float] = []
    taus_high: list[float] = []
    for i in range(n_chain):
        chain = matrix[i, :]
        low = np.where(chain <= q_low, 1.0, 0.0)
        high = np.where(chain >= q_high, 1.0, 0.0)
        taus_low.append(_tau_robust(np, low, max_lag_cap))
        taus_high.append(_tau_robust(np, high, max_lag_cap))
    tau_low = max(1.0, max(taus_low))
    tau_high = max(1.0, max(taus_high))
    n_total = n_chain * n_draw
    ess_low = n_total / tau_low
    ess_high = n_total / tau_high
    ess = min(ess_low, ess_high)
    return float(max(1.0, min(n_total, ess)))


def _mcse_mean(np: Any, matrix: Any, ess_bulk: float) -> float:
    flat = matrix.reshape(-1)
    if flat.size < 2:
        return 0.0
    var = float(np.var(flat, ddof=1))
    if var <= np.finfo(np.float64).tiny:
        return 0.0
    return float(math.sqrt(var / max(1.0, ess_bulk)))


def _build_mode_metrics(np: Any, matrix: Any, max_lag_cap: int) -> dict[str, float]:
    # matrix shape: [n_chain, n_draw], values in {0,1}
    n_chain, n_draw = int(matrix.shape[0]), int(matrix.shape[1])
    if n_chain < 1 or n_draw < 2:
        return {
            "mode_occ_mean": 0.0,
            "mode_occ_min": 0.0,
            "mode_occ_max": 0.0,
            "mode_occ_delta_max": float("inf"),
            "mode_ind_rhat": float("inf"),
            "mode_ind_ess": 1.0,
            "mode_crossings_total": 0.0,
            "mode_crossings_min": 0.0,
            "mode_roundtrips_total": 0.0,
            "mode_roundtrips_min": 0.0,
        }

    occ = np.mean(matrix, axis=1)
    occ_mean = float(np.mean(occ))
    occ_min = float(np.min(occ))
    occ_max = float(np.max(occ))
    occ_delta_max = float(np.max(np.abs(occ - occ_mean)))

    crossings = np.sum(matrix[:, 1:] != matrix[:, :-1], axis=1).astype(np.float64)
    roundtrips = np.floor(crossings / 2.0)
    mode_rhat = _split_rhat(np, matrix)
    mode_ess = _ess_bulk(np, matrix, max_lag_cap)

    return {
        "mode_occ_mean": occ_mean,
        "mode_occ_min": occ_min,
        "mode_occ_max": occ_max,
        "mode_occ_delta_max": occ_delta_max,
        "mode_ind_rhat": float(mode_rhat),
        "mode_ind_ess": float(mode_ess),
        "mode_crossings_total": float(np.sum(crossings)),
        "mode_crossings_min": float(np.min(crossings)),
        "mode_roundtrips_total": float(np.sum(roundtrips)),
        "mode_roundtrips_min": float(np.min(roundtrips)),
    }


def resolve_diag_window_n_use(
    sample_counts: list[int],
    mode: str,
    fixed_window: int,
    window_min: int,
    window_max: int,
    window_fraction: float,
) -> int:
    if not sample_counts:
        return 0
    min_samples = min(sample_counts)
    if min_samples < 1:
        return 0
    if mode == "fixed":
        return min(min_samples, max(2, fixed_window))

    target = int(math.floor(window_fraction * min_samples))
    target = max(2, max(window_min, target))
    if window_max > 0:
        target = min(target, window_max)
    return min(min_samples, target)


def compute_convergence_metrics(
    chains: list[ChainRuntime],
    sample_counts: list[int],
    z_size: int,
    tra2_mode: bool,
    alpha: complex,
    beta: complex,
    mode_component: str,
    mode_threshold: float,
    diag_window_mode: str,
    diag_window_samples: int,
    diag_window_min: int,
    diag_window_max: int,
    diag_window_fraction: float,
    diag_min_samples_per_chain: int,
    diag_max_lag: int,
) -> dict[str, float] | None:
    if not chains:
        return None
    min_samples = min(sample_counts)
    if min_samples < max(2, diag_min_samples_per_chain):
        return None
    n_use = resolve_diag_window_n_use(
        sample_counts=sample_counts,
        mode=diag_window_mode,
        fixed_window=diag_window_samples,
        window_min=diag_window_min,
        window_max=diag_window_max,
        window_fraction=diag_window_fraction,
    )
    if n_use < 4:
        return None

    np = _require_numpy()
    obs_list: list[Any] = []
    phi_list: list[Any] = []
    for chain in chains:
        loaded = _load_observable_and_phi_tail(np, chain.out_dir, z_size, n_use, tra2_mode, alpha, beta)
        if loaded is None:
            return None
        obs_tail, phi_tail = loaded
        if int(obs_tail.size) < n_use or int(phi_tail.size) < n_use:
            return None
        obs_list.append(obs_tail)
        phi_list.append(phi_tail)

    obs_matrix = np.vstack(obs_list)
    phi_matrix = np.vstack(phi_list)
    phi_sum = np.sum(phi_matrix)
    phi_abs_sum = float(np.sum(np.abs(phi_matrix)))
    phi_tol = max(np.finfo(np.float64).tiny, 1e-12 * phi_abs_sum)
    if abs(phi_sum) <= phi_tol:
        return None

    weighted_obs_matrix = (obs_matrix * phi_matrix) / phi_sum
    re_matrix = np.real(weighted_obs_matrix)
    im_matrix = np.imag(weighted_obs_matrix)
    if mode_component == "im":
        mode_scalar = im_matrix
    else:
        mode_scalar = re_matrix
    mode_indicator = np.where(mode_scalar > mode_threshold, 1.0, 0.0)

    ess_bulk_re = _ess_bulk(np, re_matrix, diag_max_lag)
    ess_bulk_im = _ess_bulk(np, im_matrix, diag_max_lag)
    ess_tail_re = _ess_tail(np, re_matrix, diag_max_lag)
    ess_tail_im = _ess_tail(np, im_matrix, diag_max_lag)
    mode_metrics = _build_mode_metrics(np, mode_indicator, diag_max_lag)
    out = {
        "n_use": float(n_use),
        "rhat_re": _split_rhat(np, re_matrix),
        "rhat_im": _split_rhat(np, im_matrix),
        "ess_bulk_re": ess_bulk_re,
        "ess_bulk_im": ess_bulk_im,
        "ess_tail_re": ess_tail_re,
        "ess_tail_im": ess_tail_im,
        "mcse_mean_re": _mcse_mean(np, re_matrix, ess_bulk_re),
        "mcse_mean_im": _mcse_mean(np, im_matrix, ess_bulk_im),
        "mode_threshold": float(mode_threshold),
        "phi_sum_abs": float(abs(phi_sum)),
    }
    out.update(mode_metrics)
    return out


def diagnostics_targets_enabled(args: argparse.Namespace) -> bool:
    return args.stop_rhat_max > 0.0 or args.stop_ess_bulk_min > 0.0 or args.stop_ess_tail_min > 0.0


def diagnostics_targets_met(metrics: dict[str, float] | None, args: argparse.Namespace) -> bool:
    if metrics is None:
        return False
    ok = True
    if args.stop_rhat_max > 0.0:
        ok = ok and metrics["rhat_re"] <= args.stop_rhat_max and metrics["rhat_im"] <= args.stop_rhat_max
    if args.stop_ess_bulk_min > 0.0:
        ok = ok and metrics["ess_bulk_re"] >= args.stop_ess_bulk_min and metrics["ess_bulk_im"] >= args.stop_ess_bulk_min
    if args.stop_ess_tail_min > 0.0:
        ok = ok and metrics["ess_tail_re"] >= args.stop_ess_tail_min and metrics["ess_tail_im"] >= args.stop_ess_tail_min
    return ok


def mode_targets_enabled(args: argparse.Namespace) -> bool:
    return (
        args.stop_mode_occupancy_delta_max > 0.0
        or args.stop_mode_indicator_rhat_max > 0.0
        or args.stop_mode_indicator_ess_min > 0.0
        or args.stop_mode_crossings_min_per_chain > 0
        or args.stop_mode_roundtrips_min_per_chain > 0
    )


def mode_targets_met(metrics: dict[str, float] | None, args: argparse.Namespace) -> bool:
    if metrics is None:
        return False
    ok = True
    if args.stop_mode_occupancy_delta_max > 0.0:
        ok = ok and metrics["mode_occ_delta_max"] <= args.stop_mode_occupancy_delta_max
    if args.stop_mode_indicator_rhat_max > 0.0:
        ok = ok and metrics["mode_ind_rhat"] <= args.stop_mode_indicator_rhat_max
    if args.stop_mode_indicator_ess_min > 0.0:
        ok = ok and metrics["mode_ind_ess"] >= args.stop_mode_indicator_ess_min
    if args.stop_mode_crossings_min_per_chain > 0:
        ok = ok and metrics["mode_crossings_min"] >= float(args.stop_mode_crossings_min_per_chain)
    if args.stop_mode_roundtrips_min_per_chain > 0:
        ok = ok and metrics["mode_roundtrips_min"] >= float(args.stop_mode_roundtrips_min_per_chain)
    return ok


def any_diagnostics_targets_enabled(args: argparse.Namespace) -> bool:
    return diagnostics_targets_enabled(args) or mode_targets_enabled(args)


def main() -> int:
    configure_stdio_line_buffering()
    args = parse_args()

    if args.chains < 1:
        print("[ERROR] --chains must be >= 1", file=sys.stderr)
        return 2
    if args.check_interval <= 0.0:
        print("[ERROR] --check-interval must be > 0", file=sys.stderr)
        return 2
    if args.diag_every < 1:
        print("[ERROR] --diag-every must be >= 1", file=sys.stderr)
        return 2
    if args.diag_window_mode not in ("fixed", "adaptive"):
        print("[ERROR] --diag-window-mode must be one of: fixed, adaptive", file=sys.stderr)
        return 2
    if args.diag_window_samples < 2:
        print("[ERROR] --diag-window-samples must be >= 2", file=sys.stderr)
        return 2
    if args.diag_window_min < 2:
        print("[ERROR] --diag-window-min must be >= 2", file=sys.stderr)
        return 2
    if args.diag_window_max > 0 and args.diag_window_max < args.diag_window_min:
        print("[ERROR] --diag-window-max must be >= --diag-window-min (or <=0 for no cap).", file=sys.stderr)
        return 2
    if args.diag_window_fraction <= 0.0:
        print("[ERROR] --diag-window-fraction must be > 0.", file=sys.stderr)
        return 2
    if args.diag_min_samples_per_chain < 2:
        print("[ERROR] --diag-min-samples-per-chain must be >= 2", file=sys.stderr)
        return 2
    if args.diag_max_lag < 1:
        print("[ERROR] --diag-max-lag must be >= 1", file=sys.stderr)
        return 2
    if args.stop_mode_crossings_min_per_chain < 0 or args.stop_mode_roundtrips_min_per_chain < 0:
        print("[ERROR] mode crossing/roundtrip thresholds must be >= 0.", file=sys.stderr)
        return 2
    if (
        args.target_samples_per_chain <= 0
        and args.target_total_samples <= 0
        and args.max_wall_seconds <= 0
        and not any_diagnostics_targets_enabled(args)
    ):
        print(
            "[ERROR] At least one stop condition is required: "
            "--target-samples-per-chain, --target-total-samples, --max-wall-seconds, "
            "or convergence thresholds (--stop-rhat-max/--stop-ess-bulk-min/--stop-ess-tail-min "
            "and/or mode thresholds).",
            file=sys.stderr,
        )
        return 2

    exe_path = args.bin.resolve()
    base_params = args.base_parameters.resolve()
    output_root = args.output_root.resolve()

    if not exe_path.exists():
        print(f"[ERROR] Missing executable: {exe_path}", file=sys.stderr)
        return 2
    if not os.access(exe_path, os.X_OK):
        print(f"[ERROR] Executable is not runnable: {exe_path}", file=sys.stderr)
        return 2
    if not base_params.exists():
        print(f"[ERROR] Missing base parameters file: {base_params}", file=sys.stderr)
        return 2

    template_text = base_params.read_text(encoding="utf-8")
    kv = parse_kv_lines(base_params)
    try:
        x_size = parse_positive_int(kv, "x_size")
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2
    z_size = x_size - 1
    if z_size < 1:
        print(f"[ERROR] Invalid x_size={x_size}; expected >= 2.", file=sys.stderr)
        return 2
    try:
        tra2_mode = get_kv_bool(kv, "tra2", False)
        alpha = get_kv_complex(kv, "alpha", complex(0.0, 0.0))
        beta = get_kv_complex(kv, "beta", complex(0.0, 0.0))
    except Exception as exc:
        print(f"[ERROR] Failed to parse observable config from parameters: {exc}", file=sys.stderr)
        return 2
    observable_name = "tra2" if tra2_mode else "virial"
    diagnostics_observable = f"weighted_{observable_name}"

    run_dir = build_run_dir(output_root, args.run_name, args.force)
    seed_base = args.seed_base if args.seed_base != 0 else random.SystemRandom().randint(1, 2_000_000_000)
    seed_step = 104_729
    seeds = [seed_base + i * seed_step for i in range(args.chains)]

    manifest = {
        "created_utc": datetime.now(tz=timezone.utc).isoformat(),
        "run_dir": str(run_dir),
        "executable": str(exe_path),
        "base_parameters": str(base_params),
        "chains": args.chains,
        "x_size": x_size,
        "z_size": z_size,
        "targets": {
            "target_samples_per_chain": args.target_samples_per_chain,
            "target_total_samples": args.target_total_samples,
            "max_wall_seconds": args.max_wall_seconds,
            "stop_rhat_max": args.stop_rhat_max,
            "stop_ess_bulk_min": args.stop_ess_bulk_min,
            "stop_ess_tail_min": args.stop_ess_tail_min,
            "stop_mode_occupancy_delta_max": args.stop_mode_occupancy_delta_max,
            "stop_mode_indicator_rhat_max": args.stop_mode_indicator_rhat_max,
            "stop_mode_indicator_ess_min": args.stop_mode_indicator_ess_min,
            "stop_mode_crossings_min_per_chain": args.stop_mode_crossings_min_per_chain,
            "stop_mode_roundtrips_min_per_chain": args.stop_mode_roundtrips_min_per_chain,
        },
        "check_interval_seconds": args.check_interval,
        "diag_every_checks": args.diag_every,
        "diag_window_mode": args.diag_window_mode,
        "diag_window_samples": args.diag_window_samples,
        "diag_window_min": args.diag_window_min,
        "diag_window_max": args.diag_window_max,
        "diag_window_fraction": args.diag_window_fraction,
        "diag_min_samples_per_chain": args.diag_min_samples_per_chain,
        "diag_max_lag": args.diag_max_lag,
        "mode_diag_component": args.mode_diag_component,
        "mode_diag_threshold": args.mode_diag_threshold,
        "terminate_grace_seconds": args.terminate_grace_seconds,
        "seed_base": seed_base,
        "seed_step": seed_step,
        "seed_list": seeds,
        "chain_length_override": args.chain_length,
        "quasi_fallback_override": args.quasi_fallback,
        "diagnostics_observable": diagnostics_observable,
        "alpha": [alpha.real, alpha.imag],
        "beta": [beta.real, beta.imag],
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"[INIT] run_dir={run_dir}")
    print(f"[INIT] chains={args.chains} x_size={x_size} z_size={z_size}")
    print(f"[INIT] seed_base={seed_base} step={seed_step}")
    print(f"[INIT] diagnostics_observable={diagnostics_observable}")
    print(f"[INIT] quasi_fallback={args.quasi_fallback}")
    print("[INIT] diagnostics_basis=weighted sample=(observable*phi)/sum(phi)_all_chains")
    print(
        "[INIT] targets: per_chain="
        f"{args.target_samples_per_chain} total={args.target_total_samples} max_wall={args.max_wall_seconds}s "
        f"rhat<={args.stop_rhat_max} ess_bulk>={args.stop_ess_bulk_min} ess_tail>={args.stop_ess_tail_min} "
        f"mode_occ_delta<={args.stop_mode_occupancy_delta_max} mode_rhat<={args.stop_mode_indicator_rhat_max} "
        f"mode_ess>={args.stop_mode_indicator_ess_min} mode_cross>={args.stop_mode_crossings_min_per_chain} "
        f"mode_round>= {args.stop_mode_roundtrips_min_per_chain}"
    )
    print(
        f"[INIT] diag_window mode={args.diag_window_mode} fixed={args.diag_window_samples} "
        f"min={args.diag_window_min} max={args.diag_window_max} frac={args.diag_window_fraction}"
    )
    print(f"[INIT] mode_diag component={args.mode_diag_component} threshold={args.mode_diag_threshold}")

    chains: list[ChainRuntime] = []
    for i in range(args.chains):
        chain = launch_chain(
            chain_id=i + 1,
            seed=seeds[i],
            run_dir=run_dir,
            exe_path=exe_path,
            base_template_text=template_text,
            chain_length_override=args.chain_length,
            quasi_fallback_override=args.quasi_fallback,
        )
        chains.append(chain)
        print(
            f"[CHAIN] launched id={chain.chain_id:03d} pid={chain.process.pid} seed={chain.seed} "
            f"log={chain.log_path}"
        )

    reason = "unknown"
    start = time.monotonic()
    last_diag_metrics: dict[str, float] | None = None
    check_idx = 0

    try:
        while True:
            check_idx += 1
            elapsed = time.monotonic() - start
            sample_counts: list[int] = []
            for chain in chains:
                samples = estimate_sample_count(chain.out_dir, z_size)
                if samples > chain.last_samples:
                    chain.last_samples = samples
                chain.exit_code = chain.process.poll()
                sample_counts.append(samples)

            total_samples = sum(sample_counts)
            targets_met = compute_targets_met(
                sample_counts=sample_counts,
                target_per_chain=args.target_samples_per_chain,
                target_total=args.target_total_samples,
            )
            alive_count = sum(1 for c in chains if c.exit_code is None)
            min_samples = min(sample_counts) if sample_counts else 0
            max_samples = max(sample_counts) if sample_counts else 0
            print(
                f"[STATUS] t={elapsed:8.1f}s alive={alive_count}/{len(chains)} "
                f"total={total_samples} min={min_samples} max={max_samples}"
            )

            need_diag = any_diagnostics_targets_enabled(args) and (check_idx % args.diag_every == 0)
            if need_diag:
                last_diag_metrics = compute_convergence_metrics(
                    chains=chains,
                    sample_counts=sample_counts,
                    z_size=z_size,
                    tra2_mode=tra2_mode,
                    alpha=alpha,
                    beta=beta,
                    mode_component=args.mode_diag_component,
                    mode_threshold=args.mode_diag_threshold,
                    diag_window_mode=args.diag_window_mode,
                    diag_window_samples=args.diag_window_samples,
                    diag_window_min=args.diag_window_min,
                    diag_window_max=args.diag_window_max,
                    diag_window_fraction=args.diag_window_fraction,
                    diag_min_samples_per_chain=args.diag_min_samples_per_chain,
                    diag_max_lag=args.diag_max_lag,
                )
                if last_diag_metrics is None:
                    print(
                        f"[DIAG] waiting for enough data or stable weights "
                        f"(min_samples>={args.diag_min_samples_per_chain}, mode={args.diag_window_mode})"
                    )
                else:
                    print(
                        "[DIAG] n_use={n_use:.0f} "
                        "rhat=({rhat_re:.4f},{rhat_im:.4f}) "
                        "ess_bulk=({ess_bulk_re:.1f},{ess_bulk_im:.1f}) "
                        "ess_tail=({ess_tail_re:.1f},{ess_tail_im:.1f}) "
                        "mcse=({mcse_mean_re:.3e},{mcse_mean_im:.3e}) "
                        "mode_occ=({mode_occ_min:.3f},{mode_occ_mean:.3f},{mode_occ_max:.3f}) "
                        "mode_dmax={mode_occ_delta_max:.3f} mode_rhat={mode_ind_rhat:.4f} mode_ess={mode_ind_ess:.1f} "
                        "mode_cross(min,total)=({mode_crossings_min:.0f},{mode_crossings_total:.0f}) "
                        "mode_rt(min,total)=({mode_roundtrips_min:.0f},{mode_roundtrips_total:.0f}) "
                        "|sum(phi)|={phi_sum_abs:.3e}".format(**last_diag_metrics)
                    )
                    core_ok = diagnostics_targets_met(last_diag_metrics, args) if diagnostics_targets_enabled(args) else True
                    mode_ok = mode_targets_met(last_diag_metrics, args) if mode_targets_enabled(args) else True
                    if core_ok and mode_ok:
                        reason = "diagnostics_reached"
                        print("[DONE] Convergence thresholds reached. Terminating running chains.")
                        terminate_processes(chains, args.terminate_grace_seconds)
                        break

            if targets_met:
                reason = "target_reached"
                print("[DONE] Stop condition reached. Terminating running chains.")
                terminate_processes(chains, args.terminate_grace_seconds)
                break

            if args.max_wall_seconds > 0 and elapsed >= args.max_wall_seconds:
                reason = "max_wall_reached"
                print("[WARN] Max wall time reached. Terminating running chains.")
                terminate_processes(chains, args.terminate_grace_seconds)
                break

            if alive_count == 0:
                reason = "all_processes_exited"
                print("[WARN] All chain processes exited before target condition.")
                break

            time.sleep(args.check_interval)

    except KeyboardInterrupt:
        reason = "keyboard_interrupt"
        print("[WARN] Keyboard interrupt received. Terminating running chains.")
        terminate_processes(chains, args.terminate_grace_seconds)

    for chain in chains:
        try:
            chain.process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            chain.process.kill()
            chain.process.wait(timeout=1.0)
        chain.exit_code = chain.process.returncode
        chain.log_handle.close()

    elapsed = time.monotonic() - start
    final_counts = [estimate_sample_count(c.out_dir, z_size) for c in chains]
    summary = {
        "finished_utc": datetime.now(tz=timezone.utc).isoformat(),
        "reason": reason,
        "elapsed_seconds": elapsed,
        "targets": {
            "target_samples_per_chain": args.target_samples_per_chain,
            "target_total_samples": args.target_total_samples,
            "max_wall_seconds": args.max_wall_seconds,
            "stop_rhat_max": args.stop_rhat_max,
            "stop_ess_bulk_min": args.stop_ess_bulk_min,
            "stop_ess_tail_min": args.stop_ess_tail_min,
            "stop_mode_occupancy_delta_max": args.stop_mode_occupancy_delta_max,
            "stop_mode_indicator_rhat_max": args.stop_mode_indicator_rhat_max,
            "stop_mode_indicator_ess_min": args.stop_mode_indicator_ess_min,
            "stop_mode_crossings_min_per_chain": args.stop_mode_crossings_min_per_chain,
            "stop_mode_roundtrips_min_per_chain": args.stop_mode_roundtrips_min_per_chain,
        },
        "targets_met": compute_targets_met(
            sample_counts=final_counts,
            target_per_chain=args.target_samples_per_chain,
            target_total=args.target_total_samples,
        ),
        "diagnostics_observable": diagnostics_observable,
        "mode_diag_component": args.mode_diag_component,
        "mode_diag_threshold": args.mode_diag_threshold,
        "diag_metrics_last": last_diag_metrics,
        "diag_targets_met": diagnostics_targets_met(last_diag_metrics, args),
        "mode_targets_met": mode_targets_met(last_diag_metrics, args),
        "total_samples": sum(final_counts),
        "chains": [
            {
                "chain_id": c.chain_id,
                "pid": c.process.pid,
                "seed": c.seed,
                "samples": final_counts[idx],
                "exit_code": c.exit_code,
                "work_dir": str(c.work_dir),
                "log_path": str(c.log_path),
                "param_path": str(c.param_path),
            }
            for idx, c in enumerate(chains)
        ],
    }
    summary_path = run_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"[SUMMARY] reason={reason} elapsed={elapsed:.1f}s total_samples={sum(final_counts)}")
    print(f"[SUMMARY] summary_file={summary_path}")

    if reason in ("target_reached", "diagnostics_reached"):
        return 0
    if reason in ("max_wall_reached", "keyboard_interrupt"):
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
