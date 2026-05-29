#!/usr/bin/env python3
"""Analyze the fixed-tau nofb single-source run from binary observable histories."""

from __future__ import annotations

import argparse
from array import array
import csv
import json
import math
from pathlib import Path
import re
import statistics


DEFAULT_ROOT = Path(
    "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/"
    "stephanov_fixed_tau_nofb_init_tests/"
    "stephanov_n6_fixed_tau_t003_nofb_single_source473_512x10000_20260527h"
)
DEFAULT_OUT = DEFAULT_ROOT.parent / "analysis_single_source473_10000_20260528"
OBSERVABLES = [
    "chiral_condensate",
    "number_density",
    "logdet_dirac",
    "phase_factor",
    "min_singular_ba_m2",
]
EXACT_RE = {
    "chiral_condensate": 0.0244771983,
    "number_density": 0.5661155667,
}
WIDTH = 2 * (1 + len(OBSERVABLES))
PREFIXES = [1000, 3500, 5000, 8000, 10000, 10001]


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


def stdev(values: list[float]) -> float:
    return statistics.stdev(values) if len(values) > 1 else 0.0


def parse_summary(path: Path) -> dict[str, float | int]:
    out: dict[str, float | int] = {
        "accepts": 0,
        "rejects": 0,
        "accept_rate": 0.0,
        "samples": 0,
        "runtime_sec": 0.0,
        "metropolis_reject": 0,
        "reverse_gate_reject": 0,
        "proposal_failure": 0,
        "hamiltonian_invalid": 0,
        "delta_h_invalid": 0,
        "projection_fail": 0,
    }
    if not path.exists():
        return out
    next_slot = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("# local_transition_totals"):
            parts = line.replace("=", " ").split()
            for idx, token in enumerate(parts):
                if token in out and idx + 1 < len(parts):
                    try:
                        out[token] = int(parts[idx + 1])
                    except ValueError:
                        pass
        if line.startswith("# [slots]"):
            next_slot = True
            continue
        if next_slot and line.strip() and not line.startswith("#"):
            next_slot = False
            parts = line.split()
            if len(parts) >= 15:
                out["accepts"] = int(parts[3])
                out["rejects"] = int(parts[4])
                out["accept_rate"] = float(parts[5])
                out["projection_fail"] = int(parts[6])
                out["samples"] = int(parts[7])
                out["runtime_sec"] = float(parts[9])
                out["metropolis_reject"] = int(parts[10])
                out["reverse_gate_reject"] = int(parts[11])
                out["proposal_failure"] = int(parts[12])
                out["hamiltonian_invalid"] = int(parts[13])
                out["delta_h_invalid"] = int(parts[14])
    return out


def read_observable_prefix(path: Path, prefix: int) -> dict[str, object]:
    values = array("d")
    with path.open("rb") as handle:
        values.fromfile(handle, path.stat().st_size // 8)
    if len(values) % WIDTH != 0:
        raise RuntimeError(f"observable stream width mismatch: {path}")

    rows = len(values) // WIDTH
    used = min(prefix, rows)
    phi_sum = complex(0.0, 0.0)
    abs_sum = 0.0
    abs2_sum = 0.0
    numerators = [complex(0.0, 0.0) for _ in OBSERVABLES]
    for row_idx in range(used):
        offset = row_idx * WIDTH
        phi = complex(float(values[offset]), float(values[offset + 1]))
        phi_sum += phi
        abs_phi = abs(phi)
        abs_sum += abs_phi
        abs2_sum += abs_phi * abs_phi
        for obs_idx in range(len(OBSERVABLES)):
            obs_offset = offset + 2 + 2 * obs_idx
            obs_value = complex(float(values[obs_offset]), float(values[obs_offset + 1]))
            numerators[obs_idx] += phi * obs_value

    ratios = [
        numerator / phi_sum if abs(phi_sum) > 0.0 else complex(float("nan"), float("nan"))
        for numerator in numerators
    ]
    return {
        "samples": used,
        "D": phi_sum,
        "sum_abs_w": abs_sum,
        "sum_abs_w2": abs2_sum,
        "numerators": numerators,
        "ratios": ratios,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(DEFAULT_ROOT))
    parser.add_argument("--out", default="")
    parser.add_argument("--source-record", type=int, default=473)
    return parser.parse_args()


def discover_chains(root: Path, source_record: int) -> list[dict[str, object]]:
    chains: list[dict[str, object]] = []
    for run_dir in sorted(path for path in root.iterdir() if path.is_dir()):
        match = re.search(r"target_(\d+)_source_(\d+)", run_dir.name)
        if match:
            target = int(match.group(1))
            source = int(match.group(2))
        else:
            short_match = re.fullmatch(r"r(\d+)_t(\d+)", run_dir.name)
            if not short_match:
                continue
            target = int(short_match.group(2))
            source = source_record
        candidates = list((run_dir / "records").glob("record_*/observable_history.dat"))
        if not candidates:
            continue
        obs_path = candidates[0]
        chains.append(
            {
                "target": target,
                "source": source,
                "run": run_dir.name,
                "obs_path": obs_path,
                "summary": parse_summary(obs_path.parent / "summary.dat"),
            }
        )
    chains.sort(key=lambda row: int(row["target"]))
    return chains


def jk_error_complex(values: list[complex], part: str) -> float:
    xs = [getattr(value, part) for value in values if math.isfinite(getattr(value, part))]
    n = len(xs)
    if n < 2:
        return 0.0
    mean = sum(xs) / n
    return math.sqrt((n - 1) / n * sum((x - mean) ** 2 for x in xs))


def jk_error_scalar(values: list[float]) -> float:
    xs = [value for value in values if math.isfinite(value)]
    n = len(xs)
    if n < 2:
        return 0.0
    mean = sum(xs) / n
    return math.sqrt((n - 1) / n * sum((x - mean) ** 2 for x in xs))


def aggregate(prefix: int, rows: list[dict[str, object]]) -> list[dict[str, object]]:
    total_d = sum((row["data"]["D"] for row in rows), complex(0.0, 0.0))  # type: ignore[index]
    total_abs = sum(float(row["data"]["sum_abs_w"]) for row in rows)  # type: ignore[index]
    total_abs2 = sum(float(row["data"]["sum_abs_w2"]) for row in rows)  # type: ignore[index]
    total_samples = sum(int(row["data"]["samples"]) for row in rows)  # type: ignore[index]
    total_n = [
        sum((row["data"]["numerators"][obs_idx] for row in rows), complex(0.0, 0.0))  # type: ignore[index]
        for obs_idx in range(len(OBSERVABLES))
    ]
    estimates = [
        numerator / total_d if abs(total_d) > 0.0 else complex(float("nan"), float("nan"))
        for numerator in total_n
    ]

    jk_values = [[] for _ in OBSERVABLES]
    c_jk = []
    for leave_out in range(len(rows)):
        d = total_d - rows[leave_out]["data"]["D"]  # type: ignore[index]
        abs_w = total_abs - float(rows[leave_out]["data"]["sum_abs_w"])  # type: ignore[index]
        c_jk.append(abs(d) / abs_w if abs_w > 0.0 else float("nan"))
        for obs_idx in range(len(OBSERVABLES)):
            numerator = total_n[obs_idx] - rows[leave_out]["data"]["numerators"][obs_idx]  # type: ignore[index]
            jk_values[obs_idx].append(
                numerator / d if abs(d) > 0.0 else complex(float("nan"), float("nan"))
            )

    out = []
    for obs_idx, observable in enumerate(OBSERVABLES):
        estimate = estimates[obs_idx]
        se_re = jk_error_complex(jk_values[obs_idx], "real")
        se_im = jk_error_complex(jk_values[obs_idx], "imag")
        exact = EXACT_RE.get(observable, float("nan"))
        seed_estimates = [row["data"]["ratios"][obs_idx] for row in rows]  # type: ignore[index]
        out.append(
            {
                "prefix_samples_per_chain": prefix,
                "chains": len(rows),
                "samples_total": total_samples,
                "observable": observable,
                "estimate_re": estimate.real,
                "estimate_im": estimate.imag,
                "se_re_seed_jk": se_re,
                "se_im_seed_jk": se_im,
                "seed_std_re": stdev([value.real for value in seed_estimates]),
                "seed_std_im": stdev([value.imag for value in seed_estimates]),
                "exact_re": exact,
                "z_re": (estimate.real - exact) / se_re
                if observable in EXACT_RE and se_re > 0.0
                else float("nan"),
                "z_im": estimate.imag / se_im if se_im > 0.0 else float("nan"),
                "D_re": total_d.real,
                "D_im": total_d.imag,
                "abs_D": abs(total_d),
                "arg_D": math.atan2(total_d.imag, total_d.real),
                "sum_abs_w": total_abs,
                "phase_coherence": abs(total_d) / total_abs if total_abs > 0.0 else float("nan"),
                "phase_ESS": abs(total_d) ** 2 / total_abs2 if total_abs2 > 0.0 else float("nan"),
                "phase_C_jk_se": jk_error_scalar(c_jk),
            }
        )
    return out


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    root = Path(args.root)
    out = Path(args.out) if args.out else (root.parent / f"analysis_{root.name}")
    out.mkdir(parents=True, exist_ok=True)
    chains = discover_chains(root, args.source_record)
    prefix_rows: dict[int, list[dict[str, object]]] = {}
    for prefix in PREFIXES:
        rows = []
        for chain in chains:
            rows.append({**chain, "data": read_observable_prefix(chain["obs_path"], prefix)})  # type: ignore[arg-type]
        prefix_rows[prefix] = rows

    estimator_rows = []
    for prefix in PREFIXES:
        estimator_rows.extend(aggregate(prefix, prefix_rows[prefix]))
    write_csv(out / "estimator_summary.csv", estimator_rows)

    seed_rows = []
    for row in prefix_rows[10000]:
        data = row["data"]  # type: ignore[assignment]
        summary = row["summary"]  # type: ignore[assignment]
        seed_row: dict[str, object] = {
            "target": row["target"],
            "source": row["source"],
            "samples": data["samples"],  # type: ignore[index]
            "D_re": data["D"].real,  # type: ignore[index]
            "D_im": data["D"].imag,  # type: ignore[index]
            "abs_D": abs(data["D"]),  # type: ignore[arg-type,index]
            "arg_D": math.atan2(data["D"].imag, data["D"].real),  # type: ignore[index]
            "sum_abs_w": data["sum_abs_w"],  # type: ignore[index]
            "C": abs(data["D"]) / data["sum_abs_w"] if data["sum_abs_w"] else float("nan"),  # type: ignore[index]
            "phase_ESS": abs(data["D"]) ** 2 / data["sum_abs_w2"] if data["sum_abs_w2"] else float("nan"),  # type: ignore[index]
        }
        for obs_idx, observable in enumerate(OBSERVABLES):
            ratio = data["ratios"][obs_idx]  # type: ignore[index]
            seed_row[f"{observable}_re"] = ratio.real
            seed_row[f"{observable}_im"] = ratio.imag
        for key in [
            "accepts",
            "rejects",
            "accept_rate",
            "samples",
            "runtime_sec",
            "metropolis_reject",
            "reverse_gate_reject",
            "proposal_failure",
            "hamiltonian_invalid",
            "delta_h_invalid",
            "projection_fail",
        ]:
            seed_row[key] = summary.get(key, "")  # type: ignore[union-attr]
        seed_row["attempts"] = (
            int(summary.get("accepts", 0))  # type: ignore[union-attr]
            + int(summary.get("metropolis_reject", 0))  # type: ignore[union-attr]
            + int(summary.get("reverse_gate_reject", 0))  # type: ignore[union-attr]
            + int(summary.get("proposal_failure", 0))  # type: ignore[union-attr]
        )
        seed_rows.append(seed_row)
    write_csv(out / "seed_summary_10000.csv", seed_rows)

    accepts = [int(chain["summary"].get("accepts", 0)) for chain in chains]  # type: ignore[union-attr]
    acc_rates = [float(chain["summary"].get("accept_rate", 0.0)) for chain in chains]  # type: ignore[union-attr]
    proposal = [int(chain["summary"].get("proposal_failure", 0)) for chain in chains]  # type: ignore[union-attr]
    reverse = [int(chain["summary"].get("reverse_gate_reject", 0)) for chain in chains]  # type: ignore[union-attr]
    metropolis = [int(chain["summary"].get("metropolis_reject", 0)) for chain in chains]  # type: ignore[union-attr]
    runtime = [float(chain["summary"].get("runtime_sec", 0.0)) for chain in chains]  # type: ignore[union-attr]
    attempts_total = sum(accepts) + sum(proposal) + sum(reverse) + sum(metropolis)
    transition_summary = {
        "chains": len(chains),
        "zero_accept_chains": sum(1 for value in accepts if value == 0),
        "accepts_total": sum(accepts),
        "attempts_total": attempts_total,
        "accept_rate_over_attempts": sum(accepts) / attempts_total,
        "accept_rate_min": min(acc_rates),
        "accept_rate_q25": quantile(acc_rates, 0.25),
        "accept_rate_median": quantile(acc_rates, 0.5),
        "accept_rate_q75": quantile(acc_rates, 0.75),
        "accept_rate_max": max(acc_rates),
        "proposal_failure_total": sum(proposal),
        "proposal_failure_rate": sum(proposal) / attempts_total,
        "reverse_gate_reject_total": sum(reverse),
        "reverse_gate_reject_rate": sum(reverse) / attempts_total,
        "metropolis_reject_total": sum(metropolis),
        "metropolis_reject_rate": sum(metropolis) / attempts_total,
        "runtime_sec_min": min(runtime),
        "runtime_sec_median": quantile(runtime, 0.5),
        "runtime_sec_max": max(runtime),
        "estimated_parallel_wall_sec_16chunks": max(runtime),
        "estimated_node_hours_16nodes": 16 * max(runtime) / 3600.0,
    }
    (out / "transition_summary.json").write_text(
        json.dumps(transition_summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    low_keys = [
        "target",
        "source",
        "accept_rate",
        "accepts",
        "proposal_failure",
        "reverse_gate_reject",
        "metropolis_reject",
        "runtime_sec",
        "C",
        "phase_ESS",
        "chiral_condensate_re",
        "chiral_condensate_im",
        "number_density_re",
        "number_density_im",
    ]
    low_rows = sorted(seed_rows, key=lambda row: float(row["accept_rate"]))[:20]
    write_csv(out / "lowest_acceptance_20.csv", [{key: row[key] for key in low_keys} for row in low_rows])

    lines = [
        "# Fixed-tau nofb single source 473, 10k result",
        "",
        f"root: {root}",
        "cut: first 10000 observable-history samples per chain",
        f"chains: {len(chains)}",
        f"zero-accept chains: {transition_summary['zero_accept_chains']}",
        (
            "accept rate: "
            f"min={transition_summary['accept_rate_min']:.6f}, "
            f"median={transition_summary['accept_rate_median']:.6f}, "
            f"max={transition_summary['accept_rate_max']:.6f}"
        ),
        (
            "diagnostic rates: "
            f"proposal_failure={transition_summary['proposal_failure_rate']:.6f}, "
            f"reverse_gate_reject={transition_summary['reverse_gate_reject_rate']:.6f}, "
            f"metropolis_reject={transition_summary['metropolis_reject_rate']:.6f}"
        ),
        "",
    ]
    for row in estimator_rows:
        if row["prefix_samples_per_chain"] == 10000 and row["observable"] in {
            "chiral_condensate",
            "number_density",
            "phase_factor",
        }:
            lines.append(
                f"- {row['observable']}: "
                f"{row['estimate_re']:.10f} {row['estimate_im']:+.10f}i; "
                f"SE=({row['se_re_seed_jk']:.10f},{row['se_im_seed_jk']:.10f}); "
                f"z=({row['z_re']:.3f},{row['z_im']:.3f}); "
                f"C={row['phase_coherence']:.6f}; ESS={row['phase_ESS']:.1f}"
            )
    (out / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"OUT={out}")
    print(json.dumps(transition_summary, indent=2, sort_keys=True))
    print("KEY_ESTIMATES_PREFIX10000")
    for row in estimator_rows:
        if row["prefix_samples_per_chain"] == 10000 and row["observable"] in {
            "chiral_condensate",
            "number_density",
            "phase_factor",
        }:
            print(json.dumps(row, sort_keys=True))


if __name__ == "__main__":
    main()
