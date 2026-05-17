#!/usr/bin/env python3
"""Compare a tolerance-profile Stage3 run against a strict reference run."""

import argparse
import csv
import math
from pathlib import Path


METHODS = ("no_fb", "fb_norefine")
METHOD_ALIASES = {
    "no_fb": ("no_fb", "nofb"),
    "fb_norefine": ("fb_norefine", "withfb"),
}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build paired observable/diagnostic deltas for a loose tolerance profile."
    )
    parser.add_argument("--reference-root", required=True, help="Strict reference root.")
    parser.add_argument("--candidate-root", required=True, help="Candidate tolerance-profile root.")
    parser.add_argument("--output-root", required=True, help="Directory for comparison outputs.")
    parser.add_argument("--candidate-label", default="candidate", help="Label used in reports.")
    return parser.parse_args()


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def as_float(row, key, default=float("nan")):
    value = row.get(key, "")
    if value in ("", "NA", None):
        return default
    try:
        return float(value)
    except ValueError:
        return default


def as_int(row, key, default=0):
    value = as_float(row, key, float("nan"))
    if not math.isfinite(value):
        return default
    return int(round(value))


def mean(values):
    values = list(values)
    return sum(values) / len(values) if values else float("nan")


def sample_std(values):
    values = list(values)
    if len(values) < 2:
        return float("nan")
    avg = mean(values)
    return math.sqrt(sum((value - avg) ** 2 for value in values) / (len(values) - 1))


def stderr(values):
    values = list(values)
    if len(values) < 2:
        return float("nan")
    return sample_std(values) / math.sqrt(len(values))


def zscore(values):
    se = stderr(values)
    if not math.isfinite(se) or se == 0.0:
        return float("nan")
    return mean(values) / se


def fmt(value):
    if isinstance(value, str):
        return value
    if value is None or not math.isfinite(value):
        return "NA"
    return "{:.12g}".format(value)


def method_file(root, method, filename):
    for method_dir in METHOD_ALIASES.get(method, (method,)):
        path = root / method_dir / filename
        if path.exists():
            return path
    direct = root / filename
    if direct.exists():
        return direct
    raise FileNotFoundError("missing {0} under {1}".format(filename, root / method))


def keyed_by_seed(rows):
    return {row["seed_id"]: row for row in rows if row.get("seed_id")}


def reject_count(row):
    total = 0
    for key, value in row.items():
        if key.startswith("reverse_gate_") and key.endswith("_reject_count"):
            total += as_int(row, key)
    return total


def load_method(root, method):
    return {
        "per_seed": read_csv(method_file(root, method, "per_seed_summary_table.csv")),
        "aggregate": read_csv(method_file(root, method, "aggregated_summary_table.csv"))[0],
    }


def aggregate_delta(method, ref, cand):
    ref_agg = ref["aggregate"]
    cand_agg = cand["aggregate"]
    keys = (
        "mean_Ohat_re",
        "mean_Ohat_im",
        "Zmean_re",
        "Zmean_im",
        "total_unresolved_failure_count",
        "mean_pair0_accept_rate",
        "mean_runtime_total",
    )
    row = {"method": method}
    for key in keys:
        ref_value = as_float(ref_agg, key)
        cand_value = as_float(cand_agg, key)
        row["reference_" + key] = fmt(ref_value)
        row["candidate_" + key] = fmt(cand_value)
        row["delta_" + key] = fmt(cand_value - ref_value)
    rg_ref = as_float(ref_agg, "total_reverse_gate_total_reject_count", float("nan"))
    rg_cand = as_float(cand_agg, "total_reverse_gate_total_reject_count", float("nan"))
    row["reference_total_reverse_gate_total_reject_count"] = fmt(rg_ref)
    row["candidate_total_reverse_gate_total_reject_count"] = fmt(rg_cand)
    row["delta_total_reverse_gate_total_reject_count"] = fmt(rg_cand - rg_ref)
    return row


def paired_delta(method, ref, cand):
    ref_rows = keyed_by_seed(ref["per_seed"])
    cand_rows = keyed_by_seed(cand["per_seed"])
    seeds = sorted(set(ref_rows).intersection(cand_rows), key=lambda value: int(value))
    deltas_re = []
    deltas_im = []
    deltas_fail = []
    deltas_rg = []
    deltas_accept = []
    max_abs_re = 0.0
    max_abs_im = 0.0
    for seed in seeds:
        ref_row = ref_rows[seed]
        cand_row = cand_rows[seed]
        d_re = as_float(cand_row, "Ohat_re") - as_float(ref_row, "Ohat_re")
        d_im = as_float(cand_row, "Ohat_im") - as_float(ref_row, "Ohat_im")
        deltas_re.append(d_re)
        deltas_im.append(d_im)
        deltas_fail.append(
            as_int(cand_row, "unresolved_failure_count") - as_int(ref_row, "unresolved_failure_count")
        )
        deltas_rg.append(reject_count(cand_row) - reject_count(ref_row))
        deltas_accept.append(as_float(cand_row, "pair0_accept_rate") - as_float(ref_row, "pair0_accept_rate"))
        max_abs_re = max(max_abs_re, abs(d_re))
        max_abs_im = max(max_abs_im, abs(d_im))
    return {
        "method": method,
        "paired_seeds": str(len(seeds)),
        "mean_delta_Ohat_re": fmt(mean(deltas_re)),
        "stderr_delta_Ohat_re": fmt(stderr(deltas_re)),
        "z_delta_Ohat_re": fmt(zscore(deltas_re)),
        "max_abs_delta_Ohat_re": fmt(max_abs_re),
        "mean_delta_Ohat_im": fmt(mean(deltas_im)),
        "stderr_delta_Ohat_im": fmt(stderr(deltas_im)),
        "z_delta_Ohat_im": fmt(zscore(deltas_im)),
        "max_abs_delta_Ohat_im": fmt(max_abs_im),
        "mean_delta_unresolved_failure_count": fmt(mean(deltas_fail)),
        "mean_delta_reverse_gate_reject_count": fmt(mean(deltas_rg)),
        "mean_delta_pair0_accept_rate": fmt(mean(deltas_accept)),
    }


def write_csv(path, rows, fieldnames):
    with path.open("w", newline="", encoding="utf-8") as handle:
        delimiter = "\t" if path.suffix == ".tsv" else ","
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", delimiter=delimiter)
        writer.writeheader()
        writer.writerows(rows)


def write_report(path, label, aggregate_rows, paired_rows):
    lines = [
        "# Tolerance Profile Reference Comparison",
        "",
        "Candidate: `{0}`".format(label),
        "",
        "## Paired Observable Drift",
        "",
        "| method | seeds | mean dRe | SE dRe | Z dRe | max | mean dIm | SE dIm | Z dIm | max | d failures/seed | d RG rejects/seed | d pair0 accept |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in paired_rows:
        lines.append(
            "| {method} | {paired_seeds} | {mean_delta_Ohat_re} | {stderr_delta_Ohat_re} | {z_delta_Ohat_re} | {max_abs_delta_Ohat_re} | "
            "{mean_delta_Ohat_im} | {stderr_delta_Ohat_im} | {z_delta_Ohat_im} | {max_abs_delta_Ohat_im} | "
            "{mean_delta_unresolved_failure_count} | {mean_delta_reverse_gate_reject_count} | {mean_delta_pair0_accept_rate} |".format(**row)
        )
    lines.extend(["", "## Aggregate Delta", ""])
    for row in aggregate_rows:
        lines.append(
            "- `{method}`: d mean Re `{delta_mean_Ohat_re}`, d mean Im `{delta_mean_Ohat_im}`, "
            "d failures `{delta_total_unresolved_failure_count}`, d RG rejects `{delta_total_reverse_gate_total_reject_count}`, "
            "d runtime `{delta_mean_runtime_total}`.".format(**row)
        )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    args = parse_args()
    reference_root = Path(args.reference_root)
    candidate_root = Path(args.candidate_root)
    output_root = Path(args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    aggregate_rows = []
    paired_rows = []
    for method in METHODS:
        ref = load_method(reference_root, method)
        cand = load_method(candidate_root, method)
        aggregate_rows.append(aggregate_delta(method, ref, cand))
        paired_rows.append(paired_delta(method, ref, cand))

    write_csv(output_root / "aggregate_delta.tsv", aggregate_rows, list(aggregate_rows[0].keys()))
    write_csv(output_root / "paired_observable_drift.tsv", paired_rows, list(paired_rows[0].keys()))
    write_report(output_root / "REPORT.md", args.candidate_label, aggregate_rows, paired_rows)
    print("wrote {0}".format(output_root / "REPORT.md"))


if __name__ == "__main__":
    main()
