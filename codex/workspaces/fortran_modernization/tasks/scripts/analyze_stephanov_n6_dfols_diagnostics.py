#!/usr/bin/env python3
"""Summarize official DFO-LS diagnostic CSVs from Stephanov n=6 replay arrays."""

import argparse
import csv
import math
from collections import Counter, defaultdict
from pathlib import Path


ITER_BUCKETS = (
    "Very successful",
    "Successful",
    "Acceptable",
    "Unsuccessful",
    "Safety",
    "Geometry",
)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--attempts-csv", type=Path, default=None)
    parser.add_argument("--out-prefix", type=Path, default=None)
    return parser.parse_args()


def read_csv_rows(path):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = []
    seen = set()
    for row in rows:
        for key in row:
            if key not in seen:
                fieldnames.append(key)
                seen.add(key)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def to_float(row, key):
    raw = row.get(key, "")
    if raw is None or raw == "":
        return float("nan")
    try:
        return float(raw)
    except ValueError:
        return float("nan")


def to_int(row, key, default=0):
    value = to_float(row, key)
    if math.isfinite(value):
        return int(value)
    return default


def fmt(value):
    if not math.isfinite(value):
        return ""
    return "{0:.16g}".format(value)


def percentile(values, q):
    clean = sorted(value for value in values if math.isfinite(value))
    if not clean:
        return float("nan")
    if len(clean) == 1:
        return clean[0]
    pos = (len(clean) - 1) * q
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(clean) - 1)
    frac = pos - lo
    return clean[lo] * (1.0 - frac) + clean[hi] * frac


def mean(values):
    clean = [value for value in values if math.isfinite(value)]
    if not clean:
        return float("nan")
    return sum(clean) / float(len(clean))


def diagnostic_file_for_attempt(row):
    diag_dir = row.get("diagnostic_dir", "").strip()
    if not diag_dir:
        return None
    sample_idx = to_int(row, "sample_idx", -1)
    if sample_idx >= 0:
        expected = Path(diag_dir) / "sample_{0:06d}_dfols_diagnostic.csv".format(sample_idx)
        if expected.exists():
            return expected
    matches = sorted(Path(diag_dir).glob("*_dfols_diagnostic.csv"))
    return matches[0] if matches else None


def iter_bucket(iter_type):
    clean = (iter_type or "").strip()
    for bucket in ITER_BUCKETS:
        if bucket.lower() in clean.lower():
            return bucket
    return clean or "unknown"


def count_rho_reductions(rows):
    reductions = 0
    previous = float("nan")
    for row in rows:
        rho = to_float(row, "rho")
        if math.isfinite(rho) and math.isfinite(previous) and rho < previous:
            reductions += 1
        if math.isfinite(rho):
            previous = rho
    return reductions


def summarize_attempt(row):
    diag_path = diagnostic_file_for_attempt(row)
    diag_rows = read_csv_rows(diag_path) if diag_path is not None else []
    iter_counts = Counter(iter_bucket(diag.get("iter_type", "")) for diag in diag_rows)
    metrics = defaultdict(list)
    for diag in diag_rows:
        for key in (
            "ratio",
            "rho",
            "delta",
            "fk",
            "norm_gk",
            "norm_sk",
            "poisedness",
            "max_distance_xk",
            "interpolation_condition_number",
            "interpolation_error",
            "interpolation_change_J_norm",
            "interpolation_total_residual",
        ):
            metrics[key].append(to_float(diag, key))

    last = diag_rows[-1] if diag_rows else {}
    sample_summary = {
        "candidate": row.get("candidate", ""),
        "sample_idx": row.get("sample_idx", ""),
        "residual_success": row.get("residual_success", ""),
        "dfols_flag": row.get("dfols_flag", ""),
        "dfols_message": row.get("dfols_message", ""),
        "dfols_nf": row.get("dfols_nf", ""),
        "dfols_nx": row.get("dfols_nx", ""),
        "initial_residual_norm": row.get("initial_residual_norm", ""),
        "final_residual_norm": row.get("final_residual_norm", ""),
        "diagnostic_available": 1 if diag_rows else 0,
        "diagnostic_rows": len(diag_rows),
        "diagnostic_file": str(diag_path) if diag_path is not None else "",
        "final_iter_type": last.get("iter_type", ""),
        "final_rho": last.get("rho", ""),
        "final_delta": last.get("delta", ""),
        "final_fk": last.get("fk", ""),
        "rho_reduction_count": count_rho_reductions(diag_rows),
    }
    for bucket in ITER_BUCKETS + ("unknown",):
        sample_summary["iter_count_" + bucket.lower().replace(" ", "_")] = iter_counts.get(bucket, 0)
    return sample_summary, iter_counts, metrics


def summarize_candidate(candidate, attempts, sample_summaries, iter_counts, metrics):
    successes = [row for row in attempts if to_int(row, "residual_success") == 1 and not row.get("error", "").strip()]
    nf = [to_float(row, "dfols_nf") for row in attempts]
    success_nf = [to_float(row, "dfols_nf") for row in successes]
    diag_samples = [row for row in sample_summaries if int(row.get("diagnostic_available", 0)) == 1]
    diag_rows = sum(int(row.get("diagnostic_rows", 0)) for row in sample_summaries)
    total_iter = sum(iter_counts.values())
    final_types = Counter(str(row.get("final_iter_type", "")).strip() or "unknown" for row in diag_samples)

    out = {
        "candidate": candidate,
        "attempt_count": len(attempts),
        "success_count": len(successes),
        "failure_count": len(attempts) - len(successes),
        "success_fraction": fmt(float(len(successes)) / float(len(attempts))) if attempts else "",
        "diagnostic_sample_count": len(diag_samples),
        "diagnostic_row_count": diag_rows,
        "dfols_nf_median": fmt(percentile(nf, 0.50)),
        "dfols_nf_p90": fmt(percentile(nf, 0.90)),
        "dfols_nf_max": fmt(percentile(nf, 1.00)),
        "success_nf_median": fmt(percentile(success_nf, 0.50)),
        "success_nf_p90": fmt(percentile(success_nf, 0.90)),
        "success_nf_max": fmt(percentile(success_nf, 1.00)),
        "rho_reduction_median": fmt(percentile([float(row.get("rho_reduction_count", 0)) for row in sample_summaries], 0.50)),
        "rho_reduction_p90": fmt(percentile([float(row.get("rho_reduction_count", 0)) for row in sample_summaries], 0.90)),
        "final_type_mode": final_types.most_common(1)[0][0] if final_types else "",
    }
    for key in (
        "ratio",
        "rho",
        "delta",
        "fk",
        "norm_gk",
        "norm_sk",
        "poisedness",
        "max_distance_xk",
        "interpolation_condition_number",
        "interpolation_error",
        "interpolation_change_J_norm",
        "interpolation_total_residual",
    ):
        values = metrics.get(key, [])
        out[key + "_median"] = fmt(percentile(values, 0.50))
        out[key + "_p90"] = fmt(percentile(values, 0.90))
        out[key + "_max"] = fmt(percentile(values, 1.00))
        out[key + "_mean"] = fmt(mean(values))
    for bucket in sorted(iter_counts):
        count = iter_counts[bucket]
        safe_bucket = bucket.lower().replace(" ", "_").replace("/", "_")
        out["iter_count_" + safe_bucket] = count
        out["iter_fraction_" + safe_bucket] = fmt(float(count) / float(total_iter)) if total_iter else ""
    return out


def main():
    args = parse_args()
    run_root = args.run_root.resolve()
    attempts_csv = args.attempts_csv.resolve() if args.attempts_csv else run_root / "sample_array_attempts.csv"
    out_prefix = args.out_prefix.resolve() if args.out_prefix else run_root
    attempts = read_csv_rows(attempts_csv)
    if not attempts:
        raise RuntimeError("No attempts found: {0}".format(attempts_csv))

    sample_rows = []
    candidate_iter_counts = defaultdict(Counter)
    candidate_metrics = defaultdict(lambda: defaultdict(list))
    attempts_by_candidate = defaultdict(list)
    samples_by_candidate = defaultdict(list)

    for row in attempts:
        candidate = row.get("candidate", "")
        attempts_by_candidate[candidate].append(row)
        sample_summary, iter_counts, metrics = summarize_attempt(row)
        sample_rows.append(sample_summary)
        samples_by_candidate[candidate].append(sample_summary)
        candidate_iter_counts[candidate].update(iter_counts)
        for key, values in metrics.items():
            candidate_metrics[candidate][key].extend(values)

    candidate_rows = []
    iter_rows = []
    for candidate in sorted(attempts_by_candidate):
        candidate_rows.append(
            summarize_candidate(
                candidate,
                attempts_by_candidate[candidate],
                samples_by_candidate[candidate],
                candidate_iter_counts[candidate],
                candidate_metrics[candidate],
            )
        )
        total = sum(candidate_iter_counts[candidate].values())
        for iter_type, count in sorted(candidate_iter_counts[candidate].items()):
            iter_rows.append(
                {
                    "candidate": candidate,
                    "iter_type": iter_type,
                    "count": count,
                    "fraction": fmt(float(count) / float(total)) if total else "",
                }
            )

    write_csv(out_prefix / "dfols_diagnostic_sample_summary.csv", sample_rows)
    write_csv(out_prefix / "dfols_diagnostic_candidate_summary.csv", candidate_rows)
    write_csv(out_prefix / "dfols_diagnostic_iter_type_summary.csv", iter_rows)
    print("wrote {0}".format(out_prefix / "dfols_diagnostic_candidate_summary.csv"))
    print("wrote {0}".format(out_prefix / "dfols_diagnostic_sample_summary.csv"))
    print("wrote {0}".format(out_prefix / "dfols_diagnostic_iter_type_summary.csv"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
