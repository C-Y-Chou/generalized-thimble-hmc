#!/usr/bin/env python3
"""Aggregate standalone WV-HMC pilot outputs with ratio-preserving jackknife."""

import argparse
import csv
import json
import math
from pathlib import Path


EXACT = {
    "chiral_condensate": 0.380047505938398,
    "number_density": 0.0387173396674602,
}


def parse_complex(re_text, im_text):
    return complex(float(re_text), float(im_text))


def read_one_row_csv(path):
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
    if len(rows) != 1:
        raise RuntimeError("expected one row in {}".format(path))
    return rows[0]


def read_observables(path):
    observables = {}
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            name = row["name"]
            observables[name] = parse_complex(row["estimate_re"], row["estimate_im"])
    return observables


def discover_pairs(root):
    pairs = []
    for summary_path in sorted(root.glob("*_summary.csv")):
        obs_path = summary_path.with_name(summary_path.name.replace("_summary.csv", "_observables.csv"))
        if obs_path.exists():
            pairs.append((summary_path, obs_path))
    return pairs


def jk_se(values):
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / n
    return math.sqrt((n - 1.0) / n * sum((value - mean) ** 2 for value in values))


def safe_float(row, key):
    try:
        return float(row[key])
    except (KeyError, ValueError):
        return float("nan")


def weighted_summary_mean(records, value_key, weight_key):
    numerator = 0.0
    denominator = 0.0
    for record in records:
        value = safe_float(record["summary"], value_key)
        try:
            weight = float(record["summary"].get(weight_key, 0))
        except (TypeError, ValueError):
            weight = 0.0
        if math.isfinite(value) and weight > 0.0:
            numerator += value * weight
            denominator += weight
    return numerator / denominator if denominator > 0.0 else float("nan")


def load_records(root):
    records = []
    for summary_path, obs_path in discover_pairs(root):
        summary = read_one_row_csv(summary_path)
        estimates = read_observables(obs_path)
        denominator = parse_complex(summary["wv_denominator_re"], summary["wv_denominator_im"])
        numerators = {}
        for name, estimate in estimates.items():
            numerators[name] = estimate * denominator
        records.append({
            "summary_path": str(summary_path),
            "observable_path": str(obs_path),
            "summary": summary,
            "estimates": estimates,
            "D": denominator,
            "sum_abs_weight": safe_float(summary, "wv_sum_abs_weight"),
            "numerators": numerators,
        })
    if not records:
        raise RuntimeError("no *_summary.csv / *_observables.csv pairs found under {}".format(root))
    return records


def total_record(records):
    names = sorted(records[0]["numerators"].keys())
    total = {
        "D": sum((record["D"] for record in records), complex(0.0, 0.0)),
        "sum_abs_weight": sum(record["sum_abs_weight"] for record in records),
        "numerators": {},
    }
    for name in names:
        total["numerators"][name] = sum((record["numerators"][name] for record in records), complex(0.0, 0.0))
    return total


def estimates_from_total(total):
    return {
        name: numerator / total["D"]
        for name, numerator in total["numerators"].items()
    }


def leave_one_total(total, record):
    output = {
        "D": total["D"] - record["D"],
        "sum_abs_weight": total["sum_abs_weight"] - record["sum_abs_weight"],
        "numerators": {},
    }
    for name, numerator in total["numerators"].items():
        output["numerators"][name] = numerator - record["numerators"][name]
    return output


def write_outputs(records, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    total = total_record(records)
    pooled = estimates_from_total(total)
    jk_estimates = {name: [] for name in pooled}
    phase_jk = []
    for record in records:
        leave = leave_one_total(total, record)
        leave_estimates = estimates_from_total(leave)
        for name, value in leave_estimates.items():
            jk_estimates[name].append(value)
        phase_jk.append(abs(leave["D"]) / leave["sum_abs_weight"] if leave["sum_abs_weight"] > 0.0 else float("nan"))

    total_cycles = sum(int(record["summary"]["cycles_completed"]) for record in records)
    total_measurements = sum(int(record["summary"]["measurement_included"]) for record in records)
    total_bounced = sum(int(record["summary"]["bounced_steps"]) for record in records)
    total_trajectory = sum(int(record["summary"]["trajectory_steps"]) for record in records)
    total_odex_failure = sum(int(record["summary"]["odex_failure"]) for record in records)
    total_transitions_failed = sum(int(record["summary"]["transitions_failed"]) for record in records)
    total_metropolis_rejected = sum(int(record["summary"].get("metropolis_rejected", 0)) for record in records)
    total_reverse_gate_rejected = sum(int(record["summary"].get("reverse_gate_rejected", 0)) for record in records)
    total_accepted_jump_count = sum(int(record["summary"].get("accepted_jump_count", 0)) for record in records)
    accepted_x_jump_sq_mean = weighted_summary_mean(records, "accepted_x_jump_sq_mean", "accepted_jump_count")
    accepted_z_jump_sq_mean = weighted_summary_mean(records, "accepted_z_jump_sq_mean", "accepted_jump_count")
    accepted_flow_time_jump_abs_mean = weighted_summary_mean(
        records, "accepted_flow_time_jump_abs_mean", "accepted_jump_count"
    )
    effective_x_jump_sq_mean = weighted_summary_mean(records, "effective_x_jump_sq_mean", "cycles_completed")
    effective_z_jump_sq_mean = weighted_summary_mean(records, "effective_z_jump_sq_mean", "cycles_completed")
    effective_flow_time_jump_abs_mean = weighted_summary_mean(
        records, "effective_flow_time_jump_abs_mean", "cycles_completed"
    )
    phase = abs(total["D"]) / total["sum_abs_weight"] if total["sum_abs_weight"] > 0.0 else float("nan")

    summary_path = out_dir / "wv_hmc_pilot_summary.csv"
    with summary_path.open("w", newline="") as handle:
        fieldnames = [
            "seeds", "total_cycles", "total_measurements", "total_trajectory_steps", "total_bounced_steps",
            "bounce_rate_per_step", "total_transitions_failed", "total_metropolis_rejected",
            "total_reverse_gate_rejected", "total_odex_failure", "phase_coherence",
            "phase_coherence_seed_jk_se", "accepted_jump_count", "accepted_x_jump_sq_mean",
            "accepted_z_jump_sq_mean", "accepted_flow_time_jump_abs_mean", "effective_x_jump_sq_mean",
            "effective_z_jump_sq_mean", "effective_flow_time_jump_abs_mean", "denominator_re",
            "denominator_im", "sum_abs_weight",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow({
            "seeds": len(records),
            "total_cycles": total_cycles,
            "total_measurements": total_measurements,
            "total_trajectory_steps": total_trajectory,
            "total_bounced_steps": total_bounced,
            "bounce_rate_per_step": total_bounced / total_trajectory if total_trajectory else float("nan"),
            "total_transitions_failed": total_transitions_failed,
            "total_metropolis_rejected": total_metropolis_rejected,
            "total_reverse_gate_rejected": total_reverse_gate_rejected,
            "total_odex_failure": total_odex_failure,
            "phase_coherence": phase,
            "phase_coherence_seed_jk_se": jk_se(phase_jk),
            "accepted_jump_count": total_accepted_jump_count,
            "accepted_x_jump_sq_mean": accepted_x_jump_sq_mean,
            "accepted_z_jump_sq_mean": accepted_z_jump_sq_mean,
            "accepted_flow_time_jump_abs_mean": accepted_flow_time_jump_abs_mean,
            "effective_x_jump_sq_mean": effective_x_jump_sq_mean,
            "effective_z_jump_sq_mean": effective_z_jump_sq_mean,
            "effective_flow_time_jump_abs_mean": effective_flow_time_jump_abs_mean,
            "denominator_re": total["D"].real,
            "denominator_im": total["D"].imag,
            "sum_abs_weight": total["sum_abs_weight"],
        })

    obs_path = out_dir / "wv_hmc_pilot_observable_z.csv"
    with obs_path.open("w", newline="") as handle:
        fieldnames = [
            "observable", "estimate_re", "estimate_im", "se_re", "se_im",
            "target_re", "target_im", "z_re", "z_im",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for name in sorted(pooled):
            estimate = pooled[name]
            se_re = jk_se([value.real for value in jk_estimates[name]])
            se_im = jk_se([value.imag for value in jk_estimates[name]])
            target_re = EXACT[name] if name in EXACT else 0.0
            target_im = 0.0
            writer.writerow({
                "observable": name,
                "estimate_re": estimate.real,
                "estimate_im": estimate.imag,
                "se_re": se_re,
                "se_im": se_im,
                "target_re": target_re if name in EXACT else "",
                "target_im": target_im if name in EXACT else "",
                "z_re": (estimate.real - target_re) / se_re if name in EXACT and se_re > 0.0 else "",
                "z_im": estimate.imag / se_im if name in EXACT and se_im > 0.0 else "",
            })

    metadata_path = out_dir / "wv_hmc_pilot_readback_metadata.json"
    metadata = {
        "input_records": [
            {
                "summary_path": record["summary_path"],
                "observable_path": record["observable_path"],
                "cycles_completed": int(record["summary"]["cycles_completed"]),
                "accepted": int(record["summary"]["accepted"]),
                "rejected": int(record["summary"]["rejected"]),
                "metropolis_rejected": int(record["summary"].get("metropolis_rejected", 0)),
                "reverse_gate_rejected": int(record["summary"].get("reverse_gate_rejected", 0)),
                "transitions_failed": int(record["summary"]["transitions_failed"]),
                "flow_time_min": safe_float(record["summary"], "flow_time_min"),
                "flow_time_max": safe_float(record["summary"], "flow_time_max"),
                "flow_time_mean": safe_float(record["summary"], "flow_time_mean"),
                "accepted_jump_count": int(record["summary"].get("accepted_jump_count", 0)),
                "accepted_x_jump_sq_mean": safe_float(record["summary"], "accepted_x_jump_sq_mean"),
                "accepted_z_jump_sq_mean": safe_float(record["summary"], "accepted_z_jump_sq_mean"),
                "accepted_flow_time_jump_abs_mean": safe_float(
                    record["summary"], "accepted_flow_time_jump_abs_mean"
                ),
                "effective_x_jump_sq_mean": safe_float(record["summary"], "effective_x_jump_sq_mean"),
                "effective_z_jump_sq_mean": safe_float(record["summary"], "effective_z_jump_sq_mean"),
                "effective_flow_time_jump_abs_mean": safe_float(
                    record["summary"], "effective_flow_time_jump_abs_mean"
                ),
            }
            for record in records
        ],
        "exact_reference": EXACT,
        "ratio_policy": "pooled numerator reconstructed as D_seed * O_hat_seed; denominator pooled as sum D_seed",
    }
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")

    markdown_path = out_dir / "wv_hmc_pilot_readback.md"
    rows = list(csv.DictReader(obs_path.open()))
    summary_rows = list(csv.DictReader(summary_path.open()))
    lines = [
        "# WV-HMC Pilot Readback",
        "",
        "This readback preserves the complex ratio estimator across seed outputs.",
        "",
        "## Summary",
        "",
        "| seeds | cycles | measurements | phase coherence | bounced/step | failures |",
        "|---:|---:|---:|---:|---:|---:|",
    ]
    srow = summary_rows[0]
    lines.append("| {seeds} | {cycles} | {meas} | {phase:.6g} | {bounce:.6g} | {fail} |".format(
        seeds=srow["seeds"],
        cycles=srow["total_cycles"],
        meas=srow["total_measurements"],
        phase=float(srow["phase_coherence"]),
        bounce=float(srow["bounce_rate_per_step"]),
        fail=int(srow["total_transitions_failed"]) + int(srow["total_odex_failure"]),
    ))
    lines.extend([
        "",
        "Transition diagnostics:",
        "- Metropolis rejections: `{}`".format(srow["total_metropolis_rejected"]),
        "- Reverse-gate rejections: `{}`".format(srow["total_reverse_gate_rejected"]),
        "- Forward construction failures: `{}`".format(srow["total_transitions_failed"]),
        "- ODE failures: `{}`".format(srow["total_odex_failure"]),
        "- Effective x jump sq / cycle: `{:.6g}`".format(float(srow["effective_x_jump_sq_mean"])),
        "- Effective z jump sq / cycle: `{:.6g}`".format(float(srow["effective_z_jump_sq_mean"])),
        "- Accepted x jump sq / accepted proposal: `{:.6g}`".format(float(srow["accepted_x_jump_sq_mean"])),
        "- Accepted z jump sq / accepted proposal: `{:.6g}`".format(float(srow["accepted_z_jump_sq_mean"])),
    ])
    lines.extend([
        "",
        "## Observables",
        "",
        "| observable | Re | SE Re | z Re | Im | SE Im | z Im |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ])
    for row in rows:
        lines.append("| {obs} | {re:.9g} | {sre:.3g} | {zre} | {im:.9g} | {sim:.3g} | {zim} |".format(
            obs=row["observable"],
            re=float(row["estimate_re"]),
            sre=float(row["se_re"]) if row["se_re"] else float("nan"),
            zre="{:.3g}".format(float(row["z_re"])) if row["z_re"] else "",
            im=float(row["estimate_im"]),
            sim=float(row["se_im"]) if row["se_im"] else float("nan"),
            zim="{:.3g}".format(float(row["z_im"])) if row["z_im"] else "",
        ))
    lines.extend([
        "",
        "Artifacts:",
        "- `{}`".format(summary_path),
        "- `{}`".format(obs_path),
        "- `{}`".format(metadata_path),
    ])
    markdown_path.write_text("\n".join(lines) + "\n")
    return summary_path, obs_path, metadata_path, markdown_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()
    records = load_records(args.root)
    outputs = write_outputs(records, args.out_dir)
    for path in outputs:
        print(path)


if __name__ == "__main__":
    main()
