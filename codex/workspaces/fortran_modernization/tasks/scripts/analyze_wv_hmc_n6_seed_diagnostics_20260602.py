#!/usr/bin/env python3
"""Join WV-HMC n=6 seed observables with production diagnostics.

This script is intentionally dependency-free.  It is used for the 2026-06-02
correctness audit where the goal is to locate which production mechanism, if
any, is associated with the observed chiral-condensate drift.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from statistics import mean, median


EXACT_CHIRAL = 0.0244771983
EXACT_DENSITY = 0.5661155667


def to_float(text: str, default: float = float("nan")) -> float:
    if text is None:
        return default
    text = str(text).strip()
    if text == "":
        return default
    try:
        return float(text.replace("D", "E").replace("d", "e"))
    except ValueError:
        return default


def to_int(text: str, default: int = 0) -> int:
    value = to_float(text, float("nan"))
    if not math.isfinite(value):
        return default
    return int(value)


def safe_ratio(num: float, den: float) -> float:
    if den == 0 or not math.isfinite(num) or not math.isfinite(den):
        return float("nan")
    return num / den


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def parse_hist(text: str) -> list[int]:
    if text is None:
        return []
    text = text.strip()
    if not text:
        return []
    out = []
    for token in text.split(";"):
        token = token.strip()
        if not token:
            continue
        out.append(to_int(token))
    return out


def hist_features(row: dict[str, str], prefix: str, t0: float, t1: float) -> dict[str, float]:
    hist = parse_hist(row.get(prefix, ""))
    total = float(sum(hist))
    result: dict[str, float] = {
        prefix + "_total": total,
        prefix + "_low8_frac": float("nan"),
        prefix + "_high8_frac": float("nan"),
        prefix + "_edge4_frac": float("nan"),
        prefix + "_mean_t": float("nan"),
        prefix + "_rms_flat_deviation": float("nan"),
    }
    if not hist or total <= 0.0 or t1 <= t0:
        return result
    nbin = len(hist)
    centers = [t0 + (i + 0.5) * (t1 - t0) / nbin for i in range(nbin)]
    probs = [h / total for h in hist]
    result[prefix + "_low8_frac"] = sum(hist[: min(8, nbin)]) / total
    result[prefix + "_high8_frac"] = sum(hist[max(0, nbin - 8) :]) / total
    result[prefix + "_edge4_frac"] = (sum(hist[: min(4, nbin)]) + sum(hist[max(0, nbin - 4) :])) / total
    result[prefix + "_mean_t"] = sum(p * c for p, c in zip(probs, centers))
    flat = 1.0 / nbin
    result[prefix + "_rms_flat_deviation"] = math.sqrt(sum((p - flat) ** 2 for p in probs) / nbin)
    return result


def rank_values(values: list[float]) -> list[float]:
    indexed = sorted((v, i) for i, v in enumerate(values))
    ranks = [0.0] * len(values)
    start = 0
    while start < len(indexed):
        end = start + 1
        while end < len(indexed) and indexed[end][0] == indexed[start][0]:
            end += 1
        avg_rank = 0.5 * (start + end - 1) + 1.0
        for _, idx in indexed[start:end]:
            ranks[idx] = avg_rank
        start = end
    return ranks


def pearson(xs: list[float], ys: list[float]) -> float:
    if len(xs) < 3 or len(xs) != len(ys):
        return float("nan")
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    vx = sum((x - mx) ** 2 for x in xs)
    vy = sum((y - my) ** 2 for y in ys)
    if vx <= 0.0 or vy <= 0.0:
        return float("nan")
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / math.sqrt(vx * vy)


def spearman(xs: list[float], ys: list[float]) -> float:
    return pearson(rank_values(xs), rank_values(ys))


def finite_pair_rows(rows: list[dict[str, float]], x_name: str, y_name: str) -> tuple[list[float], list[float]]:
    xs: list[float] = []
    ys: list[float] = []
    for row in rows:
        x = row.get(x_name, float("nan"))
        y = row.get(y_name, float("nan"))
        if math.isfinite(x) and math.isfinite(y):
            xs.append(x)
            ys.append(y)
    return xs, ys


def quartile_diff(rows: list[dict[str, float]], x_name: str, y_name: str) -> tuple[float, float, float, int, int]:
    clean = [(row[x_name], row[y_name]) for row in rows if math.isfinite(row.get(x_name, float("nan"))) and math.isfinite(row.get(y_name, float("nan")))]
    clean.sort(key=lambda pair: pair[0])
    if len(clean) < 8:
        return (float("nan"), float("nan"), float("nan"), 0, 0)
    q = max(1, len(clean) // 4)
    low_y = [v for _, v in clean[:q]]
    high_y = [v for _, v in clean[-q:]]
    return (mean(high_y), mean(low_y), mean(high_y) - mean(low_y), len(high_y), len(low_y))


def collect_raw_summary(summary_root: Path) -> dict[int, dict[str, str]]:
    out: dict[int, dict[str, str]] = {}
    for path in sorted(summary_root.glob("chunks/**/seed_*_summary.csv")):
        rows = read_csv(path)
        if not rows:
            continue
        row = rows[0]
        seed = to_int(row.get("base_seed", ""))
        if seed:
            out[seed] = row
    return out


def collect_manifest(summary_root: Path) -> dict[int, dict[str, str]]:
    out: dict[int, dict[str, str]] = {}
    for path in sorted(summary_root.glob("chunks/**/wv_hmc_dense_observable_validation_manifest.csv")):
        for row in read_csv(path):
            seed = to_int(row.get("seed", ""))
            if seed:
                out[seed] = row
    return out


def build_panel(seed_summary_path: Path, raw_root: Path) -> list[dict[str, float | int | str]]:
    seed_rows = {to_int(row["seed"]): row for row in read_csv(seed_summary_path)}
    raw_rows = collect_raw_summary(raw_root)
    manifest_rows = collect_manifest(raw_root)
    rows: list[dict[str, float | int | str]] = []
    for seed, obs in sorted(seed_rows.items()):
        raw = raw_rows.get(seed, {})
        manifest = manifest_rows.get(seed, {})
        cycles = to_float(raw.get("cycles_completed", manifest.get("cycles", "")))
        trajectory_steps = to_float(raw.get("trajectory_steps", ""))
        reverse_steps = to_float(raw.get("reverse_trajectory_steps", ""))
        reverse_checked = to_float(raw.get("reverse_gate_checked", ""))
        odex_calls = to_float(raw.get("odex_calls", ""))
        measurement_included = to_float(raw.get("measurement_included", obs.get("samples", "")))
        sampler_t0 = to_float(raw.get("sampler_t0", manifest.get("sampler_t0", "")))
        sampler_t1 = to_float(raw.get("sampler_t1", manifest.get("sampler_t1", "")))
        init_record = to_int(raw.get("init_bank_record", manifest.get("init_bank_record", "")), -999)
        chiral_re = to_float(obs.get("chiral_condensate_re", ""))
        density_re = to_float(obs.get("number_density_re", ""))
        denom_re = to_float(raw.get("wv_denominator_re", ""))
        denom_im = to_float(raw.get("wv_denominator_im", ""))
        row: dict[str, float | int | str] = {
            "seed": seed,
            "init_bank_record": init_record,
            "samples": to_int(obs.get("samples", "0")),
            "cycles_completed": cycles,
            "runtime_sec": to_float(manifest.get("runtime_sec", "")),
            "chiral_re": chiral_re,
            "chiral_im": to_float(obs.get("chiral_condensate_im", "")),
            "chiral_err": chiral_re - EXACT_CHIRAL,
            "abs_chiral_err": abs(chiral_re - EXACT_CHIRAL),
            "density_re": density_re,
            "density_im": to_float(obs.get("number_density_im", "")),
            "density_err": density_re - EXACT_DENSITY,
            "phase_coherence_history": to_float(obs.get("phase_coherence", "")),
            "phase_coherence_summary": to_float(raw.get("measurement_phase_coherence", "")),
            "abs_denominator": to_float(obs.get("abs_denominator", "")),
            "denominator_re": denom_re,
            "denominator_im": denom_im,
            "denominator_arg": math.atan2(denom_im, denom_re)
            if math.isfinite(denom_re) and math.isfinite(denom_im)
            else float("nan"),
            "accepted_rate": safe_ratio(to_float(raw.get("accepted", "")), cycles),
            "rejected_rate": safe_ratio(to_float(raw.get("rejected", "")), cycles),
            "transition_failure_rate": safe_ratio(to_float(raw.get("transitions_failed", "")), cycles),
            "metropolis_reject_rate": safe_ratio(to_float(raw.get("metropolis_rejected", "")), cycles),
            "reverse_gate_reject_rate": safe_ratio(to_float(raw.get("reverse_gate_rejected", "")), cycles),
            "reverse_gate_failed_rate": safe_ratio(to_float(raw.get("reverse_gate_failed", "")), reverse_checked),
            "bounce_rate_per_step": safe_ratio(to_float(raw.get("bounced_steps", "")), trajectory_steps),
            "reverse_bounce_rate_per_step": safe_ratio(to_float(raw.get("reverse_solver_stop_boundary_exit", "")), reverse_steps),
            "solver_max_iter_rate": safe_ratio(to_float(raw.get("solver_stop_max_iter", "")), trajectory_steps),
            "reverse_solver_max_iter_rate": safe_ratio(to_float(raw.get("reverse_solver_stop_max_iter", "")), reverse_steps),
            "solver_failure_rate": safe_ratio(to_float(raw.get("solver_stop_failure", "")), trajectory_steps),
            "reverse_solver_failure_rate": safe_ratio(to_float(raw.get("reverse_solver_stop_failure", "")), reverse_steps),
            "solver_large_residual_rate": safe_ratio(to_float(raw.get("solver_stop_large_residual", "")), trajectory_steps),
            "reverse_solver_large_residual_rate": safe_ratio(to_float(raw.get("reverse_solver_stop_large_residual", "")), reverse_steps),
            "odex_failure_rate": safe_ratio(to_float(raw.get("odex_failure", "")), odex_calls),
            "solver_iterations_per_step": safe_ratio(to_float(raw.get("solver_iterations", "")), trajectory_steps),
            "reverse_solver_iterations_per_step": safe_ratio(to_float(raw.get("reverse_solver_iterations", "")), reverse_steps),
            "flow_time_mean": to_float(raw.get("flow_time_mean", "")),
            "flow_time_min": to_float(raw.get("flow_time_min", "")),
            "flow_time_max": to_float(raw.get("flow_time_max", "")),
            "accepted_flow_time_jump_abs_mean": to_float(raw.get("accepted_flow_time_jump_abs_mean", "")),
            "effective_flow_time_jump_abs_mean": to_float(raw.get("effective_flow_time_jump_abs_mean", "")),
            "accepted_x_jump_sq_mean": to_float(raw.get("accepted_x_jump_sq_mean", "")),
            "effective_x_jump_sq_mean": to_float(raw.get("effective_x_jump_sq_mean", "")),
            "w_gamma": to_float(raw.get("w_gamma", manifest.get("w_gamma", ""))),
            "boundary_policy": raw.get("boundary_policy", ""),
            "measurement_included": measurement_included,
        }
        row.update(hist_features(raw, "flow_time_hist_inside", sampler_t0, sampler_t1))
        row.update(hist_features(raw, "measurement_flow_time_hist_inside", sampler_t0, sampler_t1))
        rows.append(row)
    return rows


def write_panel(path: Path, rows: list[dict[str, float | int | str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted({key for row in rows for key in row.keys()})
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_correlations(path: Path, rows: list[dict[str, float | int | str]]) -> list[dict[str, str]]:
    metric_names = [
        "phase_coherence_history",
        "phase_coherence_summary",
        "abs_denominator",
        "accepted_rate",
        "transition_failure_rate",
        "reverse_gate_reject_rate",
        "reverse_gate_failed_rate",
        "bounce_rate_per_step",
        "reverse_bounce_rate_per_step",
        "solver_max_iter_rate",
        "reverse_solver_max_iter_rate",
        "solver_iterations_per_step",
        "reverse_solver_iterations_per_step",
        "odex_failure_rate",
        "flow_time_mean",
        "flow_time_hist_inside_low8_frac",
        "flow_time_hist_inside_high8_frac",
        "measurement_flow_time_hist_inside_low8_frac",
        "measurement_flow_time_hist_inside_high8_frac",
        "measurement_flow_time_hist_inside_mean_t",
        "measurement_flow_time_hist_inside_rms_flat_deviation",
        "accepted_flow_time_jump_abs_mean",
        "effective_flow_time_jump_abs_mean",
        "accepted_x_jump_sq_mean",
        "effective_x_jump_sq_mean",
        "runtime_sec",
        "samples",
    ]
    targets = ["chiral_re", "chiral_err", "abs_chiral_err", "density_re", "density_err"]
    out: list[dict[str, str]] = []
    float_rows = [dict((k, float(v) if isinstance(v, (int, float)) else float("nan")) for k, v in row.items() if not isinstance(v, str)) for row in rows]
    for target in targets:
        for metric in metric_names:
            xs, ys = finite_pair_rows(float_rows, metric, target)
            if len(xs) < 8:
                continue
            high_mean, low_mean, diff, high_n, low_n = quartile_diff(float_rows, metric, target)
            out.append(
                {
                    "target": target,
                    "metric": metric,
                    "n": str(len(xs)),
                    "pearson": f"{pearson(xs, ys):.8g}",
                    "spearman": f"{spearman(xs, ys):.8g}",
                    "high_metric_target_mean": f"{high_mean:.12g}",
                    "low_metric_target_mean": f"{low_mean:.12g}",
                    "high_minus_low_target_mean": f"{diff:.12g}",
                    "high_n": str(high_n),
                    "low_n": str(low_n),
                }
            )
    out.sort(key=lambda row: abs(to_float(row["spearman"])), reverse=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "target",
                "metric",
                "n",
                "pearson",
                "spearman",
                "high_metric_target_mean",
                "low_metric_target_mean",
                "high_minus_low_target_mean",
                "high_n",
                "low_n",
            ],
        )
        writer.writeheader()
        writer.writerows(out)
    return out


def by_record_summary(rows: list[dict[str, float | int | str]]) -> list[dict[str, str]]:
    groups: dict[int, list[dict[str, float | int | str]]] = {}
    for row in rows:
        groups.setdefault(int(row["init_bank_record"]), []).append(row)
    out: list[dict[str, str]] = []
    for record, rec_rows in sorted(groups.items()):
        chiral = [float(r["chiral_re"]) for r in rec_rows if math.isfinite(float(r["chiral_re"]))]
        flow_mean = [float(r["measurement_flow_time_hist_inside_mean_t"]) for r in rec_rows if math.isfinite(float(r["measurement_flow_time_hist_inside_mean_t"]))]
        if not chiral:
            continue
        out.append(
            {
                "init_bank_record": str(record),
                "seed_count": str(len(rec_rows)),
                "chiral_re_mean": f"{mean(chiral):.12g}",
                "chiral_re_median": f"{median(chiral):.12g}",
                "chiral_re_min": f"{min(chiral):.12g}",
                "chiral_re_max": f"{max(chiral):.12g}",
                "chiral_err_mean": f"{mean(chiral) - EXACT_CHIRAL:.12g}",
                "measurement_mean_t_mean": f"{mean(flow_mean):.12g}" if flow_mean else "",
            }
        )
    return out


def write_record_summary(path: Path, rows: list[dict[str, float | int | str]]) -> list[dict[str, str]]:
    out = by_record_summary(rows)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "init_bank_record",
                "seed_count",
                "chiral_re_mean",
                "chiral_re_median",
                "chiral_re_min",
                "chiral_re_max",
                "chiral_err_mean",
                "measurement_mean_t_mean",
            ],
        )
        writer.writeheader()
        writer.writerows(out)
    return out


def complex_from_row(row: dict[str, float | int | str], re_name: str, im_name: str) -> complex:
    re = float(row.get(re_name, float("nan")))
    im = float(row.get(im_name, float("nan")))
    if not math.isfinite(re) or not math.isfinite(im):
        return complex(float("nan"), float("nan"))
    return complex(re, im)


def write_influence(path: Path, rows: list[dict[str, float | int | str]]) -> list[dict[str, str]]:
    denoms: dict[int, complex] = {}
    numerators: dict[str, dict[int, complex]] = {"chiral": {}, "density": {}}
    row_by_seed: dict[int, dict[str, float | int | str]] = {}
    for row in rows:
        seed = int(row["seed"])
        denom = complex_from_row(row, "denominator_re", "denominator_im")
        if not math.isfinite(denom.real) or not math.isfinite(denom.imag):
            continue
        denoms[seed] = denom
        row_by_seed[seed] = row
        numerators["chiral"][seed] = denom * complex(float(row["chiral_re"]), float(row["chiral_im"]))
        numerators["density"][seed] = denom * complex(float(row["density_re"]), float(row["density_im"]))

    total_d = sum(denoms.values(), complex(0.0, 0.0))
    total_n = {name: sum(vals.values(), complex(0.0, 0.0)) for name, vals in numerators.items()}
    pooled = {name: total_n[name] / total_d for name in total_n}
    out: list[dict[str, str]] = []
    for seed, denom in denoms.items():
        loo_d = total_d - denom
        if abs(loo_d) == 0.0:
            continue
        row = row_by_seed[seed]
        loo = {name: (total_n[name] - numerators[name][seed]) / loo_d for name in total_n}
        chiral_delta = loo["chiral"] - pooled["chiral"]
        density_delta = loo["density"] - pooled["density"]
        out.append(
            {
                "seed": str(seed),
                "init_bank_record": str(row["init_bank_record"]),
                "phase_coherence_history": f"{float(row['phase_coherence_history']):.12g}",
                "abs_denominator": f"{float(row['abs_denominator']):.12g}",
                "denominator_arg": f"{float(row['denominator_arg']):.12g}",
                "seed_chiral_re": f"{float(row['chiral_re']):.12g}",
                "seed_density_re": f"{float(row['density_re']):.12g}",
                "pooled_chiral_re": f"{pooled['chiral'].real:.12g}",
                "loo_chiral_re": f"{loo['chiral'].real:.12g}",
                "loo_chiral_delta_re": f"{chiral_delta.real:.12g}",
                "abs_loo_chiral_delta": f"{abs(chiral_delta):.12g}",
                "pooled_density_re": f"{pooled['density'].real:.12g}",
                "loo_density_re": f"{loo['density'].real:.12g}",
                "loo_density_delta_re": f"{density_delta.real:.12g}",
                "abs_loo_density_delta": f"{abs(density_delta):.12g}",
                "measurement_mean_t": f"{float(row['measurement_flow_time_hist_inside_mean_t']):.12g}",
                "transition_failure_rate": f"{float(row['transition_failure_rate']):.12g}",
                "bounce_rate_per_step": f"{float(row['bounce_rate_per_step']):.12g}",
                "reverse_gate_reject_rate": f"{float(row['reverse_gate_reject_rate']):.12g}",
            }
        )
    out.sort(key=lambda row: to_float(row["abs_loo_chiral_delta"]), reverse=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "seed",
                "init_bank_record",
                "phase_coherence_history",
                "abs_denominator",
                "denominator_arg",
                "seed_chiral_re",
                "seed_density_re",
                "pooled_chiral_re",
                "loo_chiral_re",
                "loo_chiral_delta_re",
                "abs_loo_chiral_delta",
                "pooled_density_re",
                "loo_density_re",
                "loo_density_delta_re",
                "abs_loo_density_delta",
                "measurement_mean_t",
                "transition_failure_rate",
                "bounce_rate_per_step",
                "reverse_gate_reject_rate",
            ],
        )
        writer.writeheader()
        writer.writerows(out)
    return out


def write_summary(
    path: Path,
    rows: list[dict[str, float | int | str]],
    correlations: list[dict[str, str]],
    record_rows: list[dict[str, str]],
    influence_rows: list[dict[str, str]],
) -> None:
    chiral = [float(r["chiral_re"]) for r in rows]
    flow_mean = [float(r["measurement_flow_time_hist_inside_mean_t"]) for r in rows if math.isfinite(float(r["measurement_flow_time_hist_inside_mean_t"]))]
    high8 = [float(r["measurement_flow_time_hist_inside_high8_frac"]) for r in rows if math.isfinite(float(r["measurement_flow_time_hist_inside_high8_frac"]))]
    low8 = [float(r["measurement_flow_time_hist_inside_low8_frac"]) for r in rows if math.isfinite(float(r["measurement_flow_time_hist_inside_low8_frac"]))]
    top_chiral = [r for r in correlations if r["target"] in ("chiral_re", "chiral_err")][:12]
    top_abs = [r for r in correlations if r["target"] == "abs_chiral_err"][:8]
    with path.open("w") as handle:
        handle.write("# WV-HMC n=6 15k Seed Diagnostic Readback\n\n")
        handle.write("## Scope\n\n")
        handle.write("This is a diagnostic join of per-seed observables with production transition summaries. It does not assume any proposed formula bug is correct.\n\n")
        handle.write("## Panel Inventory\n\n")
        handle.write(f"- seeds: {len(rows)}\n")
        handle.write(f"- chiral target: {EXACT_CHIRAL:.10f}\n")
        handle.write(f"- seed chiral mean/median/min/max: {mean(chiral):.8g} / {median(chiral):.8g} / {min(chiral):.8g} / {max(chiral):.8g}\n")
        handle.write(f"- measurement mean flow-time mean/median: {mean(flow_mean):.8g} / {median(flow_mean):.8g}\n")
        handle.write(f"- measurement low8/high8 fraction mean: {mean(low8):.8g} / {mean(high8):.8g}\n\n")
        handle.write("## Strongest Chiral-Re Correlations\n\n")
        handle.write("| metric | target | spearman | pearson | high-low target mean |\n")
        handle.write("|---|---:|---:|---:|---:|\n")
        for row in top_chiral:
            handle.write(
                f"| {row['metric']} | {row['target']} | {row['spearman']} | {row['pearson']} | {row['high_minus_low_target_mean']} |\n"
            )
        handle.write("\n## Strongest Absolute-Chiral-Error Correlations\n\n")
        handle.write("| metric | spearman | pearson | high-low abs error |\n")
        handle.write("|---|---:|---:|---:|\n")
        for row in top_abs:
            handle.write(
                f"| {row['metric']} | {row['spearman']} | {row['pearson']} | {row['high_minus_low_target_mean']} |\n"
            )
        handle.write("\n## Init-Bank Record Summary\n\n")
        handle.write("| record | seeds | chiral mean | chiral err mean | mean t |\n")
        handle.write("|---:|---:|---:|---:|---:|\n")
        for row in record_rows:
            handle.write(
                f"| {row['init_bank_record']} | {row['seed_count']} | {row['chiral_re_mean']} | {row['chiral_err_mean']} | {row['measurement_mean_t_mean']} |\n"
            )
        handle.write("\n## Largest Leave-One-Seed-Out Chiral Influences\n\n")
        handle.write("| seed | record | C | seed chiral Re | LOO delta Re | abs LOO delta |\n")
        handle.write("|---:|---:|---:|---:|---:|---:|\n")
        for row in influence_rows[:12]:
            handle.write(
                f"| {row['seed']} | {row['init_bank_record']} | {row['phase_coherence_history']} | {row['seed_chiral_re']} | {row['loo_chiral_delta_re']} | {row['abs_loo_chiral_delta']} |\n"
            )
        handle.write("\n## Immediate Diagnostic Meaning\n\n")
        handle.write("- Use this table to identify which mechanism should receive the next invariant test or code audit.\n")
        handle.write("- A strong diagnostic correlation is not by itself a proof of causality or correctness.\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed-summary", required=True, type=Path)
    parser.add_argument("--raw-root", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    panel = build_panel(args.seed_summary, args.raw_root)
    write_panel(args.out_dir / "prod15k_seed_diagnostic_panel.csv", panel)
    correlations = write_correlations(args.out_dir / "prod15k_seed_diagnostic_correlations.csv", panel)
    record_rows = write_record_summary(args.out_dir / "prod15k_init_bank_record_summary.csv", panel)
    influence_rows = write_influence(args.out_dir / "prod15k_seed_leave_one_out_influence.csv", panel)
    write_summary(args.out_dir / "prod15k_seed_diagnostic_readback.md", panel, correlations, record_rows, influence_rows)


if __name__ == "__main__":
    main()
