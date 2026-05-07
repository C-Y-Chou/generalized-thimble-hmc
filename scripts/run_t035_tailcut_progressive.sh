#!/usr/bin/env bash
set -euo pipefail

# Baseline-first runner for t=0.35:
# - legacy rescue tree forced off
# - progressive stage controls incremental compute investment
# - keeps evaluate + post-session + online-vs-geometry alignment

STAGE="${STAGE:-0}"
RUN_NAME="${RUN_NAME:-s20l2_t035_tailprog_s${STAGE}_10k}"
CHAINS="${CHAINS:-24}"
SAMPLES="${SAMPLES:-10000}"
SEED_BASE="${SEED_BASE:-410000001}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters_t035.dat}"
OUT_ROOT="${OUT_ROOT:-output/multichain_auto}"
POST_ROOT="${POST_ROOT:-output/post_session_analysis}"
POST_N="${POST_N:-600}"

RUN_DIR="output/multichain_auto/${RUN_NAME}"
RUN_LOG="${OUT_ROOT}/${RUN_NAME}.nohup.log"
EVAL_LOG="${OUT_ROOT}/${RUN_NAME}.evaluate.log"
PS_DIR="${POST_ROOT}/${RUN_NAME}"

mkdir -p "${OUT_ROOT}"

if [[ -e "${RUN_DIR}" ]]; then
  echo "[ERROR] run dir already exists: ${RUN_DIR}"
  exit 1
fi
if [[ ! -f "${BASE_PARAMETERS}" ]]; then
  echo "[ERROR] base parameter file not found: ${BASE_PARAMETERS}"
  exit 1
fi

if [[ "${POST_N}" -le 0 ]]; then
  TRACE_TAG="all"
else
  TRACE_TAG="${POST_N}"
fi
TRACE_CSV="${PS_DIR}/constraint_solver_fail_quasi_trace_first${TRACE_TAG}.csv"
GEOM_DIR="${PS_DIR}/geometry_${TRACE_TAG}"
TYPE_SUMMARY="${PS_DIR}/failure_type_summary_${TRACE_TAG}.csv"
TYPE_COUNTS="${PS_DIR}/failure_type_counts_${TRACE_TAG}.csv"
ALIGN_PREFIX="online_vs_geometry_alignment_${TRACE_TAG}"

echo "[BUILD] generate_markov_chain"
make -C build ../bin/generate_markov_chain >/dev/null

FLOW_TIME="$(awk -F '=' '/^[[:space:]]*initial_flow_time/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "${BASE_PARAMETERS}")"
echo "[INIT] base_parameters=${BASE_PARAMETERS} initial_flow_time=${FLOW_TIME:-unknown}"

echo "[RUN] ${RUN_NAME} stage=${STAGE}"
env \
  QN_ENABLE_LEGACY_RESCUE=0 \
  QN_PROGRESSIVE_RESCUE_STAGE="${STAGE}" \
  QN_RESCUE_LEVEL=0 \
  QN_FAR_RESCUE_REBUILD=off \
  QN_FAR_LIGHT_MICRO_EXT=off \
  QN_FAR_ANCHOR_FASTTRACK=off \
  QN_FAR_ANCHOR_MIX_RESTART=off \
  QN_NEAR_SEEDED_NEWTON=off \
  OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  python3 scripts/run_multichain_auto.py \
    --chains "${CHAINS}" \
    --run-name "${RUN_NAME}" \
    --seed-base "${SEED_BASE}" \
    --base-parameters "${BASE_PARAMETERS}" \
    --chain-length "${SAMPLES}" \
    --target-samples-per-chain "${SAMPLES}" \
    --quasi-fallback on \
    --check-interval "${CHECK_INTERVAL}" \
    --max-wall-seconds "${MAX_WALL_SECONDS}" \
    > "${RUN_LOG}" 2>&1

echo "[EVAL] ${RUN_NAME}"
EVAL_MULTICHAIN_RUN_DIR="${RUN_DIR}" bin/evaluate_expectations > "${EVAL_LOG}" 2>&1

echo "[POST] build bundle"
python3 scripts/build_post_session_bundle.py \
  --run-dir "${RUN_DIR}" \
  --out-dir "${PS_DIR}" \
  --first-n "${POST_N}" \
  --light-n "${POST_N}"

echo "[POST] geometry classify align (no plots)"
python3 scripts/plot_constraint_geometry.py --no-plots \
  --z0-file "${PS_DIR}/constraint_solver_fail_z0.dat" \
  --delz-file "${PS_DIR}/constraint_solver_fail_delz.dat" \
  --x0-file "${PS_DIR}/constraint_solver_fail_x0.dat" \
  --quasi-trace-csv "${TRACE_CSV}" \
  --ensemble-z-history-file "${PS_DIR}/ensemble_z_history_merged.dat" \
  --max-cases "${POST_N}" \
  --out-dir "${GEOM_DIR}"

python3 scripts/classify_failure_types.py \
  --geometry-summary-csv "${GEOM_DIR}/intersection_summary.csv" \
  --quasi-trace-csv "${TRACE_CSV}" \
  --ensemble-z-history-file "${PS_DIR}/ensemble_z_history_merged.dat" \
  --z0-file "${PS_DIR}/constraint_solver_fail_z0.dat" \
  --out-summary-csv "${TYPE_SUMMARY}" \
  --out-counts-csv "${TYPE_COUNTS}"

python3 scripts/check_online_geometry_alignment.py \
  --post-session-dir "${PS_DIR}" \
  --summary-csv "${TYPE_SUMMARY}" \
  --trace-csv "${TRACE_CSV}" \
  --out-prefix "${ALIGN_PREFIX}"

echo "[DONE] ${RUN_NAME}"
echo "  run_dir: ${RUN_DIR}"
echo "  eval:    ${EVAL_LOG}"
echo "  post:    ${PS_DIR}"
