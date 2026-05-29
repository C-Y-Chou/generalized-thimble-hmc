#!/usr/bin/env python3
"""Write a z-only all-available observable report for current TLTM runs."""

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
EXACT_RE = {
    "chiral_condensate": 0.0244771983,
    "number_density": 0.5661155667,
}
WIDTH = 2 * (1 + len(OBSERVABLES))


def read_sums(path: Path) -> dict[str, object]:
    values = array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) % WIDTH != 0:
        raise RuntimeError(f"observable stream width mismatch: {path}")

    rows = len(values) // WIDTH
    denominator = complex(0.0, 0.0)
    numerators = [complex(0.0, 0.0) for _ in OBSERVABLES]
    for row_idx in range(rows):
        offset = row_idx * WIDTH
        weight = complex(float(values[offset]), float(values[offset + 1]))
        denominator += weight
        for obs_idx in range(len(OBSERVABLES)):
            obs_offset = offset + 2 + 2 * obs_idx
            obs_value = complex(float(values[obs_offset]), float(values[obs_offset + 1]))
            numerators[obs_idx] += weight * obs_value
    return {"samples": rows, "D": denominator, "N": numerators}


def record_id(path: Path) -> int:
    return int(path.parent.name.rsplit("_", 1)[1])


def discover(root: Path, topdir_prefix: str) -> dict[int, list[Path]]:
    grouped: dict[int, list[Path]] = {}
    for path in sorted(root.glob(f"{topdir_prefix}*/records/record_*/observable_history.dat")):
        grouped.setdefault(record_id(path), []).append(path)
    return grouped


def aggregate_records(paths_by_record: dict[int, list[Path]]) -> dict[str, object]:
    records = {}
    for rid, paths in sorted(paths_by_record.items()):
        denominator = complex(0.0, 0.0)
        numerators = [complex(0.0, 0.0) for _ in OBSERVABLES]
        samples = 0
        for path in paths:
            sums = read_sums(path)
            denominator += sums["D"]  # type: ignore[operator]
            samples += int(sums["samples"])
            for obs_idx, value in enumerate(sums["N"]):  # type: ignore[union-attr]
                numerators[obs_idx] += value
        records[rid] = {"samples": samples, "D": denominator, "N": numerators}

    total_d = sum((row["D"] for row in records.values()), complex(0.0, 0.0))  # type: ignore[misc]
    total_n = [
        sum((row["N"][obs_idx] for row in records.values()), complex(0.0, 0.0))  # type: ignore[index]
        for obs_idx in range(len(OBSERVABLES))
    ]
    estimates = [numerator / total_d for numerator in total_n]

    jackknife: list[list[complex]] = [[] for _ in OBSERVABLES]
    for row in records.values():
        d_leave = total_d - row["D"]  # type: ignore[operator]
        for obs_idx in range(len(OBSERVABLES)):
            n_leave = total_n[obs_idx] - row["N"][obs_idx]  # type: ignore[index]
            jackknife[obs_idx].append(n_leave / d_leave)

    return {
        "records": records,
        "total_samples": sum(int(row["samples"]) for row in records.values()),
        "estimates": estimates,
        "jackknife": jackknife,
    }


def jk_se(values: list[complex], part: str) -> float:
    components = [getattr(value, part) for value in values]
    n = len(components)
    if n < 2:
        return float("nan")
    mean = sum(components) / n
    return math.sqrt((n - 1) / n * sum((value - mean) ** 2 for value in components))


def z_row(method: str, aggregate: dict[str, object]) -> dict[str, object]:
    estimates = aggregate["estimates"]  # type: ignore[assignment]
    jackknife = aggregate["jackknife"]  # type: ignore[assignment]
    chiral_idx = OBSERVABLES.index("chiral_condensate")
    density_idx = OBSERVABLES.index("number_density")

    chiral = estimates[chiral_idx]
    density = estimates[density_idx]
    chiral_se_re = jk_se(jackknife[chiral_idx], "real")
    chiral_se_im = jk_se(jackknife[chiral_idx], "imag")
    density_se_re = jk_se(jackknife[density_idx], "real")
    density_se_im = jk_se(jackknife[density_idx], "imag")

    return {
        "method": method,
        "records": len(aggregate["records"]),  # type: ignore[arg-type]
        "samples": int(aggregate["total_samples"]),
        "z_chiral_condensate_Re": (chiral.real - EXACT_RE["chiral_condensate"]) / chiral_se_re,
        "z_chiral_condensate_Im": chiral.imag / chiral_se_im,
        "z_number_density_Re": (density.real - EXACT_RE["number_density"]) / density_se_re,
        "z_number_density_Im": density.imag / density_se_im,
    }


def fmt_z(value: object) -> str:
    return f"{float(value):.3f}"


def write_markdown(path: Path, rows: list[dict[str, object]], metadata: dict[str, object]) -> None:
    lines = [
        "# Observable Z Only, All Available",
        "",
        "| method | records | samples | z chiral Re | z chiral Im | z density Re | z density Im |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["method"]),
                    str(row["records"]),
                    str(row["samples"]),
                    fmt_z(row["z_chiral_condensate_Re"]),
                    fmt_z(row["z_chiral_condensate_Im"]),
                    fmt_z(row["z_number_density_Re"]),
                    fmt_z(row["z_number_density_Im"]),
                ]
            )
            + " |"
        )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--withfb-root", required=True)
    parser.add_argument("--nofb-root", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    withfb_root = Path(args.withfb_root)
    nofb_root = Path(args.nofb_root)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    datasets = [
        ("withfb", withfb_root, "withfb"),
        ("nofb", nofb_root, "nofb15"),
    ]
    rows = []
    inventory = []
    for method, root, prefix in datasets:
        paths_by_record = discover(root, prefix)
        aggregate = aggregate_records(paths_by_record)
        rows.append(z_row(method, aggregate))
        inventory.append(
            {
                "method": method,
                "root": str(root),
                "topdir_prefix": prefix,
                "records": len(paths_by_record),
                "segments": sum(len(paths) for paths in paths_by_record.values()),
                "samples": int(aggregate["total_samples"]),
            }
        )

    metadata = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "cut": "all_available_observable_history_rows",
        "inventory": inventory,
    }

    with (out_dir / "observable_z_only_all_available.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    write_markdown(out_dir / "observable_z_only_all_available.md", rows, metadata)
    (out_dir / "observable_z_only_all_available_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(out_dir)


if __name__ == "__main__":
    main()
