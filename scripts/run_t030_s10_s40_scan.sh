#!/usr/bin/env bash
set -euo pipefail

# Sequential t=0.30 scan for s10l2 and s40l2.
# Reuses the same seed schedule for both settings.
#
# Usage:
#   bash scripts/run_t030_s10_s40_scan.sh
#
# Env knobs (passed through):
#   FLOW_TIME TRAJ_LEN SAMPLES CHAINS SEEDS SEED_START SEED_STEP
#   CHECK_INTERVAL MAX_WALL_SECONDS FORCE
#   ROOT_BASE (default output/multichain_auto_t030_s10_s40_scan_<ts>)

FLOW_TIME="${FLOW_TIME:-0.30}"
TRAJ_LEN="${TRAJ_LEN:-2}"
SAMPLES="${SAMPLES:-50000}"
CHAINS="${CHAINS:-24}"
SEEDS="${SEEDS:-10}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-1000003}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
FORCE="${FORCE:-0}"

TS="$(date +%m%d_%H%M%S)"
ROOT_BASE="${ROOT_BASE:-output/multichain_auto_t030_s10_s40_scan_${TS}}"
mkdir -p "${ROOT_BASE}"
progress_log="${ROOT_BASE}/driver.progress.log"

{
  echo "[INIT] ROOT_BASE=${ROOT_BASE}"
  echo "[INIT] flow=${FLOW_TIME} traj_len=${TRAJ_LEN} samples=${SAMPLES} chains=${CHAINS}"
  echo "[INIT] seeds=${SEEDS} seed_start=${SEED_START} seed_step=${SEED_STEP}"
  echo "[NOTE] s20l2 uses existing old data; this run only does s10l2 and s40l2."
} | tee -a "${progress_log}"

for STEPS in 10 40; do
  ROOT="${ROOT_BASE}/s${STEPS}l2"
  {
    echo "[RUN] STEPS=${STEPS} ROOT=${ROOT}"
  } | tee -a "${progress_log}"

  env \
    STEPS="${STEPS}" \
    ROOT="${ROOT}" \
    FLOW_TIME="${FLOW_TIME}" \
    TRAJ_LEN="${TRAJ_LEN}" \
    SAMPLES="${SAMPLES}" \
    CHAINS="${CHAINS}" \
    SEEDS="${SEEDS}" \
    SEED_START="${SEED_START}" \
    SEED_STEP="${SEED_STEP}" \
    CHECK_INTERVAL="${CHECK_INTERVAL}" \
    MAX_WALL_SECONDS="${MAX_WALL_SECONDS}" \
    FORCE="${FORCE}" \
    bash scripts/run_t030_steps_compare10.sh | tee -a "${progress_log}"

done

{
  echo "[ALL DONE] ROOT_BASE=${ROOT_BASE}"
  echo "[ALL DONE] s10 nofb summary=${ROOT_BASE}/s10l2/nofb/summary.csv"
  echo "[ALL DONE] s10 withfb summary=${ROOT_BASE}/s10l2/withfb/summary.csv"
  echo "[ALL DONE] s40 nofb summary=${ROOT_BASE}/s40l2/nofb/summary.csv"
  echo "[ALL DONE] s40 withfb summary=${ROOT_BASE}/s40l2/withfb/summary.csv"
} | tee -a "${progress_log}"
