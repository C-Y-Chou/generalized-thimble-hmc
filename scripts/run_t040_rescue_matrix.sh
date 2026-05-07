#!/usr/bin/env bash
set -euo pipefail

# Quick rescue-impact matrix for t=0.4.
# Purpose: isolate structure vs gate tuning effects before any major redesign.

STAMP="$(date +%m%d_%H%M%S)"
ROOT="${ROOT:-output/multichain_auto_t040_matrix_${STAMP}}"
RUN_PREFIX="${RUN_PREFIX:-s20l2_t040_mx_${STAMP}}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters_t040.dat}"
CHAINS="${CHAINS:-24}"
SAMPLES="${SAMPLES:-10000}"
SEED_BASE="${SEED_BASE:-410000001}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"

mkdir -p "${ROOT}"

run_case() {
  local run_name="$1"
  local fb="$2"
  local rescue="$3"
  local micro="$4"
  local hard="$5"
  local soft1=0
  local soft2=0
  local run_log="${ROOT}/${run_name}.nohup.log"
  local eval_log="${ROOT}/${run_name}.evaluate.log"
  local eval_log_global="output/multichain_auto/${run_name}.evaluate.log"

  echo "[RUN] ${run_name} fb=${fb} rescue=${rescue} micro=${micro} hard=${hard}"

  if [[ "${fb}" == "on" ]]; then
    if [[ "${hard}" -gt 0 ]]; then
      soft1=$((hard / 3))
      soft2=$(((2 * hard) / 3))
    fi
    env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      QN_RESCUE_LEVEL="${rescue}" \
      QN_FAR_LIGHT_MICRO_EXT="${micro}" \
      QN_STEP_BUDGET_SOFT1="${soft1}" \
      QN_STEP_BUDGET_SOFT2="${soft2}" \
      QN_STEP_BUDGET_HARD="${hard}" \
      python3 scripts/run_multichain_auto.py \
        --chains "${CHAINS}" \
        --run-name "${run_name}" \
        --seed-base "${SEED_BASE}" \
        --base-parameters "${BASE_PARAMETERS}" \
        --chain-length "${SAMPLES}" \
        --target-samples-per-chain "${SAMPLES}" \
        --quasi-fallback on \
        --check-interval "${CHECK_INTERVAL}" \
        --max-wall-seconds "${MAX_WALL_SECONDS}" \
        > "${run_log}" 2>&1
  else
    env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      python3 scripts/run_multichain_auto.py \
        --chains "${CHAINS}" \
        --run-name "${run_name}" \
        --seed-base "${SEED_BASE}" \
        --base-parameters "${BASE_PARAMETERS}" \
        --chain-length "${SAMPLES}" \
        --target-samples-per-chain "${SAMPLES}" \
        --quasi-fallback off \
        --check-interval "${CHECK_INTERVAL}" \
        --max-wall-seconds "${MAX_WALL_SECONDS}" \
        > "${run_log}" 2>&1
  fi

  EVAL_MULTICHAIN_RUN_DIR="output/multichain_auto/${run_name}" \
    bin/evaluate_expectations > "${eval_log}" 2>&1
  cp -f "${eval_log}" "${eval_log_global}"

  echo "[DONE] ${run_name}"
}

# Matrix (6 cases) = baseline + structure + gate levels.
CASE_01="${RUN_PREFIX}_c01_nofb_10k"
CASE_02="${RUN_PREFIX}_c02_l2_off_h400_10k"
CASE_03="${RUN_PREFIX}_c03_l3_off_h400_10k"
CASE_04="${RUN_PREFIX}_c04_l3_on_h400_10k"
CASE_05="${RUN_PREFIX}_c05_l3_on_h650_10k"
CASE_06="${RUN_PREFIX}_c06_l3_on_h850_10k"

run_case "${CASE_01}" off 0 off 0
run_case "${CASE_02}" on 2 off 400
run_case "${CASE_03}" on 3 off 400
run_case "${CASE_04}" on 3 on 400
run_case "${CASE_05}" on 3 on 650
run_case "${CASE_06}" on 3 on 850

SUMMARY_CSV="${ROOT}/matrix_rescue_impact.csv"
python3 scripts/summarize_rescue_impact.py \
  --run-dir "output/multichain_auto/${CASE_01}" \
  --run-dir "output/multichain_auto/${CASE_02}" \
  --run-dir "output/multichain_auto/${CASE_03}" \
  --run-dir "output/multichain_auto/${CASE_04}" \
  --run-dir "output/multichain_auto/${CASE_05}" \
  --run-dir "output/multichain_auto/${CASE_06}" \
  --output-csv "${SUMMARY_CSV}"

export SUMMARY_CSV
python3 - << 'PY'
import csv
import os
from pathlib import Path
p = Path(os.environ["SUMMARY_CSV"])
rows = list(csv.DictReader(p.open()))
print("run_name,pass1_components,pass2_components,pass_rhat_101,near_fail_total,far_fail_total,rhat_max,rescue_level,micro,budget_hard")
for r in rows:
    print(",".join([
        r.get("run_name",""),
        r.get("pass1_components",""),
        r.get("pass2_components",""),
        r.get("pass_rhat_101",""),
        r.get("near_fail_total",""),
        r.get("far_fail_total",""),
        r.get("rhat_max",""),
        r.get("rescue_level_mode",""),
        r.get("micro_ext_mode",""),
        r.get("budget_hard_mode",""),
    ]))
PY

echo "[DONE] matrix summary: ${SUMMARY_CSV}"
