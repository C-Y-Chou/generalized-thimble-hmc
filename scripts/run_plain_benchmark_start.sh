#!/usr/bin/env bash
set -euo pipefail

# Unique plain benchmark starting point:
# - quasi fallback on
# - rescue skeleton disabled (probe-only) via QN_RESCUE_LEVEL=0
# - full post-session bundle + classification + online/geometry alignment
# - no plotting

RUN="s20l2t05_plain_benchmark_p00_probeonly"
SEED_BASE=410000001
CHAINS=24
SAMPLES=10000
BASE_PARAMS="data/parameters_t05.dat"
POST_OFFICIAL_N="${POST_OFFICIAL_N:-0}"
POST_LIGHT_N="${POST_LIGHT_N:-600}"

RUN_DIR="output/multichain_auto/${RUN}"
RUN_LOG="output/multichain_auto/${RUN}.nohup.log"
EVAL_LOG="output/multichain_auto/${RUN}.evaluate.log"
PS_DIR="output/post_session_analysis/${RUN}"

subset_tag() {
  local n="$1"
  if [[ "${n}" -le 0 ]]; then
    echo "all"
  else
    echo "${n}"
  fi
}

OFFICIAL_TAG="$(subset_tag "${POST_OFFICIAL_N}")"
LIGHT_TAG="$(subset_tag "${POST_LIGHT_N}")"
OFFICIAL_TRACE="${PS_DIR}/constraint_solver_fail_quasi_trace_first${OFFICIAL_TAG}.csv"
LIGHT_TRACE="${PS_DIR}/constraint_solver_fail_quasi_trace_first${LIGHT_TAG}.csv"
OFFICIAL_GEOM_DIR="${PS_DIR}/geometry_official_${OFFICIAL_TAG}"
LIGHT_GEOM_DIR="${PS_DIR}/geometry_light_${LIGHT_TAG}"
OFFICIAL_SUMMARY="${PS_DIR}/failure_type_summary_official_${OFFICIAL_TAG}.csv"
OFFICIAL_COUNTS="${PS_DIR}/failure_type_counts_official_${OFFICIAL_TAG}.csv"
LIGHT_SUMMARY="${PS_DIR}/failure_type_summary_light_${LIGHT_TAG}.csv"
LIGHT_COUNTS="${PS_DIR}/failure_type_counts_light_${LIGHT_TAG}.csv"
OFFICIAL_ALIGN_PREFIX="online_vs_geometry_alignment_official_${OFFICIAL_TAG}"
LIGHT_ALIGN_PREFIX="online_vs_geometry_alignment_light_${LIGHT_TAG}"
OFFICIAL_MAX_CASES="${POST_OFFICIAL_N}"
LIGHT_MAX_CASES="${POST_LIGHT_N}"

if [[ -e "${RUN_DIR}" ]]; then
  echo "[ERROR] ${RUN_DIR} already exists. Keep this benchmark unique; clean outputs first."
  exit 1
fi

echo "[BUILD] generate_markov_chain"
make -C build ../bin/generate_markov_chain >/dev/null

echo "[RUN] ${RUN}"
env QN_RESCUE_LEVEL=0 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
python3 scripts/run_multichain_auto.py \
  --chains "${CHAINS}" \
  --run-name "${RUN}" \
  --seed-base "${SEED_BASE}" \
  --base-parameters "${BASE_PARAMS}" \
  --chain-length "${SAMPLES}" \
  --target-samples-per-chain "${SAMPLES}" \
  --quasi-fallback on \
  --check-interval 10 \
  --max-wall-seconds 43200 \
  > "${RUN_LOG}" 2>&1

echo "[EVAL] ${RUN}"
EVAL_MULTICHAIN_RUN_DIR="${RUN_DIR}" bin/evaluate_expectations > "${EVAL_LOG}" 2>&1

echo "[POST] bundle"
python3 scripts/build_post_session_bundle.py \
  --run-dir "${RUN_DIR}" \
  --out-dir "${PS_DIR}" \
  --first-n "${POST_OFFICIAL_N}" \
  --light-n "${POST_LIGHT_N}"

if [[ "${OFFICIAL_MAX_CASES}" -le 0 || "${LIGHT_MAX_CASES}" -le 0 ]]; then
  FAIL_SAMPLES=$(python3 - "${PS_DIR}/bundle_metadata.json" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1], "r", encoding="utf-8"))
    print(int(d.get("merged_failure_samples", 0)))
except Exception:
    print(0)
PY
)
  if [[ "${OFFICIAL_MAX_CASES}" -le 0 ]]; then
    OFFICIAL_MAX_CASES="${FAIL_SAMPLES}"
  fi
  if [[ "${LIGHT_MAX_CASES}" -le 0 ]]; then
    LIGHT_MAX_CASES="${FAIL_SAMPLES}"
  fi
fi

echo "[POST] geometry (no plots)"
python3 scripts/plot_constraint_geometry.py --no-plots \
  --z0-file "${PS_DIR}/constraint_solver_fail_z0.dat" \
  --delz-file "${PS_DIR}/constraint_solver_fail_delz.dat" \
  --x0-file "${PS_DIR}/constraint_solver_fail_x0.dat" \
  --quasi-trace-csv "${OFFICIAL_TRACE}" \
  --ensemble-z-history-file "${PS_DIR}/ensemble_z_history_merged.dat" \
  --max-cases "${OFFICIAL_MAX_CASES}" \
  --out-dir "${OFFICIAL_GEOM_DIR}"

python3 scripts/plot_constraint_geometry.py --no-plots \
  --z0-file "${PS_DIR}/constraint_solver_fail_z0.dat" \
  --delz-file "${PS_DIR}/constraint_solver_fail_delz.dat" \
  --x0-file "${PS_DIR}/constraint_solver_fail_x0.dat" \
  --quasi-trace-csv "${LIGHT_TRACE}" \
  --ensemble-z-history-file "${PS_DIR}/ensemble_z_history_merged.dat" \
  --max-cases "${LIGHT_MAX_CASES}" \
  --out-dir "${LIGHT_GEOM_DIR}"

echo "[POST] failure classification"
python3 scripts/classify_failure_types.py \
  --geometry-summary-csv "${OFFICIAL_GEOM_DIR}/intersection_summary.csv" \
  --quasi-trace-csv "${OFFICIAL_TRACE}" \
  --ensemble-z-history-file "${PS_DIR}/ensemble_z_history_merged.dat" \
  --z0-file "${PS_DIR}/constraint_solver_fail_z0.dat" \
  --out-summary-csv "${OFFICIAL_SUMMARY}" \
  --out-counts-csv "${OFFICIAL_COUNTS}"

python3 scripts/classify_failure_types.py \
  --geometry-summary-csv "${LIGHT_GEOM_DIR}/intersection_summary.csv" \
  --quasi-trace-csv "${LIGHT_TRACE}" \
  --ensemble-z-history-file "${PS_DIR}/ensemble_z_history_merged.dat" \
  --z0-file "${PS_DIR}/constraint_solver_fail_z0.dat" \
  --out-summary-csv "${LIGHT_SUMMARY}" \
  --out-counts-csv "${LIGHT_COUNTS}"

echo "[POST] online-vs-geometry alignment"
python3 scripts/check_online_geometry_alignment.py \
  --post-session-dir "${PS_DIR}" \
  --summary-csv "${OFFICIAL_SUMMARY}" \
  --trace-csv "${OFFICIAL_TRACE}" \
  --out-prefix "${OFFICIAL_ALIGN_PREFIX}"

python3 scripts/check_online_geometry_alignment.py \
  --post-session-dir "${PS_DIR}" \
  --summary-csv "${LIGHT_SUMMARY}" \
  --trace-csv "${LIGHT_TRACE}" \
  --out-prefix "${LIGHT_ALIGN_PREFIX}"

echo "[DONE] plain benchmark complete"
echo "  run_dir: ${RUN_DIR}"
echo "  eval:    ${EVAL_LOG}"
echo "  post:    ${PS_DIR}"
