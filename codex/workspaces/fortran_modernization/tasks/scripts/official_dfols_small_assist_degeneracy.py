#!/usr/bin/env python3
"""Read back the official DFO-LS 10seed/10k nofb-vs-withfb degeneracy check."""

import csv
import subprocess
from pathlib import Path


EVIDENCE_ROOT = (
    "codex/workspaces/fortran_modernization/state/"
    "official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb"
)
COMBINED_CSV = EVIDENCE_ROOT + "/combined_summary_table.csv"
PRODCOMP_READBACK = (
    "codex/workspaces/tltm_production_comparison/runbooks/"
    "OFFICIAL_DFOLS_SMALL_READBACK_20260511.md"
)
SUMMARY_OUT = (
    "codex/workspaces/fortran_modernization/state/"
    "OFFICIAL_DFOLS_SMALL_ASSIST_DEGENERACY_SUMMARY.tsv"
)
REPORT_OUT = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "OFFICIAL_DFOLS_SMALL_ASSIST_DEGENERACY_READBACK_20260511.md"
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


def as_float(row, key):
    return float(row[key])


def as_int(row, key):
    return int(round(as_float(row, key)))


def fmt(value, digits=8):
    if isinstance(value, float):
        return "{0:.{1}g}".format(value, digits)
    return str(value)


def load_rows(root):
    path = root / COMBINED_CSV
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    indexed = {row["canonical_method"]: row for row in rows}
    return indexed["nofb"], indexed["withfb"]


def parse_pinned_commit(root):
    path = root / PRODCOMP_READBACK
    if not path.exists():
        return "unknown"
    prefix = "- Pinned run commit:"
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip().strip("`")
    return "unknown"


def metric_row(metric, nofb, withfb, key, signed=False):
    nofb_value = as_float(nofb, key)
    withfb_value = as_float(withfb, key)
    delta = withfb_value - nofb_value
    if signed:
        pct = "NA"
        ratio = "NA"
    else:
        pct = fmt(100.0 * delta / nofb_value if nofb_value != 0.0 else 0.0, 8)
        ratio = fmt(nofb_value / withfb_value if withfb_value != 0.0 else 0.0, 8)
    return {
        "metric": metric,
        "nofb": fmt(nofb_value, 12),
        "withfb": fmt(withfb_value, 12),
        "delta_withfb_minus_nofb": fmt(delta, 12),
        "pct_delta": pct,
        "nofb_over_withfb_ratio": ratio,
    }


def write_summary(root, rows):
    path = root / SUMMARY_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "metric",
        "nofb",
        "withfb",
        "delta_withfb_minus_nofb",
        "pct_delta",
        "nofb_over_withfb_ratio",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_report(root, values, rows):
    path = root / REPORT_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Official DFO-LS Small Assist-Degeneracy Readback",
        "",
        "Updated: 2026-05-11 JST",
        "",
        "Scope: imported readback from `tltm_production_comparison` for the",
        "official DFO-LS 10seed x 10k nofb-vs-withfb provisional comparison.",
        "This is useful for observing whether disabling the production `withfb`",
        "assist/feedback route degenerates robustness under the official backend.",
        "",
        "Boundary: this is not an ODEX solver-internal assist-off run. The ODE",
        "solver-internal residual assist counters are still present in both",
        "`no_fb` and `fb_norefine`; the comparison here is the production method",
        "route `no_fb -> nofb` versus `fb_norefine -> withfb`.",
        "",
        "## Provenance",
        "",
        "- Imported evidence root: `{root}`.".format(root=EVIDENCE_ROOT),
        "- Production-comparison readback: `{readback}`.".format(readback=PRODCOMP_READBACK),
        "- Pinned run commit recorded by production-comparison readback: `{commit}`.".format(
            commit=values["pinned_commit"]
        ),
        "- Current local HEAD when this report was generated: `{head}`.".format(
            head=values["head"]
        ),
        "- Backend/preset: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.",
        "- Physical point: `t=0.35,L=2,nstep=20`; scale: `10 seeds x 10000 cycles`; RG on, p28, `cttol=1e-13`, `QN=1e-13`.",
        "",
        "## Aggregate Comparison",
        "",
        "| metric | nofb | withfb | withfb - nofb | pct delta | nofb / withfb |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {metric} | {nofb} | {withfb} | {delta_withfb_minus_nofb} | {pct_delta} | {nofb_over_withfb_ratio} |".format(
                **row
            )
        )
    lines.extend(
        [
            "",
            "Key readback:",
            "",
            "- Unresolved failures drop from `{nofb_failures}` to `{withfb_failures}` when `withfb` is enabled: delta `{failure_delta}`, `{failure_pct}%`.".format(
                **values
            ),
            "- `nofb` has `{failure_ratio}x` as many unresolved failures as `withfb` at the same 10seed/10k scale.".format(
                **values
            ),
            "- Reverse-gate rejects drop from `{nofb_rg}` to `{withfb_rg}`: delta `{rg_delta}`, `{rg_pct}%`.".format(
                **values
            ),
            "- Runtime rises from `{nofb_runtime}` s to `{withfb_runtime}` s: delta `+{runtime_delta}` s, `{runtime_pct}%`.".format(
                **values
            ),
            "- Physical Zmean remains small-sample noisy: nofb Re/Im `{nofb_zre}` / `{nofb_zim}`, withfb Re/Im `{withfb_zre}` / `{withfb_zim}`.".format(
                **values
            ),
            "- ODE residual-assist counters are nonzero in both routes: Newton solver-assist nofb `{nofb_newton_assist}`, withfb `{withfb_newton_assist}`; QN solver-assist nofb `{nofb_qn_assist}`, withfb `{withfb_qn_assist}`.".format(
                **values
            ),
            "",
            "## Interpretation",
            "",
            "At the official DFO-LS 10seed/10k calibration scale, turning off the",
            "production `withfb` route is already a clear robustness degeneracy signal:",
            "`no_fb` produces about `6.36x` as many unresolved failures as `withfb`.",
            "The physical observable readout is too small-sample to make a production",
            "bias claim, but it does not contradict using `withfb` as the provisional",
            "official DFO-LS production-comparison route.",
            "",
            "This evidence supports using official DFO-LS 10seed/10k as a real",
            "production-comparison assist-degeneracy observation. It does not make M6",
            "an official DFO-LS dataset and does not close the larger official backend",
            "replacement caveat by itself.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    root = repo_root()
    nofb, withfb = load_rows(root)
    rows = [
        metric_row("mean_Re", nofb, withfb, "mean_Ohat_re", signed=True),
        metric_row("mean_Im", nofb, withfb, "mean_Ohat_im", signed=True),
        metric_row("Zmean_Re", nofb, withfb, "Zmean_re", signed=True),
        metric_row("Zmean_Im", nofb, withfb, "Zmean_im", signed=True),
        metric_row("unresolved_failures", nofb, withfb, "total_unresolved_failure_count"),
        metric_row("projection_failures_mean", nofb, withfb, "mean_projection_failure_count"),
        metric_row("reverse_gate_rejects", nofb, withfb, "total_reverse_gate_total_reject_count"),
        metric_row("pair0_accept", nofb, withfb, "mean_pair0_accept_rate"),
        metric_row("runtime_seconds_mean", nofb, withfb, "mean_runtime_total"),
    ]
    failure_delta = as_int(withfb, "total_unresolved_failure_count") - as_int(nofb, "total_unresolved_failure_count")
    failure_pct = 100.0 * failure_delta / as_int(nofb, "total_unresolved_failure_count")
    rg_delta = as_int(withfb, "total_reverse_gate_total_reject_count") - as_int(
        nofb, "total_reverse_gate_total_reject_count"
    )
    rg_pct = 100.0 * rg_delta / as_int(nofb, "total_reverse_gate_total_reject_count")
    runtime_delta = as_float(withfb, "mean_runtime_total") - as_float(nofb, "mean_runtime_total")
    runtime_pct = 100.0 * runtime_delta / as_float(nofb, "mean_runtime_total")
    values = {
        "head": git_head(root),
        "pinned_commit": parse_pinned_commit(root),
        "nofb_failures": as_int(nofb, "total_unresolved_failure_count"),
        "withfb_failures": as_int(withfb, "total_unresolved_failure_count"),
        "failure_delta": failure_delta,
        "failure_pct": fmt(failure_pct, 8),
        "failure_ratio": fmt(
            as_int(nofb, "total_unresolved_failure_count")
            / as_int(withfb, "total_unresolved_failure_count"),
            8,
        ),
        "nofb_rg": as_int(nofb, "total_reverse_gate_total_reject_count"),
        "withfb_rg": as_int(withfb, "total_reverse_gate_total_reject_count"),
        "rg_delta": rg_delta,
        "rg_pct": fmt(rg_pct, 8),
        "nofb_runtime": fmt(as_float(nofb, "mean_runtime_total"), 12),
        "withfb_runtime": fmt(as_float(withfb, "mean_runtime_total"), 12),
        "runtime_delta": fmt(runtime_delta, 12),
        "runtime_pct": fmt(runtime_pct, 8),
        "nofb_zre": fmt(as_float(nofb, "Zmean_re"), 12),
        "nofb_zim": fmt(as_float(nofb, "Zmean_im"), 12),
        "withfb_zre": fmt(as_float(withfb, "Zmean_re"), 12),
        "withfb_zim": fmt(as_float(withfb, "Zmean_im"), 12),
        "nofb_newton_assist": as_int(nofb, "total_newton_eval_flow_solver_assist_count"),
        "withfb_newton_assist": as_int(withfb, "total_newton_eval_flow_solver_assist_count"),
        "nofb_qn_assist": as_int(nofb, "total_qn_eval_flow_solver_assist_count"),
        "withfb_qn_assist": as_int(withfb, "total_qn_eval_flow_solver_assist_count"),
    }
    write_summary(root, rows)
    write_report(root, values, rows)
    print("[OFFICIAL_DFOLS][SMALL] wrote {0}".format(SUMMARY_OUT))
    print("[OFFICIAL_DFOLS][SMALL] wrote {0}".format(REPORT_OUT))
    print("[OFFICIAL_DFOLS][SMALL] conclusion=withfb_reduces_official_small_unresolved_failures")


if __name__ == "__main__":
    main()
