#!/usr/bin/env bash
set -uo pipefail

# Fixed-solver N-scan runner for t=0.35 with fallback.
# Goal:
#   - keep solver/rescue configuration fixed
#   - run same seeds across N in {50k,100k,200k} (configurable)
#   - report Dmax and z_im bias drift vs N
#
# Output:
#   ROOT/summary_runs.csv   (per run)
#   ROOT/summary_by_N.csv   (aggregated by N)
#   ROOT/summary_drift.csv  (pairwise N drift using common seeds)

ROOT="${ROOT:-output/multichain_auto_t035_s1_nscan_$(date +%m%d_%H%M%S)}"
RUN_PREFIX="${RUN_PREFIX:-s20l2_t035_s1_nscan}"
N_LIST="${N_LIST:-50000 100000 200000}"
SEEDS="${SEEDS:-10}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-1000003}"
CHAINS="${CHAINS:-24}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters_t035.dat}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-172800}"
FORCE="${FORCE:-0}"

mkdir -p "${ROOT}"

progress_log="${ROOT}/driver.progress.log"
summary_runs="${ROOT}/summary_runs.csv"
summary_by_n="${ROOT}/summary_by_N.csv"
summary_drift="${ROOT}/summary_drift.csv"

echo "N,idx,seed,run_name,status,elapsed_s,rhat_z_re,rhat_z_im,rhat_virial_re,rhat_virial_im,virial_re,virial_im,z_re,z_im,err_virial_re,err_virial_im,err_z_re,err_z_im,dev_sigma_vir_re,dev_sigma_vir_im,dev_sigma_z_re,dev_sigma_z_im,Dmax,z_im_bias,z_im_bias_over_err,near_fail,near_unusable,far_fail" > "${summary_runs}"

echo "[INIT] ROOT=${ROOT}" | tee -a "${progress_log}"
echo "[INIT] N_LIST=${N_LIST} SEEDS=${SEEDS} CHAINS=${CHAINS}" | tee -a "${progress_log}"

parse_eval_metrics() {
  local eval_log="$1"
  python3 - "$eval_log" <<'PY'
import re
import sys
from pathlib import Path

eval_log = Path(sys.argv[1])
text = eval_log.read_text(encoding="utf-8", errors="replace")

def grab2(pat):
    m = re.search(pat, text)
    if not m:
        return None
    return float(m.group(1)), float(m.group(2))

vir = grab2(r"\[RESULT\]\s+<virial>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
z = grab2(r"\[RESULT\]\s+<z>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
err_vir = grab2(r"\[RESULT\]\s+error_robust_<virial>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
err_z = grab2(r"\[RESULT\]\s+error_robust_<z>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
rhat_vir = grab2(r"\[RESULT\]\s+split_rhat_virial\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
rhat_z = grab2(r"\[RESULT\]\s+split_rhat_z\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")

if None in (vir, z, err_vir, err_z, rhat_vir, rhat_z):
    print(",".join(["NA"] * 19))
    raise SystemExit(0)

vir_re, vir_im = vir
z_re, z_im = z
err_v_re, err_v_im = err_vir
err_z_re, err_z_im = err_z
rhat_v_re, rhat_v_im = rhat_vir
rhat_z_re, rhat_z_im = rhat_z

# References: virial=(0,0), z=(0,-1)
dev_v_re = abs(vir_re) / err_v_re if err_v_re > 0 else float("nan")
dev_v_im = abs(vir_im) / err_v_im if err_v_im > 0 else float("nan")
dev_z_re = abs(z_re) / err_z_re if err_z_re > 0 else float("nan")
z_im_bias = z_im + 1.0
dev_z_im = abs(z_im_bias) / err_z_im if err_z_im > 0 else float("nan")
dmax = max(dev_v_re, dev_v_im, dev_z_re, dev_z_im)

vals = [
    rhat_z_re, rhat_z_im, rhat_v_re, rhat_v_im,
    vir_re, vir_im, z_re, z_im,
    err_v_re, err_v_im, err_z_re, err_z_im,
    dev_v_re, dev_v_im, dev_z_re, dev_z_im, dmax,
    z_im_bias, (z_im_bias / err_z_im if err_z_im > 0 else float("nan")),
]
print(",".join(f"{v:.10g}" for v in vals))
PY
}

parse_fail_counters() {
  local run_dir="$1"
  if ! ls "${run_dir}"/chain_*/logs/generate_markov_chain.log >/dev/null 2>&1; then
    echo "NA,NA,NA"
    return 0
  fi

  awk '
    /near_fail=/ {
      nf=nu=ff=0;
      for(i=1;i<=NF;i++){
        if($i ~ /^near_fail=/){split($i,a,"="); nf=a[2]}
        else if($i ~ /^near_unusable=/){split($i,a,"="); nu=a[2]}
        else if($i ~ /^far_fail=/){split($i,a,"="); ff=a[2]}
      }
      last_nf=nf; last_nu=nu; last_ff=ff;
    }
    ENDFILE {
      sum_nf += last_nf+0; sum_nu += last_nu+0; sum_ff += last_ff+0;
      last_nf=last_nu=last_ff=0
    }
    END {printf "%s,%s,%s\n", sum_nf, sum_nu, sum_ff}
  ' "${run_dir}"/chain_*/logs/generate_markov_chain.log
}

for N in ${N_LIST}; do
  echo "[SCAN] N=${N}" | tee -a "${progress_log}"
  for i in $(seq 1 "${SEEDS}"); do
    seed=$((SEED_START + (i - 1) * SEED_STEP))
    run_name=$(printf "%s_N%s_p%02d_withfb" "${RUN_PREFIX}" "${N}" "${i}")
    run_dir="output/multichain_auto/${run_name}"
    run_log="${ROOT}/${run_name}.nohup.log"
    eval_log="${ROOT}/${run_name}.evaluate.log"

    echo "[RUN] ${run_name} seed=${seed}" | tee -a "${progress_log}"

    run_status="done"
    if [[ -d "${run_dir}" && "${FORCE}" != "1" ]]; then
      echo "[SKIP] existing run_dir=${run_dir}" | tee -a "${progress_log}"
    else
      force_args=()
      if [[ "${FORCE}" == "1" ]]; then
        force_args+=(--force)
      fi

      if ! env \
          OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
          QN_ENABLE_LEGACY_RESCUE=0 \
          QN_PROGRESSIVE_RESCUE_STAGE=1 \
          QN_RESCUE_LEVEL=0 \
          QN_FAR_RESCUE_REBUILD=off \
          QN_FAR_LIGHT_MICRO_EXT=off \
          QN_FAR_ANCHOR_FASTTRACK=off \
          QN_FAR_ANCHOR_MIX_RESTART=off \
          QN_NEAR_SEEDED_NEWTON=off \
          python3 scripts/run_multichain_auto.py \
            "${force_args[@]}" \
            --chains "${CHAINS}" \
            --run-name "${run_name}" \
            --seed-base "${seed}" \
            --base-parameters "${BASE_PARAMETERS}" \
            --chain-length "${N}" \
            --target-samples-per-chain "${N}" \
            --quasi-fallback on \
            --check-interval "${CHECK_INTERVAL}" \
            --max-wall-seconds "${MAX_WALL_SECONDS}" \
            > "${run_log}" 2>&1; then
        run_status="run_failed"
      fi
    fi

    eval_status="NA"
    if [[ "${run_status}" == "done" ]]; then
      if EVAL_MULTICHAIN_RUN_DIR="${run_dir}" EVAL_MULTICHAIN_DIAG_WINDOW="${N}" \
        bin/evaluate_expectations > "${eval_log}" 2>&1; then
        eval_status="eval_done"
      else
        eval_status="eval_failed"
      fi
    fi

    status="${run_status}"
    if [[ "${run_status}" == "done" && "${eval_status}" == "eval_failed" ]]; then
      status="eval_failed"
    fi

    elapsed="NA"
    if [[ -f "${run_dir}/summary.json" ]]; then
      elapsed=$(jq -r '.elapsed_seconds // "NA"' "${run_dir}/summary.json" 2>/dev/null || echo "NA")
    fi

    eval_vals="NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA"
    if [[ -f "${eval_log}" ]]; then
      eval_vals="$(parse_eval_metrics "${eval_log}")"
    fi

    fail_vals="$(parse_fail_counters "${run_dir}")"

    printf "%s,%d,%d,%s,%s,%s,%s,%s\n" \
      "${N}" "${i}" "${seed}" "${run_name}" "${status}" "${elapsed}" \
      "${eval_vals}" "${fail_vals}" >> "${summary_runs}"

    echo "[DONE] ${run_name} status=${status}" | tee -a "${progress_log}"
  done
done

python3 - "${summary_runs}" "${summary_by_n}" "${summary_drift}" <<'PY'
import csv
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

summary_runs = Path(sys.argv[1])
summary_by_n = Path(sys.argv[2])
summary_drift = Path(sys.argv[3])

rows = []
with summary_runs.open() as f:
    r = csv.DictReader(f)
    for row in r:
        rows.append(row)

def f(x):
    try:
        return float(x)
    except Exception:
        return math.nan

ok = [r for r in rows if r["status"] == "done"]

by_n = defaultdict(list)
for r in ok:
    by_n[int(r["N"])].append(r)

fields_n = [
    "N", "n_runs",
    "Dmax_mean", "Dmax_std",
    "z_im_bias_mean", "z_im_bias_std",
    "z_im_bias_over_err_mean", "z_im_bias_over_err_std",
    "rhat_max_mean", "rhat_max_p95",
    "elapsed_s_mean", "elapsed_s_p95",
]
with summary_by_n.open("w", newline="") as fcsv:
    w = csv.DictWriter(fcsv, fieldnames=fields_n)
    w.writeheader()
    for N in sorted(by_n):
        rs = by_n[N]
        dmax = [f(r["Dmax"]) for r in rs]
        zb = [f(r["z_im_bias"]) for r in rs]
        zbse = [f(r["z_im_bias_over_err"]) for r in rs]
        rhat_max = [max(f(r["rhat_z_re"]), f(r["rhat_z_im"]), f(r["rhat_virial_re"]), f(r["rhat_virial_im"])) for r in rs]
        elapsed = [f(r["elapsed_s"]) for r in rs]

        def mean_std(xs):
            ys = [x for x in xs if not math.isnan(x)]
            if not ys:
                return math.nan, math.nan
            if len(ys) == 1:
                return ys[0], 0.0
            return statistics.mean(ys), statistics.stdev(ys)

        def p95(xs):
            ys = sorted(x for x in xs if not math.isnan(x))
            if not ys:
                return math.nan
            i = int(math.ceil(0.95 * len(ys))) - 1
            i = max(0, min(i, len(ys) - 1))
            return ys[i]

        dmax_m, dmax_s = mean_std(dmax)
        zb_m, zb_s = mean_std(zb)
        zbse_m, zbse_s = mean_std(zbse)
        rh_m, _ = mean_std(rhat_max)
        el_m, _ = mean_std(elapsed)

        w.writerow({
            "N": N,
            "n_runs": len(rs),
            "Dmax_mean": f"{dmax_m:.10g}",
            "Dmax_std": f"{dmax_s:.10g}",
            "z_im_bias_mean": f"{zb_m:.10g}",
            "z_im_bias_std": f"{zb_s:.10g}",
            "z_im_bias_over_err_mean": f"{zbse_m:.10g}",
            "z_im_bias_over_err_std": f"{zbse_s:.10g}",
            "rhat_max_mean": f"{rh_m:.10g}",
            "rhat_max_p95": f"{p95(rhat_max):.10g}",
            "elapsed_s_mean": f"{el_m:.10g}",
            "elapsed_s_p95": f"{p95(elapsed):.10g}",
        })

# pairwise drift by common seeds
seed_map = defaultdict(dict)  # seed -> N -> row
for r in ok:
    seed = int(r["seed"])
    N = int(r["N"])
    seed_map[seed][N] = r

n_values = sorted(by_n.keys())
drift_fields = [
    "N_low", "N_high", "n_common_seed",
    "mean_delta_Dmax", "mean_delta_abs_z_im_bias",
    "mean_delta_abs_z_im_bias_over_err",
]
with summary_drift.open("w", newline="") as fcsv:
    w = csv.DictWriter(fcsv, fieldnames=drift_fields)
    w.writeheader()
    for i in range(len(n_values)):
        for j in range(i + 1, len(n_values)):
            n0, n1 = n_values[i], n_values[j]
            d_dmax = []
            d_abs_bias = []
            d_abs_bias_over_err = []
            for _, mp in seed_map.items():
                if n0 in mp and n1 in mp:
                    r0 = mp[n0]
                    r1 = mp[n1]
                    d_dmax.append(f(r1["Dmax"]) - f(r0["Dmax"]))
                    d_abs_bias.append(abs(f(r1["z_im_bias"])) - abs(f(r0["z_im_bias"])))
                    d_abs_bias_over_err.append(abs(f(r1["z_im_bias_over_err"])) - abs(f(r0["z_im_bias_over_err"])))
            if not d_dmax:
                continue
            w.writerow({
                "N_low": n0,
                "N_high": n1,
                "n_common_seed": len(d_dmax),
                "mean_delta_Dmax": f"{statistics.mean(d_dmax):.10g}",
                "mean_delta_abs_z_im_bias": f"{statistics.mean(d_abs_bias):.10g}",
                "mean_delta_abs_z_im_bias_over_err": f"{statistics.mean(d_abs_bias_over_err):.10g}",
            })
PY

echo "[ALL DONE] summary_runs=${summary_runs}" | tee -a "${progress_log}"
echo "[ALL DONE] summary_by_N=${summary_by_n}" | tee -a "${progress_log}"
echo "[ALL DONE] summary_drift=${summary_drift}" | tee -a "${progress_log}"
