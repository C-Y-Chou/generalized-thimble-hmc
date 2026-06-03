#!/usr/bin/env python3
"""History-aware WV-HMC production-validation readback.

This script consumes per-seed ``seed_*_observable_history.csv`` files written by
``run_wv_hmc_dense_observable_validation_20260529.py``.  It preserves the
complex ratio estimator by jackknifing block sums of numerator and denominator,
not independently resampled observables.
"""

import argparse
import array
import csv
import json
import math
import re
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


DEFAULT_EXACT = {
    "chiral_condensate": 0.380047505938398,
    "number_density": 0.0387173396674602,
}
EXACT = dict(DEFAULT_EXACT)

OBSERVABLE_FALLBACK = {
    1: "chiral_condensate",
    2: "number_density",
}


class Sample:
    def __init__(self, seed, cycle, flow_time, weight, abs_weight, numerators):
        self.seed = seed
        self.cycle = cycle
        self.flow_time = flow_time
        self.weight = weight
        self.abs_weight = abs_weight
        self.numerators = numerators


class Block:
    def __init__(self, seed, cycle_start, cycle_end, samples, d_sum, abs_w_sum, numerators):
        self.seed = seed
        self.cycle_start = cycle_start
        self.cycle_end = cycle_end
        self.samples = samples
        self.d_sum = d_sum
        self.abs_w_sum = abs_w_sum
        self.numerators = numerators


def parse_complex(re_text: str, im_text: str) -> complex:
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


def jk_se(values: Sequence[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    mean = sum(values) / float(n)
    return math.sqrt((n - 1.0) / n * sum((value - mean) ** 2 for value in values))


def parse_int_list(text: str) -> List[int]:
    out = []
    for part in text.split(","):
        part = part.strip()
        if part:
            out.append(int(part))
    return out


def discover_observable_histories(root: Path) -> List[Path]:
    paths = sorted(root.rglob("seed_*_observable_history.csv"))
    chosen: Dict[int, Path] = {}
    duplicates: Dict[int, List[Path]] = {}
    for path in paths:
        seed = seed_from_path(path)
        if seed is None:
            continue
        if seed in chosen:
            duplicates.setdefault(seed, [chosen[seed]]).append(path)
            if "/combined" in str(path):
                chosen[seed] = path
        else:
            chosen[seed] = path
    return [chosen[seed] for seed in sorted(chosen)]


def seed_from_path(path: Path) -> Optional[int]:
    match = re.search(r"seed_(\d+)_", path.name)
    return int(match.group(1)) if match else None


def observable_names_for_history(path: Path, observable_count: int) -> List[str]:
    obs_path = path.with_name(path.name.replace("_observable_history.csv", "_observables.csv"))
    names: Dict[int, str] = {}
    if obs_path.exists():
        with obs_path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                idx = safe_int(row.get("index"), 0)
                if idx > 0 and row.get("name"):
                    names[idx] = row["name"]
    return [names.get(idx, OBSERVABLE_FALLBACK.get(idx, "obs_{0}".format(idx)))
            for idx in range(1, observable_count + 1)]


def infer_observable_count(fieldnames: Sequence[str]) -> int:
    count = 0
    for name in fieldnames:
        match = re.match(r"num_(\d+)_re$", name)
        if match:
            count = max(count, int(match.group(1)))
    if count <= 0:
        raise RuntimeError("observable history has no num_* columns")
    return count


def read_history(path: Path) -> Tuple[List[str], List[Sample]]:
    seed = seed_from_path(path)
    if seed is None:
        raise RuntimeError("cannot infer seed from {0}".format(path))
    samples: List[Sample] = []
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise RuntimeError("missing header in {0}".format(path))
        observable_count = infer_observable_count(reader.fieldnames)
        names = observable_names_for_history(path, observable_count)
        for row in reader:
            numerators = [
                parse_complex(row["num_{0}_re".format(idx)], row["num_{0}_im".format(idx)])
                for idx in range(1, observable_count + 1)
            ]
            samples.append(Sample(
                seed=seed,
                cycle=safe_int(row["cycle"]),
                flow_time=safe_float(row["flow_time"]),
                weight=parse_complex(row["weight_re"], row["weight_im"]),
                abs_weight=safe_float(row["abs_weight"]),
                numerators=numerators,
            ))
    return names, samples


def total_from_samples(samples: Sequence[Sample], observable_count: int) -> Block:
    block = empty_block(-1, 0, 0, observable_count)
    if samples:
        block.cycle_start = min(sample.cycle for sample in samples)
        block.cycle_end = max(sample.cycle for sample in samples)
    for sample in samples:
        add_sample(block, sample)
    return block


def empty_block(seed: int, cycle_start: int, cycle_end: int, observable_count: int) -> Block:
    return Block(
        seed=seed,
        cycle_start=cycle_start,
        cycle_end=cycle_end,
        samples=0,
        d_sum=complex(0.0, 0.0),
        abs_w_sum=0.0,
        numerators=[complex(0.0, 0.0) for _ in range(observable_count)],
    )


def add_sample(block: Block, sample: Sample) -> None:
    block.samples += 1
    block.d_sum += sample.weight
    block.abs_w_sum += sample.abs_weight
    for idx, value in enumerate(sample.numerators):
        block.numerators[idx] += value


def add_block(target: Block, source: Block) -> None:
    target.samples += source.samples
    target.d_sum += source.d_sum
    target.abs_w_sum += source.abs_w_sum
    target.cycle_start = min(target.cycle_start, source.cycle_start)
    target.cycle_end = max(target.cycle_end, source.cycle_end)
    for idx, value in enumerate(source.numerators):
        target.numerators[idx] += value


def subtract_block(total: Block, source: Block) -> Block:
    out = Block(
        seed=-1,
        cycle_start=total.cycle_start,
        cycle_end=total.cycle_end,
        samples=total.samples - source.samples,
        d_sum=total.d_sum - source.d_sum,
        abs_w_sum=total.abs_w_sum - source.abs_w_sum,
        numerators=[left - right for left, right in zip(total.numerators, source.numerators)],
    )
    return out


def estimates_from_block(block: Block) -> List[complex]:
    if abs(block.d_sum) == 0.0:
        return [complex(float("nan"), float("nan")) for _ in block.numerators]
    return [numerator / block.d_sum for numerator in block.numerators]


def phase_coherence(block: Block) -> float:
    if block.abs_w_sum <= 0.0:
        return float("nan")
    return abs(block.d_sum) / block.abs_w_sum


def make_seed_blocks(samples: Sequence[Sample], observable_count: int) -> List[Block]:
    by_seed: Dict[int, Block] = {}
    for sample in samples:
        if sample.seed not in by_seed:
            by_seed[sample.seed] = empty_block(sample.seed, sample.cycle, sample.cycle, observable_count)
        block = by_seed[sample.seed]
        block.cycle_start = min(block.cycle_start, sample.cycle)
        block.cycle_end = max(block.cycle_end, sample.cycle)
        add_sample(block, sample)
    return [by_seed[seed] for seed in sorted(by_seed)]


def make_cycle_blocks(samples: Sequence[Sample], block_cycles: int, observable_count: int) -> List[Block]:
    by_key: Dict[Tuple[int, int], Block] = {}
    for sample in samples:
        block_index = sample.cycle // block_cycles
        start = block_index * block_cycles
        end = start + block_cycles - 1
        key = (sample.seed, block_index)
        if key not in by_key:
            by_key[key] = empty_block(sample.seed, start, end, observable_count)
        add_sample(by_key[key], sample)
    return [by_key[key] for key in sorted(by_key)]


def summarize_with_jackknife(
    label: str,
    error_method: str,
    blocks: Sequence[Block],
    observable_names: Sequence[str],
) -> List[Dict[str, object]]:
    if not blocks:
        return []
    observable_count = len(observable_names)
    total = empty_block(-1, min(block.cycle_start for block in blocks), max(block.cycle_end for block in blocks),
                        observable_count)
    for block in blocks:
        add_block(total, block)
    estimates = estimates_from_block(total)
    jk_values = [[] for _ in observable_names]
    for block in blocks:
        leave = subtract_block(total, block)
        leave_estimates = estimates_from_block(leave)
        for idx, value in enumerate(leave_estimates):
            jk_values[idx].append(value)

    rows = []
    for idx, name in enumerate(observable_names):
        estimate = estimates[idx]
        se_re = jk_se([value.real for value in jk_values[idx]])
        se_im = jk_se([value.imag for value in jk_values[idx]])
        target = EXACT.get(name)
        rows.append({
            "cut": label,
            "error_method": error_method,
            "blocks": len(blocks),
            "seeds": len(set(block.seed for block in blocks if block.seed >= 0)),
            "samples": total.samples,
            "cycle_start": total.cycle_start,
            "cycle_end": total.cycle_end,
            "phase_coherence": phase_coherence(total),
            "denominator_re": total.d_sum.real,
            "denominator_im": total.d_sum.imag,
            "abs_denominator": abs(total.d_sum),
            "sum_abs_weight": total.abs_w_sum,
            "observable": name,
            "estimate_re": estimate.real,
            "estimate_im": estimate.imag,
            "se_re": se_re,
            "se_im": se_im,
            "target_re": target if target is not None else "",
            "target_im": 0.0 if target is not None else "",
            "z_re": (estimate.real - target) / se_re if target is not None and se_re > 0.0 else "",
            "z_im": estimate.imag / se_im if target is not None and se_im > 0.0 else "",
        })
    return rows


def filter_cut(samples: Sequence[Sample], cycle_end: Optional[int] = None,
               cycle_start: Optional[int] = None) -> List[Sample]:
    out = []
    for sample in samples:
        if cycle_start is not None and sample.cycle < cycle_start:
            continue
        if cycle_end is not None and sample.cycle > cycle_end:
            continue
        out.append(sample)
    return out


def seed_summary(samples: Sequence[Sample], observable_names: Sequence[str]) -> List[Dict[str, object]]:
    observable_count = len(observable_names)
    rows = []
    for block in make_seed_blocks(samples, observable_count):
        estimates = estimates_from_block(block)
        row: Dict[str, object] = {
            "seed": block.seed,
            "samples": block.samples,
            "cycle_start": block.cycle_start,
            "cycle_end": block.cycle_end,
            "phase_coherence": phase_coherence(block),
            "denominator_re": block.d_sum.real,
            "denominator_im": block.d_sum.imag,
            "abs_denominator": abs(block.d_sum),
            "sum_abs_weight": block.abs_w_sum,
        }
        for idx, name in enumerate(observable_names):
            row["{0}_re".format(name)] = estimates[idx].real
            row["{0}_im".format(name)] = estimates[idx].imag
        rows.append(row)
    return rows


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def collect_manifest_rows(root: Path) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    for path in sorted(root.rglob("wv_hmc_dense_observable_validation_manifest.csv")):
        rows.extend(read_csv_rows(path))
    return rows


def collect_summary_rows(root: Path) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    for path in sorted(root.rglob("seed_*_summary.csv")):
        if "/readback/" in str(path):
            continue
        for row in read_csv_rows(path):
            row = dict(row)
            row["summary_path"] = str(path)
            rows.append(row)
    return rows


def summarize_run_metadata(summary_rows: Sequence[Dict[str, str]],
                           manifest_rows: Sequence[Dict[str, str]]) -> Dict[str, object]:
    cycles = sum(safe_int(row.get("cycles_completed")) for row in summary_rows)
    accepted = sum(safe_int(row.get("accepted")) for row in summary_rows)
    rejected = sum(safe_int(row.get("rejected")) for row in summary_rows)
    transitions_failed = sum(safe_int(row.get("transitions_failed")) for row in summary_rows)
    metropolis_rejected = sum(safe_int(row.get("metropolis_rejected")) for row in summary_rows)
    reverse_gate_rejected = sum(safe_int(row.get("reverse_gate_rejected")) for row in summary_rows)
    reverse_gate_checked = sum(safe_int(row.get("reverse_gate_checked")) for row in summary_rows)
    reverse_gate_failed = sum(safe_int(row.get("reverse_gate_failed")) for row in summary_rows)
    runtime_sec = sum(safe_float(row.get("runtime_sec"), 0.0) for row in manifest_rows)
    return {
        "summary_seed_rows": len(summary_rows),
        "manifest_seed_rows": len(manifest_rows),
        "cycles_completed": cycles,
        "accepted": accepted,
        "rejected": rejected,
        "acceptance_rate_including_rejects": accepted / float(accepted + rejected) if accepted + rejected > 0 else float("nan"),
        "transitions_failed": transitions_failed,
        "metropolis_rejected": metropolis_rejected,
        "reverse_gate_rejected": reverse_gate_rejected,
        "reverse_gate_checked": reverse_gate_checked,
        "reverse_gate_failed": reverse_gate_failed,
        "runtime_sec_sum_over_seeds": runtime_sec,
    }


def read_state_history_metrics(history_path: Path, state_size: int) -> Dict[str, object]:
    width = state_size + 1
    values = array.array("d")
    with history_path.open("rb") as handle:
        values.fromfile(handle, history_path.stat().st_size // 8)
    if len(values) % width != 0:
        return {
            "state_history_path": str(history_path),
            "state_history_rows": 0,
            "state_history_error": "width_mismatch",
        }
    rows = len(values) // width
    if rows <= 0:
        return {
            "state_history_path": str(history_path),
            "state_history_rows": 0,
            "state_history_error": "",
        }
    flow_values = [values[idx * width] for idx in range(rows)]
    jump_sum = 0.0
    jump_count = 0
    span_min = [float("inf")] * state_size
    span_max = [float("-inf")] * state_size
    previous: Optional[List[float]] = None
    for row_idx in range(rows):
        offset = row_idx * width + 1
        x = [values[offset + idx] for idx in range(state_size)]
        for idx, value in enumerate(x):
            span_min[idx] = min(span_min[idx], value)
            span_max[idx] = max(span_max[idx], value)
        if previous is not None:
            jump_sum += sum((left - right) ** 2 for left, right in zip(x, previous))
            jump_count += 1
        previous = x
    span_sq = sum((hi - lo) ** 2 for lo, hi in zip(span_min, span_max))
    return {
        "state_history_path": str(history_path),
        "state_history_rows": rows,
        "state_flow_min": min(flow_values),
        "state_flow_max": max(flow_values),
        "state_flow_mean": sum(flow_values) / float(rows),
        "state_x_span_sq": span_sq,
        "state_x_successive_jump_sq_mean": jump_sum / float(jump_count) if jump_count else float("nan"),
        "state_history_error": "",
    }


def collect_state_history_metrics(root: Path, state_size: int) -> List[Dict[str, object]]:
    rows = []
    for path in sorted(root.rglob("seed_*_state_history.dat")):
        seed = seed_from_path(path)
        row = read_state_history_metrics(path, state_size)
        row["seed"] = seed if seed is not None else ""
        rows.append(row)
    return rows


def write_csv(path: Path, rows: Sequence[Dict[str, object]], fieldnames: Optional[Sequence[str]] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        keys: List[str] = []
        for row in rows:
            for key in row:
                if key not in keys:
                    keys.append(key)
        fieldnames = keys
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fieldnames))
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def strongest_z(rows: Sequence[Dict[str, object]]) -> Tuple[str, float]:
    best_label = ""
    best_value = -1.0
    for row in rows:
        if row.get("cut") != "all":
            continue
        if row.get("error_method") != "seed_jackknife":
            continue
        for part in ("z_re", "z_im"):
            value = row.get(part)
            if value == "":
                continue
            z_abs = abs(float(value))
            if z_abs > best_value:
                best_value = z_abs
                best_label = "{0} {1}".format(row.get("observable"), part)
    return best_label, best_value


def write_markdown(path: Path, root: Path, metadata: Dict[str, object],
                   estimator_rows: Sequence[Dict[str, object]],
                   state_rows: Sequence[Dict[str, object]]) -> None:
    all_seed_rows = [row for row in estimator_rows
                     if row.get("cut") == "all" and row.get("error_method") == "seed_jackknife"]
    all_block_rows = [row for row in estimator_rows
                      if row.get("cut") == "all" and str(row.get("error_method", "")).startswith("block_")]
    best_label, best_value = strongest_z(estimator_rows)
    lines = [
        "# WV-HMC History Readback",
        "",
        "Input root: `{0}`".format(root),
        "",
        "## Run Metadata",
        "",
        "| item | value |",
        "|---|---:|",
    ]
    for key in [
        "summary_seed_rows", "manifest_seed_rows", "cycles_completed", "accepted", "rejected",
        "acceptance_rate_including_rejects", "transitions_failed", "metropolis_rejected",
        "reverse_gate_rejected", "reverse_gate_checked", "reverse_gate_failed",
        "runtime_sec_sum_over_seeds",
    ]:
        value = metadata.get(key, "")
        lines.append("| {0} | {1} |".format(key, value))
    lines.extend([
        "",
        "## Production Gate Signal",
        "",
        "- strongest all-cut seed-jackknife exact-reference z: `{0}` = `{1:.3g}`".format(
            best_label, best_value
        ) if best_value >= 0.0 else "- strongest all-cut seed-jackknife exact-reference z: unavailable",
        "- block rows available: `{0}`".format(len(all_block_rows)),
        "- state-history rows available: `{0}`".format(len(state_rows)),
        "",
        "## All-Cut Seed Jackknife",
        "",
        "| observable | Re | SE Re | z Re | Im | SE Im | z Im | phase coherence | samples |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ])
    for row in all_seed_rows:
        lines.append("| {observable} | {estimate_re:.9g} | {se_re:.3g} | {z_re} | {estimate_im:.9g} | {se_im:.3g} | {z_im} | {phase:.6g} | {samples} |".format(
            observable=row["observable"],
            estimate_re=float(row["estimate_re"]),
            se_re=float(row["se_re"]),
            z_re="{:.3g}".format(float(row["z_re"])) if row["z_re"] != "" else "",
            estimate_im=float(row["estimate_im"]),
            se_im=float(row["se_im"]),
            z_im="{:.3g}".format(float(row["z_im"])) if row["z_im"] != "" else "",
            phase=float(row["phase_coherence"]),
            samples=row["samples"],
        ))
    lines.extend([
        "",
        "Artifacts are written next to this Markdown file.",
    ])
    path.write_text("\n".join(lines) + "\n")


def main() -> None:
    global EXACT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--prefix-cycles", default="5000,10000,15000,20000,30000,50000")
    parser.add_argument("--block-cycle-sizes", default="250,500,1000,2500,5000")
    parser.add_argument("--state-size", type=int, default=8)
    parser.add_argument("--exact-chiral", type=float, default=DEFAULT_EXACT["chiral_condensate"])
    parser.add_argument("--exact-density", type=float, default=DEFAULT_EXACT["number_density"])
    args = parser.parse_args()
    EXACT = {
        "chiral_condensate": args.exact_chiral,
        "number_density": args.exact_density,
    }

    history_paths = discover_observable_histories(args.root)
    if not history_paths:
        raise SystemExit("no seed_*_observable_history.csv files found under {0}".format(args.root))

    observable_names: Optional[List[str]] = None
    samples: List[Sample] = []
    for path in history_paths:
        names, path_samples = read_history(path)
        if observable_names is None:
            observable_names = names
        elif observable_names != names:
            raise RuntimeError("observable names differ for {0}".format(path))
        samples.extend(path_samples)
    if observable_names is None:
        raise RuntimeError("no observable names inferred")
    samples.sort(key=lambda sample: (sample.seed, sample.cycle))

    summary_rows = collect_summary_rows(args.root)
    manifest_rows = collect_manifest_rows(args.root)
    metadata = summarize_run_metadata(summary_rows, manifest_rows)
    metadata.update({
        "history_files": len(history_paths),
        "history_samples": len(samples),
        "cycle_min": min(sample.cycle for sample in samples),
        "cycle_max": max(sample.cycle for sample in samples),
        "observable_names": observable_names,
    })

    estimator_rows: List[Dict[str, object]] = []
    cuts: List[Tuple[str, List[Sample]]] = [("all", samples)]
    cycle_min = min(sample.cycle for sample in samples)
    cycle_max = max(sample.cycle for sample in samples)
    midpoint = (cycle_min + cycle_max) // 2
    cuts.append(("first_half", filter_cut(samples, cycle_end=midpoint)))
    cuts.append(("second_half", filter_cut(samples, cycle_start=midpoint + 1)))
    for prefix in parse_int_list(args.prefix_cycles):
        prefix_samples = filter_cut(samples, cycle_end=prefix)
        if prefix_samples:
            cuts.append(("prefix_{0}".format(prefix), prefix_samples))

    for cut_name, cut_samples in cuts:
        if not cut_samples:
            continue
        seed_blocks = make_seed_blocks(cut_samples, len(observable_names))
        estimator_rows.extend(summarize_with_jackknife(cut_name, "seed_jackknife", seed_blocks, observable_names))
        for block_cycles in parse_int_list(args.block_cycle_sizes):
            blocks = make_cycle_blocks(cut_samples, block_cycles, len(observable_names))
            estimator_rows.extend(summarize_with_jackknife(
                cut_name, "block_{0}_cycle_jackknife".format(block_cycles), blocks, observable_names
            ))

    seed_rows = seed_summary(samples, observable_names)
    state_rows = collect_state_history_metrics(args.root, args.state_size)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    estimator_path = args.out_dir / "wv_hmc_history_estimator_summary.csv"
    seed_path = args.out_dir / "wv_hmc_history_seed_summary.csv"
    state_path = args.out_dir / "wv_hmc_history_state_summary.csv"
    metadata_path = args.out_dir / "wv_hmc_history_metadata.json"
    markdown_path = args.out_dir / "wv_hmc_history_readback.md"

    write_csv(estimator_path, estimator_rows)
    write_csv(seed_path, seed_rows)
    write_csv(state_path, state_rows)
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    write_markdown(markdown_path, args.root, metadata, estimator_rows, state_rows)

    for path in [markdown_path, estimator_path, seed_path, state_path, metadata_path]:
        print(path)


if __name__ == "__main__":
    main()
