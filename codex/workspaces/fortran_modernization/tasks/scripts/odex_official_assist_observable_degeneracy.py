#!/usr/bin/env python3
"""Paired observable readback for official DFO-LS ODEX assist on/off evidence."""

import csv
import math
import subprocess
from pathlib import Path


EVIDENCE_ROOT = (
    "codex/workspaces/fortran_modernization/state/"
    "odex_official_dfols_assist_onoff_20260511"
)
SUMMARY_OUT = (
    "codex/workspaces/fortran_modernization/state/"
    "ODEX_OFFICIAL_ASSIST_OBSERVABLE_DEGENERACY_SUMMARY.tsv"
)
REPORT_OUT = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "ODEX_OFFICIAL_ASSIST_OBSERVABLE_DEGENERACY_READBACK_20260512.md"
)
SOURCE_READBACK = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "ODEX_OFFICIAL_ASSIST_ONOFF_READBACK_20260511.md"
)


def repo_root():
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        stdout=subprocess.PIPE,
        universal_newlines=True,
    )
    return Path(result.stdout.strip()).resolve()


def git_head(root):
    result = subprocess.run(
        ["git", "rev-parse", "--short=12", "HEAD"],
        cwd=str(root),
        check=True,
        stdout=subprocess.PIPE,
        universal_newlines=True,
    )
    return result.stdout.strip()


def read_manifest_value(path, key):
    if not path.exists():
        return ""
    prefix = key + "="
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line.split("=", 1)[1].strip()
    return ""


def load_per_seed(root, variant):
    path = root / EVIDENCE_ROOT / variant / "per_seed_summary_table.csv"
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    indexed = {}
    for row in rows:
        if row.get("method") != "fb_norefine":
            raise ValueError("{0} expected method fb_norefine, got {1}".format(path, row.get("method")))
        indexed[row["seed_id"]] = row
    return indexed


def as_float(row, key):
    value = row.get(key, "")
    if value == "":
        return 0.0
    return float(value)


def as_int(row, key):
    return int(round(as_float(row, key)))


def fmt(value, digits=10):
    if isinstance(value, float):
        if not math.isfinite(value):
            return "NA"
        return "{0:.{1}g}".format(value, digits)
    return str(value)


def mean(values):
    return sum(values) / float(len(values)) if values else 0.0


def sample_std(values):
    if len(values) < 2:
        return 0.0
    mu = mean(values)
    return math.sqrt(sum((value - mu) ** 2 for value in values) / float(len(values) - 1))


def paired_metric(seeds, on_rows, off_rows, label, key):
    on_values = [as_float(on_rows[seed], key) for seed in seeds]
    off_values = [as_float(off_rows[seed], key) for seed in seeds]
    deltas = [off - on for on, off in zip(on_values, off_values)]
    delta_std = sample_std(deltas)
    delta_se = delta_std / math.sqrt(float(len(deltas))) if deltas else 0.0
    delta_mean = mean(deltas)
    if delta_se > 0.0:
        delta_z = delta_mean / delta_se
    else:
        delta_z = 0.0
    return {
        "metric": label,
        "n_seed": len(seeds),
        "assist_on_mean": mean(on_values),
        "assist_off_mean": mean(off_values),
        "delta_off_minus_on_mean": delta_mean,
        "delta_seed_std": delta_std,
        "delta_se": delta_se,
        "delta_z": delta_z,
        "delta_min": min(deltas) if deltas else 0.0,
        "delta_max": max(deltas) if deltas else 0.0,
        "positive_delta_count": sum(1 for value in deltas if value > 0.0),
        "negative_delta_count": sum(1 for value in deltas if value < 0.0),
    }


def write_summary(root, rows):
    path = root / SUMMARY_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "metric",
        "n_seed",
        "assist_on_mean",
        "assist_off_mean",
        "delta_off_minus_on_mean",
        "delta_seed_std",
        "delta_se",
        "delta_z",
        "delta_min",
        "delta_max",
        "positive_delta_count",
        "negative_delta_count",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: fmt(row[key], 12) for key in fields})


def conclusion_tag(rows):
    observable_rows = [row for row in rows if row["metric"] in ("Ohat_Re", "Ohat_Im")]
    max_abs_z = max(abs(row["delta_z"]) for row in observable_rows)
    if max_abs_z >= 2.0:
        return "observable_shift_detected_at_10seed_10k"
    return "no_observable_degeneracy_conclusion_at_10seed_10k"


def write_report(root, seeds, rows, values):
    path = root / REPORT_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    by_metric = {row["metric"]: row for row in rows}
    tag = values["conclusion"]
    lines = [
        "# ODEX Official Assist Observable-Degeneracy Readback",
        "",
        "Updated: 2026-05-12 JST",
        "",
        "Scope: paired per-seed observable readback for the existing official",
        "DFO-LS ODEX solver-internal assist on/off evidence. Both variants use",
        "`fb_norefine`; the only intended difference is",
        "`INTODE_SOLVER_ASSIST_ENABLED=1` versus `0`.",
        "",
        "## Provenance",
        "",
        "- Evidence root: `{root}`.".format(root=EVIDENCE_ROOT),
        "- Source aggregate readback: `{source}`.".format(source=SOURCE_READBACK),
        "- Run commit recorded by manifest: `{commit}`.".format(commit=values["run_commit"] or "unknown"),
        "- Local HEAD when this readback was generated: `{head}`.".format(head=values["head"]),
        "- Seeds paired: `{seeds}`.".format(seeds=", ".join(seeds)),
        "- Scale: 10 seeds x 10000 cycles, `t=0.35,L=2,nstep=20`, official DFO-LS `stable_gate77`.",
        "",
        "## Paired Metrics",
        "",
        "| metric | n | assist on mean | assist off mean | off - on mean | SE(delta) | Z(delta) | + / - seed deltas |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {metric} | {n_seed} | {assist_on_mean} | {assist_off_mean} | {delta} | {se} | {z} | {pos}/{neg} |".format(
                metric=row["metric"],
                n_seed=row["n_seed"],
                assist_on_mean=fmt(row["assist_on_mean"], 12),
                assist_off_mean=fmt(row["assist_off_mean"], 12),
                delta=fmt(row["delta_off_minus_on_mean"], 12),
                se=fmt(row["delta_se"], 12),
                z=fmt(row["delta_z"], 12),
                pos=row["positive_delta_count"],
                neg=row["negative_delta_count"],
            )
        )
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- Solver-health degeneracy is present at this scale: unresolved failures increase from `{on_fail}` to `{off_fail}` (`+{fail_delta}`), and Newton/QN h-min failures change from `0/0` to `{off_newton_hmin}/{off_qn_hmin}` when assist is disabled.".format(
                **values
            ),
            "- Observable readout is not yet a production-grade degeneracy conclusion: paired `Ohat_Re` delta Z is `{zre}` and paired `Ohat_Im` delta Z is `{zim}`.".format(
                zre=fmt(by_metric["Ohat_Re"]["delta_z"], 12),
                zim=fmt(by_metric["Ohat_Im"]["delta_z"], 12),
            ),
            "- Conclusion tag: `{tag}`.".format(tag=tag),
            "",
            "Current conclusion: the existing 10seed x 10k evidence proves that",
            "assist-off degrades solver health, but it does not prove an actual",
            "observable degeneracy. A larger paired assist-on/off observable gate is",
            "needed if F14 requires an observable-level decision rather than a solver",
            "health decision.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    root = repo_root()
    on_rows = load_per_seed(root, "assist_on")
    off_rows = load_per_seed(root, "assist_off")
    seeds = sorted(set(on_rows).intersection(set(off_rows)))
    if len(seeds) != len(on_rows) or len(seeds) != len(off_rows):
        raise ValueError("assist-on/off seed sets do not match")
    rows = [
        paired_metric(seeds, on_rows, off_rows, "Ohat_Re", "Ohat_re"),
        paired_metric(seeds, on_rows, off_rows, "Ohat_Im", "Ohat_im"),
        paired_metric(seeds, on_rows, off_rows, "unresolved_failures", "unresolved_failure_count"),
        paired_metric(seeds, on_rows, off_rows, "projection_failures", "projection_failure_count"),
        paired_metric(seeds, on_rows, off_rows, "reverse_gate_rejects", "reverse_gate_total_reject_count"),
        paired_metric(seeds, on_rows, off_rows, "pair0_accept", "pair0_accept_rate"),
    ]
    values = {
        "head": git_head(root),
        "run_commit": read_manifest_value(root / EVIDENCE_ROOT / "run_manifest.txt", "git_commit"),
        "on_fail": sum(as_int(on_rows[seed], "unresolved_failure_count") for seed in seeds),
        "off_fail": sum(as_int(off_rows[seed], "unresolved_failure_count") for seed in seeds),
        "off_newton_hmin": sum(as_int(off_rows[seed], "newton_eval_flow_failure_h_min_count") for seed in seeds),
        "off_qn_hmin": sum(as_int(off_rows[seed], "qn_eval_flow_failure_h_min_count") for seed in seeds),
    }
    values["fail_delta"] = values["off_fail"] - values["on_fail"]
    values["conclusion"] = conclusion_tag(rows)
    write_summary(root, rows)
    write_report(root, seeds, rows, values)
    print("[ODEX][ASSIST_OBSERVABLE] wrote {0}".format(SUMMARY_OUT))
    print("[ODEX][ASSIST_OBSERVABLE] wrote {0}".format(REPORT_OUT))
    print("[ODEX][ASSIST_OBSERVABLE] conclusion={0}".format(values["conclusion"]))


if __name__ == "__main__":
    main()
