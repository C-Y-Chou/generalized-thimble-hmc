#!/usr/bin/env bash
set -euo pipefail

# t=0.35 geometric iteration matrix (10k pilots).
#
# Goal:
# - iterate unsolvable cut-off policies (near/far fail-fast + step budget),
# - keep compute on solvable traces,
# - verify with post-session geometry (3x3 bands) + online/offline alignment.
#
# Usage example:
#   ROOT="output/multichain_auto_t035_geomiter_$(date +%m%d_%H%M%S)" \
#   bash scripts/run_t035_geom_iter_matrix.sh
#
# Optional env knobs:
#   ROOT, RUN_PREFIX, BASE_PARAMETERS, CHAINS, SAMPLES,
#   SEEDS, SEED_START, SEED_STEP, TARGET_FLOW_TIME,
#   GEOM_MAX_CASES, GEOM_N_MANIFOLD, CHECK_INTERVAL, MAX_WALL_SECONDS,
#   POST_OFFICIAL_N, POST_LIGHT_N,
#   OUTPUT_ROOT, POST_ROOT,
#   CASE_IDS (comma-separated, e.g. "c02_default,c03_far_tight")

STAMP="$(date +%m%d_%H%M%S)"
ROOT="${ROOT:-output/multichain_auto_t035_geomiter_${STAMP}}"
RUN_PREFIX="${RUN_PREFIX:-s20l2_t035_geomiter}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters_t035.dat}"
CHAINS="${CHAINS:-24}"
SAMPLES="${SAMPLES:-10000}"
SEEDS="${SEEDS:-3}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-104729}"
TARGET_FLOW_TIME="${TARGET_FLOW_TIME:-0.35}"
GEOM_MAX_CASES="${GEOM_MAX_CASES:-100}"
GEOM_N_MANIFOLD="${GEOM_N_MANIFOLD:-1201}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
POST_OFFICIAL_N="${POST_OFFICIAL_N:-0}"
POST_LIGHT_N="${POST_LIGHT_N:-600}"
OUTPUT_ROOT="${OUTPUT_ROOT:-output/multichain_auto}"
POST_ROOT="${POST_ROOT:-output/post_session_analysis}"
CASE_IDS="${CASE_IDS:-}"

mkdir -p "${ROOT}"
mkdir -p "${OUTPUT_ROOT}"
mkdir -p "${POST_ROOT}"

SUMMARY_CSV="${ROOT}/geom_iter_summary.csv"
echo "timestamp,run_name,case_id,seed,samples,target_flow_time,status,elapsed_s,rhat_z_re,rhat_z_im,rhat_virial_re,rhat_virial_im,rhat_max,max_abs_zscore,all2sigma,near_fail,near_try,near_ok,near_unusable,far_fail,near_fail_fast,far_fail_fast,start_downgraded_chains,total_chains,post_fail_samples,band_lt_min,band_in_band,band_gt_max,band_no_hit,stuck_re_pass,stuck_re_fail,side_same,side_opposite,side_touch_zero,side_no_hit,side_no_stuck,cross_zero_count,sidez0_same,sidez0_opposite,sidez0_touch_zero,sidez0_unknown,cross_zero_vs_z0_count,align_best_match,align_global_precision,align_gtmax_recall,rescue_level,micro_ext,near_ff,near_ff_limit,far_ff,far_ff_limit,far_ff_flowzr_limit,budget_hard,accepted_iter_budget,note" > "${SUMMARY_CSV}"

want_case() {
  local cid="$1"
  if [[ -z "${CASE_IDS}" ]]; then
    return 0
  fi
  [[ ",${CASE_IDS}," == *",${cid},"* ]]
}

subset_tag() {
  local n="$1"
  if [[ "${n}" -le 0 ]]; then
    echo "all"
  else
    echo "${n}"
  fi
}

parse_eval_metrics() {
  local eval_log="$1"
  python3 - "$eval_log" <<'PY'
import math
import re
import sys

path = sys.argv[1]
txt = open(path, "r", encoding="utf-8", errors="replace").read()

def grab2(pattern, default=(math.nan, math.nan)):
    m = re.search(pattern, txt)
    if not m:
        return default
    return float(m.group(1)), float(m.group(2))

vir_re, vir_im = grab2(r"\[RESULT\]\s+<virial>\s+\(Re, Im\)=\s+([-+0-9.Ee]+)\s+([-+0-9.Ee]+)")
z_re, z_im = grab2(r"\[RESULT\]\s+<z>\s+\(Re, Im\)=\s+([-+0-9.Ee]+)\s+([-+0-9.Ee]+)")
err_v_re, err_v_im = grab2(r"\[RESULT\]\s+error_robust_<virial>\s+\(Re, Im\)=\s+([-+0-9.Ee]+)\s+([-+0-9.Ee]+)")
err_z_re, err_z_im = grab2(r"\[RESULT\]\s+error_robust_<z>\s+\(Re, Im\)=\s+([-+0-9.Ee]+)\s+([-+0-9.Ee]+)")
rhat_v_re, rhat_v_im = grab2(r"\[RESULT\]\s+split_rhat_virial\s+\(Re, Im\)=\s+([-+0-9.Ee]+)\s+([-+0-9.Ee]+)")
rhat_z_re, rhat_z_im = grab2(r"\[RESULT\]\s+split_rhat_z\s+\(Re, Im\)=\s+([-+0-9.Ee]+)\s+([-+0-9.Ee]+)")

zscores = []
if err_v_re > 0:
    zscores.append(abs(vir_re) / err_v_re)
if err_v_im > 0:
    zscores.append(abs(vir_im) / err_v_im)
if err_z_re > 0:
    zscores.append(abs(z_re) / err_z_re)
if err_z_im > 0:
    zscores.append(abs(z_im + 1.0) / err_z_im)

max_abs_zscore = max(zscores) if zscores else math.nan
all2 = int(all(z <= 2.0 for z in zscores)) if zscores else 0
rhat_max = max(rhat_v_re, rhat_v_im, rhat_z_re, rhat_z_im)

print(",".join([
    f"{rhat_z_re}",
    f"{rhat_z_im}",
    f"{rhat_v_re}",
    f"{rhat_v_im}",
    f"{rhat_max}",
    f"{max_abs_zscore}",
    f"{all2}",
]))
PY
}

parse_chain_counters() {
  local run_dir="$1"
  local target_flow="$2"
  python3 - "$run_dir" "$target_flow" <<'PY'
import glob
import os
import re
import sys

run_dir = sys.argv[1]
target = float(sys.argv[2])
logs = sorted(glob.glob(os.path.join(run_dir, "chain_*", "logs", "generate_markov_chain.log")))

pat_nf = re.compile(r"near_fail=(\d+)")
pat_nt = re.compile(r"near_try=(\d+)")
pat_no = re.compile(r"near_ok=(\d+)")
pat_nu = re.compile(r"near_unusable=(\d+)")
pat_ff = re.compile(r"far_fail=(\d+)")
pat_nff = re.compile(r"near_fail_fast=(\d+)")
pat_fff = re.compile(r"far_fail_fast=(\d+)")
pat_start = re.compile(r"Adaptive random start succeeded: .*flow_time=\s*([0-9.]+)")

sum_nf = sum_nt = sum_no = sum_nu = sum_ff = 0
sum_nff = sum_fff = 0
down = 0
n_chain = 0

for lp in logs:
    n_chain += 1
    last = None
    start = None
    with open(lp, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "near_fail=" in line:
                last = line
            if start is None:
                m = pat_start.search(line)
                if m:
                    start = float(m.group(1))
    if last:
        m = pat_nf.search(last); sum_nf += int(m.group(1)) if m else 0
        m = pat_nt.search(last); sum_nt += int(m.group(1)) if m else 0
        m = pat_no.search(last); sum_no += int(m.group(1)) if m else 0
        m = pat_nu.search(last); sum_nu += int(m.group(1)) if m else 0
        m = pat_ff.search(last); sum_ff += int(m.group(1)) if m else 0
        m = pat_nff.search(last); sum_nff += int(m.group(1)) if m else 0
        m = pat_fff.search(last); sum_fff += int(m.group(1)) if m else 0
    if start is not None and start < (target - 1.0e-12):
        down += 1

print(",".join([
    str(sum_nf), str(sum_nt), str(sum_no), str(sum_nu), str(sum_ff),
    str(sum_nff), str(sum_fff), str(down), str(n_chain)
]))
PY
}

collect_post_metrics() {
  local post_dir="$1"
  local counts_csv="$2"
  local align_json="$3"
  python3 - "$post_dir" "$counts_csv" "$align_json" <<'PY'
import csv
import json
import math
import os
import sys

post_dir = sys.argv[1]
counts_csv = sys.argv[2]
align_json = sys.argv[3]
meta_json = os.path.join(post_dir, "bundle_metadata.json")

fail_samples = -1
if os.path.exists(meta_json):
    try:
        fail_samples = int(json.load(open(meta_json, "r", encoding="utf-8")).get("merged_failure_samples", -1))
    except Exception:
        fail_samples = -1

band = {
    "abs_re_hit_lt_min_abs_re": 0,
    "min_abs_re_le_abs_re_hit_le_max_abs_re": 0,
    "abs_re_hit_gt_max_abs_re": 0,
    "no_hit": 0,
}
stuck_pass = 0
stuck_fail = 0
side_rel = {
    "same_side": 0,
    "opposite_side": 0,
    "touch_zero": 0,
    "no_hit": 0,
    "no_stuck": 0,
}
cross_zero_count = 0
side_rel_z0 = {
    "same_side": 0,
    "opposite_side": 0,
    "touch_zero": 0,
    "unknown": 0,
}
cross_zero_vs_z0_count = 0
if os.path.exists(counts_csv):
    with open(counts_csv, "r", newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            kind = row.get("kind", "")
            typ = row.get("type", "")
            cnt = int(row.get("count", "0") or "0")
            if kind == "intersection_band" and typ in band:
                band[typ] = cnt
            if kind == "stuck_re_filter" and typ == "pass":
                stuck_pass = cnt
            if kind == "stuck_re_filter" and typ == "fail":
                stuck_fail = cnt
            if kind == "final_vs_hit_side" and typ in side_rel:
                side_rel[typ] = cnt
            if kind == "cross_zero_flag" and typ == "1":
                cross_zero_count = cnt
            if kind == "final_vs_z0_side" and typ in side_rel_z0:
                side_rel_z0[typ] = cnt
            if kind == "cross_zero_vs_z0_flag" and typ == "1":
                cross_zero_vs_z0_count = cnt

best = gprec = grec = math.nan
if os.path.exists(align_json):
    try:
        m = json.load(open(align_json, "r", encoding="utf-8"))
        best = float(m.get("best_match_accuracy_3x3", math.nan))
        gprec = float(m.get("global_to_gt_max_precision", math.nan))
        grec = float(m.get("gt_max_to_global_recall", math.nan))
    except Exception:
        pass

print(",".join([
    str(fail_samples),
    str(band["abs_re_hit_lt_min_abs_re"]),
    str(band["min_abs_re_le_abs_re_hit_le_max_abs_re"]),
    str(band["abs_re_hit_gt_max_abs_re"]),
    str(band["no_hit"]),
    str(stuck_pass),
    str(stuck_fail),
    str(side_rel["same_side"]),
    str(side_rel["opposite_side"]),
    str(side_rel["touch_zero"]),
    str(side_rel["no_hit"]),
    str(side_rel["no_stuck"]),
    str(cross_zero_count),
    str(side_rel_z0["same_side"]),
    str(side_rel_z0["opposite_side"]),
    str(side_rel_z0["touch_zero"]),
    str(side_rel_z0["unknown"]),
    str(cross_zero_vs_z0_count),
    str(best),
    str(gprec),
    str(grec),
]))
PY
}

CASE_TABLE=$(
cat <<'EOF'
c01_base,0,3000,0,2000,12000,0,on,baseline_no_failfast
c02_default,1,3000,1,2000,12000,0,on,default_failfast
c03_far_tight,1,3000,1,1400,7000,0,on,far_tight_only
c04_far_tight_b650,1,3000,1,1400,7000,650,on,far_tight_plus_budget
c05_far_vtight_b500,1,2200,1,1000,5000,500,on,very_tight_cutoff
c06_far_tight_b300,1,3000,1,1400,7000,300,on,data_driven_budget300
c07_far_tight_b260,1,3000,1,1400,7000,260,on,data_driven_budget260
c08_far_tight_b240,1,3000,1,1400,7000,240,on,data_driven_budget240
c09_far_tight_acc300,1,3000,1,1400,7000,0,on,data_driven_acciter300
c10_far_tight_acc260,1,3000,1,1400,7000,0,on,data_driven_acciter260
c11_far_tight_acc220,1,3000,1,1400,7000,0,on,data_driven_acciter220
EOF
)

while IFS=',' read -r CASE_ID NEAR_FF NEAR_FF_LIMIT FAR_FF FAR_FF_LIMIT FAR_FF_FLOWZR BUDGET_HARD MICRO_EXT NOTE; do
  [[ -z "${CASE_ID}" ]] && continue
  if ! want_case "${CASE_ID}"; then
    continue
  fi

  ACCEPT_ITER_BUDGET=0
  case "${CASE_ID}" in
    c09_far_tight_acc300) ACCEPT_ITER_BUDGET=300 ;;
    c10_far_tight_acc260) ACCEPT_ITER_BUDGET=260 ;;
    c11_far_tight_acc220) ACCEPT_ITER_BUDGET=220 ;;
  esac

  SOFT1=0
  SOFT2=0
  if [[ "${BUDGET_HARD}" -gt 0 ]]; then
    SOFT1=$((BUDGET_HARD / 3))
    SOFT2=$(((2 * BUDGET_HARD) / 3))
  fi

  for ((i=1; i<=SEEDS; i++)); do
    SEED=$((SEED_START + (i - 1) * SEED_STEP))
    RUN_NAME=$(printf "%s_%s_p%02d_%s_withfb" "${RUN_PREFIX}" "${CASE_ID}" "${i}" "${SAMPLES}")
    RUN_DIR="${OUTPUT_ROOT}/${RUN_NAME}"
    RUN_LOG="${ROOT}/${RUN_NAME}.nohup.log"
    EVAL_LOG="${ROOT}/${RUN_NAME}.evaluate.log"
    POST_DIR="${POST_ROOT}/${RUN_NAME}"

    STATUS="OK"
    ELAPSED="nan"
    RHAT_Z_RE="nan"
    RHAT_Z_IM="nan"
    RHAT_V_RE="nan"
    RHAT_V_IM="nan"
    RHAT_MAX="nan"
    MAX_ABS_ZSCORE="nan"
    ALL2SIGMA="0"
    NEAR_FAIL="0"
    NEAR_TRY="0"
    NEAR_OK="0"
    NEAR_UNUSABLE="0"
    FAR_FAIL="0"
    NEAR_FF_CNT="0"
    FAR_FF_CNT="0"
    DOWN_CHAINS="0"
    TOTAL_CHAINS="0"
    FAIL_SAMPLES="-1"
    BAND_LT_MIN="0"
    BAND_IN_BAND="0"
    BAND_GT_MAX="0"
    BAND_NO_HIT="0"
    STUCK_PASS="0"
    STUCK_FAIL="0"
    SIDE_SAME="0"
    SIDE_OPPOSITE="0"
    SIDE_TOUCH_ZERO="0"
    SIDE_NO_HIT="0"
    SIDE_NO_STUCK="0"
    CROSS_ZERO_COUNT="0"
    SIDEZ0_SAME="0"
    SIDEZ0_OPPOSITE="0"
    SIDEZ0_TOUCH_ZERO="0"
    SIDEZ0_UNKNOWN="0"
    CROSS_ZERO_VS_Z0_COUNT="0"
    ALIGN_BEST="nan"
    ALIGN_GPREC="nan"
    ALIGN_GRECALL="nan"
    OFFICIAL_TAG="$(subset_tag "${POST_OFFICIAL_N}")"
    OFFICIAL_LABEL="official_${OFFICIAL_TAG}"
    OFFICIAL_TRACE="${POST_DIR}/constraint_solver_fail_quasi_trace_first${OFFICIAL_TAG}.csv"
    OFFICIAL_GEOM_DIR="${POST_DIR}/geometry_plots_${OFFICIAL_LABEL}_noplot"
    OFFICIAL_SUMMARY_CSV="${POST_DIR}/failure_type_summary_${OFFICIAL_LABEL}.csv"
    OFFICIAL_COUNTS_CSV="${POST_DIR}/failure_type_counts_${OFFICIAL_LABEL}.csv"
    OFFICIAL_ALIGN_PREFIX="online_vs_geometry_alignment_${OFFICIAL_LABEL}"
    OFFICIAL_ALIGN_JSON="${POST_DIR}/${OFFICIAL_ALIGN_PREFIX}.metrics.json"
    OFFICIAL_MAX_CASES="0"

    echo "[RUN] ${RUN_NAME} seed=${SEED} case=${CASE_ID}" | tee -a "${ROOT}/driver.log"
    if ! env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      QN_RESCUE_LEVEL=3 \
      QN_FAR_LIGHT_MICRO_EXT="${MICRO_EXT}" \
      QN_FAR_ANCHOR_FASTTRACK=0 \
      QN_FAR_ANCHOR_MIX_RESTART=0 \
      QN_NEAR_SEEDED_NEWTON=1 \
      QN_NEAR_UNSOLVABLE_FAIL_FAST="${NEAR_FF}" \
      QN_NEAR_FAIL_FAST_FINAL_RESORT_LIMIT="${NEAR_FF_LIMIT}" \
      QN_FAR_FAIL_FAST="${FAR_FF}" \
      QN_FAR_FAIL_FAST_FINAL_RESORT_LIMIT="${FAR_FF_LIMIT}" \
      QN_FAR_FAIL_FAST_FLOWZR_LIMIT="${FAR_FF_FLOWZR}" \
      QN_STEP_BUDGET_SOFT1="${SOFT1}" \
      QN_STEP_BUDGET_SOFT2="${SOFT2}" \
      QN_STEP_BUDGET_HARD="${BUDGET_HARD}" \
      QN_ACCEPTED_ITER_BUDGET="${ACCEPT_ITER_BUDGET}" \
      python3 scripts/run_multichain_auto.py \
        --output-root "${OUTPUT_ROOT}" \
        --chains "${CHAINS}" \
        --run-name "${RUN_NAME}" \
        --force \
        --seed-base "${SEED}" \
        --base-parameters "${BASE_PARAMETERS}" \
        --chain-length "${SAMPLES}" \
        --target-samples-per-chain "${SAMPLES}" \
        --check-interval "${CHECK_INTERVAL}" \
        --max-wall-seconds "${MAX_WALL_SECONDS}" \
        --quasi-fallback on \
        > "${RUN_LOG}" 2>&1; then
      STATUS="RUN_FAIL"
      echo "[WARN] ${RUN_NAME} run failed" | tee -a "${ROOT}/driver.log"
    fi

    if [[ "${STATUS}" == "OK" ]]; then
      if ! EVAL_MULTICHAIN_RUN_DIR="${RUN_DIR}" EVAL_MULTICHAIN_DIAG_WINDOW="${SAMPLES}" \
        bin/evaluate_expectations > "${EVAL_LOG}" 2>&1; then
        STATUS="EVAL_FAIL"
      fi
    fi

    if [[ -f "${RUN_DIR}/summary.json" ]]; then
      ELAPSED=$(jq -r '.elapsed_seconds' "${RUN_DIR}/summary.json" 2>/dev/null || echo "nan")
    fi

    if [[ "${STATUS}" == "OK" && -f "${EVAL_LOG}" ]]; then
      IFS=',' read -r RHAT_Z_RE RHAT_Z_IM RHAT_V_RE RHAT_V_IM RHAT_MAX MAX_ABS_ZSCORE ALL2SIGMA < <(parse_eval_metrics "${EVAL_LOG}")
    fi

    if [[ -d "${RUN_DIR}" ]]; then
      IFS=',' read -r NEAR_FAIL NEAR_TRY NEAR_OK NEAR_UNUSABLE FAR_FAIL NEAR_FF_CNT FAR_FF_CNT DOWN_CHAINS TOTAL_CHAINS < <(parse_chain_counters "${RUN_DIR}" "${TARGET_FLOW_TIME}")
    fi

    if [[ "${STATUS}" == "OK" ]]; then
      mkdir -p "${POST_DIR}"
      if python3 scripts/build_post_session_bundle.py \
        --run-dir "${RUN_DIR}" \
        --out-dir "${POST_DIR}" \
        --first-n "${POST_OFFICIAL_N}" \
        --light-n "${POST_LIGHT_N}" \
        > "${ROOT}/${RUN_NAME}.bundle.log" 2>&1; then

        FAIL_SAMPLES=$(python3 - "${POST_DIR}/bundle_metadata.json" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1],"r",encoding="utf-8"))
    print(int(d.get("merged_failure_samples",-1)))
except Exception:
    print(-1)
PY
)

        if [[ "${FAIL_SAMPLES}" -gt 0 ]]; then
          if [[ "${POST_OFFICIAL_N}" -le 0 ]]; then
            OFFICIAL_MAX_CASES="${FAIL_SAMPLES}"
          else
            OFFICIAL_MAX_CASES="${POST_OFFICIAL_N}"
            if [[ "${GEOM_MAX_CASES}" -gt 0 && "${OFFICIAL_MAX_CASES}" -gt "${GEOM_MAX_CASES}" ]]; then
              OFFICIAL_MAX_CASES="${GEOM_MAX_CASES}"
            fi
          fi

          python3 scripts/plot_constraint_geometry.py \
            --z0-file "${POST_DIR}/constraint_solver_fail_z0.dat" \
            --delz-file "${POST_DIR}/constraint_solver_fail_delz.dat" \
            --x0-file "${POST_DIR}/constraint_solver_fail_x0.dat" \
            --quasi-trace-csv "${OFFICIAL_TRACE}" \
            --ensemble-z-history-file "${POST_DIR}/ensemble_z_history_merged.dat" \
            --out-dir "${OFFICIAL_GEOM_DIR}" \
            --max-cases "${OFFICIAL_MAX_CASES}" \
            --n-manifold "${GEOM_N_MANIFOLD}" \
            --no-plots \
            > "${ROOT}/${RUN_NAME}.geom.log" 2>&1 || STATUS="GEOM_FAIL"

          if [[ "${STATUS}" == "OK" ]]; then
            python3 scripts/classify_failure_types.py \
              --geometry-summary-csv "${OFFICIAL_GEOM_DIR}/intersection_summary.csv" \
              --quasi-trace-csv "${OFFICIAL_TRACE}" \
              --z0-file "${POST_DIR}/constraint_solver_fail_z0.dat" \
              --ensemble-z-history-file "${POST_DIR}/ensemble_z_history_merged.dat" \
              --out-summary-csv "${OFFICIAL_SUMMARY_CSV}" \
              --out-counts-csv "${OFFICIAL_COUNTS_CSV}" \
              > "${ROOT}/${RUN_NAME}.classify.log" 2>&1 || STATUS="CLASSIFY_FAIL"
          fi

          if [[ "${STATUS}" == "OK" ]]; then
            python3 scripts/check_online_geometry_alignment.py \
              --post-session-dir "${POST_DIR}" \
              --summary-csv "${OFFICIAL_SUMMARY_CSV}" \
              --trace-csv "${OFFICIAL_TRACE}" \
              --out-prefix "${OFFICIAL_ALIGN_PREFIX}" \
              > "${ROOT}/${RUN_NAME}.align.log" 2>&1 || STATUS="ALIGN_FAIL"
          fi

          if [[ "${STATUS}" == "OK" ]]; then
            IFS=',' read -r FAIL_SAMPLES BAND_LT_MIN BAND_IN_BAND BAND_GT_MAX BAND_NO_HIT STUCK_PASS STUCK_FAIL SIDE_SAME SIDE_OPPOSITE SIDE_TOUCH_ZERO SIDE_NO_HIT SIDE_NO_STUCK CROSS_ZERO_COUNT SIDEZ0_SAME SIDEZ0_OPPOSITE SIDEZ0_TOUCH_ZERO SIDEZ0_UNKNOWN CROSS_ZERO_VS_Z0_COUNT ALIGN_BEST ALIGN_GPREC ALIGN_GRECALL < <(collect_post_metrics "${POST_DIR}" "${OFFICIAL_COUNTS_CSV}" "${OFFICIAL_ALIGN_JSON}")
          fi
        fi
      else
        STATUS="POST_BUNDLE_FAIL"
      fi
    fi

    TS_NOW="$(date +%Y-%m-%dT%H:%M:%S)"
    echo "${TS_NOW},${RUN_NAME},${CASE_ID},${SEED},${SAMPLES},${TARGET_FLOW_TIME},${STATUS},${ELAPSED},${RHAT_Z_RE},${RHAT_Z_IM},${RHAT_V_RE},${RHAT_V_IM},${RHAT_MAX},${MAX_ABS_ZSCORE},${ALL2SIGMA},${NEAR_FAIL},${NEAR_TRY},${NEAR_OK},${NEAR_UNUSABLE},${FAR_FAIL},${NEAR_FF_CNT},${FAR_FF_CNT},${DOWN_CHAINS},${TOTAL_CHAINS},${FAIL_SAMPLES},${BAND_LT_MIN},${BAND_IN_BAND},${BAND_GT_MAX},${BAND_NO_HIT},${STUCK_PASS},${STUCK_FAIL},${SIDE_SAME},${SIDE_OPPOSITE},${SIDE_TOUCH_ZERO},${SIDE_NO_HIT},${SIDE_NO_STUCK},${CROSS_ZERO_COUNT},${SIDEZ0_SAME},${SIDEZ0_OPPOSITE},${SIDEZ0_TOUCH_ZERO},${SIDEZ0_UNKNOWN},${CROSS_ZERO_VS_Z0_COUNT},${ALIGN_BEST},${ALIGN_GPREC},${ALIGN_GRECALL},3,${MICRO_EXT},${NEAR_FF},${NEAR_FF_LIMIT},${FAR_FF},${FAR_FF_LIMIT},${FAR_FF_FLOWZR},${BUDGET_HARD},${ACCEPT_ITER_BUDGET},${NOTE}" >> "${SUMMARY_CSV}"
    echo "[DONE] ${RUN_NAME} status=${STATUS} rhat_z_re=${RHAT_Z_RE} near_unusable=${NEAR_UNUSABLE} far_fail=${FAR_FAIL} side_opposite=${SIDE_OPPOSITE} sidez0_opposite=${SIDEZ0_OPPOSITE} down_chains=${DOWN_CHAINS}/${TOTAL_CHAINS}" | tee -a "${ROOT}/driver.log"
  done
done <<< "${CASE_TABLE}"

python3 - "${SUMMARY_CSV}" <<'PY'
import csv
import math
import sys
from pathlib import Path

p = Path(sys.argv[1])
rows = list(csv.DictReader(p.open("r", encoding="utf-8")))
ok = [r for r in rows if r.get("status") == "OK"]

print(f"[DONE] summary_csv={p}")
print(f"[DONE] rows_total={len(rows)} rows_ok={len(ok)}")
if not ok:
    raise SystemExit(0)

def f(r, k, d=math.inf):
    try:
        return float(r.get(k, "nan"))
    except Exception:
        return d

ranked = sorted(
    ok,
    key=lambda r: (
        f(r, "rhat_max"),
        f(r, "max_abs_zscore"),
        f(r, "elapsed_s"),
    ),
)
print("top_candidates(run_name,status,rhat_max,max_abs_zscore,elapsed_s,near_unusable,far_fail,band_no_hit,band_gt_max,align_best)")
for r in ranked[:10]:
    print(",".join([
        r.get("run_name",""),
        r.get("status",""),
        r.get("rhat_max",""),
        r.get("max_abs_zscore",""),
        r.get("elapsed_s",""),
        r.get("near_unusable",""),
        r.get("far_fail",""),
        r.get("band_no_hit",""),
        r.get("band_gt_max",""),
        r.get("align_best_match",""),
    ]))
PY
