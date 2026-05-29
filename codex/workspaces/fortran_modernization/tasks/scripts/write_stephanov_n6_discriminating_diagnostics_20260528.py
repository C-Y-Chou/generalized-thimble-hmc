#!/usr/bin/env python3
"""High-discrimination diagnostics for current Stephanov n=6 nofb/withfb data.

This version reads each observable stream once per method and snapshots only the
cycle boundaries needed for paired deltas, half-drift, block-z, and influence.
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
    ("chiral_condensate", "Re"): 0.0244771982754,
    ("chiral_condensate", "Im"): 0.0,
    ("number_density", "Re"): 0.56611556665,
    ("number_density", "Im"): 0.0,
}
COMPONENTS = [
    ("chiral_condensate", "Re", "chiral_Re"),
    ("chiral_condensate", "Im", "chiral_Im"),
    ("number_density", "Re", "density_Re"),
    ("number_density", "Im", "density_Im"),
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
    abs_w = abs(weight)
    value["sum_abs_w"] = float(value["sum_abs_w"]) + abs_w
    value["sum_abs_w2"] = float(value["sum_abs_w2"]) + abs_w * abs_w
    for obs_idx in range(len(OBSERVABLES)):
        obs_offset = offset + 2 + 2 * obs_idx
        obs_value = complex(float(data[obs_offset]), float(data[obs_offset + 1]))
        value["N"][obs_idx] += weight * obs_value  # type: ignore[index]


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
    needed = sorted(boundaries)
    next_idx = 0
    for path in paths:
        data = array("d")
        with path.open("rb") as handle:
            data.fromfile(handle, path.stat().st_size // 8)
        if len(data) % WIDTH != 0:
            raise RuntimeError(f"observable stream width mismatch: {path}")
        for row_idx in range(len(data) // WIDTH):
            count += 1
            add_row(current, data, row_idx * WIDTH)
            while next_idx < len(needed) and count == needed[next_idx]:
                snapshots[needed[next_idx]] = clone(current)
                next_idx += 1
    snapshots["all"] = clone(current)
    snapshots["total"] = {"samples": count}
    return snapshots


def build_cache(grouped: dict[int, list[Path]], boundaries: set[int]) -> dict[int, dict[object, dict[str, object]]]:
    return {rid: stream_record(paths, boundaries) for rid, paths in grouped.items()}


def slice_group(
    cache: dict[int, dict[object, dict[str, object]]],
    start: int,
    stop: int | str,
) -> dict[int, dict[str, object]]:
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
    for value in records.values():
        add_sums(total, value)
    return total


def estimates(value: dict[str, object]) -> list[complex]:
    return [numerator / value["D"] for numerator in value["N"]]  # type: ignore[operator]


def comp(est: list[complex], observable: str, part: str) -> float:
    value = est[OBSERVABLES.index(observable)]
    return value.real if part == "Re" else value.imag


def jk_se(values: list[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / n
    return math.sqrt((n - 1) / n * sum((value - mean) ** 2 for value in values))


def quantile(values: list[float], p: float) -> float:
    values = sorted(values)
    if not values:
        return float("nan")
    if len(values) == 1:
        return values[0]
    x = (len(values) - 1) * p
    lo = int(math.floor(x))
    hi = int(math.ceil(x))
    if lo == hi:
        return values[lo]
    return values[lo] * (hi - x) + values[hi] * (x - lo)


def summary(label: str, records: dict[int, dict[str, object]]) -> dict[str, object]:
    total = total_sums(records)
    full = estimates(total)
    row: dict[str, object] = {
        "label": label,
        "seeds": len(records),
        "samples": sum(int(value["samples"]) for value in records.values()),
        "phase": abs(total["D"]) / float(total["sum_abs_w"]) if float(total["sum_abs_w"]) > 0 else float("nan"),  # type: ignore[arg-type]
    }
    for observable, part, short in COMPONENTS:
        value = comp(full, observable, part)
        jk = []
        for record in records.values():
            leave = subtract_sums(total, record)
            jk.append(comp(estimates(leave), observable, part))
        se = jk_se(jk)
        row[f"{short}_estimate"] = value
        row[f"{short}_se"] = se
        row[f"{short}_z"] = (value - EXACT[(observable, part)]) / se if se > 0 else float("nan")
    return row


def paired_delta(
    label: str,
    left_name: str,
    left: dict[int, dict[str, object]],
    right_name: str,
    right: dict[int, dict[str, object]],
) -> list[dict[str, object]]:
    ids = sorted(set(left) & set(right))
    left = {rid: left[rid] for rid in ids}
    right = {rid: right[rid] for rid in ids}
    left_total = total_sums(left)
    right_total = total_sums(right)
    left_est = estimates(left_total)
    right_est = estimates(right_total)
    rows = []
    for observable, part, short in COMPONENTS:
        left_value = comp(left_est, observable, part)
        right_value = comp(right_est, observable, part)
        delta = left_value - right_value
        jk = []
        seed_delta = []
        closer = 0
        target = EXACT[(observable, part)]
        for rid in ids:
            left_leave = subtract_sums(left_total, left[rid])
            right_leave = subtract_sums(right_total, right[rid])
            jk.append(comp(estimates(left_leave), observable, part) - comp(estimates(right_leave), observable, part))
            left_seed = comp(estimates(left[rid]), observable, part)
            right_seed = comp(estimates(right[rid]), observable, part)
            seed_delta.append(left_seed - right_seed)
            closer += int(abs(left_seed - target) < abs(right_seed - target))
        se = jk_se(jk)
        rows.append(
            {
                "label": label,
                "component": short,
                "left": left_name,
                "right": right_name,
                "seeds": len(ids),
                "left_estimate": left_value,
                "right_estimate": right_value,
                "delta_left_minus_right": delta,
                "se_delta": se,
                "z_delta": delta / se if se > 0 else float("nan"),
                "frac_left_seed_closer_to_target": closer / len(ids),
                "seed_delta_median": quantile(seed_delta, 0.5),
                "seed_delta_iqr": quantile(seed_delta, 0.75) - quantile(seed_delta, 0.25),
            }
        )
    return rows


def influence_rows(label: str, records: dict[int, dict[str, object]]) -> list[dict[str, object]]:
    total = total_sums(records)
    full_est = estimates(total)
    base = summary(label, records)
    rows = []
    for rid, value in records.items():
        leave = subtract_sums(total, value)
        leave_est = estimates(leave)
        for observable, part, short in COMPONENTS:
            full_value = comp(full_est, observable, part)
            leave_value = comp(leave_est, observable, part)
            se = float(base[f"{short}_se"])
            rows.append(
                {
                    "label": label,
                    "record_id": rid,
                    "component": short,
                    "full_estimate": full_value,
                    "leave_one_out_estimate": leave_value,
                    "delta_loo_minus_full": leave_value - full_value,
                    "abs_delta_over_full_se": abs(leave_value - full_value) / se if se > 0 else float("nan"),
                }
            )
    return rows


def block_rows(method: str, cache: dict[int, dict[object, dict[str, object]]], common_max: int) -> list[dict[str, object]]:
    rows = []
    for start in range(0, common_max, 500):
        stop = min(start + 500, common_max)
        if stop - start < 250:
            continue
        block = slice_group(cache, start, stop)
        item = summary(f"{method}_{start}_{stop}", block)
        row = {
            "method": method,
            "block_start": start,
            "block_stop": stop,
            "seeds": item["seeds"],
            "samples": item["samples"],
        }
        for _, _, short in COMPONENTS:
            row[f"{short}_z"] = item[f"{short}_z"]
            row[f"{short}_estimate"] = item[f"{short}_estimate"]
            row[f"{short}_se"] = item[f"{short}_se"]
        rows.append(row)
    return rows


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def fmt(value: object, digits: int = 3, signed: bool = True) -> str:
    number = float(value)
    return f"{'+' if signed and number >= 0 else ''}{number:.{digits}f}"


def write_markdown(path: Path, paired: list[dict[str, object]], drift: list[dict[str, object]], influence: list[dict[str, object]], meta: dict[str, object]) -> None:
    lines = [
        "# Stephanov N6 Discriminating Diagnostics - 2026-05-28",
        "",
        f"withfb common max prefix: `{meta['withfb_common_max']}`",
        f"nofb common max prefix: `{meta['nofb_common_max']}`",
        "",
        "Paired method delta:",
        "",
        "| label | component | delta | SE_delta | z_delta | frac withfb seed closer |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for row in paired:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["label"]),
                    str(row["component"]),
                    fmt(row["delta_left_minus_right"], 6),
                    fmt(row["se_delta"], 6, False),
                    fmt(row["z_delta"]),
                    fmt(row["frac_left_seed_closer_to_target"], 3, False),
                ]
            )
            + " |"
        )
    lines.extend(["", "First-half vs second-half drift:", "", "| label | component | delta second-first | SE_delta | z_delta |", "|---|---|---:|---:|---:|"])
    for row in drift:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["label"]),
                    str(row["component"]),
                    fmt(row["delta_left_minus_right"], 6),
                    fmt(row["se_delta"], 6, False),
                    fmt(row["z_delta"]),
                ]
            )
            + " |"
        )
    lines.extend(["", "Top leave-one-seed-out influence:", "", "| label | record | component | abs delta / full SE | delta LOO-full |", "|---|---:|---|---:|---:|"])
    for row in sorted(influence, key=lambda item: float(item["abs_delta_over_full_se"]), reverse=True)[:20]:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["label"]),
                    str(row["record_id"]),
                    str(row["component"]),
                    fmt(row["abs_delta_over_full_se"], 3, False),
                    fmt(row["delta_loo_minus_full"], 6),
                ]
            )
            + " |"
        )
    lines.extend(["", "Artifacts:", "", "- `paired_method_delta.csv`", "- `half_drift_delta.csv`", "- `block500_z.csv`", "- `leave_one_seed_influence.csv`", "- `group_summaries.csv`", "- `metadata.json`"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def boundary_grid(max_prefix: int) -> set[int]:
    values = {max_prefix, max_prefix // 2}
    values.update(range(500, max_prefix + 1, 500))
    values.update({1500, 2500, 3800})
    return {value for value in values if 0 < value <= max_prefix}


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

    withfb_bounds = boundary_grid(withfb_common)
    nofb_bounds = boundary_grid(nofb_common) | {withfb_common, withfb_common // 2}
    withfb_cache = build_cache(withfb_grouped, withfb_bounds)
    nofb_cache = build_cache(nofb_grouped, nofb_bounds)

    paired: list[dict[str, object]] = []
    for prefix in [1500, 2500, withfb_common]:
        paired.extend(
            paired_delta(
                f"withfb_minus_nofb_prefix{prefix}",
                "withfb",
                slice_group(withfb_cache, 0, prefix),
                "nofb",
                slice_group(nofb_cache, 0, prefix),
            )
        )

    withfb_half = withfb_common // 2
    nofb_half = nofb_common // 2
    drift = []
    drift.extend(
        paired_delta(
            f"withfb_second_minus_first_common{withfb_common}",
            "second",
            slice_group(withfb_cache, withfb_half, withfb_common),
            "first",
            slice_group(withfb_cache, 0, withfb_half),
        )
    )
    drift.extend(
        paired_delta(
            f"nofb_second_minus_first_common{withfb_common}",
            "second",
            slice_group(nofb_cache, withfb_half, withfb_common),
            "first",
            slice_group(nofb_cache, 0, withfb_half),
        )
    )
    drift.extend(
        paired_delta(
            f"nofb_second_minus_first_common{nofb_common}",
            "second",
            slice_group(nofb_cache, nofb_half, nofb_common),
            "first",
            slice_group(nofb_cache, 0, nofb_half),
        )
    )

    groups = {
        f"withfb_prefix{withfb_common}": slice_group(withfb_cache, 0, withfb_common),
        "withfb_all_available": slice_group(withfb_cache, 0, "all"),
        f"nofb_prefix{nofb_common}": slice_group(nofb_cache, 0, nofb_common),
        "nofb_all_available": slice_group(nofb_cache, 0, "all"),
    }
    summaries = [summary(label, records) for label, records in groups.items()]
    influence: list[dict[str, object]] = []
    for label, records in groups.items():
        influence.extend(influence_rows(label, records))
    blocks = block_rows("withfb", withfb_cache, withfb_common) + block_rows("nofb", nofb_cache, nofb_common)

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
    }

    write_csv(out_dir / "paired_method_delta.csv", paired)
    write_csv(out_dir / "half_drift_delta.csv", drift)
    write_csv(out_dir / "block500_z.csv", blocks)
    write_csv(out_dir / "leave_one_seed_influence.csv", influence)
    write_csv(out_dir / "group_summaries.csv", summaries)
    (out_dir / "metadata.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(out_dir / "README.md", paired, drift, influence, meta)
    print(out_dir)


if __name__ == "__main__":
    main()
