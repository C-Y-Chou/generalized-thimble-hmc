#!/usr/bin/env bash
set -euo pipefail

# Run t=0.30 scan for one integration-steps setting (trajectory_length fixed to 2),
# with identical 10 seeds for nofb and withfb, sequentially (no resource contention).
#
# Usage:
#   STEPS=10 bash scripts/run_t030_steps_compare10.sh
#
# Env knobs:
#   STEPS           integration_steps (required)
#   TRAJ_LEN        trajectory_length (default: 2)
#   FLOW_TIME       initial_flow_time (default: 0.30)
#   SAMPLES         per-chain samples (default: 50000)
#   CHAINS          number of chains (default: 24)
#   SEEDS           number of seeds (default: 10)
#   SEED_START      default: 410000001
#   SEED_STEP       default: 1000003
#   CHECK_INTERVAL  default: 10
#   MAX_WALL_SECONDS default: 43200
#   FORCE           pass-through to per-mode scripts (default: 0)
#   ROOT            output root; default auto timestamped
#   TAG             optional run tag suffix; default timestamp
#
# Output:
#   ROOT/
#     parameters_t030_sXXl2.dat
#     driver.progress.log
#     nofb/summary.csv
#     withfb/summary.csv

STEPS="${STEPS:-}"
if [[ -z "${STEPS}" ]]; then
  echo "[ERROR] STEPS is required (e.g., STEPS=10)." >&2
  exit 2
fi
if ! [[ "${STEPS}" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] STEPS must be integer, got: ${STEPS}" >&2
  exit 2
fi

TRAJ_LEN="${TRAJ_LEN:-2}"
FLOW_TIME="${FLOW_TIME:-0.30}"
SAMPLES="${SAMPLES:-50000}"
CHAINS="${CHAINS:-24}"
SEEDS="${SEEDS:-10}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-1000003}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
FORCE="${FORCE:-0}"

TS="${TAG:-$(date +%m%d_%H%M%S)}"
ROOT="${ROOT:-output/multichain_auto_t030_s${STEPS}l2_compare10_${TS}}"

mkdir -p "${ROOT}"
progress_log="${ROOT}/driver.progress.log"

base_template="data/parameters.dat"
param_file="${ROOT}/parameters_t030_s${STEPS}l2.dat"

if [[ ! -f "${base_template}" ]]; then
  echo "[ERROR] Missing template: ${base_template}" | tee -a "${progress_log}" >&2
  exit 2
fi

cp "${base_template}" "${param_file}"
sed -Ei \
  -e "s/^([[:space:]]*initial_flow_time[[:space:]]*=[[:space:]]*).*/\\1${FLOW_TIME}/" \
  -e "s/^([[:space:]]*integration_steps[[:space:]]*=[[:space:]]*).*/\\1${STEPS}/" \
  -e "s/^([[:space:]]*trajectory_length[[:space:]]*=[[:space:]]*).*/\\1${TRAJ_LEN}/" \
  "${param_file}"

run_prefix="s${STEPS}l2_t030_s1_50k_${TS}"

{
  echo "[INIT] ROOT=${ROOT}"
  echo "[INIT] STEPS=${STEPS} TRAJ_LEN=${TRAJ_LEN} FLOW_TIME=${FLOW_TIME}"
  echo "[INIT] SAMPLES=${SAMPLES} CHAINS=${CHAINS} SEEDS=${SEEDS}"
  echo "[INIT] SEED_START=${SEED_START} SEED_STEP=${SEED_STEP}"
  echo "[INIT] PARAM=${param_file}"
  echo "[INIT] RUN_PREFIX=${run_prefix}"
} | tee -a "${progress_log}"

# 1) no fallback
{
  echo "[RUN] nofb"
} | tee -a "${progress_log}"

env \
  ROOT="${ROOT}/nofb" \
  RUN_PREFIX="${run_prefix}" \
  SEEDS="${SEEDS}" \
  SEED_START="${SEED_START}" \
  SEED_STEP="${SEED_STEP}" \
  CHAINS="${CHAINS}" \
  SAMPLES="${SAMPLES}" \
  BASE_PARAMETERS="${param_file}" \
  DIAG_WINDOW="${SAMPLES}" \
  CHECK_INTERVAL="${CHECK_INTERVAL}" \
  MAX_WALL_SECONDS="${MAX_WALL_SECONDS}" \
  FORCE="${FORCE}" \
  bash scripts/run_nofb_multiseed.sh | tee -a "${progress_log}"

# 2) with fallback (S1 config)
{
  echo "[RUN] withfb"
} | tee -a "${progress_log}"

env \
  ROOT="${ROOT}/withfb" \
  RUN_PREFIX="${run_prefix}" \
  SEEDS="${SEEDS}" \
  SEED_START="${SEED_START}" \
  SEED_STEP="${SEED_STEP}" \
  CHAINS="${CHAINS}" \
  SAMPLES="${SAMPLES}" \
  BASE_PARAMETERS="${param_file}" \
  DIAG_WINDOW="${SAMPLES}" \
  CHECK_INTERVAL="${CHECK_INTERVAL}" \
  MAX_WALL_SECONDS="${MAX_WALL_SECONDS}" \
  FORCE="${FORCE}" \
  bash scripts/run_t035_s1_multiseed.sh | tee -a "${progress_log}"

{
  echo "[ALL DONE] ROOT=${ROOT}"
  echo "[ALL DONE] nofb_summary=${ROOT}/nofb/summary.csv"
  echo "[ALL DONE] withfb_summary=${ROOT}/withfb/summary.csv"
} | tee -a "${progress_log}"
