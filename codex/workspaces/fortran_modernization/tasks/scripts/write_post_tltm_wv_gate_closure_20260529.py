#!/usr/bin/env python3
"""Write the post-TLTM closure packet used before opening WV-HMC work."""

from __future__ import annotations

import csv
import fnmatch
import json
from pathlib import Path
from statistics import mean, median
from typing import Optional


ROOT = Path(__file__).resolve().parents[5]
FW = ROOT / "codex" / "workspaces" / "fortran_modernization"
OUT = FW / "runbooks" / "generated" / "post_tltm_wv_hmc_ready_20260529"

OBS_CSV = (
    FW
    / "runbooks"
    / "generated"
    / "stephanov_n6_final_observable_z_20260529_complete"
    / "observable_and_z_summary.csv"
)
OBS_MD = (
    FW
    / "runbooks"
    / "generated"
    / "stephanov_n6_final_observable_z_20260529_complete"
    / "STEPHANOV_N6_FINAL_OBSERVABLE_Z_20260529.md"
)
RUNTIME_EXCLUSIONS = (
    FW
    / "runbooks"
    / "generated"
    / "stephanov_n6_final_runtime_exclusions_20260529"
    / "runtime_exclusion_manifest.json"
)
RAW_SUMMARIES = (
    FW
    / "runbooks"
    / "generated"
    / "stephanov_n6_final_criterion_20260529"
    / "raw_summaries"
)
INTERIM_FRAMEWORK = (
    FW
    / "runbooks"
    / "generated"
    / "withfb_criterion_framework_20260527"
    / "interim_criterion_framework_v1.md"
)
MIXING_AGG = (
    FW
    / "runbooks"
    / "generated"
    / "withfb_criterion_readback_20260527_current"
    / "mixing_highflow_aggregate.csv"
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def to_float(value: str, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def is_excluded_run(run_name: str, globs: list[str]) -> bool:
    return any(fnmatch.fnmatch(run_name, pat) for pat in globs)


def collect_summary_rows(method: str, globs: list[str]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    base = RAW_SUMMARIES / method
    included: list[dict[str, str]] = []
    excluded: list[dict[str, str]] = []
    for path in sorted(base.glob("*/tltm_ladder_summary.csv")):
        run_name = path.parent.name
        rows = read_csv(path)
        for row in rows:
            row = dict(row)
            row["run_name"] = run_name
            row["summary_path"] = str(path.relative_to(ROOT))
            if is_excluded_run(run_name, globs):
                excluded.append(row)
            else:
                included.append(row)
    return included, excluded


def summarize_runtime(method_label: str, rows: list[dict[str, str]], excluded_rows: list[dict[str, str]]) -> dict[str, object]:
    wall = [to_float(r.get("wall_sec", "")) for r in rows if r.get("wall_sec")]
    cycles = [to_float(r.get("cycles", "")) for r in rows]
    accepted = sum(to_float(r.get("accepted_local_total", "")) for r in rows)
    proposal_fail = sum(to_float(r.get("proposal_failure_total", "")) for r in rows)
    reverse_reject = sum(to_float(r.get("reverse_gate_reject_total", "")) for r in rows)
    metro_reject = sum(to_float(r.get("metropolis_reject_total", "")) for r in rows)
    attempts = accepted + proposal_fail + reverse_reject + metro_reject
    round_trips = [to_float(r.get("total_round_trip", "")) for r in rows]
    min_pair = [to_float(r.get("min_pair_accept_rate", "")) for r in rows if r.get("min_pair_accept_rate")]

    def maybe_mean(vals: list[float]) -> Optional[float]:
        return mean(vals) if vals else None

    def maybe_median(vals: list[float]) -> Optional[float]:
        return median(vals) if vals else None

    hmc_epsilon = rows[0].get("hmc_epsilon", "") if rows else ""
    hmc_nstep = rows[0].get("hmc_nstep", "") if rows else ""
    hmc_l = rows[0].get("hmc_L", "") if rows else ""
    fallback = rows[0].get("enable_quasi_fallback", "") if rows else ""
    unique_records = len({r.get("record", "") for r in rows})
    unique_runs = len({r.get("run_name", "") for r in rows})

    return {
        "method": method_label,
        "included_rows": len(rows),
        "excluded_rows": len(excluded_rows),
        "included_run_segments": unique_runs,
        "unique_records": unique_records,
        "cycles_sum": int(sum(cycles)),
        "cycles_median_per_row": maybe_median(cycles),
        "wall_sec_median_per_row": maybe_median(wall),
        "wall_sec_mean_per_row": maybe_mean(wall),
        "accepted_local_total": int(accepted),
        "proposal_failure_total": int(proposal_fail),
        "reverse_gate_reject_total": int(reverse_reject),
        "metropolis_reject_total": int(metro_reject),
        "attempts_total_proxy": int(attempts),
        "attempt_acceptance_rate_proxy": accepted / attempts if attempts else None,
        "proposal_failure_rate_proxy": proposal_fail / attempts if attempts else None,
        "reverse_gate_reject_rate_proxy": reverse_reject / attempts if attempts else None,
        "round_trip_mean_per_row": maybe_mean(round_trips),
        "round_trip_median_per_row": maybe_median(round_trips),
        "min_pair_accept_rate_mean": maybe_mean(min_pair),
        "min_pair_accept_rate_median": maybe_median(min_pair),
        "hmc_epsilon": hmc_epsilon,
        "hmc_nstep": hmc_nstep,
        "hmc_L": hmc_l,
        "enable_quasi_fallback": fallback,
        "runtime_accounting_note": (
            "segment diagnostic only; excluded rows are not used for runtime/equal-wall-clock accounting"
        ),
    }


def format_num(value: object, digits: int = 6) -> str:
    if value is None:
        return "NA"
    if isinstance(value, (int,)):
        return str(value)
    if isinstance(value, float):
        return f"{value:.{digits}g}"
    return str(value)


def obs_gate_rows(obs_rows: list[dict[str, str]]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for row in obs_rows:
        zs = {
            "chiral_Re_z": to_float(row["chiral_condensate_re_z"]),
            "chiral_Im_z": to_float(row["chiral_condensate_im_z"]),
            "density_Re_z": to_float(row["number_density_re_z"]),
            "density_Im_z": to_float(row["number_density_im_z"]),
        }
        max_abs_z = max(abs(v) for v in zs.values())
        result.append(
            {
                "group": row["group"],
                "seeds": int(to_float(row["seeds"])),
                "total_samples": int(to_float(row["total_samples"])),
                "phase": to_float(row["phase"]),
                "effN": to_float(row["effN"]),
                "max_abs_primary_z": max_abs_z,
                "primary_z_pass_abs_lt_2": max_abs_z < 2.0,
                **zs,
            }
        )
    return result


def read_mixing_reference() -> dict[str, dict[str, str]]:
    if not MIXING_AGG.exists():
        return {}
    rows = read_csv(MIXING_AGG)
    return {f"{r['variant']}:{r['cut']}": r for r in rows}


def build_dataset_groups(final_packet: str) -> list[dict[str, str]]:
    readback = str(OBS_MD.relative_to(ROOT))
    return [
        {
            "dataset_group": "fixed_tau_nofb",
            "dataset_id": "stephanov_n6_fixed_tau_nofb",
            "role": "fixed_tau_comparison_group",
            "status": "complete",
            "method": "no_fb",
            "flow_setup": "fixed_tau_t_high_0p03",
            "archive_action": "compact_only_or_legacy_archive_pending_raw_archive_decision",
            "output_root": "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_fixed_tau_nofb_init_tests/stephanov_n6_fixed_tau_t003_nofb_single_source473_512x10000_20260527h",
            "log_root": "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/stephanov_fixed_tau_nofb_init_tests/stephanov_n6_fixed_tau_t003_nofb_single_source473_512x10000_20260527h",
            "final_criterion_packet": final_packet,
            "readback_packet": readback,
            "notes": "512 summaries, 512 observable histories, 512 snapshots; fixed-tau noncanonical control group.",
        },
        {
            "dataset_group": "fixed_tau_withfb",
            "dataset_id": "stephanov_n6_fixed_tau_withfb",
            "role": "legacy_diagnostic_comparison_group",
            "status": "partial_legacy_diagnostic",
            "method": "withfb",
            "flow_setup": "fixed_tau_t_high_0p03",
            "archive_action": "legacy_archive_or_compact_only_pending_raw_archive_decision",
            "output_root": "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_fixed_tau_withfb_init_tests/stephanov_n6_fixed_tau_t003_withfb_single_source473_512x10000_20260528a",
            "log_root": "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/stephanov_fixed_tau_withfb_init_tests/stephanov_n6_fixed_tau_t003_withfb_single_source473_512x10000_20260528a",
            "final_criterion_packet": final_packet,
            "readback_packet": readback,
            "notes": "Partial withfb fixed-tau diagnostic; not a canonical production dataset.",
        },
        {
            "dataset_group": "TLTM_nofb",
            "dataset_id": "stephanov_n6_tltm_nofb",
            "role": "canonical_production_group",
            "status": "complete",
            "method": "no_fb",
            "flow_setup": "TLTM_ladder_t_high_0p03",
            "archive_action": "canonical_raw_component_pending_raw_archive_decision",
            "output_root": "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_tltm_production/stephanov_n6_nofb15k_512_equalcost_20260526f",
            "log_root": "per-record run.log files under output_root",
            "final_criterion_packet": final_packet,
            "readback_packet": readback,
            "notes": "512 seeds, 15001 samples/seed in final observable packet; repair job outputs allowed for observable completeness but excluded from runtime accounting.",
        },
        {
            "dataset_group": "TLTM_withfb",
            "dataset_id": "stephanov_n6_tltm_withfb",
            "role": "legacy_diagnostic_comparison_group",
            "status": "complete",
            "method": "withfb",
            "flow_setup": "TLTM_ladder_t_high_0p03",
            "archive_action": "legacy_archive_pending_raw_archive_decision",
            "output_root": "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_tltm_production/stephanov_n6_5000_complete_512_optimal_20260526e",
            "log_root": "per-record run.log files under output_root",
            "final_criterion_packet": final_packet,
            "readback_packet": readback,
            "notes": "512 seeds, 5001 samples/seed in final observable packet; withfb remains default-off legacy diagnostic mode.",
        },
    ]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    obs_rows = read_csv(OBS_CSV)
    obs_gate = obs_gate_rows(obs_rows)
    with RUNTIME_EXCLUSIONS.open() as fh:
        runtime_exclusion = json.load(fh)
    globs = list(runtime_exclusion.get("excluded_run_name_globs", []))

    nofb_rows, nofb_excluded = collect_summary_rows("tltm_nofb", globs)
    withfb_rows, withfb_excluded = collect_summary_rows("tltm_withfb", globs)
    runtime_summary = [
        summarize_runtime("nofb", nofb_rows, nofb_excluded),
        summarize_runtime("withfb", withfb_rows, withfb_excluded),
    ]

    diagnostic_fields = list(runtime_summary[0].keys())
    write_csv(OUT / "diagnostic_summary_by_method.csv", runtime_summary, diagnostic_fields)

    gate_rows = [
        {
            "gate": "observable_correctness",
            "status": "passes_nofb_no_withfb_rescue",
            "basis": "All four nofb primary z scores have abs(z)<2; withfb all-available also abs(z)<2 but does not improve over nofb.",
        },
        {
            "gate": "ratio_estimator_stability",
            "status": "passes_nofb_no_withfb_rescue",
            "basis": "Final pooled phase coherence: nofb_all=0.117377, withfb_all=0.120014, nofb_same_size=0.116900; no denominator rescue signal.",
        },
        {
            "gate": "ladder_transport_high_flow",
            "status": "transport_warning_secondary_no_switch",
            "basis": "Interim failure-mediated transport warning exists, but zero-round-trip fraction was 0 and final summaries show positive round trips.",
        },
        {
            "gate": "failure_mediated_repair",
            "status": "diagnostic_only_no_downstream_rescue",
            "basis": "Failure count is not a criterion; final data do not show observable or ratio-quality rescue.",
        },
        {
            "gate": "wall_clock_efficiency",
            "status": "equal_wall_clock_blocked_by_exclusion_manifest",
            "basis": "Runtime repair/outlier exclusions prevent a clean all-available equal-wall-clock cut; segment diagnostics show withfb is substantially slower per 2500-cycle row.",
        },
        {
            "gate": "production_method",
            "status": "keep_nofb_canonical_withfb_legacy_default_off",
            "basis": "Frozen gates do not justify promoting withfb; TLTM remains canonical nofb before WV-HMC work starts.",
        },
    ]
    write_csv(OUT / "gate_status.csv", gate_rows, ["gate", "status", "basis"])

    final_packet_rel = str((OUT / "FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md").relative_to(ROOT))
    dataset_groups = build_dataset_groups(final_packet_rel)
    dataset_fields = [
        "dataset_group",
        "dataset_id",
        "role",
        "status",
        "method",
        "flow_setup",
        "archive_action",
        "output_root",
        "log_root",
        "final_criterion_packet",
        "readback_packet",
        "notes",
    ]
    with (OUT / "dataset_archive_groups_final.tsv").open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=dataset_fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(dataset_groups)

    summary = {
        "generated_at": "2026-05-29",
        "scope": "Post-TLTM closure before WV-HMC implementation",
        "decision": "Keep TLTM nofb canonical; withfb is default-off legacy diagnostic mode.",
        "observable_gate": obs_gate,
        "runtime_diagnostic": runtime_summary,
        "runtime_exclusion_manifest": str(RUNTIME_EXCLUSIONS.relative_to(ROOT)),
        "runtime_exclusion_rule": runtime_exclusion.get("rule", ""),
        "dataset_groups": dataset_groups,
        "interim_framework": str(INTERIM_FRAMEWORK.relative_to(ROOT)),
        "artifacts": {
            "final_closure_md": final_packet_rel,
            "gate_status_csv": str((OUT / "gate_status.csv").relative_to(ROOT)),
            "diagnostic_summary_csv": str((OUT / "diagnostic_summary_by_method.csv").relative_to(ROOT)),
            "dataset_archive_tsv": str((OUT / "dataset_archive_groups_final.tsv").relative_to(ROOT)),
        },
    }
    with (OUT / "final_criterion_summary.json").open("w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=True)
        fh.write("\n")

    mixing = read_mixing_reference()
    nofb_all = next(r for r in obs_rows if r["group"] == "nofb_all_available")
    withfb_all = next(r for r in obs_rows if r["group"] == "withfb_all_available")
    nofb_same = next(r for r in obs_rows if r["group"] == "nofb_same_config_size_as_withfb")

    lines: list[str] = []
    lines.extend(
        [
            "# Final `withfb`/`nofb` Criterion Closure - 2026-05-29",
            "",
            "Scope: Stephanov `n=6`, TLTM ladder endpoint `t_high=0.03`, before opening the WV-HMC implementation gate.",
            "",
            "This packet applies the frozen criterion framework.  It does not retune thresholds after seeing the final data.",
            "",
            "## Decision",
            "",
            "- Keep `nofb` as canonical TLTM production mode.",
            "- Keep `withfb` / DFO-LS fallback as default-off legacy diagnostic mode.",
            "- Lower failure count remains diagnostic-only and is not a production criterion.",
            "- Do not use the runtime-excluded repair/outlier jobs for equal-wall-clock, throughput, ESS/hour, or `1/SE^2/hour` claims.",
            "",
            "## Primary Observable Gate",
            "",
            "| group | samples | phase | effN | chiral Re z | chiral Im z | density Re z | density Im z | max abs z | gate |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
        ]
    )
    for row in obs_gate:
        lines.append(
            "| `{group}` | {samples} | {phase:.6f} | {effn:.0f} | {czr:+.3f} | {czi:+.3f} | {dzr:+.3f} | {dzi:+.3f} | {maxz:.3f} | {gate} |".format(
                group=row["group"],
                samples=row["total_samples"],
                phase=row["phase"],
                effn=row["effN"],
                czr=row["chiral_Re_z"],
                czi=row["chiral_Im_z"],
                dzr=row["density_Re_z"],
                dzi=row["density_Im_z"],
                maxz=row["max_abs_primary_z"],
                gate="pass" if row["primary_z_pass_abs_lt_2"] else "fail",
            )
        )
    lines.extend(
        [
            "",
            "Observable-gate conclusion: `nofb_all_available` passes the four primary z checks (`abs(z)<2`). `withfb_all_available` also has `abs(z)<2`, but does not rescue a `nofb` observable failure and is not closer on the four checks as a set.",
            "",
            "## Ratio-Estimator Gate",
            "",
            "- `nofb_all_available` phase coherence: `{}`.".format(format_num(to_float(nofb_all["phase"]))),
            "- `withfb_all_available` phase coherence: `{}`.".format(format_num(to_float(withfb_all["phase"]))),
            "- `nofb_same_config_size_as_withfb` phase coherence: `{}`.".format(format_num(to_float(nofb_same["phase"]))),
            "",
            "Ratio-gate conclusion: there is no denominator or phase-coherence rescue that requires `withfb`.",
            "",
            "## Transport Gate",
            "",
        ]
    )
    for key in ["nofb:all_available", "withfb:all_available"]:
        if key in mixing:
            row = mixing[key]
            lines.append(
                "- `{}`: round-trip median `{}`, zero-round-trip fraction `{}`, high-flow return median `{}`.".format(
                    key,
                    row.get("round_trip_median", "NA"),
                    row.get("zero_round_trip_fraction", "NA"),
                    row.get("high_return_interval_median", "NA"),
                )
            )
    lines.extend(
        [
            "",
            "Transport-gate conclusion: the earlier failure-mediated ladder-transport signal remains a warning flag, but transport-only improvement does not justify a production switch without observable, ratio, high-flow ergodicity, or wall-clock productivity impact.",
            "",
            "## Runtime Diagnostic",
            "",
            "| method | rows included | rows excluded | median wall sec/row | mean wall sec/row | acceptance proxy | proposal failure proxy | reverse-gate reject proxy | median round trips/row | note |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
        ]
    )
    for row in runtime_summary:
        lines.append(
            "| `{method}` | {inc} | {exc} | {wmed} | {wmean} | {acc} | {pf} | {rg} | {rt} | {note} |".format(
                method=row["method"],
                inc=row["included_rows"],
                exc=row["excluded_rows"],
                wmed=format_num(row["wall_sec_median_per_row"]),
                wmean=format_num(row["wall_sec_mean_per_row"]),
                acc=format_num(row["attempt_acceptance_rate_proxy"]),
                pf=format_num(row["proposal_failure_rate_proxy"]),
                rg=format_num(row["reverse_gate_reject_rate_proxy"]),
                rt=format_num(row["round_trip_median_per_row"]),
                note=row["runtime_accounting_note"],
            )
        )
    lines.extend(
        [
            "",
            "Runtime-gate conclusion: a clean all-available equal-wall-clock comparison is blocked by the runtime exclusion manifest.  The included segment diagnostics are still sufficient to show that `withfb` is much slower per 2500-cycle row, so without an observable or ratio rescue there is no basis to promote it.",
            "",
            "## Gate Status",
            "",
            "| gate | status | basis |",
            "|---|---|---|",
        ]
    )
    for row in gate_rows:
        lines.append("| `{}` | `{}` | {} |".format(row["gate"], row["status"], row["basis"]))
    lines.extend(
        [
            "",
            "## Dataset Groups",
            "",
            "| group | status | role | archive action | output root |",
            "|---|---|---|---|---|",
        ]
    )
    for row in dataset_groups:
        lines.append(
            "| `{}` | `{}` | `{}` | `{}` | `{}` |".format(
                row["dataset_group"],
                row["status"],
                row["role"],
                row["archive_action"],
                row["output_root"],
            )
        )
    lines.extend(
        [
            "",
            "## Runtime Exclusions",
            "",
            "The manifest below is authoritative for runtime accounting:",
            "",
            "- `{}`".format(RUNTIME_EXCLUSIONS.relative_to(ROOT)),
            "",
            "Allowed use: observable/sample completeness. Forbidden use: runtime totals, throughput, equal-wall-clock, ESS/hour, and `1/SE^2/hour` claims.",
            "",
            "## Pre-WV-HMC Consequence",
            "",
            "- TLTM closure is sufficient to proceed with source hygiene and WV-HMC preparation.",
            "- Future WV-HMC must be added as a sibling sampler following `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`.",
            "- The old `wv` config residue must not be reused as the WV-HMC sampler switch.",
            "",
            "## Artifacts",
            "",
            "- `final_criterion_summary.json`",
            "- `gate_status.csv`",
            "- `diagnostic_summary_by_method.csv`",
            "- `dataset_archive_groups_final.tsv`",
        ]
    )
    (OUT / "FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md").write_text("\n".join(lines) + "\n")

    readme = [
        "# Post-TLTM WV-HMC Ready Packet",
        "",
        "Generated on 2026-05-29.",
        "",
        "This directory closes the Stephanov `n=6` `nofb`/`withfb` criterion gate and records the compact dataset registry used before opening WV-HMC work.",
        "",
        "Files:",
        "",
        "- `FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`",
        "- `final_criterion_summary.json`",
        "- `gate_status.csv`",
        "- `diagnostic_summary_by_method.csv`",
        "- `dataset_archive_groups_final.tsv`",
    ]
    (OUT / "README.md").write_text("\n".join(readme) + "\n")


if __name__ == "__main__":
    main()
