#!/usr/bin/env python3
"""Plot quasi-Newton constraint failure traces."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

import matplotlib.pyplot as plt


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create overlay and case-by-case plots from constraint failure traces."
    )
    parser.add_argument(
        "--trace-csv",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_quasi_trace.csv"),
        help="Path to constraint_solver_fail_quasi_trace.csv",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("output/constraint_fail_cases_100/plots"),
        help="Directory where plots are written",
    )
    parser.add_argument(
        "--max-samples",
        type=int,
        default=100,
        help="Maximum number of sample IDs to plot",
    )
    return parser.parse_args()


def load_traces(trace_csv: Path, max_samples: int) -> dict[int, list[tuple[int, float, int]]]:
    traces: dict[int, list[tuple[int, float, int]]] = {}
    with trace_csv.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        for row in reader:
            sample_idx = int(row["sample_idx"].strip())
            if sample_idx > max_samples:
                continue
            proposal_idx = int(row["proposal_idx"].strip())
            res_norm = float(row["res_norm"].strip())
            accepted = int(row["accepted"].strip())
            traces.setdefault(sample_idx, []).append((proposal_idx, res_norm, accepted))

    for sample_idx in traces:
        traces[sample_idx].sort(key=lambda item: item[0])
    return traces


def min_positive_residual(traces: dict[int, list[tuple[int, float, int]]]) -> float:
    best = math.inf
    for rows in traces.values():
        for _, res_norm, _ in rows:
            if res_norm > 0.0 and res_norm < best:
                best = res_norm
    if math.isinf(best):
        return 1e-16
    return best


def safe_series(
    rows: list[tuple[int, float, int]], floor_val: float
) -> tuple[list[int], list[float], list[int], list[float]]:
    x_vals: list[int] = []
    y_vals: list[float] = []
    accepted_x: list[int] = []
    accepted_y: list[float] = []

    for proposal_idx, res_norm, accepted in rows:
        y = res_norm if res_norm > 0.0 else floor_val
        x_vals.append(proposal_idx)
        y_vals.append(y)
        if accepted == 1:
            accepted_x.append(proposal_idx)
            accepted_y.append(y)
    return x_vals, y_vals, accepted_x, accepted_y


def plot_overlay(
    traces: dict[int, list[tuple[int, float, int]]], floor_val: float, out_path: Path
) -> None:
    fig, ax = plt.subplots(figsize=(12, 8))
    for sample_idx in sorted(traces):
        x_vals, y_vals, _, _ = safe_series(traces[sample_idx], floor_val)
        ax.plot(x_vals, y_vals, linewidth=0.9, alpha=0.35, label=f"{sample_idx}")

    ax.set_yscale("log")
    ax.set_xlabel("proposal_idx")
    ax.set_ylabel("res_norm")
    ax.set_title("Constraint Solver Failure Traces: Overlay (First 100 Samples)")
    ax.grid(True, which="both", alpha=0.2)
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def plot_case_grid(
    traces: dict[int, list[tuple[int, float, int]]], floor_val: float, out_path: Path
) -> None:
    sample_ids = sorted(traces)
    n_samples = len(sample_ids)
    ncols = 10
    nrows = max(1, math.ceil(n_samples / ncols))

    fig, axes = plt.subplots(nrows=nrows, ncols=ncols, figsize=(24, 2.2 * nrows), sharey=True)
    axes_flat = list(axes.flat) if hasattr(axes, "flat") else [axes]

    for idx, sample_idx in enumerate(sample_ids):
        ax = axes_flat[idx]
        x_vals, y_vals, accepted_x, accepted_y = safe_series(traces[sample_idx], floor_val)
        ax.plot(x_vals, y_vals, color="tab:blue", linewidth=0.9)
        if accepted_x:
            ax.scatter(accepted_x, accepted_y, color="tab:red", s=4, alpha=0.8)
        ax.set_yscale("log")
        ax.set_title(f"S{sample_idx}", fontsize=8)
        ax.grid(True, which="both", alpha=0.15)
        ax.tick_params(labelsize=6)

    for idx in range(n_samples, len(axes_flat)):
        axes_flat[idx].axis("off")

    fig.suptitle(
        "Constraint Solver Failure Traces: Case-by-Case Grid\n"
        "Blue line: residual norm, red dots: accepted proposals",
        fontsize=14,
    )
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    fig.savefig(out_path, dpi=200)
    plt.close(fig)


def plot_case_by_case(
    traces: dict[int, list[tuple[int, float, int]]], floor_val: float, out_dir: Path
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for sample_idx in sorted(traces):
        x_vals, y_vals, accepted_x, accepted_y = safe_series(traces[sample_idx], floor_val)
        fig, ax = plt.subplots(figsize=(8, 5))
        ax.plot(x_vals, y_vals, color="tab:blue", linewidth=1.2)
        if accepted_x:
            ax.scatter(accepted_x, accepted_y, color="tab:red", s=20, alpha=0.9)

        ax.set_yscale("log")
        ax.set_xlabel("proposal_idx")
        ax.set_ylabel("res_norm")
        ax.set_title(f"Constraint Failure Case {sample_idx}")
        ax.grid(True, which="both", alpha=0.25)
        fig.tight_layout()
        fig.savefig(out_dir / f"case_{sample_idx:03d}.png", dpi=160)
        plt.close(fig)


def main() -> None:
    args = parse_args()
    if not args.trace_csv.exists():
        raise FileNotFoundError(f"Trace CSV not found: {args.trace_csv}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    traces = load_traces(args.trace_csv, args.max_samples)
    if not traces:
        raise RuntimeError(f"No traces found in: {args.trace_csv}")

    floor_val = min_positive_residual(traces) * 0.1
    plot_overlay(traces, floor_val, args.out_dir / "quasi_residual_overlay.png")
    plot_case_grid(traces, floor_val, args.out_dir / "quasi_residual_case_grid.png")
    plot_case_by_case(traces, floor_val, args.out_dir / "case_by_case")

    print(
        f"[DONE] Wrote plots for {len(traces)} samples to {args.out_dir}"
    )


if __name__ == "__main__":
    main()
