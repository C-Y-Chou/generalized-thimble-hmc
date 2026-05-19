#!/usr/bin/env python3
"""Audit the current TLTM Stage2 v0 tempering output contract.

This script is intentionally parser-only. It reads existing Stage2/Stage3
artifacts and checks accounting, label-trace, and declared timing invariants without
changing Fortran source, output writers, production workflows, or binary files.
"""

import argparse
import csv
import json
import math
import sys
from collections import defaultdict
from pathlib import Path


LOCAL_TRANSITION_NAMES = [
    "metropolis_reject",
    "reverse_gate_reject",
    "proposal_failure",
    "hamiltonian_invalid",
    "delta_h_invalid",
    "output_size_mismatch",
]

REQUIRED_STAGE2_SCALARS = [
    "slots",
    "cycles",
    "local_updates",
    "swap_enabled",
    "elapsed_sec",
    "total_round_trip",
]

REQUIRED_STAGE2_KV_TAGS = [
    "fallback_stats",
    "constraint_stats",
    "quasi_stage_stats",
    "quasi_class_stats",
    "far_route_stats",
    "near_rescue_stats",
    "quasi_watchdog_stats",
    "far_investment_stats",
    "far_investment_units",
    "quasi_global_filter_stats",
    "newton_eval_flow_status",
    "reverse_gate_replay_status",
    "qn_eval_flow_status",
    "reverse_gate_route_candidates",
    "reverse_gate_route_pass",
    "reverse_gate_route_reject",
    "local_transition_totals",
    "accepted_local_census_totals",
    "accepted_local_route_totals",
]

REQUIRED_STAGE2_SECTIONS = [
    "accepted_local_census",
    "slots",
    "pairs",
    "labels",
]

KNOWN_UNVERIFIABLE_FROM_V0 = [
    "Exact swap energy delta E_proposed - E_current for each attempted swap.",
    "Whether a failed swap reflow left every slot-state component bitwise unchanged.",
    "Whether current-energy failure and proposed-energy failure are distinguishable in pair stats.",
    "Whether a history sample was written before or after a specific successful swap without source knowledge.",
    "Whether a rejected local proposal left every live state component unchanged.",
    "Whether RNG draw points are preserved across refactors.",
]

V0_TIMING_CONVENTION = "local_update -> swap -> measure/history/label_trace"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Parser-only TLTM Stage2 tempering protocol audit for v0 outputs."
    )
    parser.add_argument("--summary", required=True, help="Path to tltm_stage2_summary.dat.")
    parser.add_argument("--label-trace", help="Optional path to tltm_stage2_label_trace.dat.")
    parser.add_argument("--stage3-per-seed", help="Optional Stage3 per-seed CSV for cross-checks.")
    parser.add_argument("--manifest", help="Optional v1alpha manifest.json sidecar for cross-checks.")
    parser.add_argument("--protocol", help="Optional v1alpha protocol.json sidecar for cross-checks.")
    parser.add_argument("--stage3-seed-id", type=int, help="Optional seed_id filter for --stage3-per-seed.")
    parser.add_argument("--stage3-method", help="Optional method filter for --stage3-per-seed.")
    parser.add_argument("--out-json", help="Optional JSON audit report path.")
    parser.add_argument("--out-text", help="Optional text audit report path.")
    parser.add_argument(
        "--fail-on",
        choices=("error", "warning", "never"),
        default="error",
        help="Exit nonzero on errors, warnings, or never. Default: error.",
    )
    parser.add_argument(
        "--rate-tol",
        type=float,
        default=5.0e-5,
        help="Tolerance for printed accept-rate comparisons. Default: 5e-5.",
    )
    return parser.parse_args()


def to_number(text):
    token = str(text).strip()
    if token == "":
        return token
    lowered = token.lower()
    if lowered in ("t", "true"):
        return True
    if lowered in ("f", "false"):
        return False
    try:
        if any(ch in token for ch in (".", "e", "E")):
            return float(token)
        return int(token)
    except ValueError:
        return token


def as_bool(value):
    if isinstance(value, bool):
        return value
    token = str(value).strip().lower()
    if token in ("t", "true", "1", "yes", "y", "on"):
        return True
    if token in ("f", "false", "0", "no", "n", "off"):
        return False
    raise ValueError("Cannot parse logical value: {0}".format(value))


def as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def parse_key_value_pairs(text):
    values = {}
    parts = text.replace("=", " ").split()
    for idx in range(0, len(parts) - 1, 2):
        values[parts[idx]] = to_number(parts[idx + 1])
    return values


def parse_stage2_summary(summary_path):
    summary_path = Path(summary_path)
    scalars = {}
    kv_tags = {}
    sections = {}
    section = None
    section_header = None

    for line_no, raw in enumerate(summary_path.read_text().splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue

        if line.startswith("# ["):
            close_idx = line.find("]")
            if close_idx < 0:
                raise ValueError("Malformed section header at line {0}: {1}".format(line_no, raw))
            section = line[3:close_idx]
            section_header = line[close_idx + 1 :].strip().split()
            sections[section] = {"header": section_header, "rows": [], "line": line_no}
            continue

        if line.startswith("#"):
            payload = line[1:].strip()
            if "=" in payload and " " not in payload.split("=", 1)[0].strip():
                key, value = payload.split("=", 1)
                scalars[key.strip()] = to_number(value.strip())
                continue

            parts = payload.split(maxsplit=1)
            if len(parts) == 2 and "=" in parts[1]:
                key, rest = parts
                kv_tags[key] = parse_key_value_pairs(rest)
            continue

        if section is None:
            continue

        parts = line.split()
        row = {}
        for idx, value in enumerate(parts):
            if idx < len(section_header):
                row[section_header[idx]] = to_number(value)
            else:
                row["extra_{0}".format(idx - len(section_header) + 1)] = to_number(value)
        row["_line"] = line_no
        sections[section]["rows"].append(row)

    return {
        "path": str(summary_path),
        "scalars": scalars,
        "kv_tags": kv_tags,
        "sections": sections,
    }


def parse_label_trace(label_trace_path):
    if not label_trace_path:
        return None

    label_trace_path = Path(label_trace_path)
    records = []
    header = []
    for line_no, raw in enumerate(label_trace_path.read_text().splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            payload = line[1:].strip()
            if payload:
                header = payload.split()
            continue

        parts = line.split()
        if len(parts) < 4:
            raise ValueError("Malformed label trace row at line {0}: {1}".format(line_no, raw))
        records.append(
            {
                "cycle": int(parts[0]),
                "label_id": int(parts[1]),
                "slot_id": int(parts[2]),
                "round_trip_count": int(parts[3]),
                "_line": line_no,
            }
        )

    return {
        "path": str(label_trace_path),
        "header": header,
        "records": records,
    }


def parse_stage3_row(stage3_path, seed_id=None, method=None):
    if not stage3_path:
        return None

    stage3_path = Path(stage3_path)
    with stage3_path.open(newline="") as f:
        rows = list(csv.DictReader(f))

    candidates = rows
    if seed_id is not None:
        candidates = [row for row in candidates if row.get("seed_id") == str(seed_id)]
    if method is not None:
        candidates = [row for row in candidates if row.get("method") == method]

    if len(candidates) != 1:
        return {
            "path": str(stage3_path),
            "row": None,
            "selection_error": "Expected exactly one Stage3 row, found {0}".format(len(candidates)),
        }

    return {
        "path": str(stage3_path),
        "row": candidates[0],
        "selection_error": None,
    }


def parse_json_sidecar(path):
    if not path:
        return None

    sidecar_path = Path(path)
    try:
        data = json.loads(sidecar_path.read_text())
    except json.JSONDecodeError as exc:
        return {
            "path": str(sidecar_path),
            "data": None,
            "parse_error": str(exc),
        }

    return {
        "path": str(sidecar_path),
        "data": data,
        "parse_error": None,
    }


def add_check(checks, name, passed, severity="error", details=None):
    checks.append(
        {
            "name": name,
            "passed": bool(passed),
            "severity": severity,
            "details": details or {},
        }
    )


def section_rows(summary, section_name):
    return summary["sections"].get(section_name, {}).get("rows", [])


def rows_by_int_key(rows, key):
    out = {}
    for row in rows:
        if key in row:
            out[as_int(row[key])] = row
    return out


def sum_row_fields(rows, fields):
    return {field: sum(as_int(row.get(field, 0)) for row in rows) for field in fields}


def expected_pair_proposals(cycles, slot_a, swap_enabled):
    if (not swap_enabled) or cycles <= 0:
        return 0
    expected = 0
    for cycle in range(1, cycles + 1):
        first_slot = 0 if cycle % 2 == 1 else 1
        if slot_a >= first_slot and (slot_a - first_slot) % 2 == 0:
            expected += 1
    return expected


def close_enough(a, b, tol):
    if not math.isfinite(a) or not math.isfinite(b):
        return False
    return abs(a - b) <= tol


def check_stage2_summary(summary, rate_tol):
    checks = []
    scalars = summary["scalars"]
    kv_tags = summary["kv_tags"]
    sections = summary["sections"]
    slots = section_rows(summary, "slots")
    pairs = section_rows(summary, "pairs")
    labels = section_rows(summary, "labels")
    accepted_census = section_rows(summary, "accepted_local_census")

    for key in REQUIRED_STAGE2_SCALARS:
        add_check(checks, "required scalar: {0}".format(key), key in scalars)

    for key in REQUIRED_STAGE2_KV_TAGS:
        add_check(checks, "required kv tag: {0}".format(key), key in kv_tags)

    for key in REQUIRED_STAGE2_SECTIONS:
        add_check(checks, "required section: {0}".format(key), key in sections)

    n_slots = as_int(scalars.get("slots", len(slots)))
    cycles = as_int(scalars.get("cycles", 0))
    local_updates = as_int(scalars.get("local_updates", 0))
    try:
        swap_enabled = as_bool(scalars.get("swap_enabled", True))
    except ValueError:
        swap_enabled = True
        add_check(checks, "swap_enabled parseable logical", False)
    try:
        fixed_flow_mode = as_bool(scalars.get("fixed_flow_mode", False))
    except ValueError:
        fixed_flow_mode = False
        add_check(checks, "fixed_flow_mode parseable logical", False)
    expected_label_rows = 0 if fixed_flow_mode else n_slots

    add_check(
        checks,
        "slot section row count",
        len(slots) == n_slots,
        details={"expected": n_slots, "observed": len(slots)},
    )
    add_check(
        checks,
        "label section row count",
        len(labels) == expected_label_rows,
        details={"expected": expected_label_rows, "observed": len(labels), "fixed_flow_mode": fixed_flow_mode},
    )
    add_check(
        checks,
        "pair section row count",
        len(pairs) == max(0, n_slots - 1),
        details={"expected": max(0, n_slots - 1), "observed": len(pairs)},
    )

    slot_ids = [as_int(row.get("slot_id", -1)) for row in slots]
    label_ids = [as_int(row.get("label_id", -1)) for row in labels]
    add_check(checks, "slot ids are unique", len(slot_ids) == len(set(slot_ids)))
    add_check(checks, "label ids are unique", len(label_ids) == len(set(label_ids)))
    add_check(checks, "slot ids are in range", sorted(slot_ids) == list(range(n_slots)))
    add_check(checks, "label ids are in range", sorted(label_ids) == list(range(expected_label_rows)))

    expected_local_attempts = cycles * local_updates
    slot_reject_field_sums = defaultdict(int)
    total_accepts = 0
    total_rejects = 0
    for row in slots:
        slot_id = as_int(row.get("slot_id", -1))
        accepts = as_int(row.get("accepts", 0))
        rejects = as_int(row.get("rejects", 0))
        total_accepts += accepts
        total_rejects += rejects
        attempts = accepts + rejects
        add_check(
            checks,
            "slot {0} local attempts".format(slot_id),
            attempts == expected_local_attempts,
            details={"expected": expected_local_attempts, "observed": attempts},
        )

        local_reject_sum = sum(as_int(row.get(name, 0)) for name in LOCAL_TRANSITION_NAMES)
        add_check(
            checks,
            "slot {0} local rejection categories sum".format(slot_id),
            local_reject_sum == rejects,
            details={"rejects": rejects, "category_sum": local_reject_sum},
        )

        printed_rate = as_float(row.get("accept_rate", float("nan")))
        expected_rate = accepts / attempts if attempts > 0 else 0.0
        add_check(
            checks,
            "slot {0} accept_rate".format(slot_id),
            close_enough(printed_rate, expected_rate, rate_tol),
            details={"expected": expected_rate, "observed": printed_rate, "tolerance": rate_tol},
        )

        for name in LOCAL_TRANSITION_NAMES:
            slot_reject_field_sums[name] += as_int(row.get(name, 0))

    local_totals = kv_tags.get("local_transition_totals", {})
    for name in LOCAL_TRANSITION_NAMES:
        add_check(
            checks,
            "local_transition_totals {0}".format(name),
            as_int(local_totals.get(name, 0)) == slot_reject_field_sums[name],
            details={"expected": slot_reject_field_sums[name], "observed": as_int(local_totals.get(name, 0))},
        )

    accepted_total = sum(as_int(row.get("accepted_total", 0)) for row in accepted_census)
    add_check(
        checks,
        "accepted_local_census accepted_total matches slot accepts",
        accepted_total == total_accepts,
        details={"slot_accepts": total_accepts, "accepted_census_total": accepted_total},
    )

    accepted_totals_tag = kv_tags.get("accepted_local_census_totals", {})
    add_check(
        checks,
        "accepted_local_census_totals accepted_total matches table",
        as_int(accepted_totals_tag.get("accepted_total", 0)) == accepted_total,
        details={"table": accepted_total, "tag": as_int(accepted_totals_tag.get("accepted_total", 0))},
    )

    for row in pairs:
        pair_id = as_int(row.get("pair_id", -1))
        slot_a = as_int(row.get("slot_a", -1))
        slot_b = as_int(row.get("slot_b", -1))
        proposals = as_int(row.get("proposals", 0))
        accepts = as_int(row.get("accepts", 0))
        rejects = as_int(row.get("rejects", 0))
        add_check(
            checks,
            "pair {0} adjacent slots".format(pair_id),
            slot_b == slot_a + 1,
            details={"slot_a": slot_a, "slot_b": slot_b},
        )
        add_check(
            checks,
            "pair {0} proposal accounting".format(pair_id),
            proposals == accepts + rejects,
            details={"proposals": proposals, "accepts_plus_rejects": accepts + rejects},
        )
        expected_props = expected_pair_proposals(cycles, slot_a, swap_enabled)
        add_check(
            checks,
            "pair {0} v0 parity proposal count".format(pair_id),
            proposals == expected_props,
            details={"expected": expected_props, "observed": proposals, "slot_a": slot_a, "cycles": cycles},
        )
        printed_rate = as_float(row.get("accept_rate", float("nan")))
        expected_rate = accepts / proposals if proposals > 0 else 0.0
        add_check(
            checks,
            "pair {0} accept_rate".format(pair_id),
            close_enough(printed_rate, expected_rate, rate_tol),
            details={"expected": expected_rate, "observed": printed_rate, "tolerance": rate_tol},
        )
        last_accept_prob = as_float(row.get("last_accept_prob", float("nan")))
        if proposals > 0:
            add_check(
                checks,
                "pair {0} last_accept_prob finite range".format(pair_id),
                math.isfinite(last_accept_prob) and 0.0 <= last_accept_prob <= 1.0,
                details={"last_accept_prob": last_accept_prob},
            )

    label_round_trip_sum = sum(as_int(row.get("round_trip_count", 0)) for row in labels)
    add_check(
        checks,
        "total_round_trip matches labels",
        as_int(scalars.get("total_round_trip", 0)) == label_round_trip_sum,
        details={"scalar": as_int(scalars.get("total_round_trip", 0)), "labels": label_round_trip_sum},
    )

    return {
        "checks": checks,
        "summary": {
            "slots": n_slots,
            "cycles": cycles,
            "local_updates": local_updates,
            "swap_enabled": swap_enabled,
            "fixed_flow_mode": fixed_flow_mode,
            "slot_count": len(slots),
            "pair_count": len(pairs),
            "label_count": len(labels),
            "total_local_accepts": total_accepts,
            "total_local_rejects": total_rejects,
        },
    }


def check_label_trace(summary, label_trace):
    checks = []
    if label_trace is None:
        add_check(checks, "label trace provided", False, severity="warning")
        return {"checks": checks, "summary": None}

    scalars = summary["scalars"]
    try:
        fixed_flow_mode = as_bool(scalars.get("fixed_flow_mode", False))
    except ValueError:
        fixed_flow_mode = False
    labels = section_rows(summary, "labels")
    records = label_trace["records"]
    n_slots = as_int(scalars.get("slots", len(labels)))
    cycles = as_int(scalars.get("cycles", 0))
    if fixed_flow_mode:
        add_check(
            checks,
            "fixed-flow label trace has no exchange records",
            len(records) == 0,
            details={"observed": len(records)},
        )
        return {
            "checks": checks,
            "summary": {
                "record_count": len(records),
                "cycle_count": 0,
                "label_count": 0,
                "fixed_flow_mode": True,
            },
        }
    by_cycle = defaultdict(list)
    by_label = defaultdict(list)
    for record in records:
        by_cycle[record["cycle"]].append(record)
        by_label[record["label_id"]].append(record)

    expected_cycles = list(range(cycles + 1))
    observed_cycles = sorted(by_cycle)
    add_check(
        checks,
        "label trace cycles are contiguous 0..cycles",
        observed_cycles == expected_cycles,
        details={"expected": expected_cycles, "observed": observed_cycles},
    )

    for cycle in observed_cycles:
        cycle_rows = by_cycle[cycle]
        labels_at_cycle = [row["label_id"] for row in cycle_rows]
        slots_at_cycle = [row["slot_id"] for row in cycle_rows]
        add_check(
            checks,
            "label trace cycle {0} row count".format(cycle),
            len(cycle_rows) == n_slots,
            details={"expected": n_slots, "observed": len(cycle_rows)},
        )
        add_check(
            checks,
            "label trace cycle {0} unique labels".format(cycle),
            sorted(labels_at_cycle) == list(range(n_slots)),
            details={"observed": sorted(labels_at_cycle)},
        )
        add_check(
            checks,
            "label trace cycle {0} unique slots".format(cycle),
            sorted(slots_at_cycle) == list(range(n_slots)),
            details={"observed": sorted(slots_at_cycle)},
        )

    labels_by_id = rows_by_int_key(labels, "label_id")
    for label_id, rows in by_label.items():
        rows_sorted = sorted(rows, key=lambda row: row["cycle"])
        round_trips = [row["round_trip_count"] for row in rows_sorted]
        add_check(
            checks,
            "label {0} round_trip nondecreasing".format(label_id),
            all(a <= b for a, b in zip(round_trips, round_trips[1:])),
            details={"round_trip_trace": round_trips},
        )
        max_slot_seen = max((row["slot_id"] for row in rows_sorted), default=-1)
        final_row = rows_sorted[-1] if rows_sorted else None
        summary_row = labels_by_id.get(label_id, {})
        add_check(
            checks,
            "label {0} final slot matches summary".format(label_id),
            final_row is not None and final_row["slot_id"] == as_int(summary_row.get("current_slot", -1)),
            details={
                "trace": None if final_row is None else final_row["slot_id"],
                "summary": as_int(summary_row.get("current_slot", -1)),
            },
        )
        add_check(
            checks,
            "label {0} farthest slot matches trace".format(label_id),
            max_slot_seen == as_int(summary_row.get("farthest_slot_reached", -1)),
            details={
                "trace_max": max_slot_seen,
                "summary": as_int(summary_row.get("farthest_slot_reached", -1)),
            },
        )
        add_check(
            checks,
            "label {0} final round_trip matches summary".format(label_id),
            final_row is not None and final_row["round_trip_count"] == as_int(summary_row.get("round_trip_count", -1)),
            details={
                "trace": None if final_row is None else final_row["round_trip_count"],
                "summary": as_int(summary_row.get("round_trip_count", -1)),
            },
        )

    return {
        "checks": checks,
        "summary": {
            "record_count": len(records),
            "cycle_count": len(observed_cycles),
            "label_count": len(by_label),
        },
    }


def maybe_json_loads(text):
    if text is None or text == "":
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def csv_row_count(path):
    try:
        with Path(path).open(newline="") as f:
            return sum(1 for _ in csv.DictReader(f))
    except OSError:
        return None


def paths_match(path_a, path_b):
    if not path_a or not path_b:
        return False
    try:
        return Path(path_a).resolve() == Path(path_b).resolve()
    except OSError:
        return str(path_a) == str(path_b)


def check_stage3_cross(summary, label_trace, stage3, manifest, protocol, rate_tol):
    checks = []
    if stage3 is None:
        add_check(
            checks,
            "Stage3 per-seed CSV cross-check skipped",
            True,
            severity="warning",
            details={"reason": "not provided"},
        )
        return {"checks": checks, "summary": None}

    if stage3.get("selection_error"):
        add_check(
            checks,
            "Stage3 row selection",
            False,
            details={"error": stage3["selection_error"]},
        )
        return {"checks": checks, "summary": {"path": stage3["path"]}}

    row = stage3["row"]
    pairs = rows_by_int_key(section_rows(summary, "pairs"), "pair_id")
    labels = rows_by_int_key(section_rows(summary, "labels"), "label_id")
    slots = rows_by_int_key(section_rows(summary, "slots"), "slot_id")
    manifest_data = None if manifest is None else manifest.get("data")
    protocol_data = None if protocol is None else protocol.get("data")
    manifest_schema = "" if manifest_data is None else manifest_data.get("schema_version", "")

    if "pair0_accept_rate" in row and 0 in pairs:
        add_check(
            checks,
            "Stage3 pair0_accept_rate matches Stage2",
            close_enough(as_float(row["pair0_accept_rate"]), as_float(pairs[0].get("accept_rate")), rate_tol),
            details={"stage3": row["pair0_accept_rate"], "stage2": pairs[0].get("accept_rate")},
        )

    if "total_round_trip" in row:
        add_check(
            checks,
            "Stage3 total_round_trip matches Stage2",
            as_int(row["total_round_trip"]) == as_int(summary["scalars"].get("total_round_trip", 0)),
            details={"stage3": row["total_round_trip"], "stage2": summary["scalars"].get("total_round_trip", 0)},
        )

    slot_rates = maybe_json_loads(row.get("local_accept_rate_by_slot"))
    if slot_rates is not None:
        for slot_id, slot_row in slots.items():
            stage3_value = slot_rates.get(str(slot_id), slot_rates.get(slot_id))
            if stage3_value is None:
                add_check(checks, "Stage3 slot {0} accept_rate present".format(slot_id), False)
                continue
            add_check(
                checks,
                "Stage3 slot {0} accept_rate matches Stage2".format(slot_id),
                close_enough(as_float(stage3_value), as_float(slot_row.get("accept_rate")), rate_tol),
                details={"stage3": stage3_value, "stage2": slot_row.get("accept_rate")},
            )

    farthest = maybe_json_loads(row.get("farthest_slot_reached_by_label"))
    if farthest is not None:
        for label_id, label_row in labels.items():
            stage3_value = farthest.get(str(label_id), farthest.get(label_id))
            if stage3_value is None:
                add_check(checks, "Stage3 label {0} farthest present".format(label_id), False)
                continue
            add_check(
                checks,
                "Stage3 label {0} farthest matches Stage2".format(label_id),
                as_int(stage3_value) == as_int(label_row.get("farthest_slot_reached", -1)),
                details={"stage3": stage3_value, "stage2": label_row.get("farthest_slot_reached")},
            )

    if label_trace is not None and "hot_end_hit_count" in row:
        records = label_trace["records"]
        hot_slot = max((record["slot_id"] for record in records), default=-1)
        hot_hits_label0 = sum(1 for record in records if record["label_id"] == 0 and record["slot_id"] == hot_slot)
        add_check(
            checks,
            "Stage3 hot_end_hit_count matches label trace label0 convention",
            as_int(row["hot_end_hit_count"]) == hot_hits_label0,
            details={"stage3": row["hot_end_hit_count"], "label_trace": hot_hits_label0},
        )

    if row.get("stage2_v1_sidecar_enabled") == "1":
        manifest_text = row.get("stage2_v1_manifest_file", "")
        protocol_text = row.get("stage2_v1_protocol_file", "")
        config_text = row.get("stage2_v1_resolved_config_file", "")
        add_check(
            checks,
            "Stage3 records v1 manifest file",
            bool(manifest_text) and Path(manifest_text).exists(),
            details={"stage3": manifest_text},
        )
        add_check(
            checks,
            "Stage3 records v1 protocol file",
            bool(protocol_text) and Path(protocol_text).exists(),
            details={"stage3": protocol_text},
        )
        if manifest is not None:
            add_check(
                checks,
                "Stage3 manifest path matches audited manifest",
                paths_match(manifest_text, manifest.get("path")),
                details={"stage3": manifest_text, "audit_input": manifest.get("path")},
            )
        if protocol is not None:
            add_check(
                checks,
                "Stage3 protocol path matches audited protocol",
                paths_match(protocol_text, protocol.get("path")),
                details={"stage3": protocol_text, "audit_input": protocol.get("path")},
            )
        if config_text or manifest_schema == "tltm.stage2.manifest.v1alpha2":
            add_check(
                checks,
                "Stage3 records v1 resolved config file",
                bool(config_text) and Path(config_text).exists(),
                details={"stage3": config_text},
            )
            if manifest_data is not None:
                manifest_config = manifest_data.get("outputs", {}).get("v1_resolved_config_file", "")
                add_check(
                    checks,
                    "Stage3 resolved config path matches manifest",
                    paths_match(config_text, manifest_config),
                    details={"stage3": config_text, "manifest": manifest_config},
                )
        if protocol_data is not None and manifest_data is not None:
            add_check(
                checks,
                "Stage3 sidecar audit uses one protocol family",
                manifest_data.get("tempering_protocol_id") == protocol_data.get("protocol_id"),
                details={
                    "manifest": manifest_data.get("tempering_protocol_id"),
                    "protocol": protocol_data.get("protocol_id"),
                },
            )

    return {
        "checks": checks,
        "summary": {
            "path": stage3["path"],
            "seed_id": row.get("seed_id"),
            "method": row.get("method"),
        },
    }


def check_v1_sidecars(summary, manifest, protocol, rate_tol):
    checks = []
    scalars = summary["scalars"]
    slots = section_rows(summary, "slots")

    if manifest is None and protocol is None:
        add_check(
            checks,
            "v1 sidecar cross-check skipped",
            True,
            severity="warning",
            details={"reason": "not provided"},
        )
        return {"checks": checks, "summary": None}

    if manifest is not None:
        if manifest.get("parse_error"):
            add_check(checks, "v1 manifest parses as JSON", False, details={"error": manifest["parse_error"]})
        else:
            add_check(checks, "v1 manifest parses as JSON", True)
    if protocol is not None:
        if protocol.get("parse_error"):
            add_check(checks, "v1 protocol parses as JSON", False, details={"error": protocol["parse_error"]})
        else:
            add_check(checks, "v1 protocol parses as JSON", True)

    manifest_data = None if manifest is None else manifest.get("data")
    protocol_data = None if protocol is None else protocol.get("data")

    if manifest_data is not None:
        add_check(
            checks,
            "v1 manifest schema_version",
            manifest_data.get("schema_version")
            in ("tltm.stage2.manifest.v1alpha1", "tltm.stage2.manifest.v1alpha2"),
            details={"observed": manifest_data.get("schema_version")},
        )
        if manifest_data.get("schema_version") == "tltm.stage2.manifest.v1alpha2":
            add_check(
                checks,
                "v1 manifest product route identity",
                manifest_data.get("canonical_route_id") == "constrained_hmc_reverse_gate_metropolis_v1"
                and manifest_data.get("flow_policy_id") == "odex_hairer_endpoint_v1"
                and manifest_data.get("qn_solver_policy_id") == "official_dfols_residual_certified_v1",
                details={
                    "canonical_route_id": manifest_data.get("canonical_route_id"),
                    "flow_policy_id": manifest_data.get("flow_policy_id"),
                    "qn_solver_policy_id": manifest_data.get("qn_solver_policy_id"),
                },
            )
        add_check(
            checks,
            "v1 manifest timing convention",
            manifest_data.get("sweep_order") == "local_update_swap_measure_history_label_trace"
            and manifest_data.get("measurement_boundary") == "post_swap"
            and manifest_data.get("label_trace_boundary") == "post_swap",
            details={
                "sweep_order": manifest_data.get("sweep_order"),
                "measurement_boundary": manifest_data.get("measurement_boundary"),
                "label_trace_boundary": manifest_data.get("label_trace_boundary"),
            },
        )

        controls = manifest_data.get("resolved_stage2_controls", {})
        add_check(
            checks,
            "v1 manifest cycles match Stage2 summary",
            as_int(controls.get("cycles")) == as_int(scalars.get("cycles")),
            details={"manifest": controls.get("cycles"), "summary": scalars.get("cycles")},
        )
        add_check(
            checks,
            "v1 manifest local_updates match Stage2 summary",
            as_int(controls.get("local_updates")) == as_int(scalars.get("local_updates")),
            details={"manifest": controls.get("local_updates"), "summary": scalars.get("local_updates")},
        )
        try:
            manifest_swap = as_bool(controls.get("swap_enabled"))
            summary_swap = as_bool(scalars.get("swap_enabled"))
            swap_matches = manifest_swap == summary_swap
        except ValueError:
            swap_matches = False
        add_check(
            checks,
            "v1 manifest swap_enabled matches Stage2 summary",
            swap_matches,
            details={"manifest": controls.get("swap_enabled"), "summary": scalars.get("swap_enabled")},
        )

        manifest_ladder = manifest_data.get("flow_ladder", [])
        slot_flow_times = [as_float(row.get("flow_time")) for row in slots]
        add_check(
            checks,
            "v1 manifest flow_ladder length matches slots",
            len(manifest_ladder) == len(slot_flow_times),
            details={"manifest": len(manifest_ladder), "slots": len(slot_flow_times)},
        )
        if len(manifest_ladder) == len(slot_flow_times):
            add_check(
                checks,
                "v1 manifest flow_ladder values match slots",
                all(close_enough(as_float(a), as_float(b), rate_tol) for a, b in zip(manifest_ladder, slot_flow_times)),
                details={"manifest": manifest_ladder, "slots": slot_flow_times, "tolerance": rate_tol},
            )

        if manifest_data.get("schema_version") == "tltm.stage2.manifest.v1alpha2":
            outputs = manifest_data.get("outputs", {})
            config_path = outputs.get("v1_resolved_config_file")
            config_exists = bool(config_path) and Path(config_path).exists()
            add_check(
                checks,
                "v1 resolved config exists",
                config_exists,
                details={"path": config_path},
            )
            if config_exists:
                try:
                    config_data = json.loads(Path(config_path).read_text())
                    config_parse_ok = True
                except json.JSONDecodeError as exc:
                    config_data = {}
                    config_parse_ok = False
                    config_error = str(exc)
                else:
                    config_error = None
                add_check(
                    checks,
                    "v1 resolved config parses as JSON",
                    config_parse_ok,
                    details={"path": config_path, "error": config_error},
                )
                if config_parse_ok:
                    add_check(
                        checks,
                        "v1 resolved config product schema",
                        config_data.get("schema_version") == "tltm.stage2.config.resolved.v1alpha1"
                        and config_data.get("precision", {}).get("precision_policy_id") == "double_strict_v1",
                        details={
                            "schema_version": config_data.get("schema_version"),
                            "precision_policy_id": config_data.get("precision", {}).get("precision_policy_id"),
                        },
                    )

        diagnostics = manifest_data.get("diagnostics", {})
        diagnostics_written = bool(diagnostics.get("v1_diagnostics_written"))
        if diagnostics_written:
            diagnostics_expectations = [
                ("local_transition_summary_csv", len(slots)),
                ("swap_summary_csv", len(section_rows(summary, "pairs"))),
                ("label_summary_csv", len(section_rows(summary, "labels"))),
                ("per_slot_phase_summary_csv", len(slots)),
            ]
            for field_name, expected_rows in diagnostics_expectations:
                path = diagnostics.get(field_name)
                exists = bool(path) and Path(path).exists()
                add_check(
                    checks,
                    "v1 diagnostics file exists: {0}".format(field_name),
                    exists,
                    details={"path": path},
                )
                if exists:
                    observed_rows = csv_row_count(path)
                    add_check(
                        checks,
                        "v1 diagnostics row count: {0}".format(field_name),
                        observed_rows == expected_rows,
                        details={"path": path, "expected": expected_rows, "observed": observed_rows},
                    )

    if protocol_data is not None:
        add_check(
            checks,
            "v1 protocol schema_version",
            protocol_data.get("schema_version")
            in ("tltm.stage2.protocol.v1alpha1", "tltm.stage2.protocol.v1alpha2"),
            details={"observed": protocol_data.get("schema_version")},
        )
        add_check(
            checks,
            "v1 protocol timing convention",
            protocol_data.get("sweep_schedule", {}).get("cycle_order") == "local_update_swap_measure_history_label_trace"
            and protocol_data.get("measurement_policy", {}).get("sample_boundary") == "post_swap"
            and protocol_data.get("measurement_policy", {}).get("label_trace_boundary") == "post_swap",
            details={
                "cycle_order": protocol_data.get("sweep_schedule", {}).get("cycle_order"),
                "sample_boundary": protocol_data.get("measurement_policy", {}).get("sample_boundary"),
                "label_trace_boundary": protocol_data.get("measurement_policy", {}).get("label_trace_boundary"),
            },
        )
        add_check(
            checks,
            "v1 protocol target density fields present",
            bool(protocol_data.get("target_density", {}).get("base_coordinate_density"))
            and bool(protocol_data.get("target_density", {}).get("effective_energy")),
        )
        add_check(
            checks,
            "v1 protocol swap kernel fields present",
            bool(protocol_data.get("swap_kernel", {}).get("acceptance_probability"))
            and bool(protocol_data.get("swap_kernel", {}).get("invalid_reflow_semantics")),
        )

    if manifest_data is not None and protocol_data is not None:
        add_check(
            checks,
            "v1 manifest protocol id matches protocol file",
            manifest_data.get("tempering_protocol_id") == protocol_data.get("protocol_id"),
            details={
                "manifest": manifest_data.get("tempering_protocol_id"),
                "protocol": protocol_data.get("protocol_id"),
            },
        )

    return {
        "checks": checks,
        "summary": {
            "manifest_path": None if manifest is None else manifest["path"],
            "protocol_path": None if protocol is None else protocol["path"],
        },
    }


def summarize_checks(sections):
    flat = []
    for section in sections:
        flat.extend(section.get("checks", []))
    errors = [check for check in flat if (not check["passed"]) and check["severity"] == "error"]
    warnings = [check for check in flat if (not check["passed"]) and check["severity"] == "warning"]
    if errors:
        verdict = "fail"
    elif warnings:
        verdict = "warn"
    else:
        verdict = "pass"
    return {
        "total": len(flat),
        "passed": sum(1 for check in flat if check["passed"]),
        "failed": sum(1 for check in flat if not check["passed"]),
        "errors": len(errors),
        "warnings": len(warnings),
        "verdict": verdict,
    }


def make_report(summary, label_trace, stage3, manifest, protocol, rate_tol):
    summary_checks = check_stage2_summary(summary, rate_tol)
    label_checks = check_label_trace(summary, label_trace)
    stage3_checks = check_stage3_cross(summary, label_trace, stage3, manifest, protocol, rate_tol)
    sidecar_checks = check_v1_sidecars(summary, manifest, protocol, rate_tol)
    check_summary = summarize_checks([summary_checks, label_checks, stage3_checks, sidecar_checks])

    return {
        "input_files": {
            "summary": summary["path"],
            "label_trace": None if label_trace is None else label_trace["path"],
            "stage3_per_seed": None if stage3 is None else stage3["path"],
            "manifest": None if manifest is None else manifest["path"],
            "protocol": None if protocol is None else protocol["path"],
        },
        "detected_v0_schema": {
            "summary_scalars": sorted(summary["scalars"].keys()),
            "summary_kv_tags": sorted(summary["kv_tags"].keys()),
            "summary_sections": sorted(summary["sections"].keys()),
            "timing_convention": V0_TIMING_CONVENTION,
        },
        "declared_or_inferred_protocol": {
            "tempering_parameter": "flow_time",
            "fixed_zone_identifier": "slot_id",
            "mobile_walker_identifier": "label_id",
            "swap_schedule": "v0 one adjacent-pair parity sub-sweep per cycle",
            "cycle_order": V0_TIMING_CONVENTION,
            "measurement_boundary_status": "replica-exchange convention selected for regenerated datasets",
        },
        "summary_parse": {
            "scalars": summary["scalars"],
            "section_row_counts": {
                name: len(payload.get("rows", [])) for name, payload in summary["sections"].items()
            },
        },
        "accounting_checks": summary_checks,
        "label_trace_checks": label_checks,
        "stage3_cross_checks": stage3_checks,
        "v1_sidecar_checks": sidecar_checks,
        "known_unverifiable_from_v0": KNOWN_UNVERIFIABLE_FROM_V0,
        "verdict": check_summary,
    }


def format_text_report(report):
    lines = []
    verdict = report["verdict"]
    lines.append("TLTM tempering protocol audit")
    lines.append("verdict: {0} ({1}/{2} checks passed, errors={3}, warnings={4})".format(
        verdict["verdict"],
        verdict["passed"],
        verdict["total"],
        verdict["errors"],
        verdict["warnings"],
    ))
    lines.append("")
    lines.append("inputs:")
    for key, value in report["input_files"].items():
        lines.append("  {0}: {1}".format(key, value if value is not None else "(not provided)"))
    lines.append("")
    lines.append("inferred protocol:")
    protocol = report["declared_or_inferred_protocol"]
    for key in sorted(protocol):
        lines.append("  {0}: {1}".format(key, protocol[key]))
    lines.append("")

    for title, section_name in (
        ("summary/accounting checks", "accounting_checks"),
        ("label trace checks", "label_trace_checks"),
        ("Stage3 cross-checks", "stage3_cross_checks"),
        ("v1 sidecar checks", "v1_sidecar_checks"),
    ):
        lines.append(title + ":")
        for check in report[section_name]["checks"]:
            if check["passed"]:
                status = "PASS"
            elif check["severity"] == "warning":
                status = "WARN"
            else:
                status = "FAIL"
            detail_text = ""
            if check.get("details"):
                detail_text = " " + json.dumps(check["details"], sort_keys=True)
            lines.append("  [{0}] {1}{2}".format(status, check["name"], detail_text))
        lines.append("")

    lines.append("known unverifiable from v0 alone:")
    for item in report["known_unverifiable_from_v0"]:
        lines.append("  - " + item)
    lines.append("")
    return "\n".join(lines)


def write_if_requested(path, text):
    if not path:
        return
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def exit_code_for(report, fail_on):
    verdict = report["verdict"]
    if fail_on == "never":
        return 0
    if fail_on == "warning" and (verdict["errors"] > 0 or verdict["warnings"] > 0):
        return 1
    if fail_on == "error" and verdict["errors"] > 0:
        return 1
    return 0


def main():
    args = parse_args()
    summary = parse_stage2_summary(args.summary)
    label_trace = parse_label_trace(args.label_trace)
    stage3 = parse_stage3_row(args.stage3_per_seed, seed_id=args.stage3_seed_id, method=args.stage3_method)
    manifest = parse_json_sidecar(args.manifest)
    protocol = parse_json_sidecar(args.protocol)
    report = make_report(summary, label_trace, stage3, manifest, protocol, args.rate_tol)
    text_report = format_text_report(report)

    if args.out_json:
        write_if_requested(args.out_json, json.dumps(report, indent=2, sort_keys=True) + "\n")
    if args.out_text:
        write_if_requested(args.out_text, text_report + "\n")

    if not args.out_text:
        sys.stdout.write(text_report)

    return exit_code_for(report, args.fail_on)


if __name__ == "__main__":
    raise SystemExit(main())
