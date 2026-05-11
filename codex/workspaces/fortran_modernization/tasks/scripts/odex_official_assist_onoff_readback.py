#!/usr/bin/env python3
"""Read back the official DFO-LS ODEX solver-assist on/off gate."""

import csv
import subprocess
from pathlib import Path


EVIDENCE_ROOT = (
    "codex/workspaces/fortran_modernization/state/"
    "odex_official_dfols_assist_onoff_20260511"
)
SUMMARY_OUT = (
    "codex/workspaces/fortran_modernization/state/"
    "ODEX_OFFICIAL_ASSIST_ONOFF_SUMMARY.tsv"
)
REPORT_OUT = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "ODEX_OFFICIAL_ASSIST_ONOFF_READBACK_20260511.md"
)
PBS_SCRIPT = (
    "codex/workspaces/fortran_modernization/tasks/pbs/"
    "odex_official_dfols_assist_onoff_10seed_10k_20260511.pbs"
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


def load_variant(root, variant):
    path = root / EVIDENCE_ROOT / variant / "aggregated_summary_table.csv"
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise ValueError("{0} should contain exactly one aggregate row, got {1}".format(path, len(rows)))
    row = rows[0]
    if row.get("method") != "fb_norefine":
        raise ValueError("{0} expected method fb_norefine, got {1}".format(path, row.get("method")))
    return row


def as_float(row, key):
    value = row.get(key, "")
    if value == "":
        return 0.0
    return float(value)


def as_int(row, key):
    return int(round(as_float(row, key)))


def fmt(value, digits=9):
    if isinstance(value, float):
        return "{0:.{1}g}".format(value, digits)
    return str(value)


def metric_row(metric, on_row, off_row, key, signed=False):
    on_value = as_float(on_row, key)
    off_value = as_float(off_row, key)
    delta = off_value - on_value
    if signed:
        pct = "NA"
        ratio = "NA"
    elif on_value == 0.0:
        pct = "NA"
        ratio = "NA"
    else:
        pct = fmt(100.0 * delta / on_value)
        ratio = fmt(off_value / on_value)
    return {
        "metric": metric,
        "assist_on": fmt(on_value, 12),
        "assist_off": fmt(off_value, 12),
        "delta_off_minus_on": fmt(delta, 12),
        "pct_delta": pct,
        "off_over_on_ratio": ratio,
    }


def write_summary(root, rows):
    path = root / SUMMARY_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "metric",
        "assist_on",
        "assist_off",
        "delta_off_minus_on",
        "pct_delta",
        "off_over_on_ratio",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def conclusion(values):
    if values["assist_off_newton_assist"] != 0 or values["assist_off_qn_assist"] != 0:
        return "invalid_assist_off_still_used_solver_assist"
    if values["assist_on_newton_assist"] <= 0 and values["assist_on_qn_assist"] <= 0:
        return "inconclusive_assist_on_did_not_exercise_solver_assist"
    if values["failure_delta"] > 0:
        return "assist_off_increases_unresolved_failures_at_10seed_10k"
    if values["failure_delta"] < 0:
        return "assist_off_reduces_unresolved_failures_at_10seed_10k_unexpected"
    return "assist_off_no_unresolved_failure_delta_at_10seed_10k"


def write_report(root, rows, values):
    path = root / REPORT_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# ODEX Official DFO-LS Assist On/Off Readback",
        "",
        "Updated: 2026-05-11 JST",
        "",
        "Scope: current-code Stage/TLTM readback for ODEX solver-internal",
        "assist policy under the embedded official DFO-LS backend. This is not",
        "a nofb-vs-withfb production-route comparison; both variants use",
        "`fb_norefine` and differ only by `INTODE_SOLVER_ASSIST_ENABLED`.",
        "",
        "## Provenance",
        "",
        "- Imported evidence root: `{root}`.".format(root=EVIDENCE_ROOT),
        "- PBS script: `{script}`.".format(script=PBS_SCRIPT),
        "- Readback-generation local HEAD before the evidence commit: `{head}`.".format(head=values["head"]),
        "- Run commit recorded by manifest: `{commit}`.".format(commit=values["run_commit"] or "unknown"),
        "- Backend/preset: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.",
        "- Physical point: `t=0.35,L=2,nstep=20`; scale: `10 seeds x 10000 cycles`; method `fb_norefine`.",
        "- Assist-on variant: `INTODE_SOLVER_ASSIST_ENABLED=1`.",
        "- Assist-off variant: `INTODE_SOLVER_ASSIST_ENABLED=0`.",
        "",
        "## Aggregate Comparison",
        "",
        "| metric | assist on | assist off | off - on | pct delta | off / on |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {metric} | {assist_on} | {assist_off} | {delta_off_minus_on} | {pct_delta} | {off_over_on_ratio} |".format(
                **row
            )
        )

    lines.extend(
        [
            "",
            "Key readback:",
            "",
            "- Assist-on exercised solver-internal assist: Newton `{assist_on_newton_assist}`, QN `{assist_on_qn_assist}`.".format(
                **values
            ),
            "- Assist-off solver-internal assist counters: Newton `{assist_off_newton_assist}`, QN `{assist_off_qn_assist}`.".format(
                **values
            ),
            "- Unresolved failures changed from `{assist_on_failures}` to `{assist_off_failures}`: delta `{failure_delta}`.".format(
                **values
            ),
            "- H-min failures changed from Newton/QN `{assist_on_newton_hmin}`/`{assist_on_qn_hmin}` to `{assist_off_newton_hmin}`/`{assist_off_qn_hmin}`.".format(
                **values
            ),
            "",
            "## Interpretation",
            "",
            "Conclusion tag: `{conclusion}`.".format(conclusion=values["conclusion"]),
            "",
            "This closes only the representative 10seed x 10k current-code",
            "assist-on/off readback slice for `fb_norefine`. It does not by",
            "itself complete the full ODEX backend design work: result/workspace",
            "status mapping, flow/Jacobian deterministic tests, and any selected",
            "production-scale confirmation remain separate gates.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    root = repo_root()
    on_row = load_variant(root, "assist_on")
    off_row = load_variant(root, "assist_off")
    rows = [
        metric_row("mean_Re", on_row, off_row, "mean_Ohat_re", signed=True),
        metric_row("mean_Im", on_row, off_row, "mean_Ohat_im", signed=True),
        metric_row("Zmean_Re", on_row, off_row, "Zmean_re", signed=True),
        metric_row("Zmean_Im", on_row, off_row, "Zmean_im", signed=True),
        metric_row("unresolved_failures", on_row, off_row, "total_unresolved_failure_count"),
        metric_row("projection_failures_mean", on_row, off_row, "mean_projection_failure_count"),
        metric_row("reverse_gate_rejects", on_row, off_row, "total_reverse_gate_total_reject_count"),
        metric_row("newton_solver_assist", on_row, off_row, "total_newton_eval_flow_solver_assist_count"),
        metric_row("qn_solver_assist", on_row, off_row, "total_qn_eval_flow_solver_assist_count"),
        metric_row("newton_hmin_failures", on_row, off_row, "total_newton_eval_flow_failure_h_min_count"),
        metric_row("qn_hmin_failures", on_row, off_row, "total_qn_eval_flow_failure_h_min_count"),
        metric_row("pair0_accept", on_row, off_row, "mean_pair0_accept_rate"),
        metric_row("runtime_seconds_mean", on_row, off_row, "mean_runtime_total"),
    ]
    values = {
        "head": git_head(root),
        "run_commit": read_manifest_value(root / EVIDENCE_ROOT / "run_manifest.txt", "git_commit"),
        "assist_on_failures": as_int(on_row, "total_unresolved_failure_count"),
        "assist_off_failures": as_int(off_row, "total_unresolved_failure_count"),
        "assist_on_newton_assist": as_int(on_row, "total_newton_eval_flow_solver_assist_count"),
        "assist_off_newton_assist": as_int(off_row, "total_newton_eval_flow_solver_assist_count"),
        "assist_on_qn_assist": as_int(on_row, "total_qn_eval_flow_solver_assist_count"),
        "assist_off_qn_assist": as_int(off_row, "total_qn_eval_flow_solver_assist_count"),
        "assist_on_newton_hmin": as_int(on_row, "total_newton_eval_flow_failure_h_min_count"),
        "assist_off_newton_hmin": as_int(off_row, "total_newton_eval_flow_failure_h_min_count"),
        "assist_on_qn_hmin": as_int(on_row, "total_qn_eval_flow_failure_h_min_count"),
        "assist_off_qn_hmin": as_int(off_row, "total_qn_eval_flow_failure_h_min_count"),
    }
    values["failure_delta"] = values["assist_off_failures"] - values["assist_on_failures"]
    values["conclusion"] = conclusion(values)
    write_summary(root, rows)
    write_report(root, rows, values)
    print("[ODEX][ASSIST_ONOFF] wrote {0}".format(SUMMARY_OUT))
    print("[ODEX][ASSIST_ONOFF] wrote {0}".format(REPORT_OUT))
    print("[ODEX][ASSIST_ONOFF] conclusion={0}".format(values["conclusion"]))


if __name__ == "__main__":
    main()
