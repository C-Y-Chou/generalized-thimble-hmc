#!/usr/bin/env python3

import argparse
import csv
import sys
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Merge split stage-3 multiseed chunk outputs.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--config", required=True, help="Protocol JSON used for the full run.")
    parser.add_argument("--output-subdir", required=True, help="Final output directory relative to repo root.")
    parser.add_argument(
        "--chunk-glob",
        default="chunk_*",
        help="Glob under output-subdir containing chunk directories.",
    )
    parser.add_argument("--log-prefix", required=True, help="Final report filename prefix.")
    parser.add_argument("--report-title", required=True, help="Final markdown report title.")
    parser.add_argument("--expected-rows", type=int, default=100, help="Expected per-seed CSV data rows.")
    parser.add_argument("--jobs-label", default="array", help="Resource-policy jobs label for the report.")
    parser.add_argument("--requested-cpus", type=int, default=0, help="Total requested CPU budget for the split run.")
    return parser.parse_args()


def read_csv_rows(path):
    with path.open() as f:
        return list(csv.DictReader(f))


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    sys.path.insert(0, str(repo_root / "scripts"))
    from run_stage3_3_multiseed import (
        aggregate_rows,
        local_transition_aggregate_columns,
        local_transition_count_columns,
        newton_eval_flow_status_aggregate_columns,
        newton_eval_flow_status_count_columns,
        qn_eval_flow_status_aggregate_columns,
        qn_eval_flow_status_count_columns,
        read_protocol,
        reverse_gate_aggregate_columns,
        reverse_gate_count_columns,
        reverse_gate_replay_status_aggregate_columns,
        reverse_gate_replay_status_count_columns,
        write_csv,
        write_report,
    )

    setup = read_protocol(repo_root, args.config)
    out_dir = (repo_root / args.output_subdir).resolve()
    chunk_dirs = sorted(p for p in out_dir.glob(args.chunk_glob) if p.is_dir())
    if not chunk_dirs:
        raise RuntimeError("No chunk directories found under {0}".format(out_dir))

    rows = []
    for chunk_dir in chunk_dirs:
        csv_path = chunk_dir / "per_seed_summary_table.csv"
        if not csv_path.exists():
            raise RuntimeError("Missing chunk summary: {0}".format(csv_path))
        rows.extend(read_csv_rows(csv_path))

    rows_sorted = sorted(rows, key=lambda r: (r["method"], int(r["seed_id"])))
    if args.expected_rows > 0 and len(rows_sorted) != args.expected_rows:
        raise RuntimeError(
            "Merged row count mismatch: got {0}, expected {1}".format(len(rows_sorted), args.expected_rows)
        )

    seen = set()
    duplicates = []
    for row in rows_sorted:
        key = (row["method"], row["seed_id"])
        if key in seen:
            duplicates.append(key)
        seen.add(key)
    if duplicates:
        raise RuntimeError("Duplicate method/seed rows: {0}".format(duplicates[:8]))

    aggregated_rows = aggregate_rows(rows_sorted, setup["observable_exact_re"], setup["observable_exact_im"])
    per_seed_csv = out_dir / "per_seed_summary_table.csv"
    aggregated_csv = out_dir / "aggregated_summary_table.csv"
    report_md = out_dir / "{0}_report.md".format(args.log_prefix)

    per_seed_columns = [
        "seed_id",
        "method",
        "projection_failure_count",
        "unresolved_failure_count",
        "fallback_trigger_count",
        "quasi_probe_success_count",
        "full_stage_trigger_count",
        "full_stage_success_count",
        "quasi_class_local_count",
        "quasi_class_mid_count",
        "quasi_class_global_count",
        "far_route_skip_count",
        "far_route_light_count",
        "far_route_anchor_count",
        "near_rescue_candidate_count",
        "near_rescue_attempt_count",
        "near_rescue_success_count",
        "near_rescue_unusable_count",
        "quasi_watchdog_hit_count",
        "quasi_watchdog_used_sum",
        "quasi_watchdog_used_max",
        "quasi_watchdog_budget_last",
        "far_investment_scope_count",
        "far_investment_success_count",
        "far_investment_fail_count",
        "far_investment_fail_fast_count",
        "far_investment_spent_success_count",
        "far_investment_spent_fail_count",
        "far_investment_flowzr_units",
        "far_investment_final_units",
        "far_investment_success_flowzr_units",
        "far_investment_success_final_units",
        "far_investment_fail_flowzr_units",
        "far_investment_fail_final_units",
        "quasi_global_filter_candidate_count",
        "quasi_global_filter_pass_count",
        "quasi_global_filter_reject_count",
        *reverse_gate_count_columns(),
        *newton_eval_flow_status_count_columns(),
        *qn_eval_flow_status_count_columns(),
        *reverse_gate_replay_status_count_columns(),
        *local_transition_count_columns(),
        "accepted_local_total",
        "accepted_local_newton_only_count",
        "accepted_local_quasi_count",
        "accepted_local_rescue_count",
        "accepted_local_probe_only_count",
        "accepted_local_full_stage_count",
        "accepted_local_near_rescue_count",
        "accepted_local_nonnear_route_count",
        "accepted_local_uncategorized_count",
        "accepted_local_class_local_count",
        "accepted_local_class_mid_count",
        "accepted_local_class_global_count",
        "accepted_local_far_skip_count",
        "accepted_local_far_light_count",
        "accepted_local_far_anchor_count",
        "pair0_accept_rate",
        "total_round_trip",
        "avg_round_trip_cycles_if_observed",
        "hot_end_hit_count",
        "runtime_total",
        "runtime_per_cycle",
        "stage2_threads",
        "eval_threads",
        "stage2_init_mode",
        "max_flow_time",
        "schedule",
        "Ohat_re",
        "Ohat_im",
        "err_Ohat_re",
        "err_Ohat_im",
        "err_Ohat_valid",
        "Zp_re",
        "Zp_im",
        "Zp_abs_max",
        "Ohat",
        "err_Ohat",
        "Zp",
        "local_accept_rate_by_slot",
        "pairwise_swap_acceptance_by_pair",
        "farthest_slot_reached_by_label",
        "summary_file",
        "label_trace_file",
        "stage2_log",
        "eval_log",
        "multichain_meta_file",
        "all_replica_history_dir",
    ]
    aggregated_columns = [
        "method",
        "n_seeds",
        "P68_re",
        "P95_re",
        "P68_im",
        "P95_im",
        "P68",
        "P95",
        "mean_Ohat_re",
        "mean_Ohat_im",
        "std_Ohat_re",
        "std_Ohat_im",
        "Zmean_re",
        "Zmean_im",
        "mean_Zp",
        "median_abs_Zp",
        "mean_Zp_re",
        "mean_Zp_im",
        "total_unresolved_failure_count",
        "mean_projection_failure_count",
        "mean_unresolved_failure_count",
        "mean_quasi_probe_success_count",
        "mean_full_stage_trigger_count",
        "mean_pair0_accept_rate",
        "mean_total_round_trip",
        "mean_hot_end_hit_count",
        "mean_runtime_total",
        "median_runtime_total",
        *reverse_gate_aggregate_columns(),
        *newton_eval_flow_status_aggregate_columns(),
        *qn_eval_flow_status_aggregate_columns(),
        *reverse_gate_replay_status_aggregate_columns(),
        *local_transition_aggregate_columns(),
    ]

    write_csv(per_seed_csv, rows_sorted, per_seed_columns)
    write_csv(aggregated_csv, aggregated_rows, aggregated_columns)
    write_report(
        repo_root,
        setup,
        rows_sorted,
        aggregated_rows,
        report_md,
        {
            "schedule": "task-array",
            "jobs": args.jobs_label,
            "stage2_threads": 1,
            "eval_threads": 1,
            "available_cpus": args.requested_cpus,
            "requested_cpus": args.requested_cpus,
        },
        args.report_title,
        out_dir,
    )
    print("[DONE] merged {0} rows from {1} chunks".format(len(rows_sorted), len(chunk_dirs)))
    print("  {0}".format(per_seed_csv))
    print("  {0}".format(aggregated_csv))
    print("  {0}".format(report_md))


if __name__ == "__main__":
    main()
