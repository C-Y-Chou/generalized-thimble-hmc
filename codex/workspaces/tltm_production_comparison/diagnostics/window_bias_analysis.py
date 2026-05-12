#!/usr/bin/env python3
"""Window/block diagnostics for TLTM production-comparison outputs.

This script is intentionally read-only with respect to production data.  It
recomputes ratio observables from per-seed ``virial.dat`` and binary
``phi_history.dat`` files so time-window means use the same numerator and
denominator convention as ``evaluate_expectations``.
"""

from __future__ import print_function

import argparse
import csv
import math
import os
from collections import defaultdict

import numpy as np


METHOD_DIRS = ("no_fb", "fb_norefine")


def read_csv_rows(path):
    with open(path, "r") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows, fields):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    with open(path, "w") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def to_float(value, default=float("nan")):
    try:
        if value is None or value == "":
            return default
        return float(value)
    except Exception:
        return default


def to_int(value, default=0):
    try:
        if value is None or value == "":
            return default
        return int(float(value))
    except Exception:
        return default


def sample_stats(values):
    vals = [float(v) for v in values if math.isfinite(float(v))]
    n = len(vals)
    if n == 0:
        return {
            "n": 0,
            "mean": float("nan"),
            "std": float("nan"),
            "se": float("nan"),
            "zmean": float("nan"),
            "min": float("nan"),
            "max": float("nan"),
            "pos_count": 0,
            "neg_count": 0,
        }
    mean = sum(vals) / float(n)
    if n > 1:
        var = sum((v - mean) ** 2 for v in vals) / float(n - 1)
        std = math.sqrt(max(0.0, var))
        se = std / math.sqrt(float(n))
    else:
        std = 0.0
        se = float("nan")
    zmean = mean / se if se and math.isfinite(se) and se > 0.0 else float("nan")
    return {
        "n": n,
        "mean": mean,
        "std": std,
        "se": se,
        "zmean": zmean,
        "min": min(vals),
        "max": max(vals),
        "pos_count": sum(1 for v in vals if v > 0.0),
        "neg_count": sum(1 for v in vals if v < 0.0),
    }


def pearson(xs, ys):
    pairs = []
    for x, y in zip(xs, ys):
        x = float(x)
        y = float(y)
        if math.isfinite(x) and math.isfinite(y):
            pairs.append((x, y))
    n = len(pairs)
    if n < 3:
        return float("nan")
    mx = sum(x for x, _ in pairs) / float(n)
    my = sum(y for _, y in pairs) / float(n)
    vx = sum((x - mx) ** 2 for x, _ in pairs)
    vy = sum((y - my) ** 2 for _, y in pairs)
    if vx <= 0.0 or vy <= 0.0:
        return float("nan")
    cov = sum((x - mx) * (y - my) for x, y in pairs)
    return cov / math.sqrt(vx * vy)


def read_complex_text(path):
    data = np.loadtxt(path, dtype=np.float64)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    if data.shape[1] < 2:
        raise ValueError("expected at least two columns in {0}".format(path))
    return data[:, 0] + 1j * data[:, 1]


def read_complex_binary(path):
    return np.fromfile(path, dtype=np.complex128)


def ratio_for_slice(num, den, start, stop):
    den_sum = den[start:stop].sum()
    if abs(den_sum) <= np.finfo(np.float64).tiny:
        return complex(float("nan"), float("nan"))
    return num[start:stop].sum() / den_sum


def window_edges(n_samples, n_windows):
    edges = np.linspace(0, n_samples, n_windows + 1, dtype=int)
    out = []
    for i in range(n_windows):
        if edges[i] < edges[i + 1]:
            out.append((i, int(edges[i]), int(edges[i + 1])))
    return out


def cumulative_edges(n_samples, sample_caps):
    out = []
    for cap in sample_caps:
        stop = min(int(cap), n_samples)
        if stop > 0:
            out.append(("cum_{0}".format(stop), 0, stop))
    if not out or out[-1][2] != n_samples:
        out.append(("cum_{0}".format(n_samples), 0, n_samples))
    return out


def find_phi_path(seed_row):
    meta_path = seed_row.get("multichain_meta_file", "")
    if not meta_path:
        return ""
    eval_dir = os.path.dirname(meta_path)
    return os.path.join(eval_dir, "chain_001", "output", "phi_history.dat")


def seed_rows_by_method(dataset_root):
    result = {}
    for method in METHOD_DIRS:
        path = os.path.join(dataset_root, method, "per_seed_summary_table.csv")
        rows = read_csv_rows(path)
        result[method] = rows
    return result


def compute_windows(dataset_root, out_dir, n_windows_list):
    method_rows = seed_rows_by_method(dataset_root)
    per_seed_window_rows = []
    total_check_rows = []
    warning_rows = []
    sample_caps = [10000, 20000, 50000, 100000, 200000, 200001]

    for method, rows in method_rows.items():
        for idx, row in enumerate(rows):
            seed_id = row["seed_id"]
            virial_path = row.get("multichain_meta_file", "")
            if virial_path:
                virial_path = os.path.join(os.path.dirname(virial_path), "virial.dat")
            phi_path = find_phi_path(row)
            if not virial_path or not os.path.exists(virial_path):
                warning_rows.append({"method": method, "seed_id": seed_id, "warning": "missing_virial"})
                continue
            if not phi_path or not os.path.exists(phi_path):
                warning_rows.append({"method": method, "seed_id": seed_id, "warning": "missing_phi"})
                continue

            num = read_complex_text(virial_path)
            den = read_complex_binary(phi_path)
            if num.shape[0] != den.shape[0]:
                warning_rows.append({
                    "method": method,
                    "seed_id": seed_id,
                    "warning": "length_mismatch num={0} den={1}".format(num.shape[0], den.shape[0]),
                })
                n = min(num.shape[0], den.shape[0])
                num = num[:n]
                den = den[:n]
            n_samples = int(num.shape[0])
            total_ratio = ratio_for_slice(num, den, 0, n_samples)
            ohat_re = to_float(row.get("Ohat_re"))
            ohat_im = to_float(row.get("Ohat_im"))
            total_check_rows.append({
                "method": method,
                "seed_id": seed_id,
                "n_samples": n_samples,
                "recomputed_re": total_ratio.real,
                "recomputed_im": total_ratio.imag,
                "summary_re": ohat_re,
                "summary_im": ohat_im,
                "diff_re": total_ratio.real - ohat_re,
                "diff_im": total_ratio.imag - ohat_im,
            })

            edge_specs = []
            for n_windows in n_windows_list:
                for win_idx, start, stop in window_edges(n_samples, n_windows):
                    edge_specs.append(("split{0}".format(n_windows), win_idx, start, stop))
            for win_name, start, stop in cumulative_edges(n_samples, sample_caps):
                edge_specs.append(("cumulative", win_name, start, stop))

            counter_fields = [
                "fallback_trigger_count",
                "quasi_probe_success_count",
                "accepted_local_quasi_count",
                "unresolved_failure_count",
                "reverse_gate_total_reject_count",
                "local_reverse_gate_reject_count",
                "local_proposal_failure_count",
                "local_metropolis_reject_count",
                "accepted_local_total",
                "accepted_local_newton_only_count",
            ]
            counters = dict((field, to_int(row.get(field))) for field in counter_fields)

            for split_kind, win_idx, start, stop in edge_specs:
                ratio = ratio_for_slice(num, den, start, stop)
                out = {
                    "method": method,
                    "seed_id": seed_id,
                    "split_kind": split_kind,
                    "window_index": win_idx,
                    "start_sample": start,
                    "stop_sample_exclusive": stop,
                    "n_samples": stop - start,
                    "Ohat_re": ratio.real,
                    "Ohat_im": ratio.imag,
                }
                out.update(counters)
                per_seed_window_rows.append(out)

            if (idx + 1) % 32 == 0:
                print("[progress] {0} seeds processed for {1}".format(idx + 1, method))

    fields = [
        "method", "seed_id", "split_kind", "window_index", "start_sample",
        "stop_sample_exclusive", "n_samples", "Ohat_re", "Ohat_im",
        "fallback_trigger_count", "quasi_probe_success_count",
        "accepted_local_quasi_count", "unresolved_failure_count",
        "reverse_gate_total_reject_count", "local_reverse_gate_reject_count",
        "local_proposal_failure_count", "local_metropolis_reject_count",
        "accepted_local_total", "accepted_local_newton_only_count",
    ]
    write_csv(os.path.join(out_dir, "per_seed_window_observables.csv"), per_seed_window_rows, fields)
    write_csv(os.path.join(out_dir, "total_recompute_check.csv"), total_check_rows, [
        "method", "seed_id", "n_samples", "recomputed_re", "recomputed_im",
        "summary_re", "summary_im", "diff_re", "diff_im",
    ])
    if warning_rows:
        write_csv(os.path.join(out_dir, "warnings.csv"), warning_rows, ["method", "seed_id", "warning"])

    return per_seed_window_rows, total_check_rows


def summarize_windows(per_seed_window_rows, out_dir):
    by_key = defaultdict(list)
    for row in per_seed_window_rows:
        by_key[(row["method"], row["split_kind"], row["window_index"])].append(row)

    summary_rows = []
    for key in sorted(by_key):
        method, split_kind, window_index = key
        rows = by_key[key]
        re_stats = sample_stats([to_float(r["Ohat_re"]) for r in rows])
        im_stats = sample_stats([to_float(r["Ohat_im"]) for r in rows])
        summary_rows.append({
            "method": method,
            "split_kind": split_kind,
            "window_index": window_index,
            "start_sample_min": min(to_int(r["start_sample"]) for r in rows),
            "stop_sample_exclusive_max": max(to_int(r["stop_sample_exclusive"]) for r in rows),
            "n_seeds": re_stats["n"],
            "mean_re": re_stats["mean"],
            "std_re": re_stats["std"],
            "se_re": re_stats["se"],
            "Zmean_re": re_stats["zmean"],
            "mean_im": im_stats["mean"],
            "std_im": im_stats["std"],
            "se_im": im_stats["se"],
            "Zmean_im": im_stats["zmean"],
            "pos_re": re_stats["pos_count"],
            "neg_re": re_stats["neg_count"],
        })

    write_csv(os.path.join(out_dir, "window_summary.csv"), summary_rows, [
        "method", "split_kind", "window_index", "start_sample_min",
        "stop_sample_exclusive_max", "n_seeds", "mean_re", "std_re", "se_re",
        "Zmean_re", "mean_im", "std_im", "se_im", "Zmean_im", "pos_re", "neg_re",
    ])
    return summary_rows


def summarize_paired(per_seed_window_rows, out_dir):
    index = {}
    for row in per_seed_window_rows:
        key = (row["method"], row["seed_id"], row["split_kind"], row["window_index"])
        index[key] = row

    paired_groups = defaultdict(list)
    for row in per_seed_window_rows:
        if row["method"] != "fb_norefine":
            continue
        key_no = ("no_fb", row["seed_id"], row["split_kind"], row["window_index"])
        if key_no not in index:
            continue
        no = index[key_no]
        paired_groups[(row["split_kind"], row["window_index"])].append((row, no))

    paired_rows = []
    per_seed_diff_rows = []
    for key in sorted(paired_groups):
        split_kind, window_index = key
        pairs = paired_groups[key]
        diffs_re = []
        diffs_im = []
        for fb, no in pairs:
            diff_re = to_float(fb["Ohat_re"]) - to_float(no["Ohat_re"])
            diff_im = to_float(fb["Ohat_im"]) - to_float(no["Ohat_im"])
            diffs_re.append(diff_re)
            diffs_im.append(diff_im)
            per_seed_diff_rows.append({
                "seed_id": fb["seed_id"],
                "split_kind": split_kind,
                "window_index": window_index,
                "diff_re_fb_minus_nofb": diff_re,
                "diff_im_fb_minus_nofb": diff_im,
                "fb_re": fb["Ohat_re"],
                "nofb_re": no["Ohat_re"],
                "fb_accepted_local_quasi_count": fb["accepted_local_quasi_count"],
                "fb_fallback_trigger_count": fb["fallback_trigger_count"],
                "fb_reverse_gate_total_reject_count": fb["reverse_gate_total_reject_count"],
                "fb_unresolved_failure_count": fb["unresolved_failure_count"],
            })
        re_stats = sample_stats(diffs_re)
        im_stats = sample_stats(diffs_im)
        paired_rows.append({
            "split_kind": split_kind,
            "window_index": window_index,
            "paired_n": re_stats["n"],
            "mean_diff_re": re_stats["mean"],
            "std_diff_re": re_stats["std"],
            "se_diff_re": re_stats["se"],
            "t_diff_re": re_stats["zmean"],
            "pos_diff_re": re_stats["pos_count"],
            "neg_diff_re": re_stats["neg_count"],
            "mean_diff_im": im_stats["mean"],
            "std_diff_im": im_stats["std"],
            "se_diff_im": im_stats["se"],
            "t_diff_im": im_stats["zmean"],
            "pos_diff_im": im_stats["pos_count"],
            "neg_diff_im": im_stats["neg_count"],
        })

    write_csv(os.path.join(out_dir, "paired_window_summary.csv"), paired_rows, [
        "split_kind", "window_index", "paired_n", "mean_diff_re", "std_diff_re",
        "se_diff_re", "t_diff_re", "pos_diff_re", "neg_diff_re",
        "mean_diff_im", "std_diff_im", "se_diff_im", "t_diff_im",
        "pos_diff_im", "neg_diff_im",
    ])
    write_csv(os.path.join(out_dir, "per_seed_paired_window_diff.csv"), per_seed_diff_rows, [
        "seed_id", "split_kind", "window_index", "diff_re_fb_minus_nofb",
        "diff_im_fb_minus_nofb", "fb_re", "nofb_re", "fb_accepted_local_quasi_count",
        "fb_fallback_trigger_count", "fb_reverse_gate_total_reject_count",
        "fb_unresolved_failure_count",
    ])
    return paired_rows, per_seed_diff_rows


def summarize_correlations(per_seed_window_rows, out_dir):
    rows = []
    targets = ["Ohat_re", "Ohat_im"]
    counter_fields = [
        "fallback_trigger_count",
        "quasi_probe_success_count",
        "accepted_local_quasi_count",
        "unresolved_failure_count",
        "reverse_gate_total_reject_count",
        "local_reverse_gate_reject_count",
        "local_proposal_failure_count",
        "local_metropolis_reject_count",
        "accepted_local_total",
        "accepted_local_newton_only_count",
    ]
    grouped = defaultdict(list)
    for row in per_seed_window_rows:
        if row["split_kind"] in ("split4", "split20", "cumulative"):
            grouped[(row["method"], row["split_kind"], row["window_index"])].append(row)
    for key in sorted(grouped):
        method, split_kind, window_index = key
        group = grouped[key]
        for target in targets:
            ys = [to_float(r[target]) for r in group]
            for counter in counter_fields:
                xs = [to_float(r[counter]) for r in group]
                rows.append({
                    "method": method,
                    "split_kind": split_kind,
                    "window_index": window_index,
                    "target": target,
                    "counter": counter,
                    "pearson_r": pearson(xs, ys),
                    "n": len(group),
                })

    write_csv(os.path.join(out_dir, "counter_correlation_summary.csv"), rows, [
        "method", "split_kind", "window_index", "target", "counter", "pearson_r", "n",
    ])
    return rows


def summarize_dataset_scales(provisional_root, out_dir):
    dataset_paths = [
        "official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb",
        "official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb",
        "official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb",
    ]
    rows = []
    for dataset in dataset_paths:
        path = os.path.join(provisional_root, dataset, "combined_summary_table.csv")
        if not os.path.exists(path):
            continue
        for row in read_csv_rows(path):
            out = dict(row)
            out["dataset"] = dataset
            rows.append(out)
    if rows:
        fields = ["dataset"] + [f for f in rows[0].keys() if f != "dataset"]
        write_csv(os.path.join(out_dir, "dataset_scale_summary.csv"), rows, fields)
    return rows


def report_value(value, digits=6):
    try:
        value = float(value)
    except Exception:
        return str(value)
    if not math.isfinite(value):
        return "nan"
    return ("{0:." + str(digits) + "g}").format(value)


def write_report(out_dir, summary_rows, paired_rows, corr_rows, total_check_rows, scale_rows):
    report_path = os.path.join(out_dir, "REPORT.md")
    check_abs_re = [abs(to_float(r["diff_re"])) for r in total_check_rows]
    check_abs_im = [abs(to_float(r["diff_im"])) for r in total_check_rows]
    max_check_re = max(check_abs_re) if check_abs_re else float("nan")
    max_check_im = max(check_abs_im) if check_abs_im else float("nan")

    split4 = [r for r in summary_rows if r["split_kind"] == "split4"]
    split20 = [r for r in summary_rows if r["split_kind"] == "split20"]
    paired_split4 = [r for r in paired_rows if r["split_kind"] == "split4"]
    paired_split20 = [r for r in paired_rows if r["split_kind"] == "split20"]
    cumulative = [r for r in summary_rows if r["split_kind"] == "cumulative"]

    def table_rows(rows, fields):
        lines = []
        lines.append("| " + " | ".join(fields) + " |")
        lines.append("| " + " | ".join(["---"] * len(fields)) + " |")
        for row in rows:
            lines.append("| " + " | ".join(str(row.get(f, "")) for f in fields) + " |")
        return "\n".join(lines)

    split4_compact = []
    for row in split4:
        split4_compact.append({
            "method": row["method"],
            "window": row["window_index"],
            "mean_re": report_value(row["mean_re"]),
            "Zmean_re": report_value(row["Zmean_re"]),
            "mean_im": report_value(row["mean_im"]),
            "Zmean_im": report_value(row["Zmean_im"]),
        })
    paired4_compact = []
    for row in paired_split4:
        paired4_compact.append({
            "window": row["window_index"],
            "mean_diff_re": report_value(row["mean_diff_re"]),
            "t_diff_re": report_value(row["t_diff_re"]),
            "pos/neg": "{0}/{1}".format(row["pos_diff_re"], row["neg_diff_re"]),
        })

    split20_fb = [r for r in split20 if r["method"] == "fb_norefine"]
    split20_no = [r for r in split20 if r["method"] == "no_fb"]
    paired20_re = [to_float(r["mean_diff_re"]) for r in paired_split20]
    paired20_pos = sum(1 for v in paired20_re if v > 0.0)
    paired20_neg = sum(1 for v in paired20_re if v < 0.0)
    fb20_pos_mean = sum(1 for r in split20_fb if to_float(r["mean_re"]) > 0.0)
    no20_pos_mean = sum(1 for r in split20_no if to_float(r["mean_re"]) > 0.0)

    corr_focus = []
    for row in corr_rows:
        if row["method"] == "fb_norefine" and row["split_kind"] == "cumulative" and str(row["window_index"]).endswith("200001"):
            if row["target"] == "Ohat_re" and row["counter"] in (
                "accepted_local_quasi_count",
                "fallback_trigger_count",
                "reverse_gate_total_reject_count",
                "unresolved_failure_count",
                "local_metropolis_reject_count",
            ):
                corr_focus.append({
                    "target": row["target"],
                    "counter": row["counter"],
                    "pearson_r": report_value(row["pearson_r"]),
                })

    scale_compact = []
    for row in scale_rows:
        scale_compact.append({
            "dataset": row["dataset"],
            "method": row["method"],
            "n_seeds": row["n_seeds"],
            "mean_re": report_value(row["mean_Ohat_re"]),
            "std_re": report_value(row["std_Ohat_re"]),
            "Zmean_re": report_value(row["Zmean_re"]),
        })

    with open(report_path, "w") as handle:
        handle.write("# Window Bias Diagnostic Report\n\n")
        handle.write("## Integrity Check\n\n")
        handle.write("- Recomputed per-seed full-run ratios from `virial.dat` and binary `phi_history.dat`.\n")
        handle.write("- Max absolute recompute difference: Re `{0}`, Im `{1}`.\n\n".format(
            report_value(max_check_re), report_value(max_check_im)))
        handle.write("## Existing Dataset Scale Readback\n\n")
        handle.write(table_rows(scale_compact, ["dataset", "method", "n_seeds", "mean_re", "std_re", "Zmean_re"]))
        handle.write("\n\n")
        handle.write("## 200k Split Into Four Windows\n\n")
        handle.write(table_rows(split4_compact, ["method", "window", "mean_re", "Zmean_re", "mean_im", "Zmean_im"]))
        handle.write("\n\n")
        handle.write("## Paired Difference: fb_norefine - no_fb\n\n")
        handle.write(table_rows(paired4_compact, ["window", "mean_diff_re", "t_diff_re", "pos/neg"]))
        handle.write("\n\n")
        handle.write("## 20 Window Sign Summary\n\n")
        handle.write("- `fb_norefine` split20 windows with positive mean Re: `{0}/20`.\n".format(fb20_pos_mean))
        handle.write("- `no_fb` split20 windows with positive mean Re: `{0}/20`.\n".format(no20_pos_mean))
        handle.write("- paired split20 mean differences positive/negative: `{0}/{1}`.\n\n".format(paired20_pos, paired20_neg))
        handle.write("## fb_norefine Counter Correlations For Full 200k\n\n")
        handle.write(table_rows(corr_focus, ["target", "counter", "pearson_r"]))
        handle.write("\n\n")
        handle.write("## Outputs\n\n")
        handle.write("- `per_seed_window_observables.csv`\n")
        handle.write("- `window_summary.csv`\n")
        handle.write("- `paired_window_summary.csv`\n")
        handle.write("- `per_seed_paired_window_diff.csv`\n")
        handle.write("- `counter_correlation_summary.csv`\n")
        handle.write("- `total_recompute_check.csv`\n")
        handle.write("- `dataset_scale_summary.csv`\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-root", required=True)
    parser.add_argument("--provisional-root", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--windows", default="4,20")
    args = parser.parse_args()

    n_windows_list = [int(x) for x in args.windows.split(",") if x.strip()]
    if not os.path.isdir(args.out_dir):
        os.makedirs(args.out_dir)

    per_seed_window_rows, total_check_rows = compute_windows(args.dataset_root, args.out_dir, n_windows_list)
    summary_rows = summarize_windows(per_seed_window_rows, args.out_dir)
    paired_rows, _ = summarize_paired(per_seed_window_rows, args.out_dir)
    corr_rows = summarize_correlations(per_seed_window_rows, args.out_dir)
    scale_rows = summarize_dataset_scales(args.provisional_root, args.out_dir)
    write_report(args.out_dir, summary_rows, paired_rows, corr_rows, total_check_rows, scale_rows)
    print("[done] wrote diagnostics to {0}".format(args.out_dir))


if __name__ == "__main__":
    main()
