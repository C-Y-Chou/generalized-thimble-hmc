#!/usr/bin/env bash
set -euo pipefail

# Continuous far-rescue investment sweep (same seed/config).
# Goal: make runtime tunable with one continuous knob instead of
# only discrete gate switches.
#
# Outputs:
#   - per-run logs/evaluate logs under ${ROOT}
#   - run dirs under ${ROOT}/${RUN_NAME}
#   - summary csv: ${ROOT}/invest_sweep_summary.csv
#
# Example:
#   ROOT="output/multichain_auto_t035_invest_$(date +%m%d_%H%M%S)" \
#   bash scripts/run_t035_far_rescue_invest_sweep.sh

STAMP="$(date +%m%d_%H%M%S)"
ROOT="${ROOT:-output/multichain_auto_t035_invest_${STAMP}}"
RUN_PREFIX="${RUN_PREFIX:-s20l2_t035_invest}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters_t035.dat}"
CHAINS="${CHAINS:-24}"
SAMPLES="${SAMPLES:-10000}"
SEED_BASE="${SEED_BASE:-410000001}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"

# Continuous control set. Keep same seed for clean runtime comparison.
SCALES="${SCALES:-0.25 0.40 0.60 0.80 1.00 1.30}"

# Keep solver structure fixed while sweeping compute investment.
RESCUE_LEVEL="${RESCUE_LEVEL:-3}"
MICRO_EXT="${MICRO_EXT:-on}"
STEP_BUDGET_HARD="${STEP_BUDGET_HARD:-20000}"
FAR_ANCHOR_FASTTRACK="${FAR_ANCHOR_FASTTRACK:-off}"
NEAR_BUDGET_BYPASS="${NEAR_BUDGET_BYPASS:-off}"
# Fine-grained quasi cost guard (recommended for anti-tail-explosion runs):
# - disable coarse final-resort watchdog
# - use accepted-iter watchdog as primary hard cap
QUASI_FINAL_RESORT_BUDGET_CFG="${QUASI_FINAL_RESORT_BUDGET_CFG:-0}"
ACCEPTED_ITER_BUDGET_CFG="${ACCEPTED_ITER_BUDGET_CFG:-260}"

# Default tier caps for the budget controller.
FLOWZR_WEAK="${FLOWZR_WEAK:-2800}"
FLOWZR_MID="${FLOWZR_MID:-7600}"
FLOWZR_STRONG="${FLOWZR_STRONG:-15000}"
FINAL_WEAK="${FINAL_WEAK:-500}"
FINAL_MID="${FINAL_MID:-1200}"
FINAL_STRONG="${FINAL_STRONG:-2200}"
FLOWZR_FLOOR="${FLOWZR_FLOOR:-128}"
FINAL_FLOOR="${FINAL_FLOOR:-32}"

mkdir -p "${ROOT}"

soft1=0
soft2=0
if [[ "${STEP_BUDGET_HARD}" -gt 0 ]]; then
  soft1=$((STEP_BUDGET_HARD / 3))
  soft2=$(((2 * STEP_BUDGET_HARD) / 3))
fi

declare -a RUN_DIRS=()

scale_tag() {
  local s="$1"
  s="${s//./p}"
  s="${s//-/m}"
  echo "${s}"
}

run_one() {
  local scale="$1"
  local tag
  tag="$(scale_tag "${scale}")"
  local run_name="${RUN_PREFIX}_s${tag}_10k"
  local run_dir="${ROOT}/${run_name}"
  local run_log="${ROOT}/${run_name}.nohup.log"
  local eval_log="${ROOT}/${run_name}.evaluate.log"

  echo "[RUN] ${run_name} scale=${scale}"
  env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    QN_RESCUE_LEVEL="${RESCUE_LEVEL}" \
    QN_FAR_LIGHT_MICRO_EXT="${MICRO_EXT}" \
    QN_FAR_ANCHOR_FASTTRACK="${FAR_ANCHOR_FASTTRACK}" \
    QN_NEAR_BUDGET_BYPASS="${NEAR_BUDGET_BYPASS}" \
    QN_STEP_BUDGET_SOFT1="${soft1}" \
    QN_STEP_BUDGET_SOFT2="${soft2}" \
    QN_STEP_BUDGET_HARD="${STEP_BUDGET_HARD}" \
    QN_FAR_RESCUE_BUDGET=on \
    QN_FAR_RESCUE_INVEST_SCALE="${scale}" \
    QN_FAR_RESCUE_FLOWZR_WEAK="${FLOWZR_WEAK}" \
    QN_FAR_RESCUE_FLOWZR_MID="${FLOWZR_MID}" \
    QN_FAR_RESCUE_FLOWZR_STRONG="${FLOWZR_STRONG}" \
    QN_FAR_RESCUE_FINAL_RESORT_WEAK="${FINAL_WEAK}" \
    QN_FAR_RESCUE_FINAL_RESORT_MID="${FINAL_MID}" \
    QN_FAR_RESCUE_FINAL_RESORT_STRONG="${FINAL_STRONG}" \
    QN_FAR_RESCUE_FLOWZR_FLOOR="${FLOWZR_FLOOR}" \
    QN_FAR_RESCUE_FINAL_RESORT_FLOOR="${FINAL_FLOOR}" \
    QN_FAR_FAIL_FAST_FLOWZR_LIMIT=0 \
    QN_FAR_FAIL_FAST_FINAL_RESORT_LIMIT=0 \
    QN_FAR_ITER_BUDGET=off \
    QUASI_FINAL_RESORT_BUDGET="${QUASI_FINAL_RESORT_BUDGET_CFG}" \
    QN_ACCEPTED_ITER_BUDGET="${ACCEPTED_ITER_BUDGET_CFG}" \
    python3 scripts/run_multichain_auto.py \
      --chains "${CHAINS}" \
      --run-name "${run_name}" \
      --output-root "${ROOT}" \
      --seed-base "${SEED_BASE}" \
      --base-parameters "${BASE_PARAMETERS}" \
      --chain-length "${SAMPLES}" \
      --target-samples-per-chain "${SAMPLES}" \
      --quasi-fallback on \
      --check-interval "${CHECK_INTERVAL}" \
      --max-wall-seconds "${MAX_WALL_SECONDS}" \
      > "${run_log}" 2>&1

  EVAL_MULTICHAIN_RUN_DIR="${run_dir}" \
    bin/evaluate_expectations > "${eval_log}" 2>&1

  RUN_DIRS+=("${run_dir}")
  echo "[DONE] ${run_name}"
}

for scale in ${SCALES}; do
  run_one "${scale}"
done

SUMMARY_CSV="${ROOT}/invest_sweep_summary.csv"
summary_args=()
for run_dir in "${RUN_DIRS[@]}"; do
  summary_args+=(--run-dir "${run_dir}")
done
python3 scripts/summarize_rescue_impact.py \
  "${summary_args[@]}" \
  --output-csv "${SUMMARY_CSV}"

echo "[DONE] summary: ${SUMMARY_CSV}"
echo "[HINT] quick view:"
echo "  cut -d, -f2,31,14,17,19,37,44,56 ${SUMMARY_CSV} | column -s, -t"
