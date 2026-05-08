#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
build_dir="$repo_root/build"
out_dir="${ODEX_WRAPPER_CHECK_OUT_DIR:-$repo_root/output/tests/odex_wrapper_check}"
flow_times="${ODEX_WRAPPER_CHECK_FLOW_TIMES:-0.1 0.3}"

mkdir -p "$out_dir"
make -C "$build_dir" ../bin/scan_flow_vs_flowz ../bin/scan_flowzr_stability

for flow_time in $flow_times; do
  safe_time=${flow_time//-/_m}
  safe_time=${safe_time//./p}
  flow_vs_flowz_csv="$out_dir/flow_vs_flowz_ft${safe_time}.csv"
  flowzr_roundtrip_csv="$out_dir/flowzr_roundtrip_ft${safe_time}.csv"

  "$repo_root/bin/scan_flow_vs_flowz" "$flow_vs_flowz_csv" -0.5 0.5 21 "$flow_time" 0.0
  "$repo_root/bin/scan_flowzr_stability" "$flowzr_roundtrip_csv" -0.2 0.2 9 -0.2 0.2 9 "$flow_time" 0 1

done

python3 - "$out_dir" <<PY
import csv
import math
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
summary_rows = []

for path in sorted(out_dir.glob("flow_vs_flowz_ft*.csv")):
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    max_delta = 0.0
    max_j_abs = 0.0
    flowz_ok = 0
    flow_ok = 0
    flowz_ok_flow_fail = 0
    for row in rows:
        fz_ok = int(row["flowz_ok"])
        fl_ok = int(row["flow_ok"])
        flowz_ok += fz_ok
        flow_ok += fl_ok
        if fz_ok and not fl_ok:
            flowz_ok_flow_fail += 1
        if fz_ok and fl_ok:
            dz_re = float(row["z_flowz_re"]) - float(row["z_flow_re"])
            dz_im = float(row["z_flowz_im"]) - float(row["z_flow_im"])
            max_delta = max(max_delta, math.hypot(dz_re, dz_im))
            max_j_abs = max(max_j_abs, abs(float(row["j_abs"])))
    summary_rows.append([
        "flow_vs_flowz",
        path.name,
        len(rows),
        flowz_ok,
        flow_ok,
        flowz_ok_flow_fail,
        f"{max_delta:.16e}",
        f"{max_j_abs:.16e}",
        "",
        "",
    ])

for path in sorted(out_dir.glob("flowzr_roundtrip_ft*.csv")):
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    flowzr_ok = 0
    roundtrip_ok = 0
    max_roundtrip = 0.0
    fb_attempts = 0
    fb_failures = 0
    for row in rows:
        fz_ok = int(row["flowzr_ok"])
        back_ok = int(row["flowzr_back_ok"])
        flowzr_ok += fz_ok
        roundtrip_ok += back_ok
        fb_attempts += int(row["flowzr_fb_attempt"])
        fb_failures += int(row["flowzr_fb_fail"])
        value = float(row["roundtrip_abs"])
        if math.isfinite(value):
            max_roundtrip = max(max_roundtrip, value)
    summary_rows.append([
        "flowzr_roundtrip",
        path.name,
        len(rows),
        flowzr_ok,
        roundtrip_ok,
        len(rows) - roundtrip_ok,
        f"{max_roundtrip:.16e}",
        "",
        fb_attempts,
        fb_failures,
    ])

summary_path = out_dir / "summary.tsv"
with summary_path.open("w", newline="") as handle:
    writer = csv.writer(handle, delimiter="\t")
    writer.writerow([
        "check",
        "file",
        "rows",
        "ok_primary",
        "ok_secondary",
        "fail_secondary",
        "max_error",
        "max_j_abs",
        "flowzr_fb_attempts",
        "flowzr_fb_failures",
    ])
    writer.writerows(summary_rows)

print(f"[DONE] ODEX wrapper summary: {summary_path}")
for row in summary_rows:
    print("[SUMMARY] " + " ".join(str(item) for item in row))
PY
