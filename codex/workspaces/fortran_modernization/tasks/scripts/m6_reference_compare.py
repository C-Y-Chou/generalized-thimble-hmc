#!/usr/bin/env python3
"""Build a read-only comparison report for accepted M6 reference packages."""

import csv
import math
import re
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List, Optional


READBACK_REL = "codex/workspaces/fortran_modernization/runbooks/M6_REFERENCE_DATASET_READBACK_20260510.md"
REGISTRY_REL = "codex/workspaces/fortran_modernization/state/M6_REFERENCE_PACKAGES.tsv"
SUMMARY_REL = "codex/workspaces/fortran_modernization/state/M6_REFERENCE_COMPARISON_SUMMARY.tsv"
REPORT_REL = "codex/workspaces/fortran_modernization/runbooks/M6_REFERENCE_COMPARISON_REPORT_20260511.md"

CANONICAL = {
    "no_fb": "nofb",
    "fb_norefine": "withfb",
}


class AggregateRow:
    def __init__(
        self,
        level: str,
        label: str,
        raw_method: str,
        canonical_method: str,
        seeds: int,
        mean_re: float,
        mean_im: float,
        unresolved_failures: int,
        rg_rejects: int,
        pair0_accept: float,
        mean_runtime: float,
        zmean_re: Optional[float] = None,
        zmean_im: Optional[float] = None,
        source: str = "readback",
    ) -> None:
        self.level = level
        self.label = label
        self.raw_method = raw_method
        self.canonical_method = canonical_method
        self.seeds = seeds
        self.mean_re = mean_re
        self.mean_im = mean_im
        self.unresolved_failures = unresolved_failures
        self.rg_rejects = rg_rejects
        self.pair0_accept = pair0_accept
        self.mean_runtime = mean_runtime
        self.zmean_re = zmean_re
        self.zmean_im = zmean_im
        self.source = source


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        universal_newlines=True,
        stdout=subprocess.PIPE,
    )
    return Path(result.stdout.strip()).resolve()


def parse_float(value: str) -> float:
    value = value.strip().replace("`", "")
    if value.lower() in {"", "na", "nan"}:
        return math.nan
    return float(value)


def parse_int(value: str) -> int:
    return int(round(parse_float(value)))


def label_for_level(level: str) -> str:
    return {
        "R1": "r1_4seed_1k",
        "R2": "r2_10seed_10k",
        "R3": "r3_32seed_50k",
        "R4": "r4_128seed_100k",
    }.get(level, level.lower())


def load_registry(root: Path) -> Dict[str, Dict[str, str]]:
    path = root / REGISTRY_REL
    with path.open(newline="", encoding="utf-8") as handle:
        return {
            row["package_id"]: row
            for row in csv.DictReader(handle, delimiter="\t")
        }


def find_raw_csv(root: Path, package_root: str) -> Optional[Path]:
    base = root / package_root
    if not base.exists():
        return None
    candidates = [
        base / "reference_aggregate_comparison.csv",
        base / "aggregated_summary_table.csv",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    found = sorted(base.rglob("reference_aggregate_comparison.csv"))
    if found:
        return found[0]
    found = sorted(base.rglob("aggregated_summary_table.csv"))
    return found[0] if found else None


def first_present(row: Dict[str, str], names: Iterable[str]) -> Optional[str]:
    for name in names:
        if name in row and row[name] not in {"", "NA"}:
            return row[name]
    return None


def load_raw_csv_rows(root: Path, registry: Dict[str, Dict[str, str]]) -> List[AggregateRow]:
    rows: List[AggregateRow] = []
    for package_id, info in sorted(registry.items()):
        csv_path = find_raw_csv(root, info.get("package_root", ""))
        if csv_path is None:
            continue
        level_match = re.search(r"m6_r([1-4])", package_id)
        level = f"R{level_match.group(1)}" if level_match else package_id
        with csv_path.open(newline="", encoding="utf-8") as handle:
            for raw in csv.DictReader(handle):
                method = first_present(raw, ["raw_method", "method", "canonical_method"])
                if method is None:
                    continue
                canonical = CANONICAL.get(method, raw.get("canonical_method", method))
                mean_re = first_present(raw, ["mean_Ohat_re", "mean_re", "Mean Re"])
                mean_im = first_present(raw, ["mean_Ohat_im", "mean_im", "Mean Im"])
                failures = first_present(raw, ["total_unresolved_failure_count", "unresolved_failures", "Unresolved failures"])
                rg_rejects = first_present(raw, ["total_reverse_gate_total_reject_count", "rg_rejects", "RG rejects"])
                pair0 = first_present(raw, ["mean_pair0_accept_rate", "pair0_accept", "Pair0 accept"])
                runtime = first_present(raw, ["mean_runtime_total", "mean_runtime", "Mean runtime"])
                seeds = first_present(raw, ["n_seeds", "Seeds", "n"])
                if None in {mean_re, mean_im, failures, rg_rejects, pair0, runtime, seeds}:
                    continue
                rows.append(
                    AggregateRow(
                        level=level,
                        label=label_for_level(level),
                        raw_method=method,
                        canonical_method=canonical,
                        seeds=parse_int(seeds),
                        mean_re=parse_float(mean_re),
                        mean_im=parse_float(mean_im),
                        unresolved_failures=parse_int(failures),
                        rg_rejects=parse_int(rg_rejects),
                        pair0_accept=parse_float(pair0),
                        mean_runtime=parse_float(runtime),
                        zmean_re=parse_optional_float(first_present(raw, ["Zmean_re", "zmean_re"])),
                        zmean_im=parse_optional_float(first_present(raw, ["Zmean_im", "zmean_im"])),
                        source=str(csv_path),
                    )
                )
    return rows


def parse_optional_float(value: Optional[str]) -> Optional[float]:
    if value is None:
        return None
    try:
        parsed = parse_float(value)
    except ValueError:
        return None
    return parsed if math.isfinite(parsed) else None


def load_readback_rows(root: Path) -> List[AggregateRow]:
    path = root / READBACK_REL
    text = path.read_text(encoding="utf-8")
    rows: List[AggregateRow] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("| R"):
            continue
        parts = [part.strip().strip("`") for part in stripped.strip("|").split("|")]
        if len(parts) != 9:
            continue
        level, method, seeds, mean_re, mean_im, failures, rg, pair0, runtime = parts
        rows.append(
            AggregateRow(
                level=level,
                label=label_for_level(level),
                raw_method=method,
                canonical_method=CANONICAL.get(method, method),
                seeds=parse_int(seeds),
                mean_re=parse_float(mean_re),
                mean_im=parse_float(mean_im),
                unresolved_failures=parse_int(failures),
                rg_rejects=parse_int(rg),
                pair0_accept=parse_float(pair0),
                mean_runtime=parse_float(runtime),
                source=str(path),
            )
        )
    return rows


def by_level(rows: List[AggregateRow]) -> Dict[str, Dict[str, AggregateRow]]:
    grouped: Dict[str, Dict[str, AggregateRow]] = {}
    for row in rows:
        grouped.setdefault(row.level, {})[row.canonical_method] = row
    return grouped


def fmt(value: Optional[float], digits: int = 6) -> str:
    if value is None:
        return "NA"
    if isinstance(value, float) and not math.isfinite(value):
        return "NA"
    return f"{value:.{digits}g}"


def write_summary(root: Path, rows: List[AggregateRow]) -> None:
    path = root / SUMMARY_REL
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "level",
        "label",
        "raw_method",
        "canonical_method",
        "seeds",
        "mean_re",
        "mean_im",
        "zmean_re",
        "zmean_im",
        "unresolved_failures",
        "rg_rejects",
        "pair0_accept",
        "mean_runtime",
        "source",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "level": row.level,
                    "label": row.label,
                    "raw_method": row.raw_method,
                    "canonical_method": row.canonical_method,
                    "seeds": row.seeds,
                    "mean_re": fmt(row.mean_re, 10),
                    "mean_im": fmt(row.mean_im, 10),
                    "zmean_re": fmt(row.zmean_re, 10),
                    "zmean_im": fmt(row.zmean_im, 10),
                    "unresolved_failures": row.unresolved_failures,
                    "rg_rejects": row.rg_rejects,
                    "pair0_accept": fmt(row.pair0_accept, 10),
                    "mean_runtime": fmt(row.mean_runtime, 10),
                    "source": row.source,
                }
            )


def write_report(root: Path, rows: List[AggregateRow]) -> None:
    path = root / REPORT_REL
    path.parent.mkdir(parents=True, exist_ok=True)
    grouped = by_level(rows)
    lines: List[str] = [
        "# M6 Reference Comparison Report",
        "",
        "Updated: 2026-05-11 JST",
        "",
        "Scope: read-only comparison anchor for accepted M6 R1-R4 modernization reference packages.",
        "",
        "## Caveat Status",
        "",
        "- This report is a modernization reference-comparison aid, not a new production dataset.",
        "- Source changes remain gated by `CV-004` and the baseline verification matrix.",
        "- `Zmean` is reported only when raw aggregate CSV fields are available; the accepted readback table itself does not preserve those columns for every level.",
        "",
        "## Aggregate Rows",
        "",
        "| Level | Canonical | Raw | Seeds | Mean Re | Mean Im | Zmean Re | Zmean Im | Unresolved failures | RG rejects | Pair0 accept | Mean runtime s |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in sorted(rows, key=lambda item: (item.level, item.canonical_method)):
        lines.append(
            f"| {row.level} | {row.canonical_method} | {row.raw_method} | {row.seeds} | "
            f"{fmt(row.mean_re, 10)} | {fmt(row.mean_im, 10)} | {fmt(row.zmean_re, 10)} | {fmt(row.zmean_im, 10)} | "
            f"{row.unresolved_failures} | {row.rg_rejects} | {fmt(row.pair0_accept, 10)} | {fmt(row.mean_runtime, 10)} |"
        )

    lines.extend(
        [
            "",
            "## Withfb Minus Nofb",
            "",
            "| Level | dMean Re | dMean Im | Failure reduction | Failure reduction frac | dRG rejects | dRuntime s | Runtime factor |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for level in sorted(grouped):
        nofb = grouped[level].get("nofb")
        withfb = grouped[level].get("withfb")
        if nofb is None or withfb is None:
            continue
        fail_reduction = nofb.unresolved_failures - withfb.unresolved_failures
        fail_frac = fail_reduction / nofb.unresolved_failures if nofb.unresolved_failures else math.nan
        runtime_factor = withfb.mean_runtime / nofb.mean_runtime if nofb.mean_runtime else math.nan
        lines.append(
            f"| {level} | {fmt(withfb.mean_re - nofb.mean_re, 10)} | {fmt(withfb.mean_im - nofb.mean_im, 10)} | "
            f"{fail_reduction} | {fmt(fail_frac, 8)} | {withfb.rg_rejects - nofb.rg_rejects} | "
            f"{fmt(withfb.mean_runtime - nofb.mean_runtime, 10)} | {fmt(runtime_factor, 8)} |"
        )

    r4 = grouped.get("R4", {})
    nofb_r4 = r4.get("nofb")
    withfb_r4 = r4.get("withfb")
    lines.extend(["", "## Readback Interpretation", ""])
    if nofb_r4 is not None and withfb_r4 is not None:
        reduction = nofb_r4.unresolved_failures - withfb_r4.unresolved_failures
        frac = reduction / nofb_r4.unresolved_failures if nofb_r4.unresolved_failures else math.nan
        rg_delta = withfb_r4.rg_rejects - nofb_r4.rg_rejects
        runtime_factor = withfb_r4.mean_runtime / nofb_r4.mean_runtime if nofb_r4.mean_runtime else math.nan
        lines.extend(
            [
                f"- R4 is the current strongest M6 anchor: {nofb_r4.seeds} matched seeds x 100k cycles.",
                f"- At R4, canonical `withfb` reduces unresolved failures by {reduction} ({fmt(frac, 6)} of `nofb`).",
                f"- At R4, canonical `withfb` changes RG rejects by {rg_delta} and runtime factor is {fmt(runtime_factor, 6)}.",
                "- Mean observables are close to zero at R4 for both canonical roles; use full raw package statistics when deciding source-patch acceptance thresholds.",
            ]
        )
    else:
        lines.append("- R4 nofb/withfb pair was not complete in the parsed source.")

    lines.extend(
        [
            "",
            "## Next Use",
            "",
            "- Use this report as the F4 comparison anchor in `MODERNIZATION_FORWARD_WORKSTEPS_20260511.md`.",
            "- Before behavior-relevant source patches, add raw-package comparison checks that include route/counter equality and any available `Zmean` fields.",
            "- Do not use this report to make final publication-production claims.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    root = repo_root()
    registry = load_registry(root)
    rows = load_raw_csv_rows(root, registry)
    if not rows:
        rows = load_readback_rows(root)
    if not rows:
        raise SystemExit("no M6 aggregate rows found")
    write_summary(root, rows)
    write_report(root, rows)
    print(f"rows={len(rows)}")
    print(f"summary={root / SUMMARY_REL}")
    print(f"report={root / REPORT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
