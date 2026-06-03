#!/usr/bin/env python3
"""Build a WV-HMC state bank by resampling the exact small-N positive target.

The output bank has the standard WV state-bank layout:

    flow_time, x_1, ..., x_state_size

This is a diagnostic tool for one-step invariant-measure tests.  It does not
change the sampler transition.  The intended use is:

1. build deterministic quadrature candidates for
   exp(-Re S(z_t(x)) - W(t)) * alpha(x,t) * |det J_t(x)|;
2. resample those candidates with equal output weights;
3. start one WV-HMC chain per selected record and run one or a few transitions;
4. compare post-transition samples to the same exact positive target.
"""

from __future__ import print_function

import argparse
import array
import bisect
import cmath
import csv
import importlib.util
import json
import math
import os
import random
import subprocess
from pathlib import Path


def load_wv_identity_module():
    script = Path(__file__).with_name("run_stephanov_n2_wv_reweight_identity_20260531.py")
    spec = importlib.util.spec_from_file_location("wv_reweight_identity_20260531", str(script))
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load helper script: {0}".format(script))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def paper_wall_value(helper, flow_time, args):
    return helper.paper_wall_value(flow_time, args.t0, args.t1, args.d0, args.d1, args.gamma, args.c0, args.c1)[0]


def complex_pair(value):
    return {"re": value.real, "im": value.imag}


def positive_metrics(candidates, weights):
    total_w = sum(weights)
    if total_w <= 0.0:
        raise RuntimeError("nonpositive total weight")
    metrics = {
        "positive.flow_time_mean": sum(w * c["flow_time"] for c, w in zip(candidates, weights)) / total_w,
        "positive.flow_time_second": sum(w * c["flow_time"] * c["flow_time"] for c, w in zip(candidates, weights)) / total_w,
        "positive.x2_per_coord_mean": sum(w * c["x2"] for c, w in zip(candidates, weights)) / total_w,
        "positive.alpha_mean": sum(w * c["alpha"] for c, w in zip(candidates, weights)) / total_w,
        "positive.alpha2_mean": sum(w * c["alpha2"] for c, w in zip(candidates, weights)) / total_w,
    }
    for name in ("chiral_condensate", "number_density"):
        value = sum(w * c[name] for c, w in zip(candidates, weights)) / total_w
        metrics["positive.{0}.mean".format(name)] = complex_pair(value)
    return metrics


def finite_log(value):
    if value <= 0.0 or not math.isfinite(value):
        return None
    return math.log(value)


def build_candidates(args, helper):
    args.oracle_work_dir.mkdir(parents=True, exist_ok=True)
    state_size = 2 * args.n_model * args.n_model
    target_times, t_weights = helper.legendre_interval(args.t_order, args.t0, args.t1)
    x_bank, weights_csv, count = helper.generate_gh_bank(args.oracle_work_dir, args.order, args.n_model)
    bank_dir = args.oracle_work_dir / "positive_target_flow_bank_k{0}_t{1}".format(args.order, args.t_order)
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

    candidates = []
    unavailable = 0
    skipped = 0
    with weights_csv.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rec = int(row["source_record"])
            gh_weight = float(row["weight"])
            log_gh = finite_log(gh_weight)
            if log_gh is None:
                skipped += len(t_weights)
                continue
            for slot_id, t_weight in enumerate(t_weights):
                log_t = finite_log(t_weight)
                if log_t is None:
                    skipped += 1
                    continue
                slot = bank_dir / "records" / "record_{:06d}".format(rec) / "slot_{:06d}.bin".format(slot_id)
                available, flow_time, x, z, jac = helper.read_slot(slot, state_size)
                if available != 1:
                    unavailable += 1
                    if not args.allow_missing_oracle_slots:
                        raise RuntimeError("unavailable oracle slot rec={0} slot={1}".format(rec, slot_id))
                    continue
                action = helper.action_value(z, args.n_model, args.nf, args.mass, args.mu, args.tau)
                det_j = helper.det_matrix(jac)
                abs_det_j = abs(det_j)
                if abs_det_j <= 0.0 or not math.isfinite(abs_det_j):
                    skipped += 1
                    continue
                grad = helper.stephanov_gradient(z, args.n_model, args.nf, args.mass, args.mu, args.tau)
                xi = [value.conjugate() for value in grad]
                alpha, alpha2 = helper.alpha_from_jacobian_and_xi(jac, xi)
                w_value = paper_wall_value(helper, flow_time, args)
                x2_sum = sum(value * value for value in x)
                log_weight = (
                    log_gh + log_t + float(args.n_model) * x2_sum
                    - action.real - w_value + math.log(alpha) + math.log(abs_det_j)
                )
                if not math.isfinite(log_weight):
                    skipped += 1
                    continue
                chiral, density = helper.stephanov_observables(z, args.n_model, args.mass, args.mu, args.tau)
                phase = cmath.exp(-1j * action.imag) * det_j / abs_det_j
                candidates.append({
                    "source_record": rec,
                    "slot_id": slot_id,
                    "flow_time": flow_time,
                    "x": x,
                    "x2": x2_sum / float(len(x)),
                    "alpha": alpha,
                    "alpha2": alpha2,
                    "log_abs_det_j": math.log(abs_det_j),
                    "log_weight": log_weight,
                    "chiral_condensate": chiral,
                    "number_density": density,
                    "phase_re": phase.real,
                    "phase_im": phase.imag,
                })
    if not candidates:
        raise RuntimeError("no oracle candidates were available")
    return candidates, {
        "target_times": target_times,
        "target_time_weights": t_weights,
        "oracle_flow_bank_dir": str(bank_dir),
        "oracle_source_records": count,
        "oracle_candidates": len(candidates),
        "oracle_unavailable_slots": unavailable,
        "oracle_skipped_slots": skipped,
    }


def normalized_weights(candidates):
    max_log = max(candidate["log_weight"] for candidate in candidates)
    raw = [math.exp(candidate["log_weight"] - max_log) for candidate in candidates]
    total = sum(raw)
    if total <= 0.0 or not math.isfinite(total):
        raise RuntimeError("invalid normalized weight total")
    return [value / total for value in raw]


def systematic_resample(weights, sample_count, seed):
    rng = random.Random(seed)
    cumulative = []
    total = 0.0
    for weight in weights:
        total += weight
        cumulative.append(total)
    cumulative[-1] = 1.0
    start = rng.random() / float(sample_count)
    indices = []
    for k in range(sample_count):
        target = start + float(k) / float(sample_count)
        indices.append(min(len(cumulative) - 1, bisect.bisect_left(cumulative, target)))
    return indices


def multinomial_resample(weights, sample_count, seed):
    rng = random.Random(seed)
    cumulative = []
    total = 0.0
    for weight in weights:
        total += weight
        cumulative.append(total)
    cumulative[-1] = 1.0
    return [min(len(cumulative) - 1, bisect.bisect_left(cumulative, rng.random())) for _ in range(sample_count)]


def write_outputs(args, candidates, weights, indices, oracle_meta):
    args.output.parent.mkdir(parents=True, exist_ok=True)
    selected = [candidates[idx] for idx in indices]
    selected_weights = [1.0 for _ in selected]
    with args.output.open("wb") as handle:
        for candidate in selected:
            packed = array.array("d", [candidate["flow_time"]])
            packed.extend(candidate["x"])
            packed.tofile(handle)

    reference_csv = args.output.with_suffix(args.output.suffix + ".reference.csv")
    with reference_csv.open("w", newline="") as handle:
        fieldnames = [
            "record", "candidate_index", "source_record", "slot_id", "flow_time",
            "x2_per_coord", "alpha", "alpha2", "log_abs_det_j", "normalized_weight",
            "chiral_re", "chiral_im", "density_re", "density_im", "phase_re", "phase_im",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for record, idx in enumerate(indices):
            candidate = candidates[idx]
            writer.writerow({
                "record": record,
                "candidate_index": idx,
                "source_record": candidate["source_record"],
                "slot_id": candidate["slot_id"],
                "flow_time": "{:.17g}".format(candidate["flow_time"]),
                "x2_per_coord": "{:.17g}".format(candidate["x2"]),
                "alpha": "{:.17g}".format(candidate["alpha"]),
                "alpha2": "{:.17g}".format(candidate["alpha2"]),
                "log_abs_det_j": "{:.17g}".format(candidate["log_abs_det_j"]),
                "normalized_weight": "{:.17g}".format(weights[idx]),
                "chiral_re": "{:.17g}".format(candidate["chiral_condensate"].real),
                "chiral_im": "{:.17g}".format(candidate["chiral_condensate"].imag),
                "density_re": "{:.17g}".format(candidate["number_density"].real),
                "density_im": "{:.17g}".format(candidate["number_density"].imag),
                "phase_re": "{:.17g}".format(candidate["phase_re"]),
                "phase_im": "{:.17g}".format(candidate["phase_im"]),
            })

    oracle_metrics = positive_metrics(candidates, weights)
    selected_metrics = positive_metrics(selected, selected_weights)
    metadata = {
        "state_bank": str(args.output),
        "reference_csv": str(reference_csv),
        "sample_count": len(selected),
        "resample_method": args.resample_method,
        "resample_seed": args.resample_seed,
        "order": args.order,
        "t_order": args.t_order,
        "t0": args.t0,
        "t1": args.t1,
        "d0": args.d0,
        "d1": args.d1,
        "gamma": args.gamma,
        "c0": args.c0,
        "c1": args.c1,
        "n_model": args.n_model,
        "state_size": args.state_size,
        "oracle": oracle_meta,
        "oracle_positive_metrics": oracle_metrics,
        "resampled_positive_metrics": selected_metrics,
    }
    metadata_json = args.output.with_suffix(args.output.suffix + ".metadata.json")
    metadata_json.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("state_bank={0}".format(args.output))
    print("reference_csv={0}".format(reference_csv))
    print("metadata_json={0}".format(metadata_json))
    print("records={0}".format(len(selected)))
    print("oracle_candidates={0}".format(oracle_meta["oracle_candidates"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--oracle-work-dir", type=Path, required=True)
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n2_smoke.dat")
    parser.add_argument("--flow-bank-binary", default="bin/build_flow_bank_dense")
    parser.add_argument("--order", type=int, default=3)
    parser.add_argument("--t-order", type=int, default=5)
    parser.add_argument("--sample-count", type=int, default=512)
    parser.add_argument("--resample-seed", type=int, default=20260602)
    parser.add_argument("--resample-method", default="systematic", choices=("systematic", "multinomial"))
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
    args = parser.parse_args()

    if args.sample_count < 1:
        raise SystemExit("--sample-count must be positive")
    if args.state_size != 2 * args.n_model * args.n_model:
        raise SystemExit("--state-size does not match n-model")

    helper = load_wv_identity_module()
    candidates, oracle_meta = build_candidates(args, helper)
    weights = normalized_weights(candidates)
    if args.resample_method == "systematic":
        indices = systematic_resample(weights, args.sample_count, args.resample_seed)
    else:
        indices = multinomial_resample(weights, args.sample_count, args.resample_seed)
    write_outputs(args, candidates, weights, indices, oracle_meta)


if __name__ == "__main__":
    main()
