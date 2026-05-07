#!/usr/bin/env python3
"""Plot manifold-vs-normal-line geometry for constraint-solver failures."""

from __future__ import annotations

import argparse
import csv
import math
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


@dataclass
class FailureCase:
    sample_idx: int
    z0: complex
    delz: complex
    flow_time: float
    seed_u: float


@dataclass
class CaseGeometry:
    sample_idx: int
    z0: complex
    delz: complex
    base: complex
    tangent: complex
    normal: complex
    intersections: list[complex]
    primary_intersection: complex | None
    min_line_distance: float
    nearest_u: float
    nearest_z: complex


@dataclass
class EnsembleReBands:
    min_abs_re: float
    max_abs_re: float

    def vertical_lines(self) -> list[float]:
        return [-self.max_abs_re, -self.min_abs_re, self.min_abs_re, self.max_abs_re]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Plot manifold intersections with affine normal lines "
            "z0 + delz + normal(z0)."
        )
    )
    parser.add_argument(
        "--z0-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_z0.dat"),
    )
    parser.add_argument(
        "--delz-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_delz.dat"),
    )
    parser.add_argument(
        "--x0-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_x0.dat"),
    )
    parser.add_argument(
        "--quasi-trace-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_quasi_trace.csv"),
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("output/constraint_fail_cases_100/geometry_plots"),
    )
    parser.add_argument(
        "--max-cases",
        type=int,
        default=100,
        help="Maximum number of samples to process.",
    )
    parser.add_argument(
        "--n-manifold",
        type=int,
        default=2001,
        help="Number of manifold samples per flow_time.",
    )
    parser.add_argument(
        "--seed-margin",
        type=float,
        default=2.5,
        help="Extra margin around observed seed_u range.",
    )
    parser.add_argument(
        "--proposal-count",
        type=int,
        default=3,
        help="How many points to mark; #1 is first guess, then accepted iteration points.",
    )
    parser.add_argument(
        "--jump-quantile",
        type=float,
        default=90.0,
        help="Quantile of |dz| used as local scale for discontinuity detection.",
    )
    parser.add_argument(
        "--jump-factor",
        type=float,
        default=30.0,
        help="Discard manifold segments with |dz| > jump_factor * quantile_scale.",
    )
    parser.add_argument(
        "--ensemble-z-history-file",
        type=Path,
        default=Path("output/production/z_history.dat"),
        help="Raw ensemble z-history stream used to draw ±max|Re z| and ±min|Re z| lines.",
    )
    parser.add_argument(
        "--no-plots",
        action="store_true",
        help="Compute geometry/intersection_summary only; skip all PNG rendering.",
    )
    return parser.parse_args()


def read_complex_stream(path: Path) -> dict[int, np.ndarray]:
    out: dict[int, np.ndarray] = {}
    with path.open("rb") as fobj:
        while True:
            head = fobj.read(8)
            if not head:
                break
            sample_idx, n = struct.unpack("<ii", head)
            raw = fobj.read(16 * n)
            if len(raw) != 16 * n:
                raise RuntimeError(f"Truncated complex payload in {path}")
            arr = np.frombuffer(raw, dtype="<f8").reshape(n, 2)
            out[sample_idx] = arr[:, 0] + 1j * arr[:, 1]
    return out


def read_real_stream(path: Path) -> dict[int, np.ndarray]:
    out: dict[int, np.ndarray] = {}
    with path.open("rb") as fobj:
        while True:
            head = fobj.read(8)
            if not head:
                break
            sample_idx, n = struct.unpack("<ii", head)
            raw = fobj.read(8 * n)
            if len(raw) != 8 * n:
                raise RuntimeError(f"Truncated real payload in {path}")
            out[sample_idx] = np.frombuffer(raw, dtype="<f8").copy()
    return out


def read_ensemble_reals(z_history_file: Path, z_size: int) -> np.ndarray:
    if z_size <= 0:
        raise RuntimeError(f"Invalid z_size={z_size} for ensemble parsing.")
    if not z_history_file.exists():
        raise RuntimeError(f"Ensemble z-history file not found: {z_history_file}")

    raw = np.fromfile(z_history_file, dtype="<f8")
    if raw.size == 0:
        raise RuntimeError(f"Empty ensemble z-history file: {z_history_file}")
    if raw.size % 2 != 0:
        raise RuntimeError(f"Corrupted ensemble z-history (odd float64 count): {z_history_file}")

    z_flat = raw[0::2] + 1j * raw[1::2]
    if z_flat.size % z_size != 0:
        raise RuntimeError(
            "Cannot infer sample count from ensemble z-history: "
            f"n_complex={z_flat.size} not divisible by z_size={z_size}"
        )

    z_mat = z_flat.reshape(-1, z_size)
    return np.real(z_mat).reshape(-1)


def compute_ensemble_re_bands(z_reals: np.ndarray) -> EnsembleReBands:
    finite = z_reals[np.isfinite(z_reals)]
    if finite.size == 0:
        raise RuntimeError("No finite Re(z) values in ensemble z-history.")
    abs_re = np.abs(finite)
    return EnsembleReBands(min_abs_re=float(np.min(abs_re)), max_abs_re=float(np.max(abs_re)))


def load_proposals(trace_csv: Path, max_cases: int) -> dict[int, list[complex]]:
    if not trace_csv.exists():
        return {}

    # Track first guess (smallest attempt_idx/proposal_idx) and final accepted point
    # for each quasi-Newton iteration. Plot order is:
    #   1) first guess, 2..N) accepted per iteration.
    first_guess: dict[int, tuple[int, int, complex]] = {}
    by_iter: dict[int, dict[tuple[int, int], tuple[int, complex]]] = {}
    with trace_csv.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sample_idx = int(row["sample_idx"].strip())
            if sample_idx > max_cases:
                continue
            attempt_idx = int(row["attempt_idx"].strip())
            proposal_idx = int(row["proposal_idx"].strip())
            z_prop = complex(float(row["z_prop_re"].strip()), float(row["z_prop_im"].strip()))

            old_first = first_guess.get(sample_idx)
            if old_first is None or (attempt_idx, proposal_idx) < (old_first[0], old_first[1]):
                first_guess[sample_idx] = (attempt_idx, proposal_idx, z_prop)

            if int(row["accepted"].strip()) != 1:
                continue
            iter_idx = int(row["iter_idx"].strip())
            if iter_idx <= 0:
                continue
            it_key = (attempt_idx, iter_idx)
            bucket = by_iter.setdefault(sample_idx, {})
            old = bucket.get(it_key)
            if old is None or proposal_idx > old[0]:
                bucket[it_key] = (proposal_idx, z_prop)

    out: dict[int, list[complex]] = {}
    sample_ids = sorted(set(first_guess.keys()) | set(by_iter.keys()))
    for sample_idx in sample_ids:
        points: list[complex] = []
        if sample_idx in first_guess:
            points.append(first_guess[sample_idx][2])

        iter_map = by_iter.get(sample_idx, {})
        if iter_map:
            seq = sorted(iter_map.items(), key=lambda item: (item[0][0], item[0][1]))
            for _, (_, z_acc) in seq:
                if points and abs(z_acc - points[-1]) <= 1.0e-12:
                    continue
                points.append(z_acc)
        out[sample_idx] = points
    return out


def build_cases(
    z0_map: dict[int, np.ndarray],
    delz_map: dict[int, np.ndarray],
    x0_map: dict[int, np.ndarray],
    max_cases: int,
) -> list[FailureCase]:
    sample_ids = sorted(set(z0_map) & set(delz_map) & set(x0_map))
    if not sample_ids:
        raise RuntimeError("No overlapping sample IDs across z0/delz/x0 files.")

    cases: list[FailureCase] = []
    for sample_idx in sample_ids[:max_cases]:
        z0_arr = z0_map[sample_idx]
        delz_arr = delz_map[sample_idx]
        x0_arr = x0_map[sample_idx]
        if len(z0_arr) != 1:
            raise RuntimeError(f"Sample {sample_idx}: expected len(z0)=1, got {len(z0_arr)}")
        if len(delz_arr) != 2:
            raise RuntimeError(f"Sample {sample_idx}: expected len(delz)=2, got {len(delz_arr)}")
        if len(x0_arr) != 2:
            raise RuntimeError(f"Sample {sample_idx}: expected len(x0)=2, got {len(x0_arr)}")

        cases.append(
            FailureCase(
                sample_idx=sample_idx,
                z0=complex(z0_arr[0]),
                delz=complex(delz_arr[0], delz_arr[1]),
                flow_time=float(x0_arr[0]),
                seed_u=float(x0_arr[1]),
            )
        )
    return cases


def sample_manifold(
    repo_root: Path,
    out_file: Path,
    seed_min: float,
    seed_max: float,
    n_samples: int,
    flow_time: float,
) -> tuple[np.ndarray, np.ndarray]:
    build_dir = repo_root / "build"
    bin_path = repo_root / "bin" / "sample_flow_manifold"

    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file_abs = out_file.resolve()
    cmd = [
        str(bin_path),
        str(out_file_abs),
        f"{seed_min:.16e}",
        f"{seed_max:.16e}",
        str(n_samples),
        f"{flow_time:.16e}",
        "0.0",
    ]
    proc = subprocess.run(
        cmd,
        cwd=build_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "sample_flow_manifold failed\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )

    u_vals: list[float] = []
    z_vals: list[complex] = []
    with out_file.open("r") as fobj:
        for line in fobj:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            cols = line.split()
            if len(cols) < 4:
                continue
            ok = int(cols[3])
            if ok != 1:
                continue
            u = float(cols[0])
            zr = float(cols[1])
            zi = float(cols[2])
            u_vals.append(u)
            z_vals.append(complex(zr, zi))

    if len(u_vals) < 3:
        raise RuntimeError(f"Too few valid manifold points in {out_file}")
    return np.array(u_vals), np.array(z_vals, dtype=np.complex128)


def tangent_at_seed(u_vals: np.ndarray, z_vals: np.ndarray, seed_u: float) -> tuple[complex, int]:
    idx = int(np.argmin(np.abs(u_vals - seed_u)))
    if idx <= 0:
        idx = 1
    if idx >= len(u_vals) - 1:
        idx = len(u_vals) - 2

    du = u_vals[idx + 1] - u_vals[idx - 1]
    if du == 0.0:
        du = 1.0
    tangent = (z_vals[idx + 1] - z_vals[idx - 1]) / du
    if abs(tangent) < 1e-14:
        tangent = z_vals[idx + 1] - z_vals[idx]
    return complex(tangent), idx


def nearest_seed_index(u_vals: np.ndarray, seed_u: float) -> int:
    idx = int(np.argmin(np.abs(u_vals - seed_u)))
    if idx < 0:
        idx = 0
    if idx >= len(u_vals):
        idx = len(u_vals) - 1
    return idx


def jacobian_at_point(
    repo_root: Path,
    scan_dir: Path,
    seed_u: float,
    flow_time: float,
) -> complex:
    build_dir = repo_root / "build"
    bin_path = repo_root / "bin" / "scan_flow_vs_flowz"
    out_csv = scan_dir / f"scan_t{flow_time:.12f}_u{seed_u:+.16e}.csv"
    out_csv_abs = out_csv.resolve()

    cmd = [
        str(bin_path),
        str(out_csv_abs),
        f"{seed_u:.16e}",
        f"{seed_u:.16e}",
        "2",
        f"{flow_time:.16e}",
        "0.0",
    ]
    proc = subprocess.run(
        cmd,
        cwd=build_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "scan_flow_vs_flowz failed\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )

    with out_csv_abs.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            if int(row["flow_ok"].strip()) != 1:
                continue
            return complex(float(row["j_re"]), float(row["j_im"]))

    raise RuntimeError(f"No valid flow/jacobian row in {out_csv_abs}")


def cross2(a: complex, b: complex) -> float:
    return a.real * b.imag - a.imag * b.real


def intersections_with_line(
    polyline: np.ndarray,
    base: complex,
    direction: complex,
    segment_valid: np.ndarray | None = None,
    tol: float = 1e-12,
) -> list[complex]:
    ints: list[complex] = []
    d = direction
    if abs(d) < tol:
        return ints

    for i in range(len(polyline) - 1):
        if segment_valid is not None and not bool(segment_valid[i]):
            continue
        p0 = complex(polyline[i])
        p1 = complex(polyline[i + 1])
        seg = p1 - p0
        denom = cross2(seg, d)
        if abs(denom) < tol:
            continue

        num_s = cross2(base - p0, d)
        s = num_s / denom
        if -1e-10 <= s <= 1.0 + 1e-10:
            z_int = p0 + s * seg
            ints.append(z_int)

    dedup: list[complex] = []
    for z in ints:
        if not dedup:
            dedup.append(z)
            continue
        if min(abs(z - w) for w in dedup) > 1e-6:
            dedup.append(z)
    return dedup


def min_distance_points_to_line(points: np.ndarray, base: complex, direction: complex) -> float:
    d = direction
    if abs(d) < 1e-15:
        return math.inf
    numer = np.abs([cross2(complex(z) - base, d) for z in points])
    return float(np.min(numer / abs(d)))


def line_segment_for_bbox(base: complex, direction: complex, z_vals: np.ndarray) -> tuple[complex, complex]:
    d = direction
    if abs(d) < 1e-15:
        return base, base
    x_min = float(np.min(z_vals.real))
    x_max = float(np.max(z_vals.real))
    y_min = float(np.min(z_vals.imag))
    y_max = float(np.max(z_vals.imag))
    corners = [
        complex(x_min, y_min),
        complex(x_min, y_max),
        complex(x_max, y_min),
        complex(x_max, y_max),
    ]
    d2 = abs(d) ** 2
    proj = [((c - base).real * d.real + (c - base).imag * d.imag) / d2 for c in corners]
    # Always include t=0 so the rendered segment passes through `base` (= z0 + delz).
    proj.append(0.0)
    t_min = min(proj) - 0.15 * (max(proj) - min(proj) + 1e-12)
    t_max = max(proj) + 0.15 * (max(proj) - min(proj) + 1e-12)
    return base + t_min * d, base + t_max * d


def line_segment_for_limits(
    base: complex,
    direction: complex,
    x_min: float,
    x_max: float,
    y_min: float,
    y_max: float,
    pad_frac: float = 0.12,
) -> tuple[complex, complex]:
    d = direction
    if abs(d) < 1e-15:
        return base, base

    dx = x_max - x_min
    dy = y_max - y_min
    x_pad = pad_frac * (dx + 1e-12)
    y_pad = pad_frac * (dy + 1e-12)
    x0 = x_min - x_pad
    x1 = x_max + x_pad
    y0 = y_min - y_pad
    y1 = y_max + y_pad

    corners = [
        complex(x0, y0),
        complex(x0, y1),
        complex(x1, y0),
        complex(x1, y1),
    ]
    d2 = abs(d) ** 2
    proj = [((c - base).real * d.real + (c - base).imag * d.imag) / d2 for c in corners]
    proj.append(0.0)
    t_min = min(proj)
    t_max = max(proj)
    return base + t_min * d, base + t_max * d


def draw_ensemble_vertical_lines(ax: plt.Axes, ensemble_bands: EnsembleReBands | None) -> None:
    if ensemble_bands is None:
        return
    x_lines = ensemble_bands.vertical_lines()
    x_max_abs = ensemble_bands.max_abs_re
    x_min_abs = ensemble_bands.min_abs_re
    labels = [
        "-max|Re z|",
        "-min|Re z|",
        "+min|Re z|",
        "+max|Re z|",
    ]
    for x, lbl in zip(x_lines, labels):
        is_max = abs(abs(x) - x_max_abs) <= 1e-12 * max(1.0, x_max_abs)
        is_min = abs(abs(x) - x_min_abs) <= 1e-12 * max(1.0, x_min_abs)
        color = "0.35" if is_max else "0.55"
        lw = 1.0 if is_max else 0.9
        alpha = 0.55 if is_max else 0.45
        if is_min and (x_min_abs <= 1e-12):
            color = "0.55"
            alpha = 0.35
        ax.axvline(x=x, color=color, linestyle="--", linewidth=lw, alpha=alpha, label=lbl)


def robust_limits(z_vals: np.ndarray, q_low: float = 0.5, q_high: float = 99.5) -> tuple[float, float, float, float]:
    xr = np.percentile(z_vals.real, [q_low, q_high])
    yi = np.percentile(z_vals.imag, [q_low, q_high])
    x_min, x_max = float(xr[0]), float(xr[1])
    y_min, y_max = float(yi[0]), float(yi[1])
    if x_max <= x_min:
        x_max = x_min + 1.0
    if y_max <= y_min:
        y_max = y_min + 1.0
    return x_min, x_max, y_min, y_max


def segment_valid_mask(
    z_vals: np.ndarray,
    jump_quantile: float,
    jump_factor: float,
) -> np.ndarray:
    if len(z_vals) < 2:
        return np.zeros(0, dtype=bool)

    dz = np.abs(np.diff(z_vals))
    finite = np.isfinite(dz)
    if not np.any(finite):
        return np.zeros_like(dz, dtype=bool)

    scale = float(np.percentile(dz[finite], jump_quantile))
    if (not np.isfinite(scale)) or scale <= 0.0:
        nz = dz[finite & (dz > 0.0)]
        scale = float(np.median(nz)) if len(nz) > 0 else 1.0
    threshold = max(1e-12, jump_factor * scale)
    return finite & (dz <= threshold)


def iter_polyline_chunks(z_vals: np.ndarray, segment_valid: np.ndarray | None) -> list[np.ndarray]:
    if len(z_vals) < 2:
        return []
    if segment_valid is None:
        return [z_vals]
    if len(segment_valid) != len(z_vals) - 1:
        raise RuntimeError("segment_valid length mismatch for manifold polyline.")

    chunks: list[np.ndarray] = []
    start = 0
    for i, ok in enumerate(segment_valid):
        if bool(ok):
            continue
        if i + 1 - start >= 2:
            chunks.append(z_vals[start : i + 1])
        start = i + 1
    if len(z_vals) - start >= 2:
        chunks.append(z_vals[start:])
    return chunks


def plot_polyline_with_breaks(
    ax: plt.Axes,
    z_vals: np.ndarray,
    segment_valid: np.ndarray | None,
    *,
    color: str,
    linewidth: float,
    alpha: float = 1.0,
    label: str | None = None,
) -> None:
    chunks = iter_polyline_chunks(z_vals, segment_valid)
    for i, chunk in enumerate(chunks):
        this_label = label if i == 0 else None
        ax.plot(chunk.real, chunk.imag, color=color, linewidth=linewidth, alpha=alpha, label=this_label)


def _label_offsets_points() -> list[tuple[float, float]]:
    # Candidate label locations (in points), ordered from near to far.
    offsets: list[tuple[float, float]] = [
        (10.0, 8.0),
        (10.0, -8.0),
        (-10.0, 8.0),
        (-10.0, -8.0),
        (0.0, 12.0),
        (12.0, 0.0),
        (-12.0, 0.0),
        (0.0, -12.0),
    ]
    for radius in (16.0, 22.0, 28.0, 36.0, 44.0, 54.0, 66.0):
        n_theta = max(12, int(round(2.0 * math.pi * radius / 10.0)))
        for k in range(n_theta):
            theta = 2.0 * math.pi * float(k) / float(n_theta)
            offsets.append((radius * math.cos(theta), radius * math.sin(theta)))
    return offsets


def annotate_numbered_points(
    ax: plt.Axes,
    points: list[complex],
    *,
    color: str,
    fontsize: float,
) -> None:
    if not points:
        return

    fig = ax.figure
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    ax_bbox = ax.get_window_extent(renderer=renderer)

    px_per_pt = fig.dpi / 72.0
    marker_px = [ax.transData.transform((p.real, p.imag)) for p in points]
    candidate_offsets = _label_offsets_points()

    placed_boxes: list[tuple[float, float, float, float]] = []
    chosen_offsets: list[tuple[float, float]] = []

    for i, (mx, my) in enumerate(marker_px, start=1):
        text = str(i)
        w = max(8.0, 0.62 * fontsize * float(len(text)) * px_per_pt)
        h = max(8.0, 1.25 * fontsize * px_per_pt)
        best_score = math.inf
        best_offset = candidate_offsets[0]

        for dx_pt, dy_pt in candidate_offsets:
            cx = mx + dx_pt * px_per_pt
            cy = my + dy_pt * px_per_pt
            half_w = 0.5 * w + 2.0
            half_h = 0.5 * h + 1.5

            overlap_penalty = 0.0
            for ox, oy, ow, oh in placed_boxes:
                if abs(cx - ox) < (half_w + 0.5 * ow) and abs(cy - oy) < (half_h + 0.5 * oh):
                    overlap_penalty += 1.0

            marker_penalty = 0.0
            for j, (px, py) in enumerate(marker_px):
                if j == (i - 1):
                    continue
                if abs(px - cx) < half_w and abs(py - cy) < half_h:
                    marker_penalty += 1.0

            out_penalty = 0.0
            left = cx - half_w
            right = cx + half_w
            bottom = cy - half_h
            top = cy + half_h
            if left < ax_bbox.x0:
                out_penalty += (ax_bbox.x0 - left)
            if right > ax_bbox.x1:
                out_penalty += (right - ax_bbox.x1)
            if bottom < ax_bbox.y0:
                out_penalty += (ax_bbox.y0 - bottom)
            if top > ax_bbox.y1:
                out_penalty += (top - ax_bbox.y1)

            dist_penalty = math.hypot(dx_pt, dy_pt)
            score = 5000.0 * overlap_penalty + 700.0 * marker_penalty + 2.5 * out_penalty + dist_penalty
            if score < best_score:
                best_score = score
                best_offset = (dx_pt, dy_pt)

        chosen_offsets.append(best_offset)
        bx = mx + best_offset[0] * px_per_pt
        by = my + best_offset[1] * px_per_pt
        placed_boxes.append((bx, by, w, h))

    for i, p in enumerate(points, start=1):
        dx_pt, dy_pt = chosen_offsets[i - 1]
        ax.annotate(
            str(i),
            xy=(p.real, p.imag),
            xytext=(dx_pt, dy_pt),
            textcoords="offset points",
            color=color,
            fontsize=fontsize,
            ha="center",
            va="center",
            zorder=6,
            arrowprops={
                "arrowstyle": "->",
                "color": color,
                "lw": 0.7,
                "alpha": 0.9,
                "shrinkA": 0.0,
                "shrinkB": 0.0,
            },
            bbox={
                "boxstyle": "round,pad=0.11",
                "facecolor": "white",
                "edgecolor": "none",
                "alpha": 0.72,
            },
            annotation_clip=True,
        )


def compute_case_geometry(
    case: FailureCase,
    u_vals: np.ndarray,
    z_vals: np.ndarray,
    segment_valid: np.ndarray | None = None,
    tangent_override: complex | None = None,
) -> CaseGeometry:
    idx = nearest_seed_index(u_vals, case.seed_u)
    if tangent_override is None:
        tangent, _ = tangent_at_seed(u_vals, z_vals, case.seed_u)
    else:
        tangent = tangent_override
    normal = 1j * tangent
    base = case.z0 + case.delz
    ints = intersections_with_line(z_vals, base, normal, segment_valid=segment_valid)
    primary_int = None
    if ints:
        primary_int = min(ints, key=lambda z: abs(z - base))
    min_dist = min_distance_points_to_line(z_vals, base, normal)
    return CaseGeometry(
        sample_idx=case.sample_idx,
        z0=case.z0,
        delz=case.delz,
        base=base,
        tangent=tangent,
        normal=normal,
        intersections=ints,
        primary_intersection=primary_int,
        min_line_distance=min_dist,
        nearest_u=float(u_vals[idx]),
        nearest_z=complex(z_vals[idx]),
    )


def plot_overlay(
    out_path: Path,
    z_vals: np.ndarray,
    segment_valid: np.ndarray | None,
    geoms: list[CaseGeometry],
) -> None:
    fig, ax = plt.subplots(figsize=(10, 8))
    plot_polyline_with_breaks(
        ax,
        z_vals,
        segment_valid,
        color="tab:blue",
        linewidth=1.6,
        label="flowed manifold",
    )
    x_min, x_max, y_min, y_max = robust_limits(z_vals)

    all_ints: list[complex] = []
    for geom in geoms:
        p0, p1 = line_segment_for_limits(geom.base, geom.normal, x_min, x_max, y_min, y_max)
        ax.plot(
            [p0.real, p1.real],
            [p0.imag, p1.imag],
            color="tab:orange",
            alpha=0.22,
            linewidth=0.9,
        )
        all_ints.extend(geom.intersections)

    if all_ints:
        ax.scatter(
            [z.real for z in all_ints],
            [z.imag for z in all_ints],
            s=10,
            color="tab:red",
            alpha=0.65,
            label="detected intersections",
        )

    ax.set_xlabel("Re(z)")
    ax.set_ylabel("Im(z)")
    ax.set_title("Overlay: Flowed Manifold and Affine Normal Lines (100 Failure Cases)")
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_min, y_max)
    ax.grid(True, alpha=0.2)
    ax.set_aspect("equal", adjustable="box")
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def plot_case_grid(
    out_path: Path,
    z_vals: np.ndarray,
    segment_valid: np.ndarray | None,
    geoms: list[CaseGeometry],
    proposal_map: dict[int, list[complex]],
    proposal_count: int,
    ensemble_bands: EnsembleReBands | None = None,
    ncols: int = 10,
) -> None:
    n_cases = len(geoms)
    nrows = max(1, math.ceil(n_cases / ncols))
    fig, axes = plt.subplots(nrows=nrows, ncols=ncols, figsize=(2.8 * ncols, 2.5 * nrows))
    axes_flat = list(axes.flat) if hasattr(axes, "flat") else [axes]

    for i, geom in enumerate(geoms):
        ax = axes_flat[i]
        plot_polyline_with_breaks(
            ax,
            z_vals,
            segment_valid,
            color="tab:blue",
            linewidth=0.8,
            alpha=0.9,
        )

        x_pts = [geom.nearest_z.real, geom.base.real]
        y_pts = [geom.nearest_z.imag, geom.base.imag]
        if geom.intersections:
            x_pts.extend([z.real for z in geom.intersections])
            y_pts.extend([z.imag for z in geom.intersections])
        dx = max(x_pts) - min(x_pts)
        dy = max(y_pts) - min(y_pts)
        pad_x = max(0.08, 0.35 * dx + 0.08)
        pad_y = max(0.08, 0.35 * dy + 0.08)
        x_min = min(x_pts) - pad_x
        x_max = max(x_pts) + pad_x
        y_min = min(y_pts) - pad_y
        y_max = max(y_pts) + pad_y

        p0, p1 = line_segment_for_limits(geom.base, geom.normal, x_min, x_max, y_min, y_max)
        ax.plot([p0.real, p1.real], [p0.imag, p1.imag], color="tab:orange", linewidth=0.8)
        draw_ensemble_vertical_lines(ax, ensemble_bands)
        if geom.intersections:
            ax.scatter(
                [z.real for z in geom.intersections],
                [z.imag for z in geom.intersections],
                s=6,
                color="tab:red",
            )
        if geom.primary_intersection is not None:
            ax.scatter(
                [geom.primary_intersection.real],
                [geom.primary_intersection.imag],
                s=26,
                color="none",
                edgecolors="tab:red",
                marker="*",
                linewidths=0.8,
            )
        ax.scatter([geom.z0.real], [geom.z0.imag], s=8, color="black")
        ax.quiver(
            [geom.z0.real],
            [geom.z0.imag],
            [geom.delz.real],
            [geom.delz.imag],
            angles="xy",
            scale_units="xy",
            scale=1.0,
            color="tab:green",
            width=0.004,
            alpha=0.9,
        )

        proposals = proposal_map.get(geom.sample_idx, [])
        n_mark = min(max(0, proposal_count), len(proposals))
        ax.set_xlim(x_min, x_max)
        ax.set_ylim(y_min, y_max)
        ax.set_aspect("equal", adjustable="box")
        if n_mark > 0:
            p_sel = proposals[:n_mark]
            ax.scatter([p.real for p in p_sel], [p.imag for p in p_sel], s=7, color="tab:purple")
            annotate_numbered_points(ax, p_sel, color="tab:purple", fontsize=5.5)
        ax.grid(True, alpha=0.15)
        ax.tick_params(labelsize=6)
        n_int = len(geom.intersections)
        if n_int == 0:
            ax.set_title(f"S{geom.sample_idx} no hit", fontsize=8)
        else:
            ax.set_title(f"S{geom.sample_idx} I={n_int}", fontsize=8)

    for i in range(n_cases, len(axes_flat)):
        axes_flat[i].axis("off")

    fig.suptitle(
        "Case-by-Case: manifold (blue), affine line z0+delz+normal(z0) (orange), "
        "z0 (black), delz vector (green), intersections (red), "
        "point #1 first guess then accepted iter points (purple)",
        fontsize=13,
    )
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    fig.savefig(out_path, dpi=200)
    plt.close(fig)


def plot_case_individual(
    out_dir: Path,
    z_vals: np.ndarray,
    segment_valid: np.ndarray | None,
    geom: CaseGeometry,
    proposals: list[complex],
    proposal_count: int,
    ensemble_bands: EnsembleReBands | None = None,
) -> None:
    fig, ax = plt.subplots(figsize=(7, 6))
    plot_polyline_with_breaks(
        ax,
        z_vals,
        segment_valid,
        color="tab:blue",
        linewidth=1.2,
        label="flowed manifold",
    )

    x_pts = [geom.nearest_z.real, geom.base.real]
    y_pts = [geom.nearest_z.imag, geom.base.imag]
    if geom.intersections:
        x_pts.extend([z.real for z in geom.intersections])
        y_pts.extend([z.imag for z in geom.intersections])
    dx = max(x_pts) - min(x_pts)
    dy = max(y_pts) - min(y_pts)
    pad_x = max(0.12, 0.45 * dx + 0.10)
    pad_y = max(0.12, 0.45 * dy + 0.10)
    x_min = min(x_pts) - pad_x
    x_max = max(x_pts) + pad_x
    y_min = min(y_pts) - pad_y
    y_max = max(y_pts) + pad_y

    p0, p1 = line_segment_for_limits(geom.base, geom.normal, x_min, x_max, y_min, y_max)
    ax.plot(
        [p0.real, p1.real],
        [p0.imag, p1.imag],
        color="tab:orange",
        linewidth=1.2,
        label="z0 + delz + normal(z0)",
    )
    draw_ensemble_vertical_lines(ax, ensemble_bands)
    ax.scatter([geom.z0.real], [geom.z0.imag], color="black", s=30, label="z0")
    ax.quiver(
        [geom.z0.real],
        [geom.z0.imag],
        [geom.delz.real],
        [geom.delz.imag],
        angles="xy",
        scale_units="xy",
        scale=1.0,
        color="tab:green",
        width=0.004,
        alpha=0.9,
        label="delz vector",
    )

    n_mark = min(max(0, proposal_count), len(proposals))
    p_sel: list[complex] = []
    if n_mark > 0:
        p_sel = proposals[:n_mark]
        ax.scatter(
            [p.real for p in p_sel],
            [p.imag for p in p_sel],
            color="tab:purple",
            s=24,
            label="point #1 first guess; then accepted per iteration",
        )

    if geom.intersections:
        ax.scatter(
            [z.real for z in geom.intersections],
            [z.imag for z in geom.intersections],
            color="tab:red",
            s=28,
            label="detected intersections",
        )
    if geom.primary_intersection is not None:
        ax.scatter(
            [geom.primary_intersection.real],
            [geom.primary_intersection.imag],
            color="none",
            edgecolors="tab:red",
            marker="*",
            s=110,
            linewidths=1.0,
            label="primary intersection",
            zorder=7,
        )

    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_min, y_max)

    ax.set_xlabel("Re(z)")
    ax.set_ylabel("Im(z)")
    ax.set_aspect("equal", adjustable="box")
    if n_mark > 0:
        annotate_numbered_points(ax, p_sel, color="tab:purple", fontsize=10)
    ax.grid(True, alpha=0.2)
    n_int = len(geom.intersections)
    if n_int == 0:
        ax.set_title(
            f"Case {geom.sample_idx}: no hit "
            f"min_line_dist={geom.min_line_distance:.3e}"
        )
    else:
        ax.set_title(
            f"Case {geom.sample_idx}: intersections={n_int} "
            f"min_line_dist={geom.min_line_distance:.3e}"
        )
    ax.legend(loc="best", fontsize=8)
    fig.tight_layout()
    fig.savefig(out_dir / f"case_{geom.sample_idx:03d}.png", dpi=170)
    plt.close(fig)


def write_summary(out_csv: Path, cases: list[FailureCase], geoms: list[CaseGeometry]) -> None:
    by_id = {g.sample_idx: g for g in geoms}
    with out_csv.open("w", newline="") as fobj:
        writer = csv.writer(fobj)
        writer.writerow(
            [
                "sample_idx",
                "flow_time",
                "seed_u",
                "z0_re",
                "z0_im",
                "delz_re",
                "delz_im",
                "base_re",
                "base_im",
                "tangent_re",
                "tangent_im",
                "normal_re",
                "normal_im",
                "hit_status",
                "num_intersections",
                "primary_hit_re",
                "primary_hit_im",
                "primary_hit_dist_to_base",
                "min_line_distance",
                "nearest_u",
                "nearest_z_re",
                "nearest_z_im",
            ]
        )
        for case in cases:
            geom = by_id[case.sample_idx]
            writer.writerow(
                [
                    case.sample_idx,
                    case.flow_time,
                    case.seed_u,
                    case.z0.real,
                    case.z0.imag,
                    case.delz.real,
                    case.delz.imag,
                    geom.base.real,
                    geom.base.imag,
                    geom.tangent.real,
                    geom.tangent.imag,
                    geom.normal.real,
                    geom.normal.imag,
                    "no hit" if len(geom.intersections) == 0 else "hit",
                    len(geom.intersections),
                    "" if geom.primary_intersection is None else geom.primary_intersection.real,
                    "" if geom.primary_intersection is None else geom.primary_intersection.imag,
                    ""
                    if geom.primary_intersection is None
                    else abs(geom.primary_intersection - geom.base),
                    geom.min_line_distance,
                    geom.nearest_u,
                    geom.nearest_z.real,
                    geom.nearest_z.imag,
                ]
            )


def main() -> None:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]

    z0_map = read_complex_stream(args.z0_file)
    delz_map = read_real_stream(args.delz_file)
    x0_map = read_real_stream(args.x0_file)
    cases = build_cases(z0_map, delz_map, x0_map, args.max_cases)
    proposal_map = load_proposals(args.quasi_trace_csv, args.max_cases)
    ensemble_bands: EnsembleReBands | None = None
    try:
        z_size_guess = len(next(iter(z0_map.values())))
        z_reals = read_ensemble_reals(args.ensemble_z_history_file, z_size=z_size_guess)
        ensemble_bands = compute_ensemble_re_bands(z_reals)
    except Exception as exc:
        print(f"[WARN] Skip ensemble vertical lines: {exc}")

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    per_case_dir = out_dir / "case_by_case_normal"
    if not args.no_plots:
        per_case_dir.mkdir(parents=True, exist_ok=True)
    manifold_dir = out_dir / "manifold_samples"
    manifold_dir.mkdir(parents=True, exist_ok=True)
    point_scan_dir = out_dir / "point_scans"
    point_scan_dir.mkdir(parents=True, exist_ok=True)

    u_vals_all = np.array([c.seed_u for c in cases], dtype=float)
    seed_min = float(np.min(u_vals_all) - args.seed_margin)
    seed_max = float(np.max(u_vals_all) + args.seed_margin)

    manifolds: dict[float, tuple[np.ndarray, np.ndarray, np.ndarray]] = {}
    flow_times = sorted(set(round(c.flow_time, 12) for c in cases))
    for flow_time in flow_times:
        manifold_file = manifold_dir / f"manifold_t{flow_time:.12f}.dat"
        u_vals, z_vals = sample_manifold(
            repo_root=repo_root,
            out_file=manifold_file,
            seed_min=seed_min,
            seed_max=seed_max,
            n_samples=args.n_manifold,
            flow_time=flow_time,
        )
        seg_valid = segment_valid_mask(z_vals, args.jump_quantile, args.jump_factor)
        manifolds[flow_time] = (u_vals, z_vals, seg_valid)

    jac_map: dict[tuple[float, float], complex] = {}
    for case in cases:
        key = (round(case.flow_time, 12), round(case.seed_u, 14))
        if key in jac_map:
            continue
        jac_map[key] = jacobian_at_point(
            repo_root=repo_root,
            scan_dir=point_scan_dir,
            seed_u=case.seed_u,
            flow_time=case.flow_time,
        )

    geoms: list[CaseGeometry] = []
    for case in cases:
        key = round(case.flow_time, 12)
        u_vals, z_vals, seg_valid = manifolds[key]
        j_key = (round(case.flow_time, 12), round(case.seed_u, 14))
        geom = compute_case_geometry(
            case,
            u_vals,
            z_vals,
            segment_valid=seg_valid,
            tangent_override=jac_map[j_key],
        )
        geoms.append(geom)
        if not args.no_plots:
            plot_case_individual(
                per_case_dir,
                z_vals,
                seg_valid,
                geom,
                proposal_map.get(case.sample_idx, []),
                args.proposal_count,
                ensemble_bands=ensemble_bands,
            )

    if not args.no_plots:
        u_ref, z_ref, seg_ref = manifolds[round(cases[0].flow_time, 12)]
        _ = u_ref  # kept for readability and future extension
        plot_overlay(out_dir / "overlay_manifold_vs_normal.png", z_ref, seg_ref, geoms)
        plot_case_grid(
            out_dir / "case_grid_manifold_vs_normal.png",
            z_ref,
            seg_ref,
            geoms,
            proposal_map,
            args.proposal_count,
            ensemble_bands=ensemble_bands,
            ncols=10,
        )
    write_summary(out_dir / "intersection_summary.csv", cases, geoms)

    n_hit = sum(1 for g in geoms if g.intersections)
    print(
        f"[DONE] Cases={len(geoms)} with_intersections={n_hit} "
        f"plots={out_dir}"
    )


if __name__ == "__main__":
    main()
