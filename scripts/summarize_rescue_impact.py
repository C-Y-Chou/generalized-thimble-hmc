#!/usr/bin/env python3
"""Summarize near/far rescue impact per multichain run.

Builds a run-level table combining:
- chain log counters (near/far, stage/class/route/watchdog),
- runtime policy hints (rescue level, micro-extended, step budget),
- evaluate metrics (Rhat + robust 1sigma/2sigma component pass),
- summary.json runtime/sample counts.

This is intended for ablation workflows: tune gates first, then decide whether
a structural redesign is needed based on measured rescue-path effects.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Dict, Iterable, List, Optional


NEAR_RE = re.compile(
    r"near_fail=(\d+)\s+near_try=(\d+)\s+near_ok=(\d+)\s+near_unusable=(\d+)"
    r"(?:\s+near_fail_fast=(\d+)\s+far_fail_fast=(\d+))?\s+far_fail=(\d+)"
)
STAGE_RE = re.compile(
    r"quasi stage probe=(\d+)/(\d+)\s+full=(\d+)/(\d+)\s+extended=(\d+)/(\d+)"
)
CLASS_RE = re.compile(r"quasi class local=(\d+)\s+mid=(\d+)\s+global=(\d+)")
ROUTE_RE = re.compile(r"quasi_far_route skip=(\d+)\s+light=(\d+)\s+anchor=(\d+)")
WATCHDOG_RE = re.compile(
    r"quasi_watchdog hits=(\d+)\s+max_used=(\d+)\s+avg_used=\s*([0-9.+\-Ee]+)\s+budget_last=(\d+)"
)
FAR_INVEST_RE = re.compile(
    r"far_invest cases=(\d+)\s+success=(\d+)\s+fail=(\d+)\s+fail_fast=(\d+)\s+case_share=\s*([0-9.+\-Ee]+)\s+unit_share=\s*([0-9.+\-Ee]+)"
)
FAR_UNITS_RE = re.compile(
    r"far_units flowzr=(\d+)\s+final=(\d+)\s+success_flowzr=(\d+)\s+success_final=(\d+)\s+fail_flowzr=(\d+)\s+fail_final=(\d+)"
)
FAR_SPENT_CASES_RE = re.compile(r"far_spent_cases success=(\d+)\s+fail=(\d+)")

INFO_RESCUE_LEVEL_RE = re.compile(r"\[INFO\]\s+quasi rescue level=(\d+)")
INFO_MICRO_EXT_RE = re.compile(r"\[INFO\]\s+qn far light micro-extended:\s+(on|off)")
INFO_STEP_BUDGET_RE = re.compile(
    r"\[INFO\]\s+rescue step budget soft1=(\d+)\s+soft2=(\d+)\s+hard=(\d+)"
)
INFO_STEP_BUDGET_DISABLED_RE = re.compile(r"\[INFO\]\s+rescue step budget=disabled")

EVAL_VIRIAL_RE = re.compile(r"\[RESULT\]\s+<virial>\s+\(Re, Im\)=\s+([\-+0-9.Ee]+)\s+([\-+0-9.Ee]+)")
EVAL_Z_RE = re.compile(r"\[RESULT\]\s+<z>\s+\(Re, Im\)=\s+([\-+0-9.Ee]+)\s+([\-+0-9.Ee]+)")
EVAL_ERR_V_RE = re.compile(
    r"\[RESULT\]\s+error_robust_<virial>\s+\(Re, Im\)=\s+([\-+0-9.Ee]+)\s+([\-+0-9.Ee]+)"
)
EVAL_ERR_Z_RE = re.compile(
    r"\[RESULT\]\s+error_robust_<z>\s+\(Re, Im\)=\s+([\-+0-9.Ee]+)\s+([\-+0-9.Ee]+)"
)
EVAL_RHAT_V_RE = re.compile(
    r"\[RESULT\]\s+split_rhat_virial\s+\(Re, Im\)=\s+([\-+0-9.Ee]+)\s+([\-+0-9.Ee]+)"
)
EVAL_RHAT_Z_RE = re.compile(r"\[RESULT\]\s+split_rhat_z\s+\(Re, Im\)=\s+([\-+0-9.Ee]+)\s+([\-+0-9.Ee]+)")


def _safe_float(text: str) -> float:
    return float(text)


def _find_eval_log(run_dir: Path) -> Optional[Path]:
    run_name = run_dir.name
    candidates = [
        run_dir.parent / f"{run_name}.evaluate.log",
        Path("output/multichain_auto") / f"{run_name}.evaluate.log",
    ]
    for p in candidates:
        if p.exists():
            return p.resolve()
    return None


def _mode_int(values: List[int]) -> Optional[int]:
    if not values:
        return None
    return Counter(values).most_common(1)[0][0]


def _mode_str(values: List[str]) -> Optional[str]:
    if not values:
        return None
    return Counter(values).most_common(1)[0][0]


def _parse_chain_log(path: Path) -> Dict[str, object]:
    last_near = None
    last_stage = None
    last_class = None
    last_route = None
    last_watchdog = None
    last_far_invest = None
    last_far_units = None
    last_far_spent = None

    rescue_level = None
    micro_ext = None
    step_budget = None
    step_budget_disabled = False

    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = INFO_RESCUE_LEVEL_RE.search(line)
            if m:
                rescue_level = int(m.group(1))
            m = INFO_MICRO_EXT_RE.search(line)
            if m:
                micro_ext = m.group(1)
            m = INFO_STEP_BUDGET_RE.search(line)
            if m:
                step_budget = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
            if INFO_STEP_BUDGET_DISABLED_RE.search(line):
                step_budget_disabled = True

            m = NEAR_RE.search(line)
            if m:
                near_fail_fast = int(m.group(5)) if m.group(5) is not None else 0
                far_fail_fast = int(m.group(6)) if m.group(6) is not None else 0
                last_near = (
                    int(m.group(1)),
                    int(m.group(2)),
                    int(m.group(3)),
                    int(m.group(4)),
                    near_fail_fast,
                    far_fail_fast,
                    int(m.group(7)),
                )
            m = STAGE_RE.search(line)
            if m:
                last_stage = tuple(int(m.group(i)) for i in range(1, 7))
            m = CLASS_RE.search(line)
            if m:
                last_class = tuple(int(m.group(i)) for i in range(1, 4))
            m = ROUTE_RE.search(line)
            if m:
                last_route = tuple(int(m.group(i)) for i in range(1, 4))
            m = WATCHDOG_RE.search(line)
            if m:
                last_watchdog = (int(m.group(1)), int(m.group(2)), _safe_float(m.group(3)), int(m.group(4)))
            m = FAR_INVEST_RE.search(line)
            if m:
                last_far_invest = (
                    int(m.group(1)),
                    int(m.group(2)),
                    int(m.group(3)),
                    int(m.group(4)),
                    _safe_float(m.group(5)),
                    _safe_float(m.group(6)),
                )
            m = FAR_UNITS_RE.search(line)
            if m:
                last_far_units = tuple(int(m.group(i)) for i in range(1, 7))
            m = FAR_SPENT_CASES_RE.search(line)
            if m:
                last_far_spent = (int(m.group(1)), int(m.group(2)))

    out: Dict[str, object] = {
        "near": last_near,
        "stage": last_stage,
        "class": last_class,
        "route": last_route,
        "watchdog": last_watchdog,
        "far_invest": last_far_invest,
        "far_units": last_far_units,
        "far_spent": last_far_spent,
        "rescue_level": rescue_level,
        "micro_ext": micro_ext,
        "step_budget": step_budget,
        "step_budget_disabled": step_budget_disabled,
    }
    return out


def _parse_eval(eval_log: Path) -> Dict[str, object]:
    text = eval_log.read_text(encoding="utf-8", errors="replace")

    def grab2(pat: re.Pattern[str], name: str) -> tuple[float, float]:
        m = pat.search(text)
        if not m:
            raise RuntimeError(f"missing {name} in {eval_log}")
        return float(m.group(1)), float(m.group(2))

    vir_re, vir_im = grab2(EVAL_VIRIAL_RE, "<virial>")
    z_re, z_im = grab2(EVAL_Z_RE, "<z>")
    err_v_re, err_v_im = grab2(EVAL_ERR_V_RE, "error_robust_<virial>")
    err_z_re, err_z_im = grab2(EVAL_ERR_Z_RE, "error_robust_<z>")
    rhat_v_re, rhat_v_im = grab2(EVAL_RHAT_V_RE, "split_rhat_virial")
    rhat_z_re, rhat_z_im = grab2(EVAL_RHAT_Z_RE, "split_rhat_z")

    # references: virial=(0,0), z=(0,-1)
    d_vir_re = abs(vir_re)
    d_vir_im = abs(vir_im)
    d_z_re = abs(z_re)
    d_z_im = abs(z_im + 1.0)

    pass1_vir_re = d_vir_re <= err_v_re
    pass1_vir_im = d_vir_im <= err_v_im
    pass1_z_re = d_z_re <= err_z_re
    pass1_z_im = d_z_im <= err_z_im
    pass2_vir_re = d_vir_re <= 2.0 * err_v_re
    pass2_vir_im = d_vir_im <= 2.0 * err_v_im
    pass2_z_re = d_z_re <= 2.0 * err_z_re
    pass2_z_im = d_z_im <= 2.0 * err_z_im

    pass1_components = sum([pass1_vir_re, pass1_vir_im, pass1_z_re, pass1_z_im])
    pass2_components = sum([pass2_vir_re, pass2_vir_im, pass2_z_re, pass2_z_im])

    h = hashlib.sha256(text.encode("utf-8", errors="ignore")).hexdigest()

    return {
        "virial_re": vir_re,
        "virial_im": vir_im,
        "z_re": z_re,
        "z_im": z_im,
        "err_v_re": err_v_re,
        "err_v_im": err_v_im,
        "err_z_re": err_z_re,
        "err_z_im": err_z_im,
        "rhat_v_re": rhat_v_re,
        "rhat_v_im": rhat_v_im,
        "rhat_z_re": rhat_z_re,
        "rhat_z_im": rhat_z_im,
        "rhat_max": max(rhat_v_re, rhat_v_im, rhat_z_re, rhat_z_im),
        "pass_rhat_101": max(rhat_v_re, rhat_v_im, rhat_z_re, rhat_z_im) < 1.01,
        "pass1_virial_re": pass1_vir_re,
        "pass1_virial_im": pass1_vir_im,
        "pass1_z_re": pass1_z_re,
        "pass1_z_im": pass1_z_im,
        "pass2_virial_re": pass2_vir_re,
        "pass2_virial_im": pass2_vir_im,
        "pass2_z_re": pass2_z_re,
        "pass2_z_im": pass2_z_im,
        "pass1_components": pass1_components,
        "pass2_components": pass2_components,
        "pass1_all4": pass1_components == 4,
        "pass2_all4": pass2_components == 4,
        "eval_sha256": h,
    }


def _iter_run_dirs(run_dirs: Iterable[str], run_globs: Iterable[str]) -> List[Path]:
    out: List[Path] = []
    for rd in run_dirs:
        p = Path(rd).resolve()
        if p.is_dir():
            out.append(p)
    for g in run_globs:
        for p in sorted(Path(".").glob(g)):
            if p.is_dir():
                out.append(p.resolve())
    # dedup while preserving order
    seen = set()
    uniq: List[Path] = []
    for p in out:
        if p not in seen:
            seen.add(p)
            uniq.append(p)
    return uniq


def summarize_run(run_dir: Path, include_partial: bool) -> Optional[Dict[str, object]]:
    chain_logs = sorted(run_dir.glob("chain_*/logs/generate_markov_chain.log"))
    if not chain_logs:
        return None

    near_fail_total = 0
    near_try_total = 0
    near_ok_total = 0
    near_unusable_total = 0
    near_fail_fast_total = 0
    far_fail_fast_total = 0
    far_fail_total = 0

    probe_success = 0
    probe_attempt = 0
    full_success = 0
    full_attempt = 0
    ext_success = 0
    ext_attempt = 0

    class_local = 0
    class_mid = 0
    class_global = 0

    route_skip = 0
    route_light = 0
    route_anchor = 0

    watchdog_hits = 0
    watchdog_max_used = 0
    watchdog_budget_last = 0
    far_invest_cases = 0
    far_invest_success = 0
    far_invest_fail = 0
    far_invest_fail_fast = 0
    far_units_flowzr = 0
    far_units_final = 0
    far_units_success_flowzr = 0
    far_units_success_final = 0
    far_units_fail_flowzr = 0
    far_units_fail_final = 0
    far_spent_success = 0
    far_spent_fail = 0

    rescue_levels: List[int] = []
    micro_exts: List[str] = []
    budget_s1: List[int] = []
    budget_s2: List[int] = []
    budget_h: List[int] = []
    budget_disabled_count = 0

    chains_seen = 0
    for cl in chain_logs:
        parsed = _parse_chain_log(cl)
        chains_seen += 1

        near = parsed["near"]
        if isinstance(near, tuple):
            near_fail_total += near[0]
            near_try_total += near[1]
            near_ok_total += near[2]
            near_unusable_total += near[3]
            near_fail_fast_total += near[4]
            far_fail_fast_total += near[5]
            far_fail_total += near[6]

        stage = parsed["stage"]
        if isinstance(stage, tuple):
            probe_success += stage[0]
            probe_attempt += stage[1]
            full_success += stage[2]
            full_attempt += stage[3]
            ext_success += stage[4]
            ext_attempt += stage[5]

        cls = parsed["class"]
        if isinstance(cls, tuple):
            class_local += cls[0]
            class_mid += cls[1]
            class_global += cls[2]

        route = parsed["route"]
        if isinstance(route, tuple):
            route_skip += route[0]
            route_light += route[1]
            route_anchor += route[2]

        wd = parsed["watchdog"]
        if isinstance(wd, tuple):
            watchdog_hits += wd[0]
            watchdog_max_used = max(watchdog_max_used, wd[1])
            watchdog_budget_last = max(watchdog_budget_last, wd[3])

        fi = parsed["far_invest"]
        if isinstance(fi, tuple):
            far_invest_cases += fi[0]
            far_invest_success += fi[1]
            far_invest_fail += fi[2]
            far_invest_fail_fast += fi[3]

        fu = parsed["far_units"]
        if isinstance(fu, tuple):
            far_units_flowzr += fu[0]
            far_units_final += fu[1]
            far_units_success_flowzr += fu[2]
            far_units_success_final += fu[3]
            far_units_fail_flowzr += fu[4]
            far_units_fail_final += fu[5]

        fs = parsed["far_spent"]
        if isinstance(fs, tuple):
            far_spent_success += fs[0]
            far_spent_fail += fs[1]

        rl = parsed["rescue_level"]
        if isinstance(rl, int):
            rescue_levels.append(rl)

        me = parsed["micro_ext"]
        if isinstance(me, str):
            micro_exts.append(me)

        sb = parsed["step_budget"]
        if isinstance(sb, tuple):
            budget_s1.append(sb[0])
            budget_s2.append(sb[1])
            budget_h.append(sb[2])
        if bool(parsed["step_budget_disabled"]):
            budget_disabled_count += 1

    row: Dict[str, object] = {
        "run_dir": str(run_dir),
        "run_name": run_dir.name,
        "chains_seen": chains_seen,
        "rescue_level_mode": _mode_int(rescue_levels),
        "micro_ext_mode": _mode_str(micro_exts),
        "budget_soft1_mode": _mode_int(budget_s1),
        "budget_soft2_mode": _mode_int(budget_s2),
        "budget_hard_mode": _mode_int(budget_h),
        "budget_disabled_chains": budget_disabled_count,
        "near_fail_total": near_fail_total,
        "near_try_total": near_try_total,
        "near_ok_total": near_ok_total,
        "near_unusable_total": near_unusable_total,
        "near_fail_fast_total": near_fail_fast_total,
        "far_fail_fast_total": far_fail_fast_total,
        "far_fail_total": far_fail_total,
        "probe_success_total": probe_success,
        "probe_attempt_total": probe_attempt,
        "full_success_total": full_success,
        "full_attempt_total": full_attempt,
        "extended_success_total": ext_success,
        "extended_attempt_total": ext_attempt,
        "class_local_total": class_local,
        "class_mid_total": class_mid,
        "class_global_total": class_global,
        "route_skip_total": route_skip,
        "route_light_total": route_light,
        "route_anchor_total": route_anchor,
        "watchdog_hits_total": watchdog_hits,
        "watchdog_max_used_max": watchdog_max_used,
        "watchdog_budget_last_max": watchdog_budget_last,
        "far_invest_cases_total": far_invest_cases,
        "far_invest_success_total": far_invest_success,
        "far_invest_fail_total": far_invest_fail,
        "far_invest_fail_fast_total": far_invest_fail_fast,
        "far_units_flowzr_total": far_units_flowzr,
        "far_units_final_total": far_units_final,
        "far_units_success_flowzr_total": far_units_success_flowzr,
        "far_units_success_final_total": far_units_success_final,
        "far_units_fail_flowzr_total": far_units_fail_flowzr,
        "far_units_fail_final_total": far_units_fail_final,
        "far_spent_success_total": far_spent_success,
        "far_spent_fail_total": far_spent_fail,
    }

    summary_json = run_dir / "summary.json"
    if summary_json.exists():
        try:
            js = json.loads(summary_json.read_text(encoding="utf-8", errors="replace"))
            row["summary_elapsed_seconds"] = js.get("elapsed_seconds")
            row["summary_total_samples"] = js.get("total_samples")
            row["summary_targets_met"] = js.get("targets_met")
            row["summary_reason"] = js.get("reason")
        except Exception:
            row["summary_elapsed_seconds"] = None
            row["summary_total_samples"] = None
            row["summary_targets_met"] = None
            row["summary_reason"] = None
    else:
        row["summary_elapsed_seconds"] = None
        row["summary_total_samples"] = None
        row["summary_targets_met"] = None
        row["summary_reason"] = None

    eval_log = _find_eval_log(run_dir)
    if eval_log is None or (not eval_log.exists()):
        if include_partial:
            row["evaluate_log"] = ""
            row["evaluate_present"] = False
            return row
        return None

    row["evaluate_log"] = str(eval_log)
    row["evaluate_present"] = True
    row.update(_parse_eval(eval_log))
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description="Summarize near/far rescue impact per run.")
    ap.add_argument("--run-dir", action="append", default=[], help="Explicit run directory path.")
    ap.add_argument(
        "--run-glob",
        action="append",
        default=[],
        help="Glob for run directories (example: 'output/multichain_auto/s20l2_t040_*').",
    )
    ap.add_argument("--output-csv", required=True, help="Output CSV path.")
    ap.add_argument(
        "--include-partial",
        action="store_true",
        help="Include runs without evaluate log (metrics columns left empty).",
    )
    args = ap.parse_args()

    runs = _iter_run_dirs(args.run_dir, args.run_glob)
    if not runs:
        raise SystemExit("[ERROR] no run directories found.")

    rows: List[Dict[str, object]] = []
    for run_dir in runs:
        row = summarize_run(run_dir, include_partial=args.include_partial)
        if row is not None:
            rows.append(row)

    if not rows:
        raise SystemExit("[ERROR] no rows produced (check run dirs and evaluate logs).")

    field_order = [
        "run_dir",
        "run_name",
        "chains_seen",
        "rescue_level_mode",
        "micro_ext_mode",
        "budget_soft1_mode",
        "budget_soft2_mode",
        "budget_hard_mode",
        "budget_disabled_chains",
        "near_fail_total",
        "near_try_total",
        "near_ok_total",
        "near_unusable_total",
        "near_fail_fast_total",
        "far_fail_fast_total",
        "far_fail_total",
        "probe_success_total",
        "probe_attempt_total",
        "full_success_total",
        "full_attempt_total",
        "extended_success_total",
        "extended_attempt_total",
        "class_local_total",
        "class_mid_total",
        "class_global_total",
        "route_skip_total",
        "route_light_total",
        "route_anchor_total",
        "watchdog_hits_total",
        "watchdog_max_used_max",
        "watchdog_budget_last_max",
        "far_invest_cases_total",
        "far_invest_success_total",
        "far_invest_fail_total",
        "far_invest_fail_fast_total",
        "far_units_flowzr_total",
        "far_units_final_total",
        "far_units_success_flowzr_total",
        "far_units_success_final_total",
        "far_units_fail_flowzr_total",
        "far_units_fail_final_total",
        "far_spent_success_total",
        "far_spent_fail_total",
        "summary_elapsed_seconds",
        "summary_total_samples",
        "summary_targets_met",
        "summary_reason",
        "evaluate_log",
        "evaluate_present",
        "rhat_v_re",
        "rhat_v_im",
        "rhat_z_re",
        "rhat_z_im",
        "rhat_max",
        "pass_rhat_101",
        "virial_re",
        "virial_im",
        "z_re",
        "z_im",
        "err_v_re",
        "err_v_im",
        "err_z_re",
        "err_z_im",
        "pass1_virial_re",
        "pass1_virial_im",
        "pass1_z_re",
        "pass1_z_im",
        "pass2_virial_re",
        "pass2_virial_im",
        "pass2_z_re",
        "pass2_z_im",
        "pass1_components",
        "pass2_components",
        "pass1_all4",
        "pass2_all4",
        "eval_sha256",
    ]

    out_path = Path(args.output_csv)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=field_order, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            writer.writerow(r)

    print(f"[DONE] wrote {len(rows)} rows: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
