#!/usr/bin/env python3
"""Write Stephanov n=6 pooled-observable comparison tables."""

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


def read_rows(path: Path, skip: int = 0, take: int | None = None) -> dict[str, object]:
    values = array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) % WIDTH != 0:
        raise RuntimeError(f"observable stream width mismatch: {path}")

    rows_total = len(values) // WIDTH
    lo = min(skip, rows_total)
    hi = rows_total if take is None else min(rows_total, lo + take)
    denominator = complex(0.0, 0.0)
    sum_abs_w = 0.0
    sum_abs_w2 = 0.0
    numerators = [complex(0.0, 0.0) for _ in OBSERVABLES]
    for row_idx in range(lo, hi):
        offset = row_idx * WIDTH
        weight = complex(float(values[offset]), float(values[offset + 1]))
        denominator += weight
        abs_w = abs(weight)
        sum_abs_w += abs_w
        sum_abs_w2 += abs_w * abs_w
        for obs_idx in range(len(OBSERVABLES)):
            obs_offset = offset + 2 + 2 * obs_idx
            obs_value = complex(float(values[obs_offset]), float(values[obs_offset + 1]))
            numerators[obs_idx] += weight * obs_value
    return {
        "samples": hi - lo,
        "D": denominator,
        "sum_abs_w": sum_abs_w,
        "sum_abs_w2": sum_abs_w2,
        "N": numerators,
    }


def add_sums(left: dict[str, object], right: dict[str, object]) -> None:
    left["samples"] = int(left["samples"]) + int(right["samples"])
    left["D"] = left["D"] + right["D"]  # type: ignore[operator]
    left["sum_abs_w"] = float(left["sum_abs_w"]) + float(right["sum_abs_w"])
    left["sum_abs_w2"] = float(left["sum_abs_w2"]) + float(right["sum_abs_w2"])
    for obs_idx, value in enumerate(right["N"]):  # type: ignore[union-attr]
        left["N"][obs_idx] += value  # type: ignore[index]


def empty_sums() -> dict[str, object]:
    return {
        "samples": 0,
        "D": complex(0.0, 0.0),
        "sum_abs_w": 0.0,
        "sum_abs_w2": 0.0,
        "N": [complex(0.0, 0.0) for _ in OBSERVABLES],
    }


def discover(root: Path, patterns: list[str]) -> dict[int, list[Path]]:
    grouped: dict[int, list[Path]] = {}
    for pattern in patterns:
        for path in root.glob(f"{pattern}/records/record_*/observable_history.dat"):
            grouped.setdefault(record_id(path), []).append(path)
    for paths in grouped.values():
        paths.sort(key=lambda path: (stage_name(path), str(path)))
    return dict(sorted(grouped.items()))


def build_prefix_group(root: Path, patterns: list[str], prefix: int) -> dict[int, dict[str, object]]:
    grouped = discover(root, patterns)
    records: dict[int, dict[str, object]] = {}
    for rid, paths in grouped.items():
        record = empty_sums()
        remaining = prefix
        for path in paths:
            if remaining <= 0:
                break
            rows = path.stat().st_size // (8 * WIDTH)
            take = min(remaining, rows)
            add_sums(record, read_rows(path, 0, take))
            remaining -= take
        if int(record["samples"]) == prefix:
            records[rid] = record
    return records


def build_stage_group(root: Path, patterns: list[str]) -> dict[int, dict[str, object]]:
    grouped = discover(root, patterns)
    records: dict[int, dict[str, object]] = {}
    for rid, paths in grouped.items():
        record = empty_sums()
        for path in paths:
            add_sums(record, read_rows(path))
        if int(record["samples"]) > 0:
            records[rid] = record
    return records


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


def quantile(values: list[int], p: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return float("nan")
    if len(ordered) == 1:
        return float(ordered[0])
    x = (len(ordered) - 1) * p
    lo = int(math.floor(x))
    hi = int(math.ceil(x))
    if lo == hi:
        return float(ordered[lo])
    return ordered[lo] * (hi - x) + ordered[hi] * (x - lo)


def summarize_group(name: str, records: dict[int, dict[str, object]]) -> dict[str, object]:
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

    samples = [int(row["samples"]) for row in records.values()]
    phase = abs(total_d) / total_abs if total_abs > 0.0 else float("nan")
    eff_n = abs(total_d) ** 2 / total_abs2 if total_abs2 > 0.0 else float("nan")
    obs = {}
    for obs_idx, observable in enumerate(OBSERVABLES):
        estimate = estimates[obs_idx]
        se_re = jk_se(jk_estimates[obs_idx], "real")
        se_im = jk_se(jk_estimates[obs_idx], "imag")
        exact = EXACT.get(observable)
        obs[observable] = {
            "estimate_re": estimate.real,
            "estimate_im": estimate.imag,
            "se_re": se_re,
            "se_im": se_im,
            "z_re": (estimate.real - exact) / se_re
            if exact is not None and se_re > 0.0
            else float("nan"),
            "z_im": estimate.imag / se_im if se_im > 0.0 else float("nan"),
        }

    return {
        "name": name,
        "seeds": len(records),
        "samples_total": sum(samples),
        "samples_min": min(samples) if samples else 0,
        "samples_median": quantile(samples, 0.5),
        "samples_max": max(samples) if samples else 0,
        "phase": phase,
        "phase_jk_err": jk_se_float(jk_phase),
        "eff_frac": phase * phase,
        "eff_n": eff_n,
        "observables": obs,
    }


def fmt_int(value: object) -> str:
    return f"{int(value):,}"


def fmt_float(value: object, digits: int = 6, signed: bool = False) -> str:
    number = float(value)
    prefix = "+" if signed and number >= 0.0 else ""
    return f"{prefix}{number:.{digits}f}"


def fmt_value(estimate: object, error: object) -> str:
    return f"`{float(estimate):.6f} +/- {float(error):.6f}`"


def write_markdown(path: Path, summaries: list[dict[str, object]], metadata: dict[str, object]) -> None:
    lines = [
        "# Stephanov N6 Pooled Observable Data - 2026-05-28",
        "",
        "Scope: compare selected current-data cuts for Stephanov `n=6`, `mu=0.6`, `m=0.004`, TLTM ladder endpoint `t_high=0.03`.",
        "",
        "Exact values used:",
        "",
        "- chiral condensate: `0.0244771982754 + 0 i`",
        "- number density: `0.56611556665 + 0 i`",
        "",
        "Data roots:",
        "",
        f"- withfb current: `{metadata['withfb_root']}`",
        f"- nofb current: `{metadata['nofb_root']}`",
        "",
        "Pooled estimator method:",
        "",
        "- Pooled estimator: `O_pool = sum_s sum_i phi_{s,i} O_{s,i} / sum_s sum_i phi_{s,i}`.",
        "- Errors are leave-one-seed jackknife errors on `O_pool`.",
        "- `z = (O_pool - exact) / jackknife_error`, real and imaginary parts separately.",
        "- `withfb_prefix2500` and `nofb_prefix2500` use the first 2500 observable rows per seed.",
        "- `nofb_s01_to_s03` uses all observable rows in complete `nofb15_s01_*`, `nofb15_s02_*`, and `nofb15_s03_*` stage directories.",
        "",
        "Sample and phase summary:",
        "",
        "| group | seeds | total samples | min samples/seed | median samples/seed | max samples/seed | phase | phase JK err | eff frac | effN |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for summary in summaries:
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{summary['name']}`",
                    str(summary["seeds"]),
                    fmt_int(summary["samples_total"]),
                    fmt_int(summary["samples_min"]),
                    fmt_int(round(float(summary["samples_median"]))),
                    fmt_int(summary["samples_max"]),
                    fmt_float(summary["phase"]),
                    fmt_float(summary["phase_jk_err"]),
                    fmt_float(summary["eff_frac"]),
                    fmt_float(summary["eff_n"], digits=0),
                ]
            )
            + " |"
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
    for summary in summaries:
        obs = summary["observables"]  # type: ignore[assignment]
        chiral = obs["chiral_condensate"]
        density = obs["number_density"]
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{summary['name']}`",
                    fmt_value(chiral["estimate_re"], chiral["se_re"]),
                    fmt_value(chiral["estimate_im"], chiral["se_im"]),
                    fmt_value(density["estimate_re"], density["se_re"]),
                    fmt_value(density["estimate_im"], density["se_im"]),
                ]
            )
            + " |"
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
    for summary in summaries:
        obs = summary["observables"]  # type: ignore[assignment]
        chiral = obs["chiral_condensate"]
        density = obs["number_density"]
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{summary['name']}`",
                    fmt_float(chiral["z_re"], digits=3, signed=True),
                    fmt_float(chiral["z_im"], digits=3, signed=True),
                    fmt_float(density["z_re"], digits=3, signed=True),
                    fmt_float(density["z_im"], digits=3, signed=True),
                ]
            )
            + " |"
        )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def flatten_summary(summary: dict[str, object]) -> dict[str, object]:
    obs = summary["observables"]  # type: ignore[assignment]
    chiral = obs["chiral_condensate"]
    density = obs["number_density"]
    return {
        "group": summary["name"],
        "seeds": summary["seeds"],
        "samples_total": summary["samples_total"],
        "samples_min": summary["samples_min"],
        "samples_median": summary["samples_median"],
        "samples_max": summary["samples_max"],
        "phase": summary["phase"],
        "phase_jk_err": summary["phase_jk_err"],
        "eff_frac": summary["eff_frac"],
        "eff_n": summary["eff_n"],
        "chiral_re": chiral["estimate_re"],
        "chiral_re_se": chiral["se_re"],
        "chiral_re_z": chiral["z_re"],
        "chiral_im": chiral["estimate_im"],
        "chiral_im_se": chiral["se_im"],
        "chiral_im_z": chiral["z_im"],
        "density_re": density["estimate_re"],
        "density_re_se": density["se_re"],
        "density_re_z": density["z_re"],
        "density_im": density["estimate_im"],
        "density_im_se": density["se_im"],
        "density_im_z": density["z_im"],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--withfb-root", required=True)
    parser.add_argument("--nofb-root", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--metadata", required=True)
    args = parser.parse_args()

    withfb_root = Path(args.withfb_root)
    nofb_root = Path(args.nofb_root)

    groups = [
        (
            "withfb_prefix2500",
            build_prefix_group(withfb_root, ["withfb*"], 2500),
        ),
        (
            "nofb_s01_to_s03",
            build_stage_group(nofb_root, ["nofb15_s01_*", "nofb15_s02_*", "nofb15_s03_*"]),
        ),
        (
            "nofb_prefix2500",
            build_prefix_group(nofb_root, ["nofb15*"], 2500),
        ),
    ]
    summaries = [summarize_group(name, records) for name, records in groups]

    metadata = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "withfb_root": str(withfb_root),
        "nofb_root": str(nofb_root),
        "groups": [
            {
                "name": name,
                "records": len(records),
                "record_ids": sorted(records),
            }
            for name, records in groups
        ],
        "withfb_s01_s03_availability": {
            "withfb_s01_dirs": len(list(withfb_root.glob("withfb_s01_*"))),
            "withfb_s02_dirs": len(list(withfb_root.glob("withfb_s02_*"))),
            "withfb_s03_dirs": len(list(withfb_root.glob("withfb_s03_*"))),
        },
    }

    report_path = Path(args.report)
    csv_path = Path(args.csv)
    metadata_path = Path(args.metadata)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.parent.mkdir(parents=True, exist_ok=True)

    write_markdown(report_path, summaries, metadata)
    rows = [flatten_summary(summary) for summary in summaries]
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(report_path)


if __name__ == "__main__":
    main()
