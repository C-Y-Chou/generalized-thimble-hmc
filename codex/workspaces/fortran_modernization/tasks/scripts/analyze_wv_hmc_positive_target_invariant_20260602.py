#!/usr/bin/env python3
"""WV-HMC positive-target invariant-measure gate.

This script compares WV-HMC Markov samples against a deterministic quadrature
oracle for the positive worldvolume target

    rho_+(x,t) proportional to exp(-Re S(z_t(x)) - W(t)) * alpha(x,t) * |det J_t(x)|.

It also checks the complex ratio estimator using the paper measurement factor
``phase / alpha``.  The goal is to test the ensemble-generation kernel, not only
the pointwise measurement formula.
"""

from __future__ import annotations

import argparse
import array
import cmath
import csv
import importlib.util
import json
import math
import os
import re
import struct
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


OBSERVABLE_FALLBACK = {
    1: "chiral_condensate",
    2: "number_density",
    3: "logdet_dirac",
    4: "phase_factor",
    5: "min_singular_ba_m2",
}

DEFAULT_EXACT_ANALYTIC = {
    "chiral_condensate": 0.380047505938398,
    "number_density": 0.0387173396674602,
}


def load_wv_identity_module():
    script = Path(__file__).with_name("run_stephanov_n2_wv_reweight_identity_20260531.py")
    spec = importlib.util.spec_from_file_location("wv_reweight_identity_20260531", str(script))
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load helper script: {}".format(script))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_complex(re_text: object, im_text: object) -> complex:
    return complex(float(re_text), float(im_text))


def safe_float(text: object, default: float = float("nan")) -> float:
    try:
        return float(text)
    except (TypeError, ValueError):
        return default


def safe_int(text: object, default: int = 0) -> int:
    try:
        return int(float(text))
    except (TypeError, ValueError):
        return default


def seed_from_path(path: Path) -> Optional[int]:
    match = re.search(r"seed_(\d+)_", path.name)
    return int(match.group(1)) if match else None


def discover_observable_histories(root: Path) -> List[Path]:
    paths = sorted(root.rglob("seed_*_observable_history.csv"))
    chosen: Dict[int, Path] = {}
    for path in paths:
        seed = seed_from_path(path)
        if seed is None:
            continue
        if seed not in chosen or "/combined" in str(path):
            chosen[seed] = path
    return [chosen[seed] for seed in sorted(chosen)]


def state_history_path_for_observable(path: Path) -> Path:
    return path.with_name(path.name.replace("_observable_history.csv", "_state_history.dat"))


def observable_names_for_history(path: Path, observable_count: int) -> List[str]:
    obs_path = path.with_name(path.name.replace("_observable_history.csv", "_observables.csv"))
    names: Dict[int, str] = {}
    if obs_path.exists():
        with obs_path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                idx = safe_int(row.get("index"), 0)
                if idx > 0 and row.get("name"):
                    names[idx] = row["name"]
    return [names.get(idx, OBSERVABLE_FALLBACK.get(idx, "obs_{}".format(idx))) for idx in range(1, observable_count + 1)]


def infer_observable_count(fieldnames: Sequence[str]) -> int:
    count = 0
    for name in fieldnames:
        match = re.match(r"obs_(\d+)_re$", name)
        if match:
            count = max(count, int(match.group(1)))
    if count <= 0:
        raise RuntimeError("observable history has no obs_* columns")
    return count


class SeedAggregate:
    def __init__(self, seed: int, observable_names: Sequence[str]):
        self.seed = seed
        self.observable_names = list(observable_names)
        self.samples = 0
        self.t_sum = 0.0
        self.t2_sum = 0.0
        self.alpha_sum = 0.0
        self.alpha2_sum = 0.0
        self.x2_sum = 0.0
        self.x2_samples = 0
        self.obs_sum = {name: complex(0.0, 0.0) for name in observable_names}
        self.ratio_d = complex(0.0, 0.0)
        self.ratio_abs_w = 0.0
        self.ratio_n = {name: complex(0.0, 0.0) for name in observable_names}

    def add_history_row(self, row: Dict[str, str]) -> None:
        self.samples += 1
        flow_time = safe_float(row["flow_time"])
        alpha = safe_float(row["alpha"])
        alpha2 = safe_float(row["alpha2"])
        self.t_sum += flow_time
        self.t2_sum += flow_time * flow_time
        self.alpha_sum += alpha
        self.alpha2_sum += alpha2
        self.ratio_d += parse_complex(row["weight_re"], row["weight_im"])
        self.ratio_abs_w += safe_float(row["abs_weight"])
        for idx, name in enumerate(self.observable_names, start=1):
            obs = parse_complex(row["obs_{}_re".format(idx)], row["obs_{}_im".format(idx)])
            num = parse_complex(row["num_{}_re".format(idx)], row["num_{}_im".format(idx)])
            self.obs_sum[name] += obs
            self.ratio_n[name] += num

    def add_state_rows(self, state_rows: Sequence[Sequence[float]]) -> None:
        for row in state_rows:
            if len(row) <= 1:
                continue
            x = row[1:]
            self.x2_sum += sum(value * value for value in x) / float(len(x))
            self.x2_samples += 1


class TotalAggregate:
    def __init__(self, observable_names: Sequence[str]):
        self.observable_names = list(observable_names)
        self.samples = 0
        self.t_sum = 0.0
        self.t2_sum = 0.0
        self.alpha_sum = 0.0
        self.alpha2_sum = 0.0
        self.x2_sum = 0.0
        self.x2_samples = 0
        self.obs_sum = {name: complex(0.0, 0.0) for name in observable_names}
        self.ratio_d = complex(0.0, 0.0)
        self.ratio_abs_w = 0.0
        self.ratio_n = {name: complex(0.0, 0.0) for name in observable_names}

    def add_seed(self, seed: SeedAggregate) -> None:
        self.samples += seed.samples
        self.t_sum += seed.t_sum
        self.t2_sum += seed.t2_sum
        self.alpha_sum += seed.alpha_sum
        self.alpha2_sum += seed.alpha2_sum
        self.x2_sum += seed.x2_sum
        self.x2_samples += seed.x2_samples
        self.ratio_d += seed.ratio_d
        self.ratio_abs_w += seed.ratio_abs_w
        for name in self.observable_names:
            self.obs_sum[name] += seed.obs_sum[name]
            self.ratio_n[name] += seed.ratio_n[name]


def subtract_seed(total: TotalAggregate, seed: SeedAggregate) -> TotalAggregate:
    out = TotalAggregate(total.observable_names)
    out.samples = total.samples - seed.samples
    out.t_sum = total.t_sum - seed.t_sum
    out.t2_sum = total.t2_sum - seed.t2_sum
    out.alpha_sum = total.alpha_sum - seed.alpha_sum
    out.alpha2_sum = total.alpha2_sum - seed.alpha2_sum
    out.x2_sum = total.x2_sum - seed.x2_sum
    out.x2_samples = total.x2_samples - seed.x2_samples
    out.ratio_d = total.ratio_d - seed.ratio_d
    out.ratio_abs_w = total.ratio_abs_w - seed.ratio_abs_w
    for name in total.observable_names:
        out.obs_sum[name] = total.obs_sum[name] - seed.obs_sum[name]
        out.ratio_n[name] = total.ratio_n[name] - seed.ratio_n[name]
    return out


def scalar_metrics(total: TotalAggregate) -> Dict[str, complex]:
    samples = float(total.samples)
    x2_samples = float(total.x2_samples)
    metrics: Dict[str, complex] = {}
    if samples > 0.0:
        metrics["positive.flow_time_mean"] = complex(total.t_sum / samples, 0.0)
        metrics["positive.flow_time_second"] = complex(total.t2_sum / samples, 0.0)
        metrics["noalpha.flow_time_mean"] = metrics["positive.flow_time_mean"]
        metrics["noalpha.flow_time_second"] = metrics["positive.flow_time_second"]
        metrics["positive.alpha_mean"] = complex(total.alpha_sum / samples, 0.0)
        metrics["positive.alpha2_mean"] = complex(total.alpha2_sum / samples, 0.0)
        metrics["noalpha.alpha_mean"] = metrics["positive.alpha_mean"]
        metrics["noalpha.alpha2_mean"] = metrics["positive.alpha2_mean"]
        for name in total.observable_names:
            metrics["positive.{}.mean".format(name)] = total.obs_sum[name] / samples
            metrics["noalpha.{}.mean".format(name)] = metrics["positive.{}.mean".format(name)]
    if x2_samples > 0.0:
        metrics["positive.x2_per_coord_mean"] = complex(total.x2_sum / x2_samples, 0.0)
        metrics["noalpha.x2_per_coord_mean"] = metrics["positive.x2_per_coord_mean"]
    if abs(total.ratio_d) > 0.0:
        for name in total.observable_names:
            metrics["ratio.{}".format(name)] = total.ratio_n[name] / total.ratio_d
        metrics["ratio.phase_coherence"] = complex(
            abs(total.ratio_d) / total.ratio_abs_w if total.ratio_abs_w > 0.0 else float("nan"), 0.0
        )
    return metrics


def jk_se(values: Sequence[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / float(n)
    return math.sqrt((n - 1.0) / n * sum((value - mean) ** 2 for value in values))


def read_state_history(path: Path, state_size: int) -> List[List[float]]:
    if not path.exists():
        return []
    raw = path.read_bytes()
    record_size = (state_size + 1) * 8
    if len(raw) % record_size != 0:
        raise RuntimeError("state history size mismatch: {} bytes={} record={}".format(path, len(raw), record_size))
    rows = []
    for offset in range(0, len(raw), record_size):
        rows.append(list(struct.unpack_from("<" + "d" * (state_size + 1), raw, offset)))
    return rows


def read_seed_aggregate(path: Path, state_size: int) -> SeedAggregate:
    seed = seed_from_path(path)
    if seed is None:
        raise RuntimeError("cannot infer seed from {}".format(path))
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise RuntimeError("missing header in {}".format(path))
        observable_count = infer_observable_count(reader.fieldnames)
        names = observable_names_for_history(path, observable_count)
        aggregate = SeedAggregate(seed, names)
        for row in reader:
            aggregate.add_history_row(row)
    state_path = state_history_path_for_observable(path)
    state_rows = read_state_history(state_path, state_size)
    if state_rows and len(state_rows) != aggregate.samples:
        raise RuntimeError("history row mismatch seed={} observable={} state={}".format(
            seed, aggregate.samples, len(state_rows)
        ))
    aggregate.add_state_rows(state_rows)
    return aggregate


def read_simulation_aggregates(root: Path, state_size: int) -> Tuple[List[str], List[SeedAggregate]]:
    histories = discover_observable_histories(root)
    if not histories:
        raise RuntimeError("no seed_*_observable_history.csv files found under {}".format(root))
    aggregates = [read_seed_aggregate(path, state_size) for path in histories]
    names = aggregates[0].observable_names
    for aggregate in aggregates:
        if aggregate.observable_names != names:
            raise RuntimeError("observable-name mismatch for seed {}".format(aggregate.seed))
    return names, aggregates


def paper_wall_value(helper, flow_time: float, args) -> float:
    return helper.paper_wall_value(flow_time, args.t0, args.t1, args.d0, args.d1, args.gamma, args.c0, args.c1)[0]


def compute_exact_oracle(args, helper) -> Dict[str, object]:
    out_dir = args.oracle_work_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    state_size = 2 * args.n_model * args.n_model
    target_times, t_weights = helper.legendre_interval(args.t_order, args.t0, args.t1)
    x_bank, weights_csv, count = helper.generate_gh_bank(out_dir, args.order, args.n_model)
    bank_dir = out_dir / "positive_target_flow_bank_k{}_t{}".format(args.order, args.t_order)
    if not args.skip_oracle_build:
        env = os.environ.copy()
        env["TLTM_PARAMETERS_FILE"] = args.parameters_file
        subprocess.run(
            [
                args.flow_bank_binary,
                str(x_bank),
                str(bank_dir),
                ",".join("{:.17g}".format(value) for value in target_times),
                "0",
                str(count),
            ],
            check=True,
            env=env,
        )

    positive_d = 0.0
    positive_sums: Dict[str, complex] = {
        "positive.flow_time_mean": complex(0.0, 0.0),
        "positive.flow_time_second": complex(0.0, 0.0),
        "positive.x2_per_coord_mean": complex(0.0, 0.0),
        "positive.alpha_mean": complex(0.0, 0.0),
        "positive.alpha2_mean": complex(0.0, 0.0),
    }
    ratio_d = complex(0.0, 0.0)
    ratio_abs_d = 0.0
    ratio_sums: Dict[str, complex] = {}
    direct_d = complex(0.0, 0.0)
    direct_sums: Dict[str, complex] = {}
    positive_obs_sums: Dict[str, complex] = {}
    noalpha_d = 0.0
    noalpha_sums: Dict[str, complex] = {
        "noalpha.flow_time_mean": complex(0.0, 0.0),
        "noalpha.flow_time_second": complex(0.0, 0.0),
        "noalpha.x2_per_coord_mean": complex(0.0, 0.0),
        "noalpha.alpha_mean": complex(0.0, 0.0),
        "noalpha.alpha2_mean": complex(0.0, 0.0),
    }
    noalpha_obs_sums: Dict[str, complex] = {}
    max_pointwise_rel_error = 0.0
    samples = 0
    unavailable = 0

    with weights_csv.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rec = int(row["source_record"])
            gh_weight = float(row["weight"])
            for slot_id, t_weight in enumerate(t_weights):
                slot = bank_dir / "records" / "record_{:06d}".format(rec) / "slot_{:06d}.bin".format(slot_id)
                available, flow_time, x, z, jac = helper.read_slot(slot, state_size)
                if available != 1:
                    unavailable += 1
                    if not args.allow_missing_oracle_slots:
                        raise RuntimeError("unavailable oracle slot rec={} slot={}".format(rec, slot_id))
                    continue
                samples += 1
                action = helper.action_value(z, args.n_model, args.nf, args.mass, args.mu, args.tau)
                det_j = helper.det_matrix(jac)
                grad = helper.stephanov_gradient(z, args.n_model, args.nf, args.mass, args.mu, args.tau)
                xi = [value.conjugate() for value in grad]
                alpha, alpha2 = helper.alpha_from_jacobian_and_xi(jac, xi)
                chiral, density = helper.stephanov_observables(z, args.n_model, args.mass, args.mu, args.tau)
                observables = {
                    "chiral_condensate": chiral,
                    "number_density": density,
                }
                w_value = paper_wall_value(helper, flow_time, args)
                base = gh_weight * t_weight * math.exp(float(args.n_model) * sum(value * value for value in x))
                positive_weight = base * math.exp(-action.real - w_value) * alpha * abs(det_j)
                noalpha_weight = base * math.exp(-action.real - w_value) * abs(det_j)
                direct_weight = base * cmath.exp(-action - w_value) * det_j
                phase = cmath.exp(-1j * action.imag) * det_j / abs(det_j)
                ratio_weight = positive_weight * phase / alpha
                positive_d += positive_weight
                noalpha_d += noalpha_weight
                ratio_d += ratio_weight
                ratio_abs_d += positive_weight * abs(phase / alpha)
                direct_d += direct_weight
                x2 = sum(value * value for value in x) / float(len(x))
                positive_sums["positive.flow_time_mean"] += positive_weight * flow_time
                positive_sums["positive.flow_time_second"] += positive_weight * flow_time * flow_time
                positive_sums["positive.x2_per_coord_mean"] += positive_weight * x2
                positive_sums["positive.alpha_mean"] += positive_weight * alpha
                positive_sums["positive.alpha2_mean"] += positive_weight * alpha2
                noalpha_sums["noalpha.flow_time_mean"] += noalpha_weight * flow_time
                noalpha_sums["noalpha.flow_time_second"] += noalpha_weight * flow_time * flow_time
                noalpha_sums["noalpha.x2_per_coord_mean"] += noalpha_weight * x2
                noalpha_sums["noalpha.alpha_mean"] += noalpha_weight * alpha
                noalpha_sums["noalpha.alpha2_mean"] += noalpha_weight * alpha2
                for name, obs in observables.items():
                    positive_obs_sums[name] = positive_obs_sums.get(name, complex(0.0, 0.0)) + positive_weight * obs
                    noalpha_obs_sums[name] = noalpha_obs_sums.get(name, complex(0.0, 0.0)) + noalpha_weight * obs
                    ratio_sums[name] = ratio_sums.get(name, complex(0.0, 0.0)) + ratio_weight * obs
                    direct_sums[name] = direct_sums.get(name, complex(0.0, 0.0)) + direct_weight * obs
                max_pointwise_rel_error = max(
                    max_pointwise_rel_error,
                    abs(ratio_weight - direct_weight) / max(1.0, abs(direct_weight)),
                )

    exact: Dict[str, complex] = {}
    for name, value in positive_sums.items():
        exact[name] = value / positive_d
    for name, value in positive_obs_sums.items():
        exact["positive.{}.mean".format(name)] = value / positive_d
    for name, value in noalpha_sums.items():
        exact[name] = value / noalpha_d
    for name, value in noalpha_obs_sums.items():
        exact["noalpha.{}.mean".format(name)] = value / noalpha_d
    for name, value in ratio_sums.items():
        exact["ratio.{}".format(name)] = value / ratio_d
        exact["direct.{}".format(name)] = direct_sums[name] / direct_d
    exact["ratio.phase_coherence"] = complex(abs(ratio_d) / ratio_abs_d, 0.0)

    return {
        "exact": exact,
        "positive_denominator": positive_d,
        "noalpha_denominator": noalpha_d,
        "ratio_denominator_re": ratio_d.real,
        "ratio_denominator_im": ratio_d.imag,
        "ratio_abs_denominator": ratio_abs_d,
        "direct_denominator_re": direct_d.real,
        "direct_denominator_im": direct_d.imag,
        "oracle_samples": samples,
        "oracle_unavailable_slots": unavailable,
        "target_times": target_times,
        "target_time_weights": t_weights,
        "max_pointwise_ratio_direct_rel_error": max_pointwise_rel_error,
        "order": args.order,
        "t_order": args.t_order,
        "flow_bank_dir": str(bank_dir),
    }


def comparison_rows(exact: Dict[str, complex], estimate: Dict[str, complex], jk_estimates: List[Dict[str, complex]], args):
    rows = []
    metric_names = sorted(name for name in exact if name in estimate)
    for metric in metric_names:
        values_re = [entry[metric].real for entry in jk_estimates if metric in entry and math.isfinite(entry[metric].real)]
        values_im = [entry[metric].imag for entry in jk_estimates if metric in entry and math.isfinite(entry[metric].imag)]
        se_re = jk_se(values_re)
        se_im = jk_se(values_im)
        est = estimate[metric]
        ref = exact[metric]
        z_re = (est.real - ref.real) / se_re if math.isfinite(se_re) and se_re > 0.0 else float("nan")
        z_im = (est.imag - ref.imag) / se_im if math.isfinite(se_im) and se_im > 0.0 else float("nan")
        is_primary = (
            metric in {
                "positive.flow_time_mean",
                "positive.flow_time_second",
                "positive.x2_per_coord_mean",
                "positive.alpha_mean",
                "positive.alpha2_mean",
                "positive.chiral_condensate.mean",
                "positive.number_density.mean",
                "ratio.chiral_condensate",
                "ratio.number_density",
            }
        )
        max_abs_z = max(abs(z) for z in [z_re, z_im] if math.isfinite(z)) if any(math.isfinite(z) for z in [z_re, z_im]) else float("nan")
        status = "pass"
        if is_primary and (not math.isfinite(max_abs_z) or max_abs_z > args.z_fail_threshold):
            status = "fail"
        elif is_primary and max_abs_z > args.z_warn_threshold:
            status = "warn"
        rows.append({
            "metric": metric,
            "primary_gate": int(is_primary),
            "exact_re": ref.real,
            "exact_im": ref.imag,
            "estimate_re": est.real,
            "estimate_im": est.imag,
            "se_re": se_re,
            "se_im": se_im,
            "z_re": z_re,
            "z_im": z_im,
            "max_abs_z": max_abs_z,
            "status": status,
        })
    return rows


def write_outputs(out_dir: Path, args, exact_payload: Dict[str, object], seed_aggregates: List[SeedAggregate], rows: List[Dict[str, object]]) -> Dict[str, str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    comparison_csv = out_dir / "positive_target_invariant_comparison.csv"
    with comparison_csv.open("w", newline="") as handle:
        fieldnames = [
            "metric", "primary_gate", "exact_re", "exact_im", "estimate_re", "estimate_im",
            "se_re", "se_im", "z_re", "z_im", "max_abs_z", "status",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    seed_csv = out_dir / "positive_target_seed_aggregates.csv"
    with seed_csv.open("w", newline="") as handle:
        fieldnames = [
            "seed", "samples", "x2_samples", "flow_time_mean", "x2_per_coord_mean",
            "alpha_mean", "phase_coherence",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for seed in seed_aggregates:
            writer.writerow({
                "seed": seed.seed,
                "samples": seed.samples,
                "x2_samples": seed.x2_samples,
                "flow_time_mean": seed.t_sum / seed.samples if seed.samples else float("nan"),
                "x2_per_coord_mean": seed.x2_sum / seed.x2_samples if seed.x2_samples else float("nan"),
                "alpha_mean": seed.alpha_sum / seed.samples if seed.samples else float("nan"),
                "phase_coherence": abs(seed.ratio_d) / seed.ratio_abs_w if seed.ratio_abs_w > 0.0 else float("nan"),
            })

    fail_rows = [row for row in rows if row["primary_gate"] and row["status"] == "fail"]
    warn_rows = [row for row in rows if row["primary_gate"] and row["status"] == "warn"]
    status = "fail" if fail_rows else ("warn" if warn_rows else "pass")
    metadata = {
        "status": status,
        "run_root": str(args.run_root),
        "output_root": str(out_dir),
        "seeds": len(seed_aggregates),
        "samples": sum(seed.samples for seed in seed_aggregates),
        "x2_samples": sum(seed.x2_samples for seed in seed_aggregates),
        "z_warn_threshold": args.z_warn_threshold,
        "z_fail_threshold": args.z_fail_threshold,
        "oracle": {
            key: value for key, value in exact_payload.items() if key != "exact"
        },
        "failed_metrics": [row["metric"] for row in fail_rows],
        "warn_metrics": [row["metric"] for row in warn_rows],
    }
    metadata_json = out_dir / "positive_target_invariant_metadata.json"
    metadata_json.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    md_path = out_dir / "positive_target_invariant_readback.md"
    with md_path.open("w", encoding="utf-8") as handle:
        handle.write("# WV-HMC Positive-Target Invariant Gate\n\n")
        handle.write("Status: `{}`\n\n".format(status))
        handle.write("This gate compares Markov samples against the deterministic positive worldvolume target, not only against final physical observables.\n\n")
        handle.write("## Setup\n\n")
        handle.write("- run root: `{}`\n".format(args.run_root))
        handle.write("- seeds: `{}`\n".format(len(seed_aggregates)))
        handle.write("- samples: `{}`\n".format(metadata["samples"]))
        handle.write("- oracle GH/t orders: `{}` / `{}`\n".format(args.order, args.t_order))
        handle.write("- target interval: `[{}, {}]`\n".format(args.t0, args.t1))
        handle.write("- W profile: `paper_wall`, gamma `{}`\n".format(args.gamma))
        handle.write("- oracle available slots: `{}`\n".format(exact_payload["oracle_samples"]))
        handle.write("- oracle unavailable slots: `{}`\n".format(exact_payload["oracle_unavailable_slots"]))
        handle.write("- oracle missing slots allowed: `{}`\n".format(int(args.allow_missing_oracle_slots)))
        handle.write("- max pointwise ratio-direct relative error: `{:.3e}`\n\n".format(
            float(exact_payload["max_pointwise_ratio_direct_rel_error"])
        ))
        handle.write("## Primary Gates\n\n")
        handle.write("| metric | exact Re | estimate Re | SE Re | z Re | exact Im | estimate Im | SE Im | z Im | status |\n")
        handle.write("|---|---:|---:|---:|---:|---:|---:|---:|---:|---|\n")
        for row in rows:
            if not row["primary_gate"]:
                continue
            handle.write(
                "| {metric} | {exact_re:.8g} | {estimate_re:.8g} | {se_re:.3g} | {z_re:.3g} | "
                "{exact_im:.8g} | {estimate_im:.8g} | {se_im:.3g} | {z_im:.3g} | {status} |\n".format(**row)
            )
        handle.write("\nArtifacts:\n\n")
        handle.write("- `{}`\n".format(comparison_csv))
        handle.write("- `{}`\n".format(seed_csv))
        handle.write("- `{}`\n".format(metadata_json))
    return {
        "comparison_csv": str(comparison_csv),
        "seed_csv": str(seed_csv),
        "metadata_json": str(metadata_json),
        "readback_md": str(md_path),
        "status": status,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--oracle-work-dir", type=Path, required=True)
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n2_smoke.dat")
    parser.add_argument("--flow-bank-binary", default="bin/build_flow_bank_dense")
    parser.add_argument("--order", type=int, default=3)
    parser.add_argument("--t-order", type=int, default=5)
    parser.add_argument("--t0", type=float, default=0.0)
    parser.add_argument("--t1", type=float, default=0.01)
    parser.add_argument("--d0", type=float, default=0.0)
    parser.add_argument("--d1", type=float, default=0.0025)
    parser.add_argument("--c0", type=float, default=1.0)
    parser.add_argument("--c1", type=float, default=1.0)
    parser.add_argument("--gamma", type=float, default=0.0)
    parser.add_argument("--n-model", type=int, default=2)
    parser.add_argument("--nf", type=int, default=1)
    parser.add_argument("--mass", type=float, default=0.2)
    parser.add_argument("--mu", type=float, default=0.3)
    parser.add_argument("--tau", type=float, default=0.1)
    parser.add_argument("--state-size", type=int, default=8)
    parser.add_argument("--skip-oracle-build", action="store_true")
    parser.add_argument("--allow-missing-oracle-slots", action="store_true")
    parser.add_argument("--z-warn-threshold", type=float, default=3.0)
    parser.add_argument("--z-fail-threshold", type=float, default=4.0)
    parser.add_argument("--no-fail-exit", action="store_true")
    args = parser.parse_args()

    helper = load_wv_identity_module()
    exact_payload = compute_exact_oracle(args, helper)
    names, seed_aggregates = read_simulation_aggregates(args.run_root, args.state_size)
    total = TotalAggregate(names)
    for seed in seed_aggregates:
        total.add_seed(seed)
    estimate = scalar_metrics(total)
    jk_estimates = [scalar_metrics(subtract_seed(total, seed)) for seed in seed_aggregates]
    rows = comparison_rows(exact_payload["exact"], estimate, jk_estimates, args)
    outputs = write_outputs(args.output_root, args, exact_payload, seed_aggregates, rows)
    print("status={}".format(outputs["status"]))
    print("readback_md={}".format(outputs["readback_md"]))
    print("comparison_csv={}".format(outputs["comparison_csv"]))
    if outputs["status"] == "fail" and not args.no_fail_exit:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
