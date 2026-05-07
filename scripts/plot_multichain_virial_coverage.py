#!/usr/bin/env python3
"""Plot whether multichain virial estimates cover zero within mean +- error."""

from __future__ import annotations

import argparse
import csv
import math
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt


@dataclass
class RunStats:
    run_name: str
    mtime: float
    mean_re: float
    mean_im: float
    err_re: float
    err_im: float
    err_source: str
    cover_re: bool
    cover_im: bool
    z_re: float
    z_im: float


def _parse_kv_file(path: Path) -> dict[str, str]:
    kv: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        kv[key.strip()] = value.strip()
    return kv


def _parse_pair(text: str) -> tuple[float, float]:
    parts = text.replace(",", " ").split()
    if len(parts) < 2:
        raise ValueError(f"expected two numbers, got: {text!r}")
    return float(parts[0]), float(parts[1])


def _choose_error_source(kv: dict[str, str], mode: str) -> tuple[str, tuple[float, float]]:
    candidates: list[tuple[str, str]]
    if mode == "robust":
        candidates = [("robust", "err_robust_virial_re_im")]
    elif mode == "strat":
        candidates = [("strat", "err_strat_jk_virial_re_im")]
    elif mode == "chain":
        candidates = [("chain", "err_chain_jk_virial_re_im")]
    else:
        candidates = [
            ("robust", "err_robust_virial_re_im"),
            ("strat", "err_strat_jk_virial_re_im"),
            ("chain", "err_chain_jk_virial_re_im"),
        ]

    for source, key in candidates:
        if key in kv:
            return source, _parse_pair(kv[key])
    raise KeyError("no virial error field found")


def _load_run_stats(meta_path: Path, error_mode: str) -> RunStats:
    kv = _parse_kv_file(meta_path)
    mean_re, mean_im = _parse_pair(kv["mean_virial_re_im"])
    err_source, (err_re, err_im) = _choose_error_source(kv, error_mode)
    err_re = abs(err_re)
    err_im = abs(err_im)

    cover_re = abs(mean_re) <= err_re if err_re > 0.0 else False
    cover_im = abs(mean_im) <= err_im if err_im > 0.0 else False
    z_re = abs(mean_re) / err_re if err_re > 0.0 else math.inf
    z_im = abs(mean_im) / err_im if err_im > 0.0 else math.inf

    return RunStats(
        run_name=meta_path.parent.name,
        mtime=meta_path.stat().st_mtime,
        mean_re=mean_re,
        mean_im=mean_im,
        err_re=err_re,
        err_im=err_im,
        err_source=err_source,
        cover_re=cover_re,
        cover_im=cover_im,
        z_re=z_re,
        z_im=z_im,
    )


def _thin_labels(labels: list[str], max_labels: int = 24) -> tuple[list[int], list[str]]:
    n = len(labels)
    if n <= max_labels:
        return list(range(n)), labels
    step = math.ceil(n / max_labels)
    idx = list(range(0, n, step))
    return idx, [labels[i] for i in idx]


def _plot(points: list[RunStats], output_png: Path, title: str) -> None:
    n = len(points)
    labels = [p.run_name for p in points]
    x = list(range(n))

    width = max(12.0, min(24.0, 0.45 * n + 8.0))
    fig, axes = plt.subplots(2, 1, figsize=(width, 8.0), sharex=True)

    for comp_idx, (comp_name, means, errs, covers, zvals) in enumerate(
        [
            ("Re", [p.mean_re for p in points], [p.err_re for p in points], [p.cover_re for p in points], [p.z_re for p in points]),
            ("Im", [p.mean_im for p in points], [p.err_im for p in points], [p.cover_im for p in points], [p.z_im for p in points]),
        ]
    ):
        ax = axes[comp_idx]
        ax.errorbar(x, means, yerr=errs, fmt="none", ecolor="#888888", elinewidth=1.0, capsize=2)
        colors = ["#2ca02c" if ok else "#d62728" for ok in covers]
        ax.scatter(x, means, c=colors, s=28, zorder=3)
        ax.axhline(0.0, color="#1f77b4", linestyle="--", linewidth=1.2)
        ax.grid(True, axis="y", alpha=0.30)
        ax.set_ylabel(f"virial {comp_name}")
        covered = sum(1 for ok in covers if ok)
        ax.set_title(f"{comp_name}: cover(0)={covered}/{n}, median |mean|/err={_median(zvals):.2f}")

    tick_idx, tick_labels = _thin_labels(labels)
    axes[-1].set_xticks(tick_idx)
    axes[-1].set_xticklabels(tick_labels, rotation=60, ha="right")
    axes[-1].set_xlabel("run_name")

    fig.suptitle(title)
    fig.tight_layout()
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180)
    plt.close(fig)


def _median(values: list[float]) -> float:
    finite = sorted(v for v in values if math.isfinite(v))
    if not finite:
        return math.inf
    n = len(finite)
    if n % 2 == 1:
        return finite[n // 2]
    return 0.5 * (finite[n // 2 - 1] + finite[n // 2])


def _write_csv(points: list[RunStats], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "run_name",
                "mean_re",
                "err_re",
                "cover_re",
                "z_re_abs_mean_over_err",
                "mean_im",
                "err_im",
                "cover_im",
                "z_im_abs_mean_over_err",
                "err_source",
            ]
        )
        for p in points:
            writer.writerow(
                [
                    p.run_name,
                    f"{p.mean_re:.16e}",
                    f"{p.err_re:.16e}",
                    int(p.cover_re),
                    f"{p.z_re:.6f}" if math.isfinite(p.z_re) else "inf",
                    f"{p.mean_im:.16e}",
                    f"{p.err_im:.16e}",
                    int(p.cover_im),
                    f"{p.z_im:.6f}" if math.isfinite(p.z_im) else "inf",
                    p.err_source,
                ]
            )


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=repo_root / "output" / "multichain_auto",
        help="Root folder containing multichain run directories.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "output" / "multichain_auto" / "virial_coverage.png",
        help="Output PNG path.",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        default=repo_root / "output" / "multichain_auto" / "virial_coverage_summary.csv",
        help="Output CSV summary path.",
    )
    parser.add_argument(
        "--error",
        choices=("auto", "robust", "strat", "chain"),
        default="auto",
        help="Which virial error field to use.",
    )
    parser.add_argument(
        "--last",
        type=int,
        default=0,
        help="Use only the latest N runs by mtime (0 means all).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    meta_paths = sorted(root.glob("*/multichain_expectations.dat"))
    if not meta_paths:
        print(f"[ERROR] No multichain_expectations.dat found under {root}")
        return 1

    points: list[RunStats] = []
    skipped = 0
    for meta in meta_paths:
        try:
            points.append(_load_run_stats(meta, args.error))
        except Exception:
            skipped += 1
            continue

    if not points:
        print(f"[ERROR] No parseable expectation metadata under {root}")
        return 1

    points.sort(key=lambda p: p.mtime)
    if args.last > 0:
        points = points[-args.last :]

    _plot(points, args.output.resolve(), "Virial Coverage: mean ± error vs 0")
    _write_csv(points, args.csv.resolve())

    n = len(points)
    covered_re = sum(1 for p in points if p.cover_re)
    covered_im = sum(1 for p in points if p.cover_im)
    print(f"[DONE] runs={n} skipped={skipped}")
    print(f"[DONE] Re coverage: {covered_re}/{n}")
    print(f"[DONE] Im coverage: {covered_im}/{n}")
    print(f"[DONE] plot: {args.output.resolve()}")
    print(f"[DONE] csv: {args.csv.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

