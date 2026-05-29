#!/usr/bin/env python3
"""Write the final Stephanov n=6 observable/z summary table.

This script is intentionally narrow: it reproduces the compact
STEPHANOV_N6_PREFIX_COMPARISON-style table for the current completed TLTM
nofb/withfb production roots, including an exact same-config-size nofb cut.
"""

from __future__ import annotations

from array import array
import argparse
import csv
import datetime as dt
import json
import math
from pathlib import Path


OBSERVABLES = [
    "chiral_condensate",
    "number_density",
    "logdet_dirac",
    "phase_factor",
    "min_singular_ba_m2",
]
EXACT = {
    "chiral_condensate": 0.0244771982754,
    "number_density": 0.56611556665,
}
WIDTH = 2 * (1 + len(OBSERVABLES))


def record_id(path: Path) -> int:
    return int(path.parent.name.rsplit("_", 1)[1])


def stage_name(path: Path) -> str:
    return path.parts[-4]


def discover(root: Path, pattern: str) -> dict[int, list[Path]]:
    grouped: dict[int, list[Path]] = {}
    for path in root.glob(f"{pattern}/records/record_*/observable_history.dat"):
        grouped.setdefault(record_id(path), []).append(path)
    for paths in grouped.values():
        paths.sort(key=lambda item: (stage_name(item), str(item)))
    return dict(sorted(grouped.items()))


def empty_sums() -> dict[str, object]:
    return {
        "samples": 0,
        "D": complex(0.0, 0.0),
        "sum_abs_w": 0.0,
        "sum_abs_w2": 0.0,
        "N": [complex(0.0, 0.0) for _ in OBSERVABLES],
    }


def add_row(sums: dict[str, object], data: array, offset: int) -> None:
    weight = complex(float(data[offset]), float(data[offset + 1]))
    sums["samples"] = int(sums["samples"]) + 1
    sums["D"] = sums["D"] + weight  # type: ignore[operator]
    abs_weight = abs(weight)
    sums["sum_abs_w"] = float(sums["sum_abs_w"]) + abs_weight
    sums["sum_abs_w2"] = float(sums["sum_abs_w2"]) + abs_weight * abs_weight
    for obs_idx in range(len(OBSERVABLES)):
        obs_offset = offset + 2 + 2 * obs_idx
        obs = complex(float(data[obs_offset]), float(data[obs_offset + 1]))
        sums["N"][obs_idx] += weight * obs  # type: ignore[index]


def read_record(paths: list[Path], max_samples: int | None) -> dict[str, object]:
    sums = empty_sums()
    remaining = max_samples
    for path in paths:
        data = array("d")
        with path.open("rb") as handle:
            data.fromfile(handle, path.stat().st_size // 8)
        if len(data) % WIDTH != 0:
            raise RuntimeError(f"observable stream width mismatch: {path}")
        rows = len(data) // WIDTH
        if remaining is not None:
            rows = min(rows, remaining)
        for row_idx in range(rows):
            add_row(sums, data, row_idx * WIDTH)
        if remaining is not None:
            remaining -= rows
            if remaining == 0:
                break
    if max_samples is not None and int(sums["samples"]) != max_samples:
        raise RuntimeError(f"record has only {sums['samples']} samples, expected {max_samples}")
    return sums


def total_records(records: dict[int, dict[str, object]]) -> dict[str, object]:
    total = empty_sums()
    for record in records.values():
        total["samples"] = int(total["samples"]) + int(record["samples"])
        total["D"] = total["D"] + record["D"]  # type: ignore[operator]
        total["sum_abs_w"] = float(total["sum_abs_w"]) + float(record["sum_abs_w"])
        total["sum_abs_w2"] = float(total["sum_abs_w2"]) + float(record["sum_abs_w2"])
        for obs_idx in range(len(OBSERVABLES)):
            total["N"][obs_idx] += record["N"][obs_idx]  # type: ignore[index]
    return total


def subtract_record(total: dict[str, object], record: dict[str, object]) -> dict[str, object]:
    output = {
        "samples": int(total["samples"]) - int(record["samples"]),
        "D": total["D"] - record["D"],  # type: ignore[operator]
        "sum_abs_w": float(total["sum_abs_w"]) - float(record["sum_abs_w"]),
        "sum_abs_w2": float(total["sum_abs_w2"]) - float(record["sum_abs_w2"]),
        "N": list(total["N"]),  # type: ignore[arg-type]
    }
    for obs_idx in range(len(OBSERVABLES)):
        output["N"][obs_idx] -= record["N"][obs_idx]  # type: ignore[index]
    return output


def estimates(sums: dict[str, object]) -> list[complex]:
    return [value / sums["D"] for value in sums["N"]]  # type: ignore[operator]


def jk_se(values: list[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / n
    return math.sqrt((n - 1) / n * sum((value - mean) ** 2 for value in values))


def component(value: complex, part: str) -> float:
    return value.real if part == "re" else value.imag


def summarize(label: str, grouped: dict[int, list[Path]], max_samples: int | None) -> dict[str, object]:
    records = {
        rid: read_record(paths, max_samples)
        for rid, paths in grouped.items()
    }
    lengths = [int(row["samples"]) for row in records.values()]
    total = total_records(records)
    full_estimates = estimates(total)
    row: dict[str, object] = {
        "group": label,
        "seeds": len(records),
        "total_samples": int(total["samples"]),
        "min_samples_per_seed": min(lengths),
        "median_samples_per_seed": sorted(lengths)[len(lengths) // 2],
        "max_samples_per_seed": max(lengths),
        "phase": abs(total["D"]) / float(total["sum_abs_w"]),  # type: ignore[arg-type]
        "effN": abs(total["D"]) ** 2 / float(total["sum_abs_w2"]),  # type: ignore[arg-type]
    }

    phase_jk = []
    jk_estimates: list[list[complex]] = [[] for _ in OBSERVABLES]
    for record in records.values():
        leave = subtract_record(total, record)
        phase_jk.append(abs(leave["D"]) / float(leave["sum_abs_w"]))  # type: ignore[arg-type]
        leave_estimates = estimates(leave)
        for obs_idx, value in enumerate(leave_estimates):
            jk_estimates[obs_idx].append(value)
    row["phase_jk_err"] = jk_se(phase_jk)
    row["eff_frac"] = float(row["effN"]) / int(row["total_samples"])

    for obs_idx, observable in enumerate(OBSERVABLES):
        estimate = full_estimates[obs_idx]
        row[f"{observable}_re"] = estimate.real
        row[f"{observable}_im"] = estimate.imag
        for part in ("re", "im"):
            se = jk_se([component(value, part) for value in jk_estimates[obs_idx]])
            target = EXACT.get(observable, 0.0) if part == "re" else 0.0
            row[f"{observable}_{part}_se"] = se
            row[f"{observable}_{part}_z"] = (
                (component(estimate, part) - target) / se
                if observable in EXACT and se > 0.0
                else float("nan")
            )
    return row


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def fmt_pm(value: object, se: object) -> str:
    return f"`{float(value):.6f} +/- {float(se):.6f}`"


def fmt_z(value: object) -> str:
    return f"{float(value):+.3f}"


def write_markdown(path: Path, rows: list[dict[str, object]], metadata: dict[str, object]) -> None:
    lines = [
        "# Stephanov N6 Pooled Observable Data - 2026-05-29",
        "",
        "Scope: compare `nofb` and `withfb` using pooled estimators for "
        "Stephanov `n=6`, `mu=0.6`, `m=0.004`, TLTM ladder endpoint `t_high=0.03`.",
        "",
        "Exact values used:",
        "",
        "- chiral condensate: `0.0244771982754 + 0 i`",
        "- number density: `0.56611556665 + 0 i`",
        "",
        "Data roots:",
        "",
        f"- nofb 15k/equal-cost: `{metadata['nofb_root']}`",
        f"- withfb 5k: `{metadata['withfb_root']}`",
        "",
        "Pooled estimator method:",
        "",
        "- 512 seeds in each comparison.",
        "- Pooled estimator: `O_pool = sum_s sum_i phi_{s,i} O_{s,i} / sum_s sum_i phi_{s,i}`.",
        "- Errors are leave-one-seed jackknife errors on `O_pool`.",
        "- `z = (O_pool - exact) / jackknife_error`, real and imaginary parts separately.",
        f"- `nofb_same_config_size_as_withfb` truncates each nofb seed to `{metadata['same_config_size']}` samples.",
        "",
        "Sample and phase summary:",
        "",
        "| group | seeds | total samples | min samples/seed | median samples/seed | max samples/seed | phase | phase JK err | eff frac | effN |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| `{}` | {} | {:,} | {} | {} | {} | {:.6f} | {:.6f} | {:.6f} | {:.0f} |".format(
                row["group"],
                row["seeds"],
                row["total_samples"],
                row["min_samples_per_seed"],
                row["median_samples_per_seed"],
                row["max_samples_per_seed"],
                row["phase"],
                row["phase_jk_err"],
                row["eff_frac"],
                row["effN"],
            )
        )
    lines.extend(
        [
            "",
            "Pooled values:",
            "",
            "| group | chiral Re | chiral Im | density Re | density Im |",
            "|---|---:|---:|---:|---:|",
        ]
    )
    for row in rows:
        lines.append(
            "| `{}` | {} | {} | {} | {} |".format(
                row["group"],
                fmt_pm(row["chiral_condensate_re"], row["chiral_condensate_re_se"]),
                fmt_pm(row["chiral_condensate_im"], row["chiral_condensate_im_se"]),
                fmt_pm(row["number_density_re"], row["number_density_re_se"]),
                fmt_pm(row["number_density_im"], row["number_density_im_se"]),
            )
        )
    lines.extend(
        [
            "",
            "Pooled z values:",
            "",
            "| group | chiral Re z | chiral Im z | density Re z | density Im z |",
            "|---|---:|---:|---:|---:|",
        ]
    )
    for row in rows:
        lines.append(
            "| `{}` | {} | {} | {} | {} |".format(
                row["group"],
                fmt_z(row["chiral_condensate_re_z"]),
                fmt_z(row["chiral_condensate_im_z"]),
                fmt_z(row["number_density_re_z"]),
                fmt_z(row["number_density_im_z"]),
            )
        )
    lines.extend(
        [
            "",
            "Visual artifacts:",
            "",
            "- `z_convergence_curve.png`",
            "- `cumulative_estimator_trace.png`",
            "- `paired_method_delta_trace.png`",
            "- `block500_estimator_trace.png`",
            "- `combined_distance_trace.png`",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--withfb-root", required=True)
    parser.add_argument("--nofb-root", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    withfb_grouped = discover(Path(args.withfb_root), "withfb*")
    nofb_grouped = discover(Path(args.nofb_root), "nofb15*")
    withfb_lengths = [
        sum(path.stat().st_size // (8 * WIDTH) for path in paths)
        for paths in withfb_grouped.values()
    ]
    same_size = min(withfb_lengths)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = [
        summarize("nofb_all_available", nofb_grouped, None),
        summarize("withfb_all_available", withfb_grouped, None),
        summarize("nofb_same_config_size_as_withfb", nofb_grouped, same_size),
    ]
    metadata = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "withfb_root": args.withfb_root,
        "nofb_root": args.nofb_root,
        "same_config_size": same_size,
    }
    write_csv(out_dir / "observable_and_z_summary.csv", rows)
    write_markdown(out_dir / "STEPHANOV_N6_FINAL_OBSERVABLE_Z_20260529.md", rows, metadata)
    (out_dir / "observable_and_z_summary_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(out_dir)


if __name__ == "__main__":
    main()
