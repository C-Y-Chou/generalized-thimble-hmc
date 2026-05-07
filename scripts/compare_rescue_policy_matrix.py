#!/usr/bin/env python3

import argparse
import csv
import math
import statistics
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Compare stage-3 rescue policy outputs against nofb/reference policies.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--base-dir", required=True, help="Policy matrix output directory, relative to repo root or absolute.")
    parser.add_argument("--no-fb-policy", default="no_fb_ref", help="Directory containing the no_fb reference rows.")
    parser.add_argument("--reference-policy", default="nonnear_off_p28", help="Fallback policy used as the fb reference.")
    parser.add_argument("--output-csv", required=True, help="Summary CSV path, relative to repo root or absolute.")
    parser.add_argument("--output-md", required=True, help="Summary markdown path, relative to repo root or absolute.")
    return parser.parse_args()


def resolve(root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return root / path


def read_rows(path):
    with path.open() as f:
        return list(csv.DictReader(f))


def to_float(row, key, default=0.0):
    try:
        text = row.get(key, "")
        if text == "":
            return default
        return float(text)
    except (TypeError, ValueError):
        return default


def mean(values):
    values = list(values)
    return sum(values) / len(values) if values else float("nan")


def stderr(values):
    values = list(values)
    if len(values) < 2:
        return float("nan")
    return statistics.stdev(values) / math.sqrt(len(values))


def coverage(values, threshold):
    values = [x for x in values if math.isfinite(x)]
    if not values:
        return float("nan")
    return sum(1 for x in values if abs(x) <= threshold) / len(values)


def load_policy(base_dir, policy, method):
    path = base_dir / policy / "per_seed_summary_table.csv"
    rows = read_rows(path)
    out = {}
    for row in rows:
        if row.get("method") == method:
            out[row["seed_id"]] = row
    if not out:
        raise RuntimeError("No {0} rows found in {1}".format(method, path))
    return out


def format_float(value, digits=6):
    if not math.isfinite(value):
        return "nan"
    return ("{0:." + str(digits) + "g}").format(value)


def status_for(summary):
    if summary["P95_re"] < 0.88:
        return "reject_re_coverage"
    if abs(summary["z_re_vs_ref"]) > 2.5:
        return "reject_ref_shift"
    if summary["runtime_ratio_vs_ref"] > 1.35 and summary["fail_reduction_vs_nofb_pct"] < summary["ref_fail_reduction_vs_nofb_pct"] + 5.0:
        return "reject_runtime"
    return "candidate"


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    base_dir = resolve(repo_root, args.base_dir)
    output_csv = resolve(repo_root, args.output_csv)
    output_md = resolve(repo_root, args.output_md)

    nofb = load_policy(base_dir, args.no_fb_policy, "no_fb")
    ref = load_policy(base_dir, args.reference_policy, "fb")
    policies = sorted(p.name for p in base_dir.iterdir() if p.is_dir() and p.name != args.no_fb_policy)

    ref_fail = sum(to_float(row, "unresolved_failure_count") for row in ref.values())
    nofb_for_ref = {seed: nofb[seed] for seed in ref if seed in nofb}
    nofb_ref_fail = sum(to_float(row, "unresolved_failure_count") for row in nofb_for_ref.values())
    ref_fail_red = (1.0 - ref_fail / nofb_ref_fail) * 100.0 if nofb_ref_fail else float("nan")
    ref_runtime = mean(to_float(row, "runtime_total") for row in ref.values())

    summaries = []
    for policy in policies:
        fb = load_policy(base_dir, policy, "fb")
        seeds = sorted(set(fb) & set(nofb))
        ref_seeds = sorted(set(fb) & set(ref))
        if not seeds:
            raise RuntimeError("No shared seeds between {0} and {1}".format(policy, args.no_fb_policy))

        d_re_nofb = [to_float(fb[s], "Ohat_re") - to_float(nofb[s], "Ohat_re") for s in seeds]
        d_im_nofb = [to_float(fb[s], "Ohat_im") - to_float(nofb[s], "Ohat_im") for s in seeds]
        d_re_ref = [to_float(fb[s], "Ohat_re") - to_float(ref[s], "Ohat_re") for s in ref_seeds]
        d_im_ref = [to_float(fb[s], "Ohat_im") - to_float(ref[s], "Ohat_im") for s in ref_seeds]
        se_re_nofb = stderr(d_re_nofb)
        se_im_nofb = stderr(d_im_nofb)
        se_re_ref = stderr(d_re_ref)
        se_im_ref = stderr(d_im_ref)

        fb_fail = sum(to_float(row, "unresolved_failure_count") for row in fb.values())
        nofb_fail = sum(to_float(nofb[s], "unresolved_failure_count") for s in seeds)
        fail_red = (1.0 - fb_fail / nofb_fail) * 100.0 if nofb_fail else float("nan")

        summary = {
            "policy": policy,
            "n": len(seeds),
            "fb_fail": fb_fail,
            "nofb_fail": nofb_fail,
            "fail_reduction_vs_nofb_pct": fail_red,
            "ref_fail_reduction_vs_nofb_pct": ref_fail_red,
            "P68_re": coverage((to_float(row, "Zp_re") for row in fb.values()), 1.0),
            "P95_re": coverage((to_float(row, "Zp_re") for row in fb.values()), 2.0),
            "P68_im": coverage((to_float(row, "Zp_im") for row in fb.values()), 1.0),
            "P95_im": coverage((to_float(row, "Zp_im") for row in fb.values()), 2.0),
            "mean_dRe_vs_nofb": mean(d_re_nofb),
            "se_dRe_vs_nofb": se_re_nofb,
            "z_re_vs_nofb": mean(d_re_nofb) / se_re_nofb if se_re_nofb else float("nan"),
            "mean_dIm_vs_nofb": mean(d_im_nofb),
            "se_dIm_vs_nofb": se_im_nofb,
            "z_im_vs_nofb": mean(d_im_nofb) / se_im_nofb if se_im_nofb else float("nan"),
            "mean_dRe_vs_ref": mean(d_re_ref),
            "se_dRe_vs_ref": se_re_ref,
            "z_re_vs_ref": mean(d_re_ref) / se_re_ref if se_re_ref else float("nan"),
            "mean_dIm_vs_ref": mean(d_im_ref),
            "se_dIm_vs_ref": se_im_ref,
            "z_im_vs_ref": mean(d_im_ref) / se_im_ref if se_im_ref else float("nan"),
            "mean_err_re": mean(to_float(row, "err_Ohat_re") for row in fb.values()),
            "mean_err_im": mean(to_float(row, "err_Ohat_im") for row in fb.values()),
            "mean_re": mean(to_float(row, "Ohat_re") for row in fb.values()),
            "se_mean_re": stderr(to_float(row, "Ohat_re") for row in fb.values()),
            "mean_im": mean(to_float(row, "Ohat_im") for row in fb.values()),
            "se_mean_im": stderr(to_float(row, "Ohat_im") for row in fb.values()),
            "mean_runtime_total": mean(to_float(row, "runtime_total") for row in fb.values()),
            "runtime_ratio_vs_ref": mean(to_float(row, "runtime_total") for row in fb.values()) / ref_runtime if ref_runtime else float("nan"),
            "probe_success": sum(to_float(row, "quasi_probe_success_count") for row in fb.values()),
            "near_success": sum(to_float(row, "near_rescue_success_count") for row in fb.values()),
            "nonnear_accept": sum(to_float(row, "accepted_local_nonnear_route_count") for row in fb.values()),
            "far_success": sum(to_float(row, "far_investment_success_count") for row in fb.values()),
            "far_fail": sum(to_float(row, "far_investment_fail_count") for row in fb.values()),
        }
        summary["z_mean_re_exact"] = (
            summary["mean_re"] / summary["se_mean_re"] if summary["se_mean_re"] else float("nan")
        )
        summary["z_mean_im_exact"] = (
            summary["mean_im"] / summary["se_mean_im"] if summary["se_mean_im"] else float("nan")
        )
        summary["status"] = status_for(summary)
        summaries.append(summary)

    columns = [
        "status",
        "policy",
        "n",
        "fb_fail",
        "nofb_fail",
        "fail_reduction_vs_nofb_pct",
        "ref_fail_reduction_vs_nofb_pct",
        "P68_re",
        "P95_re",
        "P68_im",
        "P95_im",
        "mean_dRe_vs_nofb",
        "se_dRe_vs_nofb",
        "z_re_vs_nofb",
        "mean_dIm_vs_nofb",
        "se_dIm_vs_nofb",
        "z_im_vs_nofb",
        "mean_dRe_vs_ref",
        "se_dRe_vs_ref",
        "z_re_vs_ref",
        "mean_dIm_vs_ref",
        "se_dIm_vs_ref",
        "z_im_vs_ref",
        "mean_err_re",
        "mean_err_im",
        "mean_re",
        "se_mean_re",
        "z_mean_re_exact",
        "mean_im",
        "se_mean_im",
        "z_mean_im_exact",
        "mean_runtime_total",
        "runtime_ratio_vs_ref",
        "probe_success",
        "near_success",
        "nonnear_accept",
        "far_success",
        "far_fail",
    ]
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in summaries:
            writer.writerow(row)

    ordered = sorted(
        summaries,
        key=lambda row: (
            row["status"] != "candidate",
            abs(row["z_re_vs_ref"]) if math.isfinite(row["z_re_vs_ref"]) else 999.0,
            -row["fail_reduction_vs_nofb_pct"],
        ),
    )
    with output_md.open("w") as f:
        f.write("# Stage 3.4 Rescue Promotion Summary\n\n")
        f.write("- nofb reference: `{0}`\n".format(args.no_fb_policy))
        f.write("- fb reference: `{0}`\n".format(args.reference_policy))
        f.write("- candidate rule: keep policies with acceptable Re P95, small shift vs reference, and no large runtime penalty.\n\n")
        f.write("| status | policy | n | fail red % | Re P68 | Re P95 | mean Re | z exact | dRe vs nofb | z | dRe vs ref | z | runtime/ref | nonnear accept |\n")
        f.write("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n")
        for row in ordered:
            f.write(
                "| {status} | {policy} | {n} | {fail:.2f} | {p68:.3f} | {p95:.3f} | {mean_re} | {z_exact:.2f} | {dre_n} | {z_n:.2f} | {dre_r} | {z_r:.2f} | {rt:.2f} | {nonnear:.0f} |\n".format(
                    status=row["status"],
                    policy=row["policy"],
                    n=row["n"],
                    fail=row["fail_reduction_vs_nofb_pct"],
                    p68=row["P68_re"],
                    p95=row["P95_re"],
                    mean_re=format_float(row["mean_re"], 5),
                    z_exact=row["z_mean_re_exact"],
                    dre_n=format_float(row["mean_dRe_vs_nofb"], 5),
                    z_n=row["z_re_vs_nofb"],
                    dre_r=format_float(row["mean_dRe_vs_ref"], 5),
                    z_r=row["z_re_vs_ref"],
                    rt=row["runtime_ratio_vs_ref"],
                    nonnear=row["nonnear_accept"],
                )
            )

    print("[DONE] wrote {0}".format(output_csv))
    print("[DONE] wrote {0}".format(output_md))


if __name__ == "__main__":
    main()
