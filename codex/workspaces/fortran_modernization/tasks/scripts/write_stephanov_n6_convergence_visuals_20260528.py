#!/usr/bin/env python3
"""Generate higher-discrimination convergence visuals for Stephanov n=6 runs."""

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
COMPONENTS = [
    ("chiral_condensate", "Re", "chiral_Re", 0.0244771982754),
    ("chiral_condensate", "Im", "chiral_Im", 0.0),
    ("number_density", "Re", "density_Re", 0.56611556665),
    ("number_density", "Im", "density_Im", 0.0),
]
WIDTH = 2 * (1 + len(OBSERVABLES))


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


def clone(value: dict[str, object]) -> dict[str, object]:
    return {
        "samples": int(value["samples"]),
        "D": value["D"],
        "sum_abs_w": float(value["sum_abs_w"]),
        "sum_abs_w2": float(value["sum_abs_w2"]),
        "N": list(value["N"]),  # type: ignore[arg-type]
    }


def add_row(value: dict[str, object], data: array, offset: int) -> None:
    weight = complex(float(data[offset]), float(data[offset + 1]))
    value["samples"] = int(value["samples"]) + 1
    value["D"] = value["D"] + weight  # type: ignore[operator]
    abs_weight = abs(weight)
    value["sum_abs_w"] = float(value["sum_abs_w"]) + abs_weight
    value["sum_abs_w2"] = float(value["sum_abs_w2"]) + abs_weight * abs_weight
    for obs_idx in range(len(OBSERVABLES)):
        obs_offset = offset + 2 + 2 * obs_idx
        obs = complex(float(data[obs_offset]), float(data[obs_offset + 1]))
        value["N"][obs_idx] += weight * obs  # type: ignore[index]


def add_sums(left: dict[str, object], right: dict[str, object]) -> None:
    left["samples"] = int(left["samples"]) + int(right["samples"])
    left["D"] = left["D"] + right["D"]  # type: ignore[operator]
    left["sum_abs_w"] = float(left["sum_abs_w"]) + float(right["sum_abs_w"])
    left["sum_abs_w2"] = float(left["sum_abs_w2"]) + float(right["sum_abs_w2"])
    for obs_idx, item in enumerate(right["N"]):  # type: ignore[union-attr]
        left["N"][obs_idx] += item  # type: ignore[index]


def subtract_sums(left: dict[str, object], right: dict[str, object]) -> dict[str, object]:
    output = clone(left)
    output["samples"] = int(output["samples"]) - int(right["samples"])
    output["D"] = output["D"] - right["D"]  # type: ignore[operator]
    output["sum_abs_w"] = float(output["sum_abs_w"]) - float(right["sum_abs_w"])
    output["sum_abs_w2"] = float(output["sum_abs_w2"]) - float(right["sum_abs_w2"])
    for obs_idx in range(len(OBSERVABLES)):
        output["N"][obs_idx] -= right["N"][obs_idx]  # type: ignore[index]
    return output


def stream_record(paths: list[Path], boundaries: set[int]) -> dict[object, dict[str, object]]:
    snapshots: dict[object, dict[str, object]] = {}
    current = empty_sums()
    count = 0
    needed = sorted(boundary for boundary in boundaries if boundary > 0)
    idx = 0
    for path in paths:
        data = array("d")
        with path.open("rb") as handle:
            data.fromfile(handle, path.stat().st_size // 8)
        if len(data) % WIDTH != 0:
            raise RuntimeError(f"observable stream width mismatch: {path}")
        for row_idx in range(len(data) // WIDTH):
            count += 1
            add_row(current, data, row_idx * WIDTH)
            while idx < len(needed) and count == needed[idx]:
                snapshots[needed[idx]] = clone(current)
                idx += 1
    snapshots["all"] = clone(current)
    snapshots["total"] = {"samples": count}
    return snapshots


def build_cache(grouped: dict[int, list[Path]], boundaries: set[int]) -> dict[int, dict[object, dict[str, object]]]:
    return {rid: stream_record(paths, boundaries) for rid, paths in grouped.items()}


def slice_group(cache: dict[int, dict[object, dict[str, object]]], start: int, stop: int | str) -> dict[int, dict[str, object]]:
    records: dict[int, dict[str, object]] = {}
    for rid, snapshots in cache.items():
        if stop not in snapshots:
            continue
        right = snapshots[stop]
        left = empty_sums() if start == 0 else snapshots.get(start)
        if left is None:
            continue
        value = subtract_sums(right, left)
        if int(value["samples"]) > 0:
            records[rid] = value
    return records


def total_sums(records: dict[int, dict[str, object]]) -> dict[str, object]:
    total = empty_sums()
    for item in records.values():
        add_sums(total, item)
    return total


def estimates(value: dict[str, object]) -> list[complex]:
    if abs(value["D"]) == 0.0:  # type: ignore[arg-type]
        return [complex(float("nan"), float("nan")) for _ in OBSERVABLES]
    return [item / value["D"] for item in value["N"]]  # type: ignore[operator]


def component_value(est: list[complex], observable: str, part: str) -> float:
    value = est[OBSERVABLES.index(observable)]
    return value.real if part == "Re" else value.imag


def jk_se(values: list[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / n
    return math.sqrt((n - 1) / n * sum((value - mean) ** 2 for value in values))


def summarize(label: str, method: str, cut: str, x_value: float, records: dict[int, dict[str, object]]) -> dict[str, object]:
    total = total_sums(records)
    full_est = estimates(total)
    row: dict[str, object] = {
        "label": label,
        "method": method,
        "cut": cut,
        "x_cycle": x_value,
        "seeds": len(records),
        "samples": sum(int(value["samples"]) for value in records.values()),
        "phase": abs(total["D"]) / float(total["sum_abs_w"]) if float(total["sum_abs_w"]) > 0.0 else float("nan"),  # type: ignore[arg-type]
    }
    z_values = []
    for observable, part, short, target in COMPONENTS:
        estimate = component_value(full_est, observable, part)
        jk = []
        for record in records.values():
            leave = subtract_sums(total, record)
            jk.append(component_value(estimates(leave), observable, part))
        se = jk_se(jk)
        z = (estimate - target) / se if se > 0.0 else float("nan")
        row[f"{short}_estimate"] = estimate
        row[f"{short}_se"] = se
        row[f"{short}_target"] = target
        row[f"{short}_z"] = z
        z_values.append(z)
    row["rms_z"] = math.sqrt(sum(value * value for value in z_values) / len(z_values))
    row["max_abs_z"] = max(abs(value) for value in z_values)
    return row


def paired_delta(label: str, x_value: float, left: dict[int, dict[str, object]], right: dict[int, dict[str, object]]) -> dict[str, object]:
    ids = sorted(set(left) & set(right))
    left = {rid: left[rid] for rid in ids}
    right = {rid: right[rid] for rid in ids}
    left_total = total_sums(left)
    right_total = total_sums(right)
    left_est = estimates(left_total)
    right_est = estimates(right_total)
    row: dict[str, object] = {
        "label": label,
        "x_cycle": x_value,
        "seeds": len(ids),
        "samples_left": sum(int(item["samples"]) for item in left.values()),
        "samples_right": sum(int(item["samples"]) for item in right.values()),
    }
    delta_z_values = []
    for observable, part, short, _target in COMPONENTS:
        left_value = component_value(left_est, observable, part)
        right_value = component_value(right_est, observable, part)
        delta = left_value - right_value
        jk = []
        for rid in ids:
            left_leave = subtract_sums(left_total, left[rid])
            right_leave = subtract_sums(right_total, right[rid])
            jk.append(component_value(estimates(left_leave), observable, part) - component_value(estimates(right_leave), observable, part))
        se = jk_se(jk)
        z = delta / se if se > 0.0 else float("nan")
        row[f"{short}_delta"] = delta
        row[f"{short}_se"] = se
        row[f"{short}_z_delta"] = z
        delta_z_values.append(z)
    row["rms_z_delta"] = math.sqrt(sum(value * value for value in delta_z_values) / len(delta_z_values))
    row["max_abs_z_delta"] = max(abs(value) for value in delta_z_values)
    return row


def prefix_grid(max_prefix: int) -> list[int]:
    cuts = set()
    for value in range(500, min(max_prefix, 3000) + 1, 250):
        cuts.add(value)
    for value in range(3500, max_prefix + 1, 500):
        cuts.add(value)
    cuts.add(max_prefix)
    return sorted(cut for cut in cuts if 0 < cut <= max_prefix)


def block_boundaries(max_prefix: int) -> list[tuple[int, int]]:
    bounds = []
    for start in range(0, max_prefix, 500):
        stop = min(start + 500, max_prefix)
        if stop - start >= 250:
            bounds.append((start, stop))
    return bounds


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_xyse(path: Path, rows: list[dict[str, object]], y_key: str, se_key: str, row_filter) -> None:
    with path.open("w", encoding="utf-8") as handle:
        handle.write("# x y se\n")
        for row in rows:
            if row_filter(row):
                handle.write(f"{float(row['x_cycle']):.12g} {float(row[y_key]):.12g} {float(row[se_key]):.12g}\n")


def write_distance(path: Path, rows: list[dict[str, object]], row_filter, rms_key: str, max_key: str) -> None:
    with path.open("w", encoding="utf-8") as handle:
        handle.write("# x rms maxabs\n")
        for row in rows:
            if row_filter(row):
                handle.write(f"{float(row['x_cycle']):.12g} {float(row[rms_key]):.12g} {float(row[max_key]):.12g}\n")


def write_component_data(out_dir: Path, cumulative: list[dict[str, object]], delta: list[dict[str, object]], block: list[dict[str, object]]) -> None:
    for _observable, _part, short, _target in COMPONENTS:
        for method in ["withfb", "nofb"]:
            write_xyse(
                out_dir / f"cumulative_{method}_{short}.dat",
                cumulative,
                f"{short}_estimate",
                f"{short}_se",
                lambda row, method=method: row["method"] == method and str(row["cut"]).startswith("prefix_"),
            )
            write_xyse(
                out_dir / f"cumulative_endpoint_{method}_{short}.dat",
                cumulative,
                f"{short}_estimate",
                f"{short}_se",
                lambda row, method=method: row["method"] == method and row["cut"] == "all_available_endpoint",
            )
            write_xyse(
                out_dir / f"block500_{method}_{short}.dat",
                block,
                f"{short}_estimate",
                f"{short}_se",
                lambda row, method=method: row["method"] == method,
            )
        write_xyse(
            out_dir / f"paired_delta_{short}.dat",
            delta,
            f"{short}_delta",
            f"{short}_se",
            lambda _row: True,
        )
        write_xyse(
            out_dir / f"paired_delta_endpoint_{short}.dat",
            delta,
            f"{short}_delta",
            f"{short}_se",
            lambda row: row["label"] == "all_available_withfb_minus_nofb_matched",
        )


def write_gnuplot_scripts(out_dir: Path) -> None:
    panel_specs = [
        ("chiral_Re", "chiral Re", 0.0244771982754),
        ("chiral_Im", "chiral Im", 0.0),
        ("density_Re", "density Re", 0.56611556665),
        ("density_Im", "density Im", 0.0),
    ]

    def multiplot_body(kind: str) -> str:
        chunks = []
        for short, title, target in panel_specs:
            if kind == "cumulative":
                chunks.append(
                    f"""set title '{title}'
target={target:.15g}
plot target with lines lc rgb '#444444' dt 2 title 'target', \\
     'cumulative_withfb_{short}.dat' using 1:2:3 with yerrorlines ls 1 title 'withfb prefix', \\
     'cumulative_nofb_{short}.dat' using 1:2:3 with yerrorlines ls 2 title 'nofb prefix', \\
     'cumulative_endpoint_withfb_{short}.dat' using 1:2:3 with yerrorbars ls 3 title 'withfb all', \\
     'cumulative_endpoint_nofb_{short}.dat' using 1:2:3 with yerrorbars ls 4 title 'nofb all'
"""
                )
            elif kind == "delta":
                chunks.append(
                    f"""set title '{title}'
plot 0 with lines lc rgb '#444444' dt 2 title 'zero', \\
     'paired_delta_{short}.dat' using 1:2:3 with yerrorlines ls 5 title 'withfb-nofb prefix', \\
     'paired_delta_endpoint_{short}.dat' using 1:2:3 with yerrorbars ls 6 title 'withfb all - nofb matched'
"""
                )
            else:
                chunks.append(
                    f"""set title '{title}'
target={target:.15g}
plot target with lines lc rgb '#444444' dt 2 title 'target', \\
     'block500_withfb_{short}.dat' using 1:2:3 with yerrorlines ls 1 title 'withfb block', \\
     'block500_nofb_{short}.dat' using 1:2:3 with yerrorlines ls 2 title 'nofb block'
"""
                )
        return "\n".join(chunks)

    common_header = """set terminal pngcairo size 1500,950 enhanced font 'Arial,12'
set datafile commentschars '#'
set grid
set key outside right center
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 0.7
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 0.7
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.4
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.4
set style line 5 lc rgb '#2ca02c' lw 2 pt 7 ps 0.7
set style line 6 lc rgb '#2ca02c' lw 0 pt 9 ps 1.4
"""
    for kind, title, output in [
        ("cumulative", "Cumulative estimator traces", "cumulative_estimator_trace.png"),
        ("delta", "Paired method delta traces", "paired_method_delta_trace.png"),
        ("block", "Block500 estimator traces", "block500_estimator_trace.png"),
    ]:
        (out_dir / f"plot_{kind}.gp").write_text(
            common_header
            + f"set output '{output}'\n"
            + f"set multiplot layout 2,2 title '{title}'\n"
            + multiplot_body(kind)
            + "unset multiplot\n",
            encoding="utf-8",
        )

    (out_dir / "plot_distance.gp").write_text(
        """set terminal pngcairo size 1200,650 enhanced font 'Arial,12'
set output 'combined_distance_trace.png'
set datafile commentschars '#'
set grid
set key top right
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set ylabel 'combined four-z distance'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 0.8
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 0.8
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.5
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.5
plot 'distance_withfb_prefix.dat' using 1:2 with linespoints ls 1 title 'withfb RMS z', \\
     'distance_nofb_prefix.dat' using 1:2 with linespoints ls 2 title 'nofb RMS z', \\
     'distance_withfb_endpoint.dat' using 1:2 with points ls 3 title 'withfb all RMS z', \\
     'distance_nofb_endpoint.dat' using 1:2 with points ls 4 title 'nofb all RMS z'
""",
        encoding="utf-8",
    )


def fmt(value: object, digits: int = 3, signed: bool = True) -> str:
    number = float(value)
    return f"{'+' if signed and number >= 0 else ''}{number:.{digits}f}"


def write_readme(out_dir: Path, cumulative: list[dict[str, object]], delta: list[dict[str, object]], meta: dict[str, object]) -> None:
    selected = [
        row
        for row in cumulative
        if row["cut"] == "all_available_endpoint"
        or float(row["x_cycle"]) in {500.0, 1000.0, 1500.0, 2500.0, 3500.0, 5000.0, 7500.0, 10000.0, float(meta["withfb_common_max"]), float(meta["nofb_common_max"])}
    ]
    lines = [
        "# Stephanov N6 Convergence Visuals - 2026-05-28",
        "",
        "Generated plots:",
        "",
        "- `cumulative_estimator_trace.png`",
        "- `paired_method_delta_trace.png`",
        "- `block500_estimator_trace.png`",
        "- `combined_distance_trace.png`",
        "",
        f"withfb common max prefix: `{meta['withfb_common_max']}`",
        f"nofb common max prefix: `{meta['nofb_common_max']}`",
        "",
        "Selected cumulative rows:",
        "",
        "| method | cut | x | samples | chiral Re z | chiral Im z | density Re z | density Im z | RMS z | max |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in selected:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["method"]),
                    str(row["cut"]),
                    f"{float(row['x_cycle']):.1f}",
                    f"{int(row['samples']):,}",
                    fmt(row["chiral_Re_z"]),
                    fmt(row["chiral_Im_z"]),
                    fmt(row["density_Re_z"]),
                    fmt(row["density_Im_z"]),
                    fmt(row["rms_z"], signed=False),
                    fmt(row["max_abs_z"], signed=False),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "Selected paired deltas:",
            "",
            "| label | x | chiral Re delta z | chiral Im delta z | density Re delta z | density Im delta z | RMS delta z |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for row in delta:
        if row["label"] == "all_available_withfb_minus_nofb_matched" or float(row["x_cycle"]) in {1500.0, 2500.0, float(meta["withfb_common_max"])}:
            lines.append(
                "| "
                + " | ".join(
                    [
                        str(row["label"]),
                        f"{float(row['x_cycle']):.1f}",
                        fmt(row["chiral_Re_z_delta"]),
                        fmt(row["chiral_Im_z_delta"]),
                        fmt(row["density_Re_z_delta"]),
                        fmt(row["density_Im_z_delta"]),
                        fmt(row["rms_z_delta"], signed=False),
                    ]
                )
                + " |"
            )
    (out_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--withfb-root", required=True)
    parser.add_argument("--nofb-root", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    withfb_grouped = discover(Path(args.withfb_root), ["withfb*"])
    nofb_grouped = discover(Path(args.nofb_root), ["nofb15*"])
    withfb_lengths = {rid: sum(path.stat().st_size // (8 * WIDTH) for path in paths) for rid, paths in withfb_grouped.items()}
    nofb_lengths = {rid: sum(path.stat().st_size // (8 * WIDTH) for path in paths) for rid, paths in nofb_grouped.items()}
    withfb_common = min(withfb_lengths.values())
    nofb_common = min(nofb_lengths.values())
    withfb_prefixes = prefix_grid(withfb_common)
    nofb_prefixes = prefix_grid(nofb_common)
    pair_prefixes = prefix_grid(withfb_common)

    withfb_block_bounds = block_boundaries(withfb_common)
    nofb_block_bounds = block_boundaries(nofb_common)
    withfb_boundaries = set(withfb_prefixes)
    nofb_boundaries = set(nofb_prefixes) | set(pair_prefixes) | set(withfb_lengths.values())
    withfb_boundaries.update(value for pair in withfb_block_bounds for value in pair)
    nofb_boundaries.update(value for pair in nofb_block_bounds for value in pair)

    withfb_cache = build_cache(withfb_grouped, withfb_boundaries)
    nofb_cache = build_cache(nofb_grouped, nofb_boundaries)

    cumulative = []
    for prefix in withfb_prefixes:
        cumulative.append(summarize(f"withfb_prefix{prefix}", "withfb", f"prefix_{prefix}", float(prefix), slice_group(withfb_cache, 0, prefix)))
    for prefix in nofb_prefixes:
        cumulative.append(summarize(f"nofb_prefix{prefix}", "nofb", f"prefix_{prefix}", float(prefix), slice_group(nofb_cache, 0, prefix)))
    withfb_all = slice_group(withfb_cache, 0, "all")
    nofb_all = slice_group(nofb_cache, 0, "all")
    cumulative.append(summarize("withfb_all_available", "withfb", "all_available_endpoint", sum(withfb_lengths.values()) / len(withfb_lengths), withfb_all))
    cumulative.append(summarize("nofb_all_available", "nofb", "all_available_endpoint", sum(nofb_lengths.values()) / len(nofb_lengths), nofb_all))

    delta = []
    for prefix in pair_prefixes:
        delta.append(
            paired_delta(
                f"withfb_minus_nofb_prefix{prefix}",
                float(prefix),
                slice_group(withfb_cache, 0, prefix),
                slice_group(nofb_cache, 0, prefix),
            )
        )
    nofb_matched = {
        rid: nofb_cache[rid][withfb_lengths[rid]]
        for rid in withfb_all
        if rid in nofb_cache and withfb_lengths[rid] in nofb_cache[rid]
    }
    delta.append(
        paired_delta(
            "all_available_withfb_minus_nofb_matched",
            sum(withfb_lengths.values()) / len(withfb_lengths),
            withfb_all,
            nofb_matched,
        )
    )

    block = []
    for start, stop in withfb_block_bounds:
        block.append(summarize(f"withfb_block{start}_{stop}", "withfb", f"block_{start}_{stop}", 0.5 * (start + stop), slice_group(withfb_cache, start, stop)))
    for start, stop in nofb_block_bounds:
        block.append(summarize(f"nofb_block{start}_{stop}", "nofb", f"block_{start}_{stop}", 0.5 * (start + stop), slice_group(nofb_cache, start, stop)))

    write_csv(out_dir / "cumulative_estimator_trace.csv", cumulative)
    write_csv(out_dir / "paired_method_delta_trace.csv", delta)
    write_csv(out_dir / "block500_estimator_trace.csv", block)
    write_component_data(out_dir, cumulative, delta, block)
    write_distance(out_dir / "distance_withfb_prefix.dat", cumulative, lambda row: row["method"] == "withfb" and str(row["cut"]).startswith("prefix_"), "rms_z", "max_abs_z")
    write_distance(out_dir / "distance_nofb_prefix.dat", cumulative, lambda row: row["method"] == "nofb" and str(row["cut"]).startswith("prefix_"), "rms_z", "max_abs_z")
    write_distance(out_dir / "distance_withfb_endpoint.dat", cumulative, lambda row: row["method"] == "withfb" and row["cut"] == "all_available_endpoint", "rms_z", "max_abs_z")
    write_distance(out_dir / "distance_nofb_endpoint.dat", cumulative, lambda row: row["method"] == "nofb" and row["cut"] == "all_available_endpoint", "rms_z", "max_abs_z")
    write_gnuplot_scripts(out_dir)
    meta = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "withfb_root": args.withfb_root,
        "nofb_root": args.nofb_root,
        "withfb_records": len(withfb_grouped),
        "nofb_records": len(nofb_grouped),
        "withfb_common_max": withfb_common,
        "nofb_common_max": nofb_common,
        "withfb_samples_total": sum(withfb_lengths.values()),
        "nofb_samples_total": sum(nofb_lengths.values()),
        "nofb_matched_to_withfb_samples_total": sum(int(value["samples"]) for value in nofb_matched.values()),
    }
    (out_dir / "metadata.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_readme(out_dir, cumulative, delta, meta)
    print(out_dir)


if __name__ == "__main__":
    main()
