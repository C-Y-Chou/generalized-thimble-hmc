#!/usr/bin/env python3
"""Recompute the historical ODEX solver-assist readback from recorded evidence."""

import csv
import math
import subprocess
from pathlib import Path


ASSIST_RUNBOOK = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "ODEX_SOLVER_ASSIST_VALIDATION_RESULT_20260509_QNCLEAN.md"
)
ODEX_ONLY_RUNBOOK = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "ODEX_50K_100K_VALIDATION_RESULT_20260509_QNCLEAN.md"
)
FOUNDATION_EVIDENCE = (
    "codex/workspaces/fortran_modernization/state/ODEX_FOUNDATION_EVIDENCE.tsv"
)
SUMMARY_OUT = (
    "codex/workspaces/fortran_modernization/state/"
    "ODEX_ASSIST_REVALIDATION_SUMMARY.tsv"
)
REPORT_OUT = (
    "codex/workspaces/fortran_modernization/runbooks/"
    "ODEX_ASSIST_HISTORICAL_READBACK_20260511.md"
)


def repo_root():
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        stdout=subprocess.PIPE,
        universal_newlines=True,
    )
    return Path(result.stdout.strip()).resolve()


def split_markdown_row(line):
    return [part.strip().strip("`") for part in line.strip().strip("|").split("|")]


def is_separator(parts):
    if not parts:
        return False
    for part in parts:
        compact = part.replace(":", "").replace("-", "").strip()
        if compact:
            return False
    return True


def read_markdown_rows(path):
    rows = []
    header = None
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            header = None
            continue
        parts = split_markdown_row(stripped)
        if is_separator(parts):
            continue
        if header is None:
            header = parts
            continue
        if len(parts) != len(header):
            continue
        rows.append(dict(zip(header, parts)))
    return rows


def as_float(value):
    return float(str(value).replace("+", "").strip())


def as_int(value):
    return int(round(as_float(value)))


def row_by(rows, key, value, required_keys=()):
    for row in rows:
        if row.get(key) == value and all(required in row for required in required_keys):
            return row
    suffix = ""
    if required_keys:
        suffix = " with keys {0}".format(",".join(required_keys))
    raise RuntimeError("missing row {0}={1}{2}".format(key, value, suffix))


def load_foundation_evidence(root):
    path = root / FOUNDATION_EVIDENCE
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def fmt(value, digits=6):
    if isinstance(value, float):
        if not math.isfinite(value):
            return "NA"
        return "{0:.{1}g}".format(value, digits)
    return str(value)


def robustness_metric(name, odex50, assist50, odex100, assist100, key):
    o50 = as_float(odex50[key])
    a50 = as_float(assist50[key])
    o100 = as_float(odex100[key])
    a100 = as_float(assist100[key])
    d50 = a50 - o50
    d100 = a100 - o100
    pct100 = 100.0 * d100 / o100 if o100 != 0.0 else math.nan
    return {
        "metric": name,
        "odex_only_50k": fmt(o50, 12),
        "solver_assist_50k": fmt(a50, 12),
        "delta_50k": fmt(d50, 12),
        "odex_only_100k": fmt(o100, 12),
        "solver_assist_100k": fmt(a100, 12),
        "delta_100k": fmt(d100, 12),
        "pct_delta_100k": fmt(pct100, 8),
        "interpretation": "",
    }


def write_summary(root, rows):
    path = root / SUMMARY_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "metric",
        "odex_only_50k",
        "solver_assist_50k",
        "delta_50k",
        "odex_only_100k",
        "solver_assist_100k",
        "delta_100k",
        "pct_delta_100k",
        "interpretation",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_report(root, values, summary_rows, evidence_rows):
    path = root / REPORT_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    evidence_summary = []
    for row in evidence_rows:
        evidence_summary.append(
            "- {id}: {status} via `{command}`".format(
                id=row.get("id", row.get("evidence_id", "unknown")),
                status=row.get("status", "unknown"),
                command=row.get("commands", row.get("command", "")),
            )
        )
    if not evidence_summary:
        evidence_summary.append("- No deterministic foundation evidence TSV was found.")

    lines = [
        "# ODEX Assist Historical Readback",
        "",
        "Updated: 2026-05-11 JST",
        "",
        "Status: historical evidence readback only. This report recomputes numbers",
        "from recorded 2026-05-09 ODEX-only and solver-assist validation artifacts.",
        "It is not a fresh current-code ODEX revalidation test and must not be used",
        "by itself as a final current policy conclusion.",
        "",
        "Important evidence boundary: M6 reference datasets are historical/internal",
        "behavior anchors, not official DFO-LS evidence. They may be used as an",
        "observational degeneracy detector when comparing assist-off/assist-on",
        "behavior, but not to certify the official DFO-LS backend.",
        "",
        "## Current Source Readback",
        "",
        "- Large-scale evidence source: `{assist}`.".format(assist=ASSIST_RUNBOOK),
        "- ODEX-only comparison source: `{odex}`.".format(odex=ODEX_ONLY_RUNBOOK),
        "- Deterministic current-code boundary evidence:",
    ]
    lines.extend(evidence_summary)
    lines.extend(
        [
            "",
            "## Recomputed Robustness Comparison",
            "",
            "| metric | ODEX-only 50k | assist 50k | delta 50k | ODEX-only 100k | assist 100k | delta 100k | pct delta 100k |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for row in summary_rows:
        lines.append(
            "| {metric} | {odex_only_50k} | {solver_assist_50k} | {delta_50k} | "
            "{odex_only_100k} | {solver_assist_100k} | {delta_100k} | "
            "{pct_delta_100k} |".format(**row)
        )
    lines.extend(
        [
            "",
            "Key computed readbacks:",
            "",
            "- 100k unresolved failures: ODEX-only `{odex_unresolved_100k}`, assist `{assist_unresolved_100k}`, delta `{unresolved_delta_100k}` (`{unresolved_pct_100k}%`).".format(
                **values
            ),
            "- Pre-ODEX 100k unresolved level was `{pre_odex_unresolved_100k}`; assist 100k differs by `{assist_vs_pre_unresolved_100k}`.".format(
                **values
            ),
            "- Assist ODE counter success rate at 100k was `{assist_success_rate_100k}` with invalid count `{assist_invalid_100k}`.".format(
                **values
            ),
            "- Assist 100k physical Zmean Re/Im were `{assist_zmean_re_100k}` / `{assist_zmean_im_100k}`; ODEX-only 100k physical Zmean Re/Im were `{odex_zmean_re_100k}` / `{odex_zmean_im_100k}`.".format(
                **values
            ),
            "- Pair0 acceptance remained stable: ODEX-only 100k `{odex_pair0_100k}`, assist 100k `{assist_pair0_100k}`.".format(
                **values
            ),
            "",
            "## Readback",
            "",
            "The recorded 2026-05-09 historical campaign shows that pure ODEX-only was",
            "physically acceptable as a comparison artifact but had a large robustness",
            "loss. In that historical campaign, solver-internal assist recovered the",
            "pre-ODEX unresolved-failure level while keeping aggregate physical",
            "observables, reverse-gate rejects, and pair0 acceptance stable.",
            "",
            "What this supports as evidence:",
            "",
            "1. Pure ODEX-only remains a known comparison point.",
            "2. Solver-internal assist is a strong candidate for preserving robustness.",
            "3. A fresh current-code ODEX assist-on/off revalidation is still required before using this as a current conclusion.",
            "4. The remaining ODEX work is backend completion: result/workspace/status split, endpoint-only/stability-control decision, flow/Jacobian deterministic tests, and an actual current ODEX policy test.",
            "",
            "## Boundary",
            "",
            "This readback does not close the ODEX-only-vs-assist policy question for",
            "the current ODEX flow policy. It does not close `CV-007`/`FG-001`: the",
            "standalone backend contract, stability decision, and current ODEX policy",
            "test remain open. It also does not by itself close the official DFO-LS-line",
            "gate under `CV-008`; M6 can only help observe whether disabling assist",
            "degenerates robustness.",
            "",
            "Separate official DFO-LS production-comparison evidence may be read via",
            "`OFFICIAL_DFOLS_SMALL_ASSIST_DEGENERACY_READBACK_20260511.md`. That",
            "comparison is about the production method route `no_fb` versus",
            "`fb_norefine`, not about turning off ODE solver-internal residual assist.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    root = repo_root()
    assist_rows = read_markdown_rows(root / ASSIST_RUNBOOK)
    odex_rows = read_markdown_rows(root / ODEX_ONLY_RUNBOOK)

    odex50 = row_by(assist_rows, "run", "ODEX-only 50k", ("unresolved",))
    assist50 = row_by(assist_rows, "run", "solver-assist 50k", ("unresolved",))
    odex100 = row_by(assist_rows, "run", "ODEX-only 100k", ("unresolved",))
    assist100 = row_by(assist_rows, "run", "solver-assist 100k", ("unresolved",))

    assist_phys100 = row_by(assist_rows, "run", "solver-assist 100k", ("Zmean Re",))
    odex_phys100 = row_by(odex_rows, "run", "100k QN-clean")
    assist_counter100 = row_by(assist_rows, "run", "solver-assist 100k", ("success rate",))
    pre_unresolved_row = row_by(odex_rows, "metric", "unresolved failures")

    summary_rows = [
        robustness_metric(
            "unresolved_failures",
            odex50,
            assist50,
            odex100,
            assist100,
            "unresolved",
        ),
        robustness_metric(
            "mean_projection_failures",
            odex50,
            assist50,
            odex100,
            assist100,
            "mean projection failures",
        ),
        robustness_metric(
            "mean_unresolved_failures",
            odex50,
            assist50,
            odex100,
            assist100,
            "mean unresolved failures",
        ),
        robustness_metric(
            "rg_rejects",
            odex50,
            assist50,
            odex100,
            assist100,
            "RG rejects",
        ),
        robustness_metric(
            "pair0_accept",
            odex50,
            assist50,
            odex100,
            assist100,
            "pair0 accept",
        ),
        robustness_metric(
            "mean_runtime",
            odex50,
            assist50,
            odex100,
            assist100,
            "mean runtime",
        ),
    ]
    for row in summary_rows:
        if row["metric"] == "unresolved_failures":
            row["interpretation"] = "assist recovers robustness"
        elif row["metric"] in {"rg_rejects", "pair0_accept"}:
            row["interpretation"] = "stable physics/proposal boundary"
        elif row["metric"] == "mean_runtime":
            row["interpretation"] = "assist costs runtime but reduces unresolved failures"
        else:
            row["interpretation"] = "diagnostic improvement"

    odex_unresolved_100k = as_int(odex100["unresolved"])
    assist_unresolved_100k = as_int(assist100["unresolved"])
    unresolved_delta_100k = assist_unresolved_100k - odex_unresolved_100k
    unresolved_pct_100k = 100.0 * unresolved_delta_100k / odex_unresolved_100k
    pre_odex_unresolved_100k = as_int(pre_unresolved_row["pre-ODEX fb_norefine"])
    values = {
        "odex_unresolved_100k": odex_unresolved_100k,
        "assist_unresolved_100k": assist_unresolved_100k,
        "unresolved_delta_100k": unresolved_delta_100k,
        "unresolved_pct_100k": fmt(unresolved_pct_100k, 8),
        "pre_odex_unresolved_100k": pre_odex_unresolved_100k,
        "assist_vs_pre_unresolved_100k": assist_unresolved_100k - pre_odex_unresolved_100k,
        "assist_success_rate_100k": assist_counter100["success rate"],
        "assist_invalid_100k": assist_counter100["invalid"],
        "assist_zmean_re_100k": assist_phys100["Zmean Re"],
        "assist_zmean_im_100k": assist_phys100["Zmean Im"],
        "odex_zmean_re_100k": odex_phys100["Zmean Re"],
        "odex_zmean_im_100k": odex_phys100["Zmean Im"],
        "odex_pair0_100k": odex100["pair0 accept"],
        "assist_pair0_100k": assist100["pair0 accept"],
    }

    write_summary(root, summary_rows)
    write_report(root, values, summary_rows, load_foundation_evidence(root))
    print("[ODEX][ASSIST] wrote {0}".format(SUMMARY_OUT))
    print("[ODEX][ASSIST] wrote {0}".format(REPORT_OUT))
    print(
        "[ODEX][ASSIST] readback=historical_only_current_odex_policy_test_still_open"
    )


if __name__ == "__main__":
    main()
