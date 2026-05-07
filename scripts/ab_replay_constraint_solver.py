#!/usr/bin/env python3
"""Run and compare A/B replay results for constraint solver variants."""

from __future__ import annotations

import argparse
import csv
import math
import os
import statistics
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "A/B harness for replay_quasi_failures outputs. "
            "Each side can be provided either as an existing CSV or as a replay binary."
        )
    )
    parser.add_argument("--a-label", default="A", help="Label for variant A.")
    parser.add_argument("--b-label", default="B", help="Label for variant B.")

    parser.add_argument("--a-csv", type=Path, help="Existing replay CSV for A.")
    parser.add_argument("--b-csv", type=Path, help="Existing replay CSV for B.")
    parser.add_argument("--a-bin", type=Path, help="replay_quasi_failures binary for A.")
    parser.add_argument("--b-bin", type=Path, help="replay_quasi_failures binary for B.")
    parser.add_argument(
        "--a-solver-mode",
        help="Value for HMC_CONSTRAINT_SOLVER when running A binary (e.g. quasi_newton, dfo_gn_paper).",
    )
    parser.add_argument(
        "--b-solver-mode",
        help="Value for HMC_CONSTRAINT_SOLVER when running B binary (e.g. quasi_newton, dfo_gn_paper).",
    )
    parser.add_argument(
        "--a-run-cwd",
        type=Path,
        help="Working directory when running A binary (default: auto-infer from binary path).",
    )
    parser.add_argument(
        "--b-run-cwd",
        type=Path,
        help="Working directory when running B binary (default: auto-infer from binary path).",
    )

    parser.add_argument("--tol", type=float, default=1.0e-10, help="Replay tolerance.")
    parser.add_argument("--max-iter", type=int, default=200, help="Replay max_iter.")
    parser.add_argument(
        "--z0-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_z0.dat"),
        help="z0 stream file.",
    )
    parser.add_argument(
        "--delz-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_delz.dat"),
        help="delz stream file.",
    )
    parser.add_argument(
        "--x0-file",
        type=Path,
        default=Path("output/constraint_fail_cases_100/constraint_solver_fail_x0.dat"),
        help="x0 stream file.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("output/constraint_fail_cases_100/ab_runs"),
        help="Output directory for generated CSV/report files.",
    )
    parser.add_argument(
        "--out-prefix",
        default="ab",
        help="Prefix for generated output files.",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=20,
        help="Number of top changed cases to include in markdown report.",
    )
    return parser.parse_args()


@dataclass
class ReplayRow:
    sample_idx: int
    success: int
    min_res: float
    last_res: float
    proposal_count: int
    min_iter: int
    min_backtrack: int
    min_attempt: int


def parse_float(text: str) -> float:
    s = text.strip()
    if not s:
        return math.nan
    try:
        return float(s)
    except ValueError:
        return math.nan


def parse_int(text: str) -> int:
    s = text.strip()
    if not s:
        return 0
    try:
        return int(float(s))
    except ValueError:
        return 0


def read_replay_csv(path: Path) -> Dict[int, ReplayRow]:
    rows: Dict[int, ReplayRow] = {}
    with path.open("r", newline="") as fobj:
        reader = csv.DictReader(fobj)
        required = {"sample_idx", "success", "min_res", "last_res", "proposal_count", "min_iter", "min_backtrack", "min_attempt"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise RuntimeError(f"Missing required columns in {path}: {sorted(missing)}")
        for row in reader:
            sid = parse_int(row["sample_idx"])
            rows[sid] = ReplayRow(
                sample_idx=sid,
                success=parse_int(row["success"]),
                min_res=parse_float(row["min_res"]),
                last_res=parse_float(row["last_res"]),
                proposal_count=parse_int(row["proposal_count"]),
                min_iter=parse_int(row["min_iter"]),
                min_backtrack=parse_int(row["min_backtrack"]),
                min_attempt=parse_int(row["min_attempt"]),
            )
    if not rows:
        raise RuntimeError(f"No rows read from {path}")
    return rows


def run_replay(
    *,
    replay_bin: Path,
    tol: float,
    max_iter: int,
    z0_file: Path,
    delz_file: Path,
    x0_file: Path,
    out_csv: Path,
    run_cwd: Path,
    solver_mode: str | None = None,
) -> None:
    cmd = [
        str(replay_bin.resolve()),
        f"{tol:.16e}",
        str(max_iter),
        str(z0_file.resolve()),
        str(delz_file.resolve()),
        str(x0_file.resolve()),
        str(out_csv.resolve()),
    ]
    env = os.environ.copy()
    if solver_mode is not None and solver_mode.strip():
        env["HMC_CONSTRAINT_SOLVER"] = solver_mode.strip()
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
        cwd=str(run_cwd.resolve()),
        env=env,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "Replay command failed.\n"
            f"cmd: {' '.join(cmd)}\n"
            f"cwd: {run_cwd.resolve()}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )


def cwd_supports_default_config(cwd: Path) -> bool:
    c = cwd.resolve()
    return (c / "data/parameters.dat").exists() or (c / "../data/parameters.dat").exists()


def infer_run_cwd(binary_path: Path) -> Path:
    b = binary_path.resolve()
    candidates: list[Path] = []
    if b.parent.name == "bin":
        candidates.append((b.parent.parent / "build").resolve())
        candidates.append(b.parent.parent.resolve())
    candidates.append(Path.cwd().resolve())
    candidates.append(b.parent.resolve())

    seen: set[Path] = set()
    for c in candidates:
        if c in seen:
            continue
        seen.add(c)
        if c.exists() and c.is_dir() and cwd_supports_default_config(c):
            return c

    # Fall back to current directory; error (if any) will include cwd.
    return Path.cwd().resolve()


def ensure_side_csv(
    *,
    label: str,
    csv_path: Path | None,
    bin_path: Path | None,
    run_cwd: Path | None,
    solver_mode: str | None,
    args: argparse.Namespace,
) -> Path:
    if csv_path is not None:
        if not csv_path.exists():
            raise RuntimeError(f"{label}: CSV not found: {csv_path}")
        return csv_path

    if bin_path is None:
        raise RuntimeError(f"{label}: provide either --{label.lower()}-csv or --{label.lower()}-bin")
    if not bin_path.exists():
        raise RuntimeError(f"{label}: binary not found: {bin_path}")
    effective_cwd = run_cwd.resolve() if run_cwd is not None else infer_run_cwd(bin_path)
    if not effective_cwd.exists() or not effective_cwd.is_dir():
        raise RuntimeError(f"{label}: run cwd is not a directory: {effective_cwd}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    out_csv = args.out_dir / f"{args.out_prefix}_{label.lower()}_replay.csv"
    run_replay(
        replay_bin=bin_path,
        tol=args.tol,
        max_iter=args.max_iter,
        z0_file=args.z0_file,
        delz_file=args.delz_file,
        x0_file=args.x0_file,
        out_csv=out_csv,
        run_cwd=effective_cwd,
        solver_mode=solver_mode,
    )
    return out_csv


def safe_ratio(num: float, den: float) -> float:
    if (not math.isfinite(num)) or (not math.isfinite(den)) or den <= 0.0:
        return math.nan
    return num / den


def median_or_nan(vals: list[float]) -> float:
    finite = [v for v in vals if math.isfinite(v)]
    if not finite:
        return math.nan
    return float(statistics.median(finite))


def format_pct(x: float) -> str:
    if not math.isfinite(x):
        return "nan"
    return f"{x:.1f}%"


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    a_csv = ensure_side_csv(
        label="A",
        csv_path=args.a_csv,
        bin_path=args.a_bin,
        run_cwd=args.a_run_cwd,
        solver_mode=args.a_solver_mode,
        args=args,
    )
    b_csv = ensure_side_csv(
        label="B",
        csv_path=args.b_csv,
        bin_path=args.b_bin,
        run_cwd=args.b_run_cwd,
        solver_mode=args.b_solver_mode,
        args=args,
    )

    a_rows = read_replay_csv(a_csv)
    b_rows = read_replay_csv(b_csv)
    common_ids = sorted(set(a_rows).intersection(b_rows))
    if not common_ids:
        raise RuntimeError("No overlapping sample_idx between A and B.")

    both_success = 0
    a_only = 0
    b_only = 0
    both_fail = 0
    fail_ratio_b_over_a: list[float] = []

    case_out: list[dict[str, object]] = []
    b_only_cases: list[tuple[int, float]] = []
    a_only_cases: list[tuple[int, float]] = []

    for sid in common_ids:
        ar = a_rows[sid]
        br = b_rows[sid]
        a_ok = int(ar.success == 1)
        b_ok = int(br.success == 1)

        if a_ok and b_ok:
            status = "both_success"
            both_success += 1
        elif a_ok and not b_ok:
            status = "a_only"
            a_only += 1
            a_only_cases.append((sid, br.min_res))
        elif (not a_ok) and b_ok:
            status = "b_only"
            b_only += 1
            b_only_cases.append((sid, ar.min_res))
        else:
            both_fail += 1
            ratio = safe_ratio(br.min_res, ar.min_res)
            if math.isfinite(ratio):
                fail_ratio_b_over_a.append(ratio)
            status = "both_fail"

        case_out.append(
            {
                "sample_idx": sid,
                "status": status,
                "a_success": a_ok,
                "b_success": b_ok,
                "a_min_res": ar.min_res,
                "b_min_res": br.min_res,
                "b_over_a_min_res": safe_ratio(br.min_res, ar.min_res),
                "a_last_res": ar.last_res,
                "b_last_res": br.last_res,
                "a_proposal_count": ar.proposal_count,
                "b_proposal_count": br.proposal_count,
                "a_min_iter": ar.min_iter,
                "b_min_iter": br.min_iter,
                "a_min_backtrack": ar.min_backtrack,
                "b_min_backtrack": br.min_backtrack,
                "a_min_attempt": ar.min_attempt,
                "b_min_attempt": br.min_attempt,
            }
        )

    n = len(common_ids)
    a_success_rate = 100.0 * (both_success + a_only) / n
    b_success_rate = 100.0 * (both_success + b_only) / n
    delta_pp = b_success_rate - a_success_rate
    med_fail_ratio = median_or_nan(fail_ratio_b_over_a)

    b_only_cases.sort(key=lambda t: (math.isfinite(t[1]), t[1]), reverse=True)
    a_only_cases.sort(key=lambda t: (math.isfinite(t[1]), t[1]), reverse=True)

    cases_csv = args.out_dir / f"{args.out_prefix}_{args.a_label}_vs_{args.b_label}_cases.csv"
    with cases_csv.open("w", newline="") as fobj:
        fieldnames = [
            "sample_idx",
            "status",
            "a_success",
            "b_success",
            "a_min_res",
            "b_min_res",
            "b_over_a_min_res",
            "a_last_res",
            "b_last_res",
            "a_proposal_count",
            "b_proposal_count",
            "a_min_iter",
            "b_min_iter",
            "a_min_backtrack",
            "b_min_backtrack",
            "a_min_attempt",
            "b_min_attempt",
        ]
        writer = csv.DictWriter(fobj, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(case_out)

    report_md = args.out_dir / f"{args.out_prefix}_{args.a_label}_vs_{args.b_label}_report.md"
    with report_md.open("w") as fobj:
        fobj.write(f"# Constraint Solver A/B Report: {args.a_label} vs {args.b_label}\n\n")
        fobj.write("## Inputs\n")
        fobj.write(f"- A CSV: `{a_csv}`\n")
        fobj.write(f"- B CSV: `{b_csv}`\n")
        fobj.write(f"- Common samples: `{n}`\n\n")

        fobj.write("## Success Summary\n")
        fobj.write(f"- `{args.a_label}` success: `{both_success + a_only}/{n}` ({format_pct(a_success_rate)})\n")
        fobj.write(f"- `{args.b_label}` success: `{both_success + b_only}/{n}` ({format_pct(b_success_rate)})\n")
        fobj.write(f"- Delta (B - A): `{delta_pp:+.1f}` percentage points\n\n")

        fobj.write("## Contingency\n")
        fobj.write(f"- both_success: `{both_success}`\n")
        fobj.write(f"- A_only_success: `{a_only}`\n")
        fobj.write(f"- B_only_success: `{b_only}`\n")
        fobj.write(f"- both_fail: `{both_fail}`\n\n")

        fobj.write("## Both-Fail Residual Ratio\n")
        fobj.write("- Metric: `b_min_res / a_min_res` on both-fail samples\n")
        if math.isfinite(med_fail_ratio):
            fobj.write(f"- Median ratio: `{med_fail_ratio:.4g}` (below 1 means B usually lower residual)\n\n")
        else:
            fobj.write("- Median ratio: `nan`\n\n")

        top_k = max(0, args.top_k)
        if top_k > 0:
            fobj.write(f"## B-Only Success Cases (Top {top_k})\n")
            if not b_only_cases:
                fobj.write("- none\n")
            else:
                for sid, min_res_a in b_only_cases[:top_k]:
                    fobj.write(f"- sample `{sid}`: A min_res=`{min_res_a:.6e}`\n")
            fobj.write("\n")

            fobj.write(f"## A-Only Success Cases (Top {top_k})\n")
            if not a_only_cases:
                fobj.write("- none\n")
            else:
                for sid, min_res_b in a_only_cases[:top_k]:
                    fobj.write(f"- sample `{sid}`: B min_res=`{min_res_b:.6e}`\n")
            fobj.write("\n")

        fobj.write("## Artifacts\n")
        fobj.write(f"- per-case CSV: `{cases_csv}`\n")
        fobj.write(f"- report: `{report_md}`\n")

    print(f"[DONE] common_samples={n}")
    print(f"[DONE] {args.a_label}_success={both_success + a_only}/{n} ({format_pct(a_success_rate)})")
    print(f"[DONE] {args.b_label}_success={both_success + b_only}/{n} ({format_pct(b_success_rate)})")
    print(f"[DONE] delta_pp={delta_pp:+.1f}")
    print(f"[DONE] wrote case csv: {cases_csv}")
    print(f"[DONE] wrote report: {report_md}")


if __name__ == "__main__":
    main()
