#!/usr/bin/env python3
"""Build four-observable z-score convergence curves for current Stephanov n=6 data."""

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
FOUR_Z = [
    ("chiral_condensate", "Re", "chiral_Re_z"),
    ("chiral_condensate", "Im", "chiral_Im_z"),
    ("number_density", "Re", "density_Re_z"),
    ("number_density", "Im", "density_Im_z"),
]


def record_id(path: Path) -> int:
    return int(path.parent.name.rsplit("_", 1)[1])


def stage_name(path: Path) -> str:
    return path.parts[-4]


def discover(root: Path, patterns: list[str]) -> dict[int, list[Path]]:
    grouped: dict[int, list[Path]] = {}
    for pattern in patterns:
        for path in root.glob(f"{pattern}/records/record_*/observable_history.dat"):
            grouped.setdefault(record_id(path), []).append(path)
    for paths in grouped.values():
        paths.sort(key=lambda path: (stage_name(path), str(path)))
    return dict(sorted(grouped.items()))


def empty_sums() -> dict[str, object]:
    return {
        "samples": 0,
        "D": complex(0.0, 0.0),
        "sum_abs_w": 0.0,
        "sum_abs_w2": 0.0,
        "N": [complex(0.0, 0.0) for _ in OBSERVABLES],
    }


def copy_sums(value: dict[str, object]) -> dict[str, object]:
    return {
        "samples": int(value["samples"]),
        "D": value["D"],
        "sum_abs_w": float(value["sum_abs_w"]),
        "sum_abs_w2": float(value["sum_abs_w2"]),
        "N": list(value["N"]),  # type: ignore[arg-type]
    }


def add_row(sums: dict[str, object], row_values: array, offset: int) -> None:
    weight = complex(float(row_values[offset]), float(row_values[offset + 1]))
    sums["samples"] = int(sums["samples"]) + 1
    sums["D"] = sums["D"] + weight  # type: ignore[operator]
    abs_w = abs(weight)
    sums["sum_abs_w"] = float(sums["sum_abs_w"]) + abs_w
    sums["sum_abs_w2"] = float(sums["sum_abs_w2"]) + abs_w * abs_w
    for obs_idx in range(len(OBSERVABLES)):
        obs_offset = offset + 2 + 2 * obs_idx
        obs_value = complex(float(row_values[obs_offset]), float(row_values[obs_offset + 1]))
        sums["N"][obs_idx] += weight * obs_value  # type: ignore[index]


def record_prefix_sums(paths: list[Path], cuts: list[int]) -> tuple[dict[int, dict[str, object]], dict[str, object]]:
    needed = sorted(set(cuts))
    cut_idx = 0
    current = empty_sums()
    outputs: dict[int, dict[str, object]] = {}

    for path in paths:
        values = array("d")
        with path.open("rb") as handle:
            values.fromfile(handle, path.stat().st_size // 8)
        if len(values) % WIDTH != 0:
            raise RuntimeError(f"observable stream width mismatch: {path}")
        rows = len(values) // WIDTH
        for row_idx in range(rows):
            add_row(current, values, row_idx * WIDTH)
            while cut_idx < len(needed) and int(current["samples"]) == needed[cut_idx]:
                outputs[needed[cut_idx]] = copy_sums(current)
                cut_idx += 1
    return outputs, current


def jk_se(values: list[complex], part: str) -> float:
    components = [getattr(value, part) for value in values]
    n = len(components)
    if n < 2:
        return float("nan")
    mean = sum(components) / n
    return math.sqrt((n - 1) / n * sum((value - mean) ** 2 for value in components))


def jk_se_float(values: list[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / n
    return math.sqrt((n - 1) / n * sum((value - mean) ** 2 for value in values))


def summarize(method: str, cut_label: str, x_value: float, records: dict[int, dict[str, object]]) -> dict[str, object]:
    total_d = sum((row["D"] for row in records.values()), complex(0.0, 0.0))  # type: ignore[misc]
    total_abs = sum(float(row["sum_abs_w"]) for row in records.values())
    total_abs2 = sum(float(row["sum_abs_w2"]) for row in records.values())
    total_n = [
        sum((row["N"][obs_idx] for row in records.values()), complex(0.0, 0.0))  # type: ignore[index]
        for obs_idx in range(len(OBSERVABLES))
    ]
    estimates = [value / total_d for value in total_n]

    jk_estimates: list[list[complex]] = [[] for _ in OBSERVABLES]
    jk_phase = []
    for row in records.values():
        d_leave = total_d - row["D"]  # type: ignore[operator]
        abs_leave = total_abs - float(row["sum_abs_w"])
        jk_phase.append(abs(d_leave) / abs_leave if abs_leave > 0.0 else float("nan"))
        for obs_idx in range(len(OBSERVABLES)):
            n_leave = total_n[obs_idx] - row["N"][obs_idx]  # type: ignore[index]
            jk_estimates[obs_idx].append(n_leave / d_leave)

    row: dict[str, object] = {
        "method": method,
        "cut": cut_label,
        "x_cycle": x_value,
        "seeds": len(records),
        "samples_total": sum(int(value["samples"]) for value in records.values()),
        "phase": abs(total_d) / total_abs if total_abs > 0.0 else float("nan"),
        "phase_jk_err": jk_se_float(jk_phase),
        "eff_n": abs(total_d) ** 2 / total_abs2 if total_abs2 > 0.0 else float("nan"),
    }
    for obs_idx, observable in enumerate(OBSERVABLES):
        estimate = estimates[obs_idx]
        se_re = jk_se(jk_estimates[obs_idx], "real")
        se_im = jk_se(jk_estimates[obs_idx], "imag")
        row[f"{observable}_re"] = estimate.real
        row[f"{observable}_im"] = estimate.imag
        row[f"{observable}_se_re"] = se_re
        row[f"{observable}_se_im"] = se_im
        exact = EXACT.get(observable)
        row[f"{observable}_z_re"] = (estimate.real - exact) / se_re if exact is not None and se_re > 0.0 else float("nan")
        row[f"{observable}_z_im"] = estimate.imag / se_im if se_im > 0.0 else float("nan")
    row["chiral_Re_z"] = row["chiral_condensate_z_re"]
    row["chiral_Im_z"] = row["chiral_condensate_z_im"]
    row["density_Re_z"] = row["number_density_z_re"]
    row["density_Im_z"] = row["number_density_z_im"]
    return row


def prefix_grid(max_prefix: int) -> list[int]:
    cuts = set()
    for value in range(250, min(max_prefix, 3000) + 1, 250):
        cuts.add(value)
    for value in range(3500, max_prefix + 1, 500):
        cuts.add(value)
    cuts.add(max_prefix)
    return sorted(value for value in cuts if value <= max_prefix)


def build_method_rows(method: str, grouped: dict[int, list[Path]]) -> tuple[list[dict[str, object]], dict[str, object]]:
    lengths = {
        rid: sum(path.stat().st_size // (8 * WIDTH) for path in paths)
        for rid, paths in grouped.items()
    }
    common_max = min(lengths.values())
    cuts = prefix_grid(common_max)
    by_cut: dict[int, dict[int, dict[str, object]]] = {cut: {} for cut in cuts}
    all_records: dict[int, dict[str, object]] = {}
    for rid, paths in grouped.items():
        prefix_values, all_value = record_prefix_sums(paths, cuts)
        for cut in cuts:
            if cut in prefix_values:
                by_cut[cut][rid] = prefix_values[cut]
        all_records[rid] = all_value

    rows = [
        summarize(method, f"prefix_{cut}", float(cut), by_cut[cut])
        for cut in cuts
        if len(by_cut[cut]) == len(grouped)
    ]
    mean_samples = sum(lengths.values()) / len(lengths)
    rows.append(summarize(method, "all_available_endpoint", mean_samples, all_records))
    metadata = {
        "records": len(grouped),
        "common_max_prefix": common_max,
        "samples_min": min(lengths.values()),
        "samples_median": sorted(lengths.values())[len(lengths) // 2],
        "samples_max": max(lengths.values()),
        "samples_total": sum(lengths.values()),
    }
    return rows, metadata


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_dat(path: Path, rows: list[dict[str, object]], method: str) -> None:
    fields = ["x_cycle", "chiral_Re_z", "chiral_Im_z", "density_Re_z", "density_Im_z"]
    with path.open("w", encoding="utf-8") as handle:
        handle.write("# " + " ".join(fields) + "\n")
        for row in rows:
            if row["method"] == method and str(row["cut"]).startswith("prefix_"):
                handle.write(" ".join(f"{float(row[field]):.12g}" for field in fields) + "\n")


def write_endpoint_dat(path: Path, rows: list[dict[str, object]], method: str) -> None:
    fields = ["x_cycle", "chiral_Re_z", "chiral_Im_z", "density_Re_z", "density_Im_z"]
    with path.open("w", encoding="utf-8") as handle:
        handle.write("# " + " ".join(fields) + "\n")
        for row in rows:
            if row["method"] == method and row["cut"] == "all_available_endpoint":
                handle.write(" ".join(f"{float(row[field]):.12g}" for field in fields) + "\n")


def write_gnuplot(path: Path, out_png: Path) -> None:
    path.write_text(
        f"""set terminal pngcairo size 1400,900 enhanced font 'Arial,12'
set output '{out_png}'
set datafile commentschars '#'
set grid
set key top left
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set ylabel 'z'
set multiplot layout 2,2 title 'Stephanov n=6 TLTM four-z convergence'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 1.0
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 1.0
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.5
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.5
plot 'withfb_prefix.dat' using 1:2 with lines ls 1 title 'withfb common prefix', \\
     'nofb_prefix.dat' using 1:2 with lines ls 2 title 'nofb common prefix', \\
     'withfb_endpoint.dat' using 1:2 with points ls 3 title 'withfb all available', \\
     'nofb_endpoint.dat' using 1:2 with points ls 4 title 'nofb all available'
set title 'chiral Im z'
plot 'withfb_prefix.dat' using 1:3 with lines ls 1 title 'withfb common prefix', \\
     'nofb_prefix.dat' using 1:3 with lines ls 2 title 'nofb common prefix', \\
     'withfb_endpoint.dat' using 1:3 with points ls 3 title 'withfb all available', \\
     'nofb_endpoint.dat' using 1:3 with points ls 4 title 'nofb all available'
set title 'density Re z'
plot 'withfb_prefix.dat' using 1:4 with lines ls 1 title 'withfb common prefix', \\
     'nofb_prefix.dat' using 1:4 with lines ls 2 title 'nofb common prefix', \\
     'withfb_endpoint.dat' using 1:4 with points ls 3 title 'withfb all available', \\
     'nofb_endpoint.dat' using 1:4 with points ls 4 title 'nofb all available'
set title 'density Im z'
plot 'withfb_prefix.dat' using 1:5 with lines ls 1 title 'withfb common prefix', \\
     'nofb_prefix.dat' using 1:5 with lines ls 2 title 'nofb common prefix', \\
     'withfb_endpoint.dat' using 1:5 with points ls 3 title 'withfb all available', \\
     'nofb_endpoint.dat' using 1:5 with points ls 4 title 'nofb all available'
unset multiplot
""",
        encoding="utf-8",
    )


def fmt_z(value: object) -> str:
    number = float(value)
    return f"{number:+.3f}"


def write_markdown(path: Path, rows: list[dict[str, object]], metadata: dict[str, object]) -> None:
    selected = []
    for row in rows:
        if row["cut"] == "all_available_endpoint" or float(row["x_cycle"]) in {
            500.0,
            1000.0,
            1500.0,
            2000.0,
            2500.0,
            3000.0,
            3500.0,
            float(metadata["withfb"]["common_max_prefix"]),
            5000.0,
            7500.0,
            10000.0,
            float(metadata["nofb"]["common_max_prefix"]),
        }:
            selected.append(row)
    lines = [
        "# Stephanov N6 Four-Z Convergence - 2026-05-28",
        "",
        "Common-prefix rows use the same prefix length for all 512 seeds in that method.",
        "The all-available endpoint uses the current live data with `x_cycle = mean samples per seed`.",
        "",
        f"withfb common-prefix max: `{metadata['withfb']['common_max_prefix']}`",
        f"nofb common-prefix max: `{metadata['nofb']['common_max_prefix']}`",
        "",
        "Selected z rows:",
        "",
        "| method | cut | x cycle | seeds | samples | chiral Re z | chiral Im z | density Re z | density Im z |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in selected:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["method"]),
                    str(row["cut"]),
                    f"{float(row['x_cycle']):.1f}",
                    str(row["seeds"]),
                    f"{int(row['samples_total']):,}",
                    fmt_z(row["chiral_Re_z"]),
                    fmt_z(row["chiral_Im_z"]),
                    fmt_z(row["density_Re_z"]),
                    fmt_z(row["density_Im_z"]),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "Artifacts:",
            "",
            "- `z_convergence_curve.csv`",
            "- `z_convergence_curve.png`",
            "- `withfb_prefix.dat`, `nofb_prefix.dat`",
            "- `withfb_endpoint.dat`, `nofb_endpoint.dat`",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--withfb-root", required=True)
    parser.add_argument("--nofb-root", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    withfb = discover(Path(args.withfb_root), ["withfb*"])
    nofb = discover(Path(args.nofb_root), ["nofb15*"])
    rows_withfb, meta_withfb = build_method_rows("withfb", withfb)
    rows_nofb, meta_nofb = build_method_rows("nofb", nofb)
    rows = rows_withfb + rows_nofb
    metadata = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "withfb_root": args.withfb_root,
        "nofb_root": args.nofb_root,
        "withfb": meta_withfb,
        "nofb": meta_nofb,
    }

    write_csv(out_dir / "z_convergence_curve.csv", rows)
    write_dat(out_dir / "withfb_prefix.dat", rows, "withfb")
    write_dat(out_dir / "nofb_prefix.dat", rows, "nofb")
    write_endpoint_dat(out_dir / "withfb_endpoint.dat", rows, "withfb")
    write_endpoint_dat(out_dir / "nofb_endpoint.dat", rows, "nofb")
    write_gnuplot(out_dir / "plot_z_convergence.gp", out_dir / "z_convergence_curve.png")
    write_markdown(out_dir / "README.md", rows, metadata)
    (out_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(out_dir)


if __name__ == "__main__":
    main()
