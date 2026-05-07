#!/usr/bin/env python3
import csv
import json
import math
import os
import re
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output"

NUM_RE = re.compile(r"[-+]?\d*\.\d+(?:[Ee][-+]?\d+)?|[-+]?\d+(?:[Ee][-+]?\d+)?")


@dataclass
class ModeCfg:
    eval_root: Path
    run_root: Path
    run_pattern: str
    summary_csv: Optional[Path] = None
    log_root: Optional[Path] = None
    nohup_root: Optional[Path] = None


@dataclass
class TaskCfg:
    name: str
    samples: int
    pairs: int
    seed_start: int
    seed_step: int
    withfb: ModeCfg
    nofb: ModeCfg


def latest_scan_root() -> Path:
    cands = sorted(OUTPUT.glob("multichain_auto_t030_s10_s40_scan_*"))
    if not cands:
        raise FileNotFoundError("no output/multichain_auto_t030_s10_s40_scan_* found")
    return cands[-1]


def parse_pair_from_line(line: str) -> Tuple[float, float]:
    nums = NUM_RE.findall(line.split("=", 1)[-1])
    if len(nums) < 2:
        raise ValueError(f"cannot parse pair from: {line}")
    return float(nums[0]), float(nums[1])


def read_summary_map(path: Optional[Path]) -> Dict[int, Dict[str, str]]:
    out: Dict[int, Dict[str, str]] = {}
    if path is None or not path.exists():
        return out
    with path.open() as f:
        rd = csv.DictReader(f)
        for r in rd:
            out[int(r["idx"])] = r
    return out


def parse_eval_metrics(eval_path: Path) -> Dict[str, float]:
    if not eval_path.exists():
        raise FileNotFoundError(eval_path)
    keep: Dict[str, str] = {}
    with eval_path.open() as f:
        for line in f:
            line = line.strip()
            if line.startswith("[RESULT] <virial> (Re, Im)="):
                keep["virial"] = line
            elif line.startswith("[RESULT] <z> (Re, Im)="):
                keep["z"] = line
            elif line.startswith("[RESULT] error_robust_<virial> (Re, Im)="):
                keep["err_virial"] = line
            elif line.startswith("[RESULT] error_robust_<z> (Re, Im)="):
                keep["err_z"] = line
            elif line.startswith("[RESULT] split_rhat_virial (Re, Im)="):
                keep["rhat_virial"] = line
            elif line.startswith("[RESULT] split_rhat_z (Re, Im)="):
                keep["rhat_z"] = line

    vr, vi = parse_pair_from_line(keep["virial"])
    zr, zi = parse_pair_from_line(keep["z"])
    evr, evi = parse_pair_from_line(keep["err_virial"])
    ezr, ezi = parse_pair_from_line(keep["err_z"])
    rvr, rvi = parse_pair_from_line(keep["rhat_virial"])
    rzr, rzi = parse_pair_from_line(keep["rhat_z"])

    return {
        "virial_re": vr,
        "virial_im": vi,
        "z_re": zr,
        "z_im": zi,
        "err_virial_re": evr,
        "err_virial_im": evi,
        "err_z_re": ezr,
        "err_z_im": ezi,
        "rhat_virial_re": rvr,
        "rhat_virial_im": rvi,
        "rhat_z_re": rzr,
        "rhat_z_im": rzi,
    }


def parse_chain_log_metrics(run_dir: Path, samples: int) -> Dict[str, float]:
    log_paths = sorted(run_dir.glob("chain_*/logs/generate_markov_chain.log"))
    if not log_paths:
        raise FileNotFoundError(f"no chain logs under {run_dir}")

    near_fail = 0
    near_unusable = 0
    far_fail = 0
    acceptance_vals: List[float] = []
    solver_attempts_sum = 0
    solver_quasi_sum = 0
    runtimes: List[float] = []

    for p in log_paths:
        last_near = None
        last_acc = None
        last_solver = None
        last_prog = None
        last_prog_any = None

        with p.open() as f:
            for line in f:
                line = line.rstrip("\n")
                if "near_fail=" in line:
                    last_near = line
                if "[SUMMARY] acceptance=" in line:
                    last_acc = line
                if "[SUMMARY] solver attempts=" in line:
                    last_solver = line
                if "[PROGRESS]" in line and "elapsed=" in line:
                    last_prog_any = line
                    if f"[PROGRESS] {samples}/{samples}" in line:
                        last_prog = line

        if last_near:
            tok = {t.split("=", 1)[0]: t.split("=", 1)[1] for t in last_near.split() if "=" in t}
            near_fail += int(tok.get("near_fail", "0"))
            near_unusable += int(tok.get("near_unusable", "0"))
            far_fail += int(tok.get("far_fail", "0"))

        if last_acc:
            m = re.search(r"acceptance=\s*([0-9.]+)", last_acc)
            if m:
                acceptance_vals.append(float(m.group(1)))

        if last_solver:
            ma = re.search(r"attempts=(\d+)", last_solver)
            mq = re.search(r"quasi=(\d+)", last_solver)
            if ma:
                solver_attempts_sum += int(ma.group(1))
            if mq:
                solver_quasi_sum += int(mq.group(1))

        use_prog = last_prog if last_prog is not None else last_prog_any
        if use_prog:
            m = re.search(r"elapsed=\s*([0-9.]+)s", use_prog)
            if m:
                runtimes.append(float(m.group(1)))

    runtimes_sorted = sorted(runtimes)
    n = len(runtimes_sorted)
    p95_idx = max(0, math.ceil(0.95 * n) - 1)

    return {
        "near_fail": near_fail,
        "near_unusable": near_unusable,
        "far_fail": far_fail,
        "acceptance_mean": (sum(acceptance_vals) / len(acceptance_vals)) if acceptance_vals else float("nan"),
        "solver_attempts_sum": solver_attempts_sum,
        "solver_quasi_sum": solver_quasi_sum,
        "solver_quasi_rate": (solver_quasi_sum / solver_attempts_sum) if solver_attempts_sum > 0 else 0.0,
        "chain_mean_s": (sum(runtimes_sorted) / n) if n else float("nan"),
        "chain_p95_s": runtimes_sorted[p95_idx] if n else float("nan"),
        "chain_max_s": runtimes_sorted[-1] if n else float("nan"),
    }


def pass_flags(row: Dict[str, float]) -> Dict[str, int]:
    vr = abs(row["virial_re"])
    vi = abs(row["virial_im"])
    zr = abs(row["z_re"])
    zi = abs(row["z_im"] + 1.0)

    p1_vr = int(vr <= row["err_virial_re"])
    p1_vi = int(vi <= row["err_virial_im"])
    p1_zr = int(zr <= row["err_z_re"])
    p1_zi = int(zi <= row["err_z_im"])
    p2_vr = int(vr <= 2.0 * row["err_virial_re"])
    p2_vi = int(vi <= 2.0 * row["err_virial_im"])
    p2_zr = int(zr <= 2.0 * row["err_z_re"])
    p2_zi = int(zi <= 2.0 * row["err_z_im"])

    return {
        "pass1_vir_re": p1_vr,
        "pass1_vir_im": p1_vi,
        "pass1_z_re": p1_zr,
        "pass1_z_im": p1_zi,
        "pass1_all": p1_vr * p1_vi * p1_zr * p1_zi,
        "pass2_vir_re": p2_vr,
        "pass2_vir_im": p2_vi,
        "pass2_z_re": p2_zr,
        "pass2_z_im": p2_zi,
        "pass2_all": p2_vr * p2_vi * p2_zr * p2_zi,
    }


def wilson(k: int, n: int, z: float = 1.95996398454005) -> Tuple[float, float]:
    if n <= 0:
        return (float("nan"), float("nan"))
    p = k / n
    z2 = z * z
    den = 1.0 + z2 / n
    cen = (p + z2 / (2.0 * n)) / den
    h = z * math.sqrt((p * (1.0 - p) + z2 / (4.0 * n)) / n) / den
    lo = max(0.0, cen - h)
    hi = min(1.0, cen + h)
    return lo, hi


def as_num(v) -> float:
    try:
        return float(v)
    except Exception:
        return float("nan")


def copytree_hardlink_or_copy(src: Path, dst: Path) -> str:
    if dst.exists():
        return "exists"
    try:
        shutil.copytree(src, dst, copy_function=os.link)
        return "hardlink"
    except Exception:
        shutil.copytree(src, dst)
        return "copy"


def build_one_task(cfg: TaskCfg, out_dir: Path) -> List[Dict[str, str]]:
    tdir = out_dir / cfg.name
    analysis_dir = tdir / "analysis"
    logs_dir = tdir / "logs"
    analysis_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    with_summary = read_summary_map(cfg.withfb.summary_csv)
    nofb_summary = read_summary_map(cfg.nofb.summary_csv)

    rows: List[Dict[str, object]] = []
    raw_map_rows: List[Dict[str, str]] = []

    for i in range(1, cfg.pairs + 1):
        seed = cfg.seed_start + (i - 1) * cfg.seed_step
        for mode, mcfg, smap in (("withfb", cfg.withfb, with_summary), ("nofb", cfg.nofb, nofb_summary)):
            run_name = mcfg.run_pattern.format(i=i, p2=f"{i:02d}")
            run_dir = mcfg.run_root / run_name
            eval_path = mcfg.eval_root / f"{run_name}.evaluate.log"

            if i in smap:
                driver_elapsed = as_num(smap[i].get("elapsed_s", float("nan")))
            else:
                summary_json = run_dir / "summary.json"
                if summary_json.exists():
                    driver_elapsed = as_num(json.loads(summary_json.read_text()).get("elapsed_seconds", float("nan")))
                else:
                    driver_elapsed = float("nan")

            em = parse_eval_metrics(eval_path)
            cm = parse_chain_log_metrics(run_dir, cfg.samples)
            pf = pass_flags(em)

            row = {
                "mode": mode,
                "pair_idx": i,
                "seed": seed,
                "run_name": run_name,
                "driver_elapsed_s": driver_elapsed,
                **cm,
                **em,
                **pf,
            }
            rows.append(row)

            target_run_dir = out_dir.parent / "raw_runs" / cfg.name / mode / run_name
            target_run_dir.parent.mkdir(parents=True, exist_ok=True)
            copy_mode = copytree_hardlink_or_copy(run_dir, target_run_dir)
            raw_map_rows.append(
                {
                    "t": cfg.name,
                    "mode": mode,
                    "pair_idx": f"{i:02d}",
                    "run_name": run_name,
                    "source_dir": str(run_dir.relative_to(ROOT)),
                    "target_dir": str(target_run_dir.relative_to(ROOT)),
                    "copy_mode": copy_mode,
                }
            )

    seed_cols = [
        "mode", "pair_idx", "seed", "run_name", "driver_elapsed_s",
        "chain_mean_s", "chain_p95_s", "chain_max_s",
        "rhat_z_re", "rhat_z_im", "rhat_virial_re", "rhat_virial_im",
        "virial_re", "virial_im", "z_re", "z_im",
        "err_virial_re", "err_virial_im", "err_z_re", "err_z_im",
        "near_fail", "near_unusable", "far_fail",
        "acceptance_mean", "solver_attempts_sum", "solver_quasi_sum", "solver_quasi_rate",
        "pass1_vir_re", "pass1_vir_im", "pass1_z_re", "pass1_z_im", "pass1_all",
        "pass2_vir_re", "pass2_vir_im", "pass2_z_re", "pass2_z_im", "pass2_all",
    ]
    seed_csv = analysis_dir / "seed_metrics.csv"
    with seed_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=seed_cols)
        w.writeheader()
        for r in rows:
            w.writerow(r)

    compare_cols = [
        "mode", "n_runs", "driver_elapsed_mean_s", "chain_elapsed_mean_s",
        "rhat_z_re_mean", "rhat_z_re_max", "near_fail_sum", "near_unusable_sum", "far_fail_sum",
        "acceptance_mean", "solver_attempts_sum", "solver_quasi_sum", "solver_quasi_rate",
    ]
    compare_csv = analysis_dir / "compare10.csv"
    with compare_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=compare_cols)
        w.writeheader()
        for mode in ("withfb", "nofb"):
            rr = [r for r in rows if r["mode"] == mode]
            n = len(rr)
            att = sum(int(r["solver_attempts_sum"]) for r in rr)
            qua = sum(int(r["solver_quasi_sum"]) for r in rr)
            w.writerow(
                {
                    "mode": mode,
                    "n_runs": n,
                    "driver_elapsed_mean_s": sum(float(r["driver_elapsed_s"]) for r in rr) / n,
                    "chain_elapsed_mean_s": sum(float(r["chain_mean_s"]) for r in rr) / n,
                    "rhat_z_re_mean": sum(float(r["rhat_z_re"]) for r in rr) / n,
                    "rhat_z_re_max": max(float(r["rhat_z_re"]) for r in rr),
                    "near_fail_sum": sum(int(r["near_fail"]) for r in rr),
                    "near_unusable_sum": sum(int(r["near_unusable"]) for r in rr),
                    "far_fail_sum": sum(int(r["far_fail"]) for r in rr),
                    "acceptance_mean": sum(float(r["acceptance_mean"]) for r in rr) / n,
                    "solver_attempts_sum": att,
                    "solver_quasi_sum": qua,
                    "solver_quasi_rate": (qua / att) if att > 0 else 0.0,
                }
            )

    coverage_cols = [
        "mode", "component", "pass_1sigma", "pass_2sigma", "n_runs",
        "rate_1sigma", "rate_2sigma", "ci95_1sigma_lo", "ci95_1sigma_hi", "ci95_2sigma_lo", "ci95_2sigma_hi",
    ]
    coverage_csv = analysis_dir / "coverage.csv"
    comp_map = {
        "vir_re": ("pass1_vir_re", "pass2_vir_re"),
        "vir_im": ("pass1_vir_im", "pass2_vir_im"),
        "z_re": ("pass1_z_re", "pass2_z_re"),
        "z_im": ("pass1_z_im", "pass2_z_im"),
        "all_components": ("pass1_all", "pass2_all"),
    }
    with coverage_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=coverage_cols)
        w.writeheader()
        for mode in ("withfb", "nofb"):
            rr = [r for r in rows if r["mode"] == mode]
            n = len(rr)
            for comp, (c1, c2) in comp_map.items():
                k1 = sum(int(r[c1]) for r in rr)
                k2 = sum(int(r[c2]) for r in rr)
                lo1, hi1 = wilson(k1, n)
                lo2, hi2 = wilson(k2, n)
                w.writerow(
                    {
                        "mode": mode,
                        "component": comp,
                        "pass_1sigma": k1,
                        "pass_2sigma": k2,
                        "n_runs": n,
                        "rate_1sigma": k1 / n,
                        "rate_2sigma": k2 / n,
                        "ci95_1sigma_lo": lo1,
                        "ci95_1sigma_hi": hi1,
                        "ci95_2sigma_lo": lo2,
                        "ci95_2sigma_hi": hi2,
                    }
                )

    runtime_cols = [
        "pair_idx", "chains",
        "withfb_mean_s", "withfb_p95_s", "withfb_max_s",
        "nofb_mean_s", "nofb_p95_s", "nofb_max_s",
        "delta_mean_s_withfb_minus_nofb",
    ]
    runtime_csv = analysis_dir / "runtime_seed_compare.csv"
    with runtime_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=runtime_cols)
        w.writeheader()
        for i in range(1, cfg.pairs + 1):
            rw = next(r for r in rows if r["mode"] == "withfb" and r["pair_idx"] == i)
            rn = next(r for r in rows if r["mode"] == "nofb" and r["pair_idx"] == i)
            w.writerow(
                {
                    "pair_idx": i,
                    "chains": 24,
                    "withfb_mean_s": rw["chain_mean_s"],
                    "withfb_p95_s": rw["chain_p95_s"],
                    "withfb_max_s": rw["chain_max_s"],
                    "nofb_mean_s": rn["chain_mean_s"],
                    "nofb_p95_s": rn["chain_p95_s"],
                    "nofb_max_s": rn["chain_max_s"],
                    "delta_mean_s_withfb_minus_nofb": float(rw["chain_mean_s"]) - float(rn["chain_mean_s"]),
                }
            )

    manifest = {
        "task": cfg.name,
        "generated_utc": datetime.utcnow().isoformat() + "Z",
        "pairs": cfg.pairs,
        "seed_start": cfg.seed_start,
        "seed_step": cfg.seed_step,
        "samples": cfg.samples,
        "sources": {
            "withfb_eval_root": str(cfg.withfb.eval_root),
            "withfb_summary_csv": str(cfg.withfb.summary_csv) if cfg.withfb.summary_csv else None,
            "withfb_log_root": str(cfg.withfb.log_root or cfg.withfb.eval_root),
            "withfb_nohup_root": str(cfg.withfb.nohup_root or cfg.withfb.log_root or cfg.withfb.eval_root),
            "withfb_run_root": str(cfg.withfb.run_root),
            "nofb_eval_root": str(cfg.nofb.eval_root),
            "nofb_summary_csv": str(cfg.nofb.summary_csv) if cfg.nofb.summary_csv else None,
            "nofb_log_root": str(cfg.nofb.log_root or cfg.nofb.eval_root),
            "nofb_nohup_root": str(cfg.nofb.nohup_root or cfg.nofb.log_root or cfg.nofb.eval_root),
            "nofb_run_root": str(cfg.nofb.run_root),
        },
    }
    (analysis_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    for mode, mcfg in (("withfb", cfg.withfb), ("nofb", cfg.nofb)):
        mdir = logs_dir / mode
        mdir.mkdir(parents=True, exist_ok=True)
        log_root = mcfg.log_root if mcfg.log_root else mcfg.eval_root

        for fn in ("driver.progress.log", "driver.nohup.log", "summary.csv"):
            src = log_root / fn
            if src.exists():
                shutil.copy2(src, mdir / fn)

        eval_dir = mdir / "evaluate"
        eval_dir.mkdir(exist_ok=True)
        for i in range(1, cfg.pairs + 1):
            run_name = mcfg.run_pattern.format(i=i, p2=f"{i:02d}")
            src = mcfg.eval_root / f"{run_name}.evaluate.log"
            if src.exists():
                shutil.copy2(src, eval_dir / src.name)

        nh_root = mcfg.nohup_root if mcfg.nohup_root else log_root
        nohup_dir = mdir / "nohup"
        nohup_dir.mkdir(exist_ok=True)
        for i in range(1, cfg.pairs + 1):
            run_name = mcfg.run_pattern.format(i=i, p2=f"{i:02d}")
            src = nh_root / f"{run_name}.nohup.log"
            if src.exists():
                shutil.copy2(src, nohup_dir / src.name)

    return raw_map_rows


def main() -> None:
    scan_root = latest_scan_root()
    old_fullbundle = OUTPUT / "multichain_fullbundle_t025_t030_t035_0327_181908"
    if not old_fullbundle.exists():
        raise FileNotFoundError(old_fullbundle)

    ts = datetime.now().strftime("%m%d_%H%M%S")
    bundle = OUTPUT / f"multichain_fullbundle_t030_s10_s20_s40_{ts}"
    bundle.mkdir(parents=True, exist_ok=True)

    analysis_root = bundle / "analysis_logs_bundle"
    analysis_root.mkdir(parents=True, exist_ok=True)
    raw_root = bundle / "raw_runs"
    raw_root.mkdir(parents=True, exist_ok=True)
    meta_root = bundle / "meta"
    meta_root.mkdir(parents=True, exist_ok=True)

    tasks = [
        TaskCfg(
            name="s10l2",
            samples=50000,
            pairs=10,
            seed_start=410000001,
            seed_step=1000003,
            withfb=ModeCfg(
                eval_root=scan_root / "s10l2" / "withfb",
                run_root=OUTPUT / "multichain_auto",
                run_pattern="s10l2_t030_s1_50k_0328_013408_p{p2}_50000_withfb",
                summary_csv=scan_root / "s10l2" / "withfb" / "summary.csv",
            ),
            nofb=ModeCfg(
                eval_root=scan_root / "s10l2" / "nofb",
                run_root=OUTPUT / "multichain_auto",
                run_pattern="s10l2_t030_s1_50k_0328_013408_p{p2}_50000_nofb",
                summary_csv=scan_root / "s10l2" / "nofb" / "summary.csv",
            ),
        ),
        TaskCfg(
            name="s20l2",
            samples=50000,
            pairs=10,
            seed_start=410000001,
            seed_step=1000003,
            withfb=ModeCfg(
                eval_root=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "withfb" / "evaluate",
                log_root=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "withfb",
                nohup_root=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "withfb" / "nohup",
                run_root=old_fullbundle / "raw_runs" / "t030" / "withfb",
                run_pattern="s20l2_t030_s1_50k_0327_120754_p{p2}_50000_withfb",
                summary_csv=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "withfb" / "summary.csv",
            ),
            nofb=ModeCfg(
                eval_root=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "nofb" / "evaluate",
                log_root=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "nofb",
                nohup_root=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "nofb" / "nohup",
                run_root=old_fullbundle / "raw_runs" / "t030" / "nofb",
                run_pattern="s20l2_t030_s1_50k_0327_120754_p{p2}_50000_nofb",
                summary_csv=old_fullbundle / "analysis_logs_bundle" / "t030" / "logs" / "nofb" / "summary.csv",
            ),
        ),
        TaskCfg(
            name="s40l2",
            samples=50000,
            pairs=10,
            seed_start=410000001,
            seed_step=1000003,
            withfb=ModeCfg(
                eval_root=scan_root / "s40l2" / "withfb",
                run_root=OUTPUT / "multichain_auto",
                run_pattern="s40l2_t030_s1_50k_0328_042112_p{p2}_50000_withfb",
                summary_csv=scan_root / "s40l2" / "withfb" / "summary.csv",
            ),
            nofb=ModeCfg(
                eval_root=scan_root / "s40l2" / "nofb",
                run_root=OUTPUT / "multichain_auto",
                run_pattern="s40l2_t030_s1_50k_0328_042112_p{p2}_50000_nofb",
                summary_csv=scan_root / "s40l2" / "nofb" / "summary.csv",
            ),
        ),
    ]

    all_map_rows: List[Dict[str, str]] = []
    for t in tasks:
        all_map_rows.extend(build_one_task(t, analysis_root))

    map_csv = meta_root / "raw_run_map.csv"
    with map_csv.open("w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["t", "mode", "pair_idx", "run_name", "source_dir", "target_dir", "copy_mode"],
        )
        w.writeheader()
        for r in all_map_rows:
            w.writerow(r)

    (analysis_root / "README.txt").write_text(
        "Bundle for t030 with s10l2/s20l2/s40l2 unified format.\n"
        "Each task folder contains:\n"
        "  analysis/seed_metrics.csv\n"
        "  analysis/compare10.csv\n"
        "  analysis/coverage.csv\n"
        "  analysis/runtime_seed_compare.csv\n"
        "  analysis/manifest.json\n"
        "  logs/{withfb,nofb}/{driver logs,summary,evaluate,nohup}\n"
    )

    guide_dir = bundle / "guideline_logs_preserved"
    guide_files = guide_dir / "files"
    guide_files.mkdir(parents=True, exist_ok=True)
    preserved_src = old_fullbundle / "guideline_logs_preserved" / "files" / "multichain_bundle_t025_t030_t035_0327_180421__README.txt"
    preserved_dst = guide_files / "multichain_bundle_t025_t030_t035_0327_180421__README.txt"
    if preserved_src.exists():
        shutil.copy2(preserved_src, preserved_dst)
    (guide_dir / "README.txt").write_text(
        "Only one memory/guideline log is retained by request:\n"
        "- files/multichain_bundle_t025_t030_t035_0327_180421__README.txt\n"
    )
    with (guide_dir / "preserved_index.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["src_rel", "dst_rel"])
        w.writerow(
            [
                "multichain_bundle_t025_t030_t035_0327_180421/README.txt",
                "guideline_logs_preserved/files/multichain_bundle_t025_t030_t035_0327_180421__README.txt",
            ]
        )

    (bundle / "README.txt").write_text(
        "Full bundle for t030 s10l2/s20l2/s40l2 comparison.\n\n"
        "Contains:\n"
        "- analysis_logs_bundle/: normalized analysis + logs bundle\n"
        "- raw_runs/: raw run directories grouped by setup and mode\n"
        "- meta/raw_run_map.csv: source-target mapping and copy mode\n\n"
        "Note:\n"
        "- raw_runs are packed with hardlink when possible to reduce extra disk usage.\n"
    )

    print(bundle)


if __name__ == "__main__":
    main()
